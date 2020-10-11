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

pub fn MSR(n: u32) type {
    return struct {
        pub inline fn read() u64 {
            return rdmsr(n);
        }
        pub inline fn write(value: u64) void {
            wrmsr(n, value);
        }
    };
}

pub const APIC_BASE = MSR(0x0000_001B);
pub const EFER = MSR(0xC000_0080);
pub const LSTAR = MSR(0xC000_0082);

pub const FSBASE = MSR(0xC000_0100);
pub const GSBASE = MSR(0xC000_0101);
pub const KERNEL_GSBASE = MSR(0xC000_0102);
