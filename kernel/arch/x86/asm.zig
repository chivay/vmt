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

pub const CR3 = struct {
    pub inline fn read() u64 {
        return asm volatile ("movq %%cr3, %[ret]"
            : [ret] "=rax" (-> u64)
        );
    }

    pub inline fn write(value: u64) void {
        asm volatile ("movq %[value], %%cr3"
            :
            : [value] "{rax}" (value)
        );
    }
};

pub inline fn ltr(selector: u16) void {
    asm volatile ("ltr %[selector]"
        :
        : [selector] "{ax}" (selector)
    );
}

pub inline fn lgdt(addr: u64) void {
    asm volatile ("lgdt (%[addr])"
        :
        : [addr] "{rdi}" (addr)
    );
}

pub inline fn out(comptime T: type, address: u16, value: T) void {
    switch (T) {
        u8 => asm volatile ("out %[value], %[address]"
            :
            : [address] "{dx}" (address),
              [value] "{al}" (value)
        ),
        u16 => asm volatile ("out %[value], %[address]"
            :
            : [address] "{dx}" (address),
              [value] "{ax}" (value)
        ),
        u32 => asm volatile ("out %[value], %[address]"
            :
            : [address] "dx" (address),
              [value] "{eax}" (value)
        ),
        else => @compileError("Invalid write type"),
    }
}

pub inline fn in(comptime T: type, address: u16, value: T) T {
    switch (T) {
        u8 => asm volatile ("in %[address], %[ret]"
            : [ret] "={al}" (-> u8)
            : [address] "{dx}" (address)
        ),
        u16 => asm volatile ("in %[address], %%ax"
            : [ret] "={ax}" (-> u16)
            : [address] "{dx}" (address)
        ),
        u32 => asm volatile ("in %[address], %%eax"
            : [ret] "={ax}" (-> u32)
            : [address] "dx" (address)
        ),
        else => @compileError("Invalid read type"),
    }
}

pub inline fn hlt() void {
    asm volatile ("hlt");
}

pub inline fn cli() void {
    asm volatile ("cli");
}

pub inline fn sti() void {
    asm volatile ("sti");
}

pub inline fn set_ds(selector: u16) void {
    asm volatile ("movl %[selector], %%ds"
        :
        : [selector] "{eax}" (selector)
    );
}

pub inline fn set_es(selector: u16) void {
    asm volatile ("movl %[selector], %%es"
        :
        : [selector] "{eax}" (selector)
    );
}

pub inline fn set_fs(selector: u16) void {
    asm volatile ("movl %[selector], %%fs"
        :
        : [selector] "{eax}" (selector)
    );
}

pub inline fn set_gs(selector: u16) void {
    asm volatile ("movl %[selector], %%gs"
        :
        : [selector] "{eax}" (selector)
    );
}

pub inline fn set_ss(selector: u16) void {
    asm volatile ("movl %[selector], %%ss"
        :
        : [selector] "{eax}" (selector)
    );
}

pub inline fn rdmsr(which: u32) u64 {
    return asm volatile (
        \\ rdmsr
        \\ # results are in EDX:EAX
        \\ shl $32, %%rdx
        \\ or %%rdx, %%rax
        : [ret] "={rax}" (-> u64)
        : [which] "{ecx}" (which)
        : "rdx"
    );
}

pub inline fn wrmsr(which: u32, value: u64) void {
    return asm volatile ("wrmsr"
        :
        : [high] "{edx}" (value >> 32),
          [low] "{eax}" (@as(u32, value))
    );
}
