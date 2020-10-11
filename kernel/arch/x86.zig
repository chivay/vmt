usingnamespace @import("x86/asm.zig");

const std = @import("std");
pub const vga = @import("x86/vga.zig");
pub const serial = @import("x86/serial.zig");

pub fn get_vendor_string() [12]u8 {
    const info = cpuid(0, 0);
    const vals = [_]u32{ info.ebx, info.edx, info.ecx };

    var result: [12]u8 = undefined;
    std.mem.copy(u8, result[0..], std.mem.sliceAsBytes(vals[0..]));
    return result;
}

pub fn hang() noreturn {
    while (true) {
        cli();
        hlt();
    }
}
