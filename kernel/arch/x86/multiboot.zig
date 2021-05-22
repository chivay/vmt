const mm = @import("root").mm;
const x86 = @import("../x86.zig");
usingnamespace @import("root").lib;
pub var logger = @TypeOf(x86.logger).childOf(@typeName(@This())){};

pub const AoutSymbolTable = packed struct {
    tabsize: u32,
    strsize: u32,
    addr: u32,
    reserved: u32,
};

pub const ElfSectionHeaderTable = packed struct {
    num: u32,
    size: u32,
    addr: u32,
    shndx: u32,
};

pub const Info = packed struct {
    flags: u32,

    mem_lower: u32,
    mem_uppper: u32,

    boot_device: u32,

    cmdline: u32,

    mods_count: u32,
    mods_addr: u32,

    u: packed union {
        aout_sym: AoutSymbolTable,
        elf_sec: ElfSectionHeaderTable,
    },

    mmap_length: u32,
    mmap_addr: u32,

    drives_length: u32,
    drives_addr: u32,

    config_table: u32,

    boot_loader_name: u32,

    apm_table: u32,

    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
};

var stack: [2 * 0x1000]u8 align(0x10) = undefined;
pub var mb_phys: ?mm.PhysicalAddress = null;

export fn multiboot_entry(info: u32) callconv(.C) noreturn {
    mb_phys = mm.PhysicalAddress.new(info);
    @call(.{ .stack = stack[0..] }, x86.boot_entry, .{});
}

pub fn get_multiboot_memory() ?mm.PhysicalMemoryRange {
    if (mb_phys) |phys| {
        const mb = mm.directMapping().to_virt(phys);
        const info = mb.into_pointer(*x86.multiboot.Info);
        return detect_multiboot_memory(info);
    }
    return null;
}

fn detect_multiboot_memory(mb_info: *Info) ?mm.PhysicalMemoryRange {
    if (!bit_set(mb_info.flags, BIT(6))) {
        @panic("Missing memory map!");
    }

    const MemEntry = packed struct {
        // at -4 offset
        size: u32,
        // at 0 offset
        base_addr: u64,
        length: u64,
        type_: u32,
    };

    var best_slot: ?mm.PhysicalMemoryRange = null;

    var offset = mm.PhysicalAddress.new(mb_info.mmap_addr);
    const mmap_end = mm.PhysicalAddress.new(mb_info.mmap_addr + mb_info.mmap_length);

    logger.log("BIOS memory map:\n", .{});
    while (offset.lt(mmap_end)) {
        const entry = x86.mm.directMapping().to_virt(offset).into_pointer(*MemEntry);

        const start = entry.base_addr;
        const end = start + entry.length - 1;
        const status = switch (entry.type_) {
            1 => "Available",
            3 => "ACPI Mem",
            4 => "Preserved on hibernation",
            5 => "Defective",
            else => "Reserved",
        };
        logger.log("[{x:0>10}-{x:0>10}] {s}\n", .{ start, end, status });
        offset = offset.add(entry.size + @sizeOf(@TypeOf(entry.size)));

        if (entry.type_ != 1) {
            continue;
        }
        const this_slot = mm.PhysicalMemoryRange{
            .base = mm.PhysicalAddress.new(start),
            .size = entry.length,
        };

        if (best_slot) |slot| {
            if (this_slot.size > slot.size) {
                best_slot = this_slot;
            }
        } else {
            best_slot = this_slot;
        }
    }

    return best_slot;
}
