const std = @import("std");

pub const vga = @import("x86/vga.zig");

pub fn read_cr3() u64 {
    return asm volatile ("movq %%cr3, %[ret]"
        : [ret] "=rax" (-> u64)
    );
}

pub fn write_cr3(value: u64) void {
    asm volatile ("movq %%rax, %%cr3"
        :
        : [value] "{rax}" (value)
    );
}

pub fn out(comptime T: type, address: u16, value: T) void {
    switch (T) {
        u8 => asm volatile ("out %%al, %%dx"
            :
            : [address] "{dx}" (address),
              [value] "{al}" (value)
        ),
        u16 => asm volatile ("out %%ax, %%dx"
            :
            : [address] "{dx}" (address),
              [value] "{ax}" (value)
        ),
        u32 => asm volatile ("out %%eax, %%dx"
            :
            : [address] "dx" (address),
              [value] "{eax}" (value)
        ),
        else => @compileError("Invalid write type"),
    }
}

pub fn in(comptime T: type, address: u16, value: T) T {
    switch (T) {
        u8 => asm volatile ("in %%dx, %%al"
            : [ret] "={al}" (-> u8)
        ),
        u16 => asm volatile ("in %%dx, %%ax"
            : [ret] "={ax}" (-> u16)
        ),
        u32 => asm volatile ("in %%dx, %%eax"
            : [ret] "={ax}" (-> u32)
        ),
        else => @compileError("Invalid read type"),
    }
}

pub const CPUIDInfo = packed struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,

    fn to_bytes(self: @This()) [16]u8 {
        var output: [16]u8 = undefined;

        std.mem.copy(u8, output[0..4], std.mem.toBytes(self.eax)[0..]);
        std.mem.copy(u8, output[4..8], std.mem.toBytes(self.ebx)[0..]);
        std.mem.copy(u8, output[8..12], std.mem.toBytes(self.ecx)[0..]);
        std.mem.copy(u8, output[12..16], std.mem.toBytes(self.edx)[0..]);

        return output;
    }
};

comptime {
    asm (
        \\.type __cpuid @function;
        \\__cpuid:
        \\  mov %esi, %eax
        \\  mov %edx, %ecx
        \\  cpuid
        \\  mov %eax, 0(%rdi)
        \\  mov %ebx, 4(%rdi)
        \\  mov %ecx, 8(%rdi)
        \\  mov %edx, 12(%rdi)
        \\  retq 
    );
}

// Implicit C calling convention ?
extern fn __cpuid(
    info: *CPUIDInfo, // rdi
    leaf: u32, // esi
    subleaf: u32, // edx
) void;

pub fn cpuid(leaf: u32, subleaf: u32) CPUIDInfo {
    var info: CPUIDInfo = undefined;
    __cpuid(&info, leaf, subleaf);
    return info;
}

pub fn get_vendor_string() [12]u8 {
    const info = cpuid(0, 0);
    const vals = [_]u32{ info.ebx, info.edx, info.ecx };

    var result: [12]u8 = undefined;
    std.mem.copy(u8, result[0..], std.mem.sliceAsBytes(vals[0..]));
    return result;
}
