const x86 = @import("root").arch.x86;

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

pub fn cpuid(leaf: u32, subleaf: u32) callconv(.Inline) CPUIDInfo {
    var info: CPUIDInfo = undefined;
    asm volatile (
        \\ cpuid
        \\ movl %%eax, 0(%[info])
        \\ movl %%ebx, 4(%[info])
        \\ movl %%ecx, 8(%[info])
        \\ movl %%edx, 12(%[info])
        :
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
          [info] "r" (&info)
        : "eax", "ebx", "ecx", "edx", "m"
    );

    return info;
}

pub const CR3 = struct {
    pub fn read() callconv(.Inline) u64 {
        return asm volatile ("movq %%cr3, %[ret]"
            : [ret] "=rax" (-> u64)
        );
    }

    pub fn write(value: u64) callconv(.Inline) void {
        asm volatile ("movq %[value], %%cr3"
            :
            : [value] "{rax}" (value)
        );
    }
};

pub fn ltr(selector: u16) callconv(.Inline) void {
    asm volatile ("ltr %[selector]"
        :
        : [selector] "{ax}" (selector)
    );
}

pub fn lgdt(addr: u64) callconv(.Inline) void {
    asm volatile ("lgdt (%[addr])"
        :
        : [addr] "{rdi}" (addr)
    );
}

pub fn out(comptime T: type, address: u16, value: T) callconv(.Inline) void {
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

pub fn in(comptime T: type, address: u16) callconv(.Inline) T {
    return switch (T) {
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
    };
}

pub fn hlt() callconv(.Inline) void {
    asm volatile ("hlt");
}

pub fn cli() callconv(.Inline) void {
    asm volatile ("cli");
}

pub fn sti() callconv(.Inline) void {
    asm volatile ("sti");
}

pub fn lidt(addr: u64) callconv(.Inline) void {
    asm volatile ("lidt (%[addr])"
        :
        : [addr] "{rdi}" (addr)
    );
}

pub fn set_ds(selector: u16) callconv(.Inline) void {
    asm volatile ("movl %[selector], %%ds"
        :
        : [selector] "{eax}" (selector)
    );
}

pub fn set_es(selector: u16) callconv(.Inline) void {
    asm volatile ("movl %[selector], %%es"
        :
        : [selector] "{eax}" (selector)
    );
}

pub fn set_fs(selector: u16) callconv(.Inline) void {
    asm volatile ("movl %[selector], %%fs"
        :
        : [selector] "{eax}" (selector)
    );
}

pub fn set_gs(selector: u16) callconv(.Inline) void {
    asm volatile ("movl %[selector], %%gs"
        :
        : [selector] "{eax}" (selector)
    );
}

pub fn set_ss(selector: u16) callconv(.Inline) void {
    asm volatile ("movl %[selector], %%ss"
        :
        : [selector] "{eax}" (selector)
    );
}

pub fn rdmsr(which: u32) callconv(.Inline) u64 {
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

pub fn wrmsr(which: u32, value: u64) callconv(.Inline) void {
    return asm volatile ("wrmsr"
        :
        : [high] "{edx}" (value >> 32),
          [low] "{eax}" (@truncate(u32, value)),
          [which] "{ecx}" (which)
    );
}

// This subsection discusses usage of each register. Registers %rbp, %rbx and
// %r12 through %r15 “belong” to the calling function and the called function is
// required to preserve their values
pub extern fn asm_switch_task(from: *x86.TaskRegs, to: *x86.TaskRegs) callconv(.C) void;
comptime {
    asm (
        \\.type asm_switch_task @function;
        \\asm_switch_task:
        \\  # Save registers
        \\  push %rbp
        \\  push %rbx
        \\  push %r12
        \\  push %r13
        \\  push %r14
        \\  push %r15
        \\  # Switch stack
        \\  mov %rsp, 0(%rdi)
        \\  mov 0(%rsi), %rsp
        \\  # Restore registers
        \\  pop %r15
        \\  pop %r14
        \\  pop %r13
        \\  pop %r12
        \\  pop %rbx
        \\  pop %rbp
        \\  retq
    );
}
