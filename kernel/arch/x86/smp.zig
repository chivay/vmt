const std = @import("std");
const kernel = @import("root");
const mm = kernel.mm;
const x86 = @import("../x86.zig");
const apic = x86.apic;
const elf = kernel.lib.elf;
const MMIORegion = kernel.mmio.DynamicMMIORegion;

var logger = @TypeOf(x86.logger).childOf(@typeName(@This())){};

const TRAMPOLINE_BASE = 0x8000;

fn allocateTrampoline() !mm.PhysicalAddress {
    return mm.PhysicalAddress.new(TRAMPOLINE_BASE);
}

const RelocType = enum(u32) {
    R_AMD64_64 = 1,
    R_AMD64_32 = 10,
    R_AMD64_16 = 12,
    _,
};

fn patchCr3Value(buffer: []u8, offset: u64) void {
    const cr3_value = x86.mm.kernel_vm_impl.pml4.root.value;
    if (cr3_value > std.math.maxInt(u32)) @panic("PML4 too far");
    std.mem.writeIntSliceLittle(
        u32,
        buffer[offset .. offset + @sizeOf(u32)],
        @truncate(u32, cr3_value),
    );
}

var ap_boot_stack: [0x1000]u8 = undefined;

fn apEntry() callconv(.C) noreturn {
    const apic_id = x86.apic.getLapicId();
    logger.log("LAPIC ID {x} CPU up\n", .{apic_id});

    x86.main_gdt.load();
    x86.set_ds(x86.null_entry.raw);
    x86.set_es(x86.null_entry.raw);
    x86.set_fs(x86.null_entry.raw);
    x86.set_gs(x86.null_entry.raw);
    x86.set_ss(x86.kernel_data.raw);

    x86.main_gdt.reload_cs(x86.kernel_code);
    x86.main_idt.load();
    //GSBASE.write(@ptrToInt(&boot_cpu_gsstruct));

    logger.log("CPU{} idling\n", .{apic_id});
    x86.idle();
    while (true) {}
}

fn patchEntrypoint(buffer: []u8, offset: u64) void {
    const entry = @ptrToInt(apEntry);
    std.mem.writeIntSliceLittle(
        u64,
        buffer[offset .. offset + @sizeOf(u64)],
        @truncate(u64, entry),
    );
}

fn patchRspValue(buffer: []u8, offset: u64) void {
    const rsp_value = @ptrToInt(&ap_boot_stack) + @sizeOf(@TypeOf(ap_boot_stack));
    std.mem.writeIntSliceLittle(
        u64,
        buffer[offset .. offset + @sizeOf(u64)],
        @truncate(u64, rsp_value),
    );
}

fn patchSectionRel(buffer: []u8, offset: u64, addend: i64, typ: RelocType) void {
    // Relocate with respect to section address
    switch (typ) {
        .R_AMD64_16 => {
            const val: u32 = TRAMPOLINE_BASE + @intCast(u32, addend);
            std.mem.writeIntSliceLittle(
                u16,
                buffer[offset .. offset + @sizeOf(u16)],
                @truncate(u16, val),
            );
        },
        .R_AMD64_32 => {
            const val: u32 = TRAMPOLINE_BASE + @intCast(u32, addend);
            std.mem.writeIntSliceLittle(
                u32,
                buffer[offset .. offset + @sizeOf(u32)],
                @truncate(u32, val),
            );
        },
        .R_AMD64_64 => {
            const val: u64 = TRAMPOLINE_BASE + @intCast(u64, addend);
            std.mem.writeIntSliceLittle(
                u64,
                buffer[offset .. offset + @sizeOf(u64)],
                val,
            );
        },
        _ => @panic("Unimplemented"),
    }
}

fn relocateStartupCode(buffer: []u8) !void {
    var relocations = x86.trampoline.getSectionData(".rela.smp_trampoline").?;
    while (relocations.len > 0) : (relocations = relocations[@sizeOf(elf.Elf64_Rela)..]) {
        var rela: elf.Elf64_Rela = undefined;
        std.mem.copy(u8, std.mem.asBytes(&rela), relocations[0..@sizeOf(@TypeOf(rela))]);

        const offset = rela.r_offset;

        const typ = @intToEnum(RelocType, rela.r_type());
        const symbol = x86.trampoline.getSymbol(rela.r_sym());
        const name = x86.trampoline.getString(symbol.?.st_name);
        const has_name = name != null;

        const eql = std.mem.eql;

        logger.log("{} of symbol {e} at {}\n", .{ typ, name, rela.r_offset });
        if (has_name and eql(u8, name.?, "KERNEL_CR3") and typ == .R_AMD64_32) {
            patchCr3Value(buffer, offset);
        } else if (has_name and eql(u8, name.?, "STACK") and typ == .R_AMD64_64) {
            patchRspValue(buffer, offset);
        } else if (has_name and eql(u8, name.?, "ENTRYPOINT") and typ == .R_AMD64_64) {
            patchEntrypoint(buffer, offset);
        } else if (has_name and eql(u8, name.?, "")) {
            patchSectionRel(buffer, offset, rela.r_addend, typ);
        } else {
            logger.log("Unknown relocation\n", .{});
            logger.log("{}\n", .{symbol});
            logger.log("{}\n", .{rela});
        }
    }
}

fn wakeUpCpu(lapic: *const MMIORegion, lapic_id: u8, start_page: u8) void {
    // TODO add sleeping
    logger.debug("Sending INIT\n", .{});
    apic.sendCommand(lapic, lapic_id, 0b101 << 8 | 1 << 14);

    // SIPI command
    const command = init: {
        var v: u20 = 0;
        // vector
        v |= start_page;
        // SIPI
        v |= 0b110 << 8;
        break :init v;
    };

    logger.debug("Sending SIPI 1/2\n", .{});
    apic.sendCommand(lapic, lapic_id, command);

    logger.debug("Sending SIPI 2/2\n", .{});
    apic.sendCommand(lapic, lapic_id, command);
}

pub fn init() void {
    //logger.setLevel(@TypeOf(logger).Level.Debug);
    //defer logger.setLevel(@TypeOf(logger).Level.Info);
    const PAGE_SIZE = 0x1000;

    const phys_start = try allocateTrampoline();
    const start_page: u8 = @truncate(u8, (phys_start.value / PAGE_SIZE));

    mm.kernel_vm.map_memory(
        mm.VirtualAddress.new(TRAMPOLINE_BASE),
        phys_start,
        PAGE_SIZE,
    ) catch |err| {
        logger.err("Failed to map AP memory");
        return;
    };

    const trampoline = mm.kernel_vm.map_io(phys_start, PAGE_SIZE) catch |err| {
        logger.err("Failed to map trampoline memory");
        return;
    };

    const startup_code = x86.trampoline.getSectionData(".smp_trampoline").?;

    const buffer = trampoline.as_bytes()[0..startup_code.len];
    std.mem.copy(u8, buffer, startup_code);

    logger.log("Performing AP startup code relocation\n", .{});
    try relocateStartupCode(buffer);

    for ([_]u8{
        1,
    }) |target| {
        logger.info("Waking CPU {}\n", .{target});
        wakeUpCpu(&apic.lapic, target, start_page);
    }

    x86.idle();
}