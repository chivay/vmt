const std = @import("std");
const kernel = @import("root");
const mm = kernel.mm;
const x86 = @import("../x86.zig");
const apic = x86.apic;
const elf = std.elf;
const MMIORegion = kernel.mmio.DynamicMMIORegion;
const lib = kernel.lib;

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
        @truncate(cr3_value),
    );
}

var ap_boot_stack: [0x1000]u8 = undefined;

var startup_lock = kernel.lib.Spinlock.init();
var ap_booted: bool = false;

fn waitUntilBooted() void {
    while (true) {
        const held = startup_lock.acquire();
        defer held.release();
        if (ap_booted) break;
    }
}

fn apEntry() callconv(.C) noreturn {
    x86.main_gdt.load();
    x86.set_ds(x86.null_entry.raw);
    x86.set_es(x86.null_entry.raw);
    x86.set_fs(x86.null_entry.raw);
    x86.set_gs(x86.null_entry.raw);
    x86.set_ss(x86.kernel_data.raw);

    x86.main_gdt.reload_cs(x86.kernel_code);
    x86.main_idt.load();
    //GSBASE.write(@ptrToInt(&boot_cpu_gsstruct));

    {
        const held = startup_lock.acquire();
        defer held.release();

        ap_booted = true;
    }
    x86.hang();
}

fn patchEntrypoint(buffer: []u8, offset: u64) void {
    const entry = @intFromPtr(&apEntry);
    std.mem.writeIntSliceLittle(
        u64,
        buffer[offset .. offset + @sizeOf(u64)],
        @truncate(entry),
    );
}

fn patchRspValue(buffer: []u8, offset: u64) void {
    const rsp_value = @intFromPtr(&ap_boot_stack) + @sizeOf(@TypeOf(ap_boot_stack));
    std.mem.writeIntSliceLittle(
        u64,
        buffer[offset .. offset + @sizeOf(u64)],
        @truncate(rsp_value),
    );
}

fn patchSectionRel(buffer: []u8, offset: u64, addend: i64, typ: RelocType) void {
    // Relocate with respect to section address
    switch (typ) {
        .R_AMD64_16 => {
            const val: u32 = TRAMPOLINE_BASE + @as(u32, @intCast(addend));
            std.mem.writeIntSliceLittle(
                u16,
                buffer[offset .. offset + @sizeOf(u16)],
                @truncate(val),
            );
        },
        .R_AMD64_32 => {
            const val: u32 = TRAMPOLINE_BASE + @as(u32, @intCast(addend));
            std.mem.writeIntSliceLittle(
                u32,
                buffer[offset .. offset + @sizeOf(u32)],
                @truncate(val),
            );
        },
        .R_AMD64_64 => {
            const val: u64 = TRAMPOLINE_BASE + @as(u64, @intCast(addend));
            std.mem.writeIntSliceLittle(
                u64,
                buffer[offset .. offset + @sizeOf(u64)],
                val,
            );
        },
        _ => @panic("Unimplemented"),
    }
}

fn relocateStartupCode(buffer: []u8) void {
    var relocations = x86.trampoline.getSectionData(".rela.smp_trampoline").?;
    while (relocations.len > 0) : (relocations = relocations[@sizeOf(elf.Elf64_Rela)..]) {
        var rela: elf.Elf64_Rela = undefined;
        std.mem.copy(u8, std.mem.asBytes(&rela), relocations[0..@sizeOf(@TypeOf(rela))]);

        const offset = rela.r_offset;

        const typ = @as(RelocType, @enumFromInt(rela.r_type()));
        const symbol = x86.trampoline.getSymbol(rela.r_sym());
        const name = x86.trampoline.getString(symbol.?.st_name);
        const has_name = name != null;

        const eql = std.mem.eql;

        // zig bug variable has to be hoiseted outside {}
        // https://github.com/ziglang/zig/issues/7467
        const escaped_name = if (name) |nam| std.fmt.fmtSliceEscapeLower(nam) else std.fmt.fmtSliceEscapeLower("(null)");

        logger.debug("{} of symbol {} at {}\n", .{ typ, escaped_name, rela.r_offset });
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

const LapicIterator = struct {
    madt_it: x86.acpi.MADTIterator,

    pub fn next(self: *@This()) ?*const x86.acpi.MADTLapic {
        if (self.madt_it.next()) |header| {
            const typ = lib.intToEnumSafe(x86.acpi.MADTEntryType, header.entry_type);
            if (typ == null) return self.next();
            const typ_enum = typ.?;
            switch (typ_enum) {
                .LocalApic => {
                    return @as(*const x86.acpi.MADTLapic, @ptrCast(header));
                },
                else => return null,
            }
        }
        return null;
    }

    pub fn init(madt_it: x86.acpi.MADTIterator) LapicIterator {
        return .{ .madt_it = madt_it };
    }
};

fn iterLapic() LapicIterator {
    var it = x86.acpi.iterMADT();
    return LapicIterator.init(it);
}

pub fn init() void {
    const PAGE_SIZE = 0x1000;

    const phys_start = try allocateTrampoline();
    const start_page: u8 = @truncate((phys_start.value / PAGE_SIZE));

    const virt_start = mm.VirtualAddress.new(TRAMPOLINE_BASE);
    const trampoline = mm.getKernelVM().map_memory(
        virt_start,
        phys_start,
        PAGE_SIZE,
        mm.VirtualMemory.Protection.RWX,
    ) catch {
        logger.err("Failed to map AP memory");
        return;
    };
    defer mm.getKernelVM().unmap(trampoline) catch {
        @panic("Failed to unmap AP memory");
    };

    const startup_code = x86.trampoline.getSectionData(".smp_trampoline").?;

    const buffer = trampoline.as_bytes()[0..startup_code.len];
    if (startup_code.len > buffer.len) {
        @panic("Trampoline size more than one page long!");
    }
    std.mem.copy(u8, buffer, startup_code);

    logger.log("Performing AP startup code relocation\n", .{});
    relocateStartupCode(buffer);

    var it = iterLapic();
    const apic_id = x86.apic.getLapicId();
    while (it.next()) |lapic| {
        {
            const held = startup_lock.acquire();
            defer held.release();
            ap_booted = false;
        }
        if (apic_id != lapic.acpi_processor_uid) {
            wakeUpCpu(&apic.lapic, lapic.acpi_processor_uid, start_page);
            waitUntilBooted();
            logger.info("CPU{} up\n", .{lapic.acpi_processor_uid});
        }
    }
}
