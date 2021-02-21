const std = @import("std");
const kernel = @import("root");
const x86 = @import("../x86.zig");

const elf = kernel.lib.elf;

var logger = @TypeOf(x86.logger).childOf(@typeName(@This())){};

const trampoline_elf = @embedFile("../../../build/x86_64/trampolines.o");

pub fn getTrampolineELF() []const u8 {
    return trampoline_elf;
}

pub fn get_nth_section(header: *const elf.Header, file: anytype, idx: u16) ?elf.Elf64_Shdr {
    var sec_it = header.section_header_iterator(file);

    var cnt: u16 = 0;
    while (true) : (cnt += 1) {
        var value = sec_it.next() catch @panic("xd");
        if (value == null) break;

        if (cnt == idx) {
            return value.?;
        }
    }
    return null;
}

pub fn getString(idx: u32) ?[]const u8 {
    var fbs = std.io.fixedBufferStream(trampoline_elf);
    const header = kernel.lib.elf.Header.read(&fbs) catch |err| {
        @panic("Invalid ELF header");
    };
    const section = find_section_by_name(&header, &fbs, ".strtab").?;

    const start = section.sh_offset;
    const end = start + section.sh_size;
    const section_data = trampoline_elf[start..end];

    const data = section_data[idx..];
    const null_pos = std.mem.indexOfScalar(u8, data, 0);
    if (null_pos) |finish| {
        return data[0..finish];
    }
    return null;
}

pub fn getSymbol(idx: u32) ?elf.Elf64_Sym {
    var fbs = std.io.fixedBufferStream(trampoline_elf);
    const header = kernel.lib.elf.Header.read(&fbs) catch |err| {
        @panic("Invalid ELF header");
    };
    const section = find_section_by_name(&header, &fbs, ".symtab").?;
    const section_data = init: {
        const start = section.sh_offset;
        const end = start + section.sh_size;
        break :init trampoline_elf[start..end];
    };

    const data = init: {
        const start = @sizeOf(elf.Elf64_Sym) * idx;
        const end = start + @sizeOf(elf.Elf64_Sym);
        break :init section_data[start..end];
    };

    var result: elf.Elf64_Sym = undefined;
    std.debug.assert(@sizeOf(elf.Elf64_Sym) == data.len);
    std.mem.copy(u8, std.mem.asBytes(&result), data);
    return result;
}

pub fn find_section_by_name(header: *const elf.Header, file: anytype, name: []const u8) ?elf.Elf64_Shdr {
    const name_sections = header.shstrndx;
    const section = get_nth_section(header, file, header.shstrndx).?;
    var buffer: [0x100]u8 = undefined;
    file.seekableStream().seekTo(section.sh_offset) catch unreachable;
    file.reader().readNoEof(&buffer) catch unreachable;
    var name_it = std.mem.split(buffer[0..section.sh_size], "\x00");

    var i: u16 = 0;
    while (true) : (i += 1) {
        const v = name_it.next();
        if (v) |sname| {
            if (std.mem.eql(u8, sname, name)) {
                return get_nth_section(header, file, i);
            }
        } else {
            break;
        }
    }
    return null;
}

pub fn getSectionByName(name: []const u8) ?elf.Elf64_Shdr {
    var fbs = std.io.fixedBufferStream(trampoline_elf);
    const header = kernel.lib.elf.Header.read(&fbs) catch |err| {
        @panic("Invalid ELF header");
    };
    return find_section_by_name(&header, &fbs, name);
}

pub fn getSectionData(name: []const u8) ?[]const u8 {
    const section = getSectionByName(name);
    if (section == null) return null;
    const start = section.?.sh_offset;
    const end = start + section.?.sh_size;
    return getTrampolineELF()[start..end];
}

pub fn init() void {
    logger.log("Initializing trampolines\n", .{});
}
