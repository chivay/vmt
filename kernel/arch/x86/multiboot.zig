const std = @import("std");
const mm = @import("root").mm;
const x86 = @import("../x86.zig");
const logging = @import("root").logging;
usingnamespace @import("root").lib;

pub var logger = logging.logger(@typeName(@This())){};

fn alignTo8(n: usize) usize {
    const mask = 0b111;
    return (n - 1 | mask) + 1;
}

pub const Arch = enum(u32) {
    I386 = 0,
    MIPS = 4,
};

pub const TagType = enum(u32) {
    End = 0,
    Cmdline = 1,
    BootLoaderName = 2,
    Module = 3,
    BasicMemInfo = 4,
    BootDev = 5,
    Mmap = 6,
    VBE = 7,
    Framebuffer = 8,
    ElfSections = 9,
    APM = 10,
    EFI32 = 11,
    EFI64 = 12,
    SMBIOS = 13,
    ACPIOld = 14,
    ACPINew = 15,
    Network = 16,
    EFIMMap = 17,
    EFIBootServices = 18,
    EFI32ImageHandle = 19,
    EFI64ImageHandle = 20,
    LoadBaseAddr = 21,
    _,

    pub fn v(self: @This()) u32 {
        return @enumToInt(self);
    }
};

const MULTIBOOT2_MAGIC = 0x36d76289;

comptime {
    std.debug.assert(@sizeOf(Header) == 16);
}

pub const Header = extern struct {
    magic: u32 align(1) = MAGIC,
    architecture: u32 align(1),
    header_length: u32 align(1),
    checksum: u32 align(1),

    const MAGIC = 0xE85250D6;
    pub const Tag = extern struct {
        typ: u16 align(1),
        flags: u16 align(1),
        size: u32 align(1),
    };

    pub fn init(arch: Arch, length: u32) Header {
        return .{
            .architecture = @enumToInt(arch),
            .header_length = length,
            .checksum = 0 -% (MAGIC + length + @enumToInt(arch)),
        };
    }

    pub const NilTag = extern struct {
        const field_size = @sizeOf(Tag);
        tag: Tag align(1) = .{
            .typ = 0,
            .flags = 0,
            .size = 8,
        },

        // Force 8-aligned struct size for each tag
        _pad: [alignTo8(field_size)]u8 align(1) = undefined,
    };

    pub fn InformationRequestTag(comptime n: u32) type {
        return extern struct {
            const field_size = @sizeOf(Tag) + @sizeOf([n]u32);
            tag: Tag = .{
                .typ = 1,
                .flags = 0,
                .size = @sizeOf(u32) * n + 8,
            },
            mbi_tag_types: [n]u32,

            _pad: [alignTo8(field_size)]u8 = std.mem.zeroes([alignTo8(field_size)]u8),
        };
    }

    pub const FramebufferTag = extern struct {
        const field_size = @sizeOf(Tag) + 3 * @sizeOf(u32);

        tag: Tag = .{
            .typ = 5,
            .flags = 0,
            .size = 20,
        },
        width: u32,
        height: u32,
        depth: u32,

        _pad: [alignTo8(field_size)]u8 = std.mem.zeroes([alignTo8(field_size)]u8),
    };
};

const info_request_tag = std.mem.toBytes(Header.InformationRequestTag(2){
    .mbi_tag_types = [_]u32{ TagType.Cmdline.v(), TagType.Framebuffer.v() },
});
const framebuffer_tag = std.mem.toBytes(Header.FramebufferTag{
    .width = 640,
    .height = 480,
    .depth = 8,
});
const nil_tag = std.mem.toBytes(Header.NilTag{});

const tag_buffer = info_request_tag ++ framebuffer_tag;

const total_size = @sizeOf(Header) + tag_buffer.len + nil_tag.len;
export const mbheader align(8) linksection(".multiboot") =
    std.mem.toBytes(Header.init(Arch.I386, total_size)) ++ tag_buffer ++ nil_tag;

const BootInfoStart = extern struct {
    total_size: u32 align(1),
    reserved: u32 align(1),
};

const BootInfoHeader = extern struct {
    typ: u32 align(1),
    size: u32 align(1),
};

pub var mb_phys: ?mm.PhysicalAddress = null;
pub var loader_magic: u32 = undefined;

export fn multiboot_entry(info: u32, magic: u32) callconv(.C) noreturn {
    mb_phys = mm.PhysicalAddress.new(info);
    loader_magic = magic;
    asm volatile (
        \\ jmp *%[target]
        :
        : [stack] "{rsp}" (@ptrToInt(&x86.stack) + @sizeOf(@TypeOf(x86.stack))),
          [target] "{rax}" (&x86.boot_entry),
    );
    unreachable;
    //@call(.{ .stack = x86.stack[0..] }, x86.boot_entry, .{});
}

fn get_multiboot_tag(tag: TagType) ?[]u8 {
    if (loader_magic != MULTIBOOT2_MAGIC) {
        @panic("Not booted by multiboot2 compliant bootloader");
    }

    if (mb_phys) |phys| {
        const mb = mm.directMapping().to_virt(phys);
        const size = mb.into_pointer(*BootInfoStart).total_size;

        // Skip BootInfoStart
        var buffer = mb.into_pointer([*]u8)[@sizeOf(BootInfoStart)..size];

        // Iterate over multiboot tags
        var header: *BootInfoHeader = undefined;
        while (buffer.len > @sizeOf(BootInfoHeader)) : (buffer = buffer[alignTo8(header.size)..]) {
            const chunk = buffer[0..@sizeOf(BootInfoHeader)];
            header = std.mem.bytesAsValue(BootInfoHeader, chunk);

            const tagt = @intToEnum(TagType, header.typ);
            if (tagt == tag) {
                return buffer[0..header.size];
            }
        }
    }
    return null;
}

pub fn get_multiboot_memory() ?mm.PhysicalMemoryRange {
    return detect_multiboot_memory();
}

pub fn get_cmdline() ?[]u8 {
    var buf: []u8 = get_multiboot_tag(.Cmdline) orelse return null;
    const CmdlineTag = packed struct {
        type: u32,
        size: u32,
    };
    buf = buf[@sizeOf(CmdlineTag)..];
    return buf;
}

pub const MultibootFramebuffer = packed struct {
    addr: u64,
    pitch: u32,
    width: u32,
    height: u32,
    bpp: u8,
    type: u8,
    reserved: u8,
};

pub fn get_framebuffer() ?*MultibootFramebuffer {
    var buf: []u8 = get_multiboot_tag(.Framebuffer) orelse return null;
    buf = buf[2 * @sizeOf(u32) ..];
    return std.mem.bytesAsValue(
        MultibootFramebuffer,
        buf[0..@sizeOf(MultibootFramebuffer)],
    );
}

fn detect_multiboot_memory() ?mm.PhysicalMemoryRange {
    const MemoryMapTag = packed struct {
        typ: u32,
        size: u32,
        entry_size: u32,
        entry_version: u32,
    };

    var buf: []u8 = get_multiboot_tag(.Mmap) orelse return null;
    const tag = std.mem.bytesAsValue(MemoryMapTag, buf[0..@sizeOf(MemoryMapTag)]);
    buf = buf[@sizeOf(MemoryMapTag)..];

    const MemEntry = packed struct {
        base_addr: u64,
        length: u64,
        type: u32,
        reserved: u32,
    };

    var best_slot: ?mm.PhysicalMemoryRange = null;

    logger.log("BIOS memory map:\n", .{});

    const entry_size = tag.entry_size;
    while (buf.len >= entry_size) : (buf = buf[entry_size..]) {
        const entry = std.mem.bytesAsValue(MemEntry, buf[0..@sizeOf(MemEntry)]);

        const start = entry.base_addr;
        const end = start + entry.length - 1;
        const status = switch (entry.type) {
            1 => "Available",
            3 => "ACPI Mem",
            4 => "Preserved on hibernation",
            5 => "Defective",
            else => "Reserved",
        };
        logger.log("[{x:0>10}-{x:0>10}] {s}\n", .{ start, end, status });

        if (entry.type != 1) {
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
