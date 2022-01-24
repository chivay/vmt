const std = @import("std");
const assert = std.debug.assert;

const kernel = @import("root");
const lib = kernel.lib;

pub const vga = @import("x86/vga.zig");
pub const serial = @import("x86/serial.zig");
pub const pic = @import("x86/pic.zig");
pub const keyboard = @import("x86/keyboard.zig");
pub const mm = @import("x86/mm.zig");
pub const multiboot = @import("x86/multiboot.zig");
pub const acpi = @import("x86/acpi.zig");
pub const pci = @import("x86/pci.zig");
pub const apic = @import("x86/apic.zig");
pub const trampoline = @import("x86/trampoline.zig");
pub const smp = @import("x86/smp.zig");
pub const gdt = @import("x86/gdt.zig");
pub const framebuffer = @import("x86/framebuffer.zig");
pub const pit = @import("x86/pit.zig");
pub const timer = @import("x86/timer.zig");

comptime {
    // Force multiboot evaluation to make multiboot_entry present
    _ = multiboot;
}

pub const logger = @TypeOf(kernel.logger).childOf(@typeName(@This())){};

const GDT = gdt.GlobalDescriptorTable(8);
const IDT = InterruptDescriptorTable;

pub var main_gdt align(64) = GDT.new();
pub var main_tss align(64) = std.mem.zeroes(gdt.TSS);
pub var main_idt align(64) = std.mem.zeroes(IDT);

/// Physical-address width supported by the processor. <= 52
pub var cpu_phys_bits: u6 = undefined;

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

pub inline fn cpuid(leaf: u32, subleaf: u32) CPUIDInfo {
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
          [info] "r" (&info),
        : "eax", "ebx", "ecx", "edx", "m"
    );

    return info;
}

pub const CR3 = struct {
    pub inline fn read() u64 {
        return asm volatile ("movq %%cr3, %[ret]"
            : [ret] "=rax" (-> u64),
        );
    }

    pub inline fn write(value: u64) void {
        asm volatile ("movq %[value], %%cr3"
            :
            : [value] "{rax}" (value),
        );
    }
};

pub const CR2 = struct {
    pub inline fn read() u64 {
        return asm volatile ("movq %%cr2, %[ret]"
            : [ret] "=rax" (-> u64),
        );
    }
};

pub inline fn ltr(selector: u16) void {
    asm volatile ("ltr %[selector]"
        :
        : [selector] "{ax}" (selector),
    );
}

pub inline fn lgdt(addr: u64) void {
    asm volatile ("lgdt (%[addr])"
        :
        : [addr] "{rdi}" (addr),
    );
}

pub inline fn out(comptime T: type, address: u16, value: T) void {
    switch (T) {
        u8 => asm volatile ("out %[value], %[address]"
            :
            : [address] "{dx}" (address),
              [value] "{al}" (value),
        ),
        u16 => asm volatile ("out %[value], %[address]"
            :
            : [address] "{dx}" (address),
              [value] "{ax}" (value),
        ),
        u32 => asm volatile ("out %[value], %[address]"
            :
            : [address] "dx" (address),
              [value] "{eax}" (value),
        ),
        else => @compileError("Invalid write type"),
    }
}

pub inline fn in(comptime T: type, address: u16) T {
    return switch (T) {
        u8 => asm volatile ("in %[address], %[ret]"
            : [ret] "={al}" (-> u8),
            : [address] "{dx}" (address),
        ),
        u16 => asm volatile ("in %[address], %%ax"
            : [ret] "={ax}" (-> u16),
            : [address] "{dx}" (address),
        ),
        u32 => asm volatile ("in %[address], %%eax"
            : [ret] "={ax}" (-> u32),
            : [address] "dx" (address),
        ),
        else => @compileError("Invalid read type"),
    };
}

pub inline fn bochs_breakpoint() void {
    asm volatile ("xchgw %%bx, %%bx");
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

pub inline fn lidt(addr: u64) void {
    asm volatile ("lidt (%[addr])"
        :
        : [addr] "{rdi}" (addr),
    );
}

pub inline fn set_ds(selector: u16) void {
    asm volatile ("movl %[selector], %%ds"
        :
        : [selector] "{eax}" (selector),
    );
}

pub inline fn set_es(selector: u16) void {
    asm volatile ("movl %[selector], %%es"
        :
        : [selector] "{eax}" (selector),
    );
}

pub inline fn set_fs(selector: u16) void {
    asm volatile ("movl %[selector], %%fs"
        :
        : [selector] "{eax}" (selector),
    );
}

pub inline fn set_gs(selector: u16) void {
    asm volatile ("movl %[selector], %%gs"
        :
        : [selector] "{eax}" (selector),
    );
}

pub inline fn set_ss(selector: u16) void {
    asm volatile ("movl %[selector], %%ss"
        :
        : [selector] "{eax}" (selector),
    );
}

pub inline fn rdtsc() u64 {
    return asm volatile (
        \\ rdtsc
        \\ # results are in EDX:EAX
        \\ shl $32, %%rdx
        \\ or %%rdx, %%rax
        : [ret] "={rax}" (-> u64),
        :
        : "rdx"
    );
}

pub inline fn rdmsr(which: u32) u64 {
    return asm volatile (
        \\ rdmsr
        \\ # results are in EDX:EAX
        \\ shl $32, %%rdx
        \\ or %%rdx, %%rax
        : [ret] "={rax}" (-> u64),
        : [which] "{ecx}" (which),
        : "rdx"
    );
}

pub inline fn wrmsr(which: u32, value: u64) void {
    return asm volatile ("wrmsr"
        :
        : [high] "{edx}" (value >> 32),
          [low] "{eax}" (@truncate(u32, value)),
          [which] "{ecx}" (which),
    );
}

// This subsection discusses usage of each register. Registers %rbp, %rbx and
// %r12 through %r15 “belong” to the calling function and the called function is
// required to preserve their values
pub extern fn asm_switch_task(from: *TaskRegs, to: *TaskRegs) callconv(.C) void;
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

pub inline fn get_phy_mask() u64 {
    const one: u64 = 1;
    return @shlExact(one, cpu_phys_bits) - 1;
}

pub const TaskRegs = packed struct {
    // Layout must be kept in sync with asm_switch_stack
    rsp: u64,
    stack_bottom: u64,

    const Self = @This();

    pub fn setup(func: fn () noreturn, thread_stack: []u8) TaskRegs {
        // 7 == #saved registers + return address
        const reg_area_size = @sizeOf(u64) * 7;
        var reg_area = thread_stack[thread_stack.len - reg_area_size ..];
        var rip_area = reg_area[6 * @sizeOf(u64) ..];
        std.mem.set(u8, reg_area, 0);
        std.mem.writeIntNative(u64, @ptrCast(*[8]u8, rip_area), @ptrToInt(func));
        return TaskRegs{ .rsp = @ptrToInt(reg_area.ptr), .stack_bottom = @ptrToInt(reg_area.ptr) };
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, stream: anytype) !void {
        _ = fmt;
        try stream.writeAll(@typeName(Self));
        try stream.writeAll("{rsp=0x");
        try std.fmt.formatInt(self.rsp, 16, .lower, options, stream);
        try stream.writeAll("}");
    }
};

pub const InterruptDescriptorTable = packed struct {
    entries: [256]Entry,

    pub const Entry = packed struct {
        raw: packed struct {
            offset_low: u16,
            selector: u16,
            ist: u8,
            type_attr: u8,
            offset_mid: u16,
            offset_high: u32,
            reserved__: u32,
        },
        comptime {
            assert(@sizeOf(@This()) == 16);
        }

        pub fn new(addr: u64, code_selector: gdt.SegmentSelector, _: u3, dpl: gdt.PrivilegeLevel) Entry {
            return .{
                .raw = .{
                    .reserved__ = 0,
                    .offset_low = @intCast(u16, addr & 0xffff),
                    .offset_high = @intCast(u32, addr >> 32),
                    .offset_mid = @intCast(u16, (addr >> 16) & 0xffff),
                    .ist = 0,
                    .type_attr = 0b10001110 | (@as(u8, @enumToInt(dpl)) << 5),
                    .selector = code_selector.raw,
                },
            };
        }
    };

    const Self = @This();

    pub fn set_entry(self: *Self, which: u16, entry: Entry) void {
        self.entries[which] = entry;
    }

    pub fn load(self: Self) void {
        const descriptor = packed struct {
            size: u16,
            base: u64,
        }{
            .base = @ptrToInt(&self.entries),
            .size = @sizeOf(@TypeOf(self.entries)) - 1,
        };

        lidt(@ptrToInt(&descriptor));
    }
};

pub const InterruptFrame = packed struct {
    rip: u64,
    cs: u64,
    flags: u64,
    rsp: u64,
    ss: u64,

    comptime {
        assert(@sizeOf(InterruptFrame) == 40);
    }

    pub fn format(
        self: InterruptFrame,
        fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        _ = try writer.write("InterruptFrame{");
        _ = try writer.print("rip={x}:{x}", .{ self.cs, self.rip });
        _ = try writer.print(" rsp={x}:{x}", .{ self.ss, self.rsp });
        _ = try writer.write("}");
    }
};

pub fn get_vendor_string() [12]u8 {
    const info = cpuid(0, 0);
    const vals = [_]u32{ info.ebx, info.edx, info.ecx };

    var result: [@sizeOf(@TypeOf(vals))]u8 = undefined;
    std.mem.copy(u8, &result, std.mem.asBytes(&vals));
    return result;
}

pub fn get_maxphyaddr() u6 {
    const info = cpuid(0x80000008, 0);
    return @truncate(u6, info.eax);
}
pub fn hang() noreturn {
    while (true) {
        cli();
        hlt();
    }
}

pub fn syscall_supported() bool {
    const info = cpuid(0x80000001, 0);
    return ((info.edx >> 11) & 1) != 0;
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

pub const IA32_TSC_DEADLINE = MSR(0x6E0);
pub const APIC_BASE = MSR(0x0000_001B);
pub const EFER = MSR(0xC000_0080);
pub const IA32_STAR = MSR(0xC000_0081);
pub const IA32_LSTAR = MSR(0xC000_0082);

pub const FSBASE = MSR(0xC000_0100);
pub const GSBASE = MSR(0xC000_0101);
pub const KERNEL_GSBASE = MSR(0xC000_0102);

fn format_to_vga(buffer: []const u8) void {
    vga.getConsole().writer().writeAll(buffer) catch {};
}

fn format_to_com1(buffer: []const u8) void {
    serial.SerialPort(1).writer().writeAll(buffer) catch {};
}

const Node = kernel.logging.SinkNode;

var vga_node = Node{ .data = format_to_vga };
var serial_node = Node{ .data = format_to_com1 };

pub const KERNEL_STACK_SIZE = 1 * 0x1000;

extern var KERNEL_BASE: [*]align(0x1000) u8;
extern var KERNEL_VIRT_BASE: *align(0x1000) u8;
pub var stack: [KERNEL_STACK_SIZE * 2]u8 align(0x10) = undefined;

pub fn boot_entry() noreturn {
    kernel.logging.register_sink(&vga_node);
    kernel.logging.register_sink(&serial_node);

    kernel.task.init_task.regs.rsp = 0x2137;
    kernel.task.init_task.regs.stack_bottom = @ptrToInt(&stack) + stack.len;
    kernel.task.init_task.stack = &stack;

    // setup identity mapping
    const VIRT_START = kernel.mm.VirtualAddress.new(@ptrToInt(&KERNEL_VIRT_BASE));
    const SIZE = lib.MiB(16);
    mm.directMapping().* = kernel.mm.DirectMapping.init(VIRT_START, SIZE);

    logger.debug("CR3: 0x{x}\n", .{CR3.read()});
    logger.info("CPU Vendor: {e}\n", .{std.fmt.fmtSliceEscapeLower(&get_vendor_string())});
    logger.debug("Kernel end: {x}\n", .{mm.get_kernel_end()});

    logger.info("Booting the kernel...\n", .{});
    logger.info("Command line: {s}\n", .{multiboot.get_cmdline()});
    kernel.main.kmain();

    hang();
}

pub fn idle() void {
    while (true) {
        hlt();
    }
}

pub fn enable_interrupts() void {
    sti();
}

pub fn disable_interrupts() void {
    cli();
}

const userspace_location = 0x1337000;

pub fn setup_userspace() !void {
    const frame = try kernel.mm.frameAllocator().alloc_zero_frame();
    _ = try kernel.mm.kernel_vm.map_memory(
        kernel.mm.VirtualAddress.new(userspace_location),
        frame,
        0x1000,
        kernel.mm.VirtualMemory.Protection{
            .read = true,
            .write = true,
            .execute = true,
            .user = true,
        },
    );
    const program =
        "\x90" ++ // nop
        "\x90" ++ // nop
        "\xcc" ++ // int3
        "\x66\x87\xdb" ++ // bochs breakpoint
        "\x0f\x05" ++ // syscall
        "\xeb\xfc" // jmp to syscall
    ;
    std.mem.copy(u8, @intToPtr([*]u8, userspace_location)[0..0x1000], program);
}

pub fn enter_userspace() void {
    exit_to_userspace(userspace_location, 0x0);
}

const InterruptStub = fn () callconv(.Naked) void;

const CpuException = enum(u8) {
    DivisionByZero = 0,
    Debug = 1,
    NonMaskableInterrupt = 2,
    Breakpoint = 3,
    Overflow = 4,
    BoundRangeExceeded = 5,
    InvalidOpcode = 6,
    DeviceNotAvailable = 7,
    DoubleFault = 8,
    CoprocessorSegmentOverrun = 9,
    InvalidTSS = 10,
    SegmentNotPresent = 11,
    StackSegmentFault = 12,
    GeneralProtectionFault = 13,
    PageFault = 14,
    X87FloatingPointException = 16,
    AlignmentCheck = 17,
    MachineCheck = 18,
    SIMDFloatingPointException = 19,
    VirtualizationException = 20,
    SecurityException = 30,
    _,
};

fn has_error_code(vector: u16) bool {
    return switch (vector) {
        // Double Fault
        0x8 => true,
        // Invalid TSS
        // Segment not present
        // SS fault
        // GP fault
        // Page fault
        0xa...0xe => true,

        // Alignment check
        0x11 => true,

        // Security exception
        0x1e => true,
        else => false,
    };
}

pub const IntHandler = fn (u8, u64, *InterruptFrame) callconv(.C) void;

pub const CoreBlock = struct {
    current_task: *kernel.task.Task,
};

var initial_core_block: CoreBlock = CoreBlock{
    .current_task = &kernel.task.init_task,
};

pub const GSStruct = packed struct {
    cb: *CoreBlock,
    scratch_space: u64,
};

var boot_cpu_gsstruct: GSStruct = GSStruct{
    .cb = &initial_core_block,
    .scratch_space = 0,
};

pub inline fn getCoreBlock() *CoreBlock {
    const blockptr = asm volatile ("mov %%gs:0x0,%[ret]"
        : [ret] "={rax}" (-> u64),
    );
    return @intToPtr(*CoreBlock, blockptr);
}

/// Generate stub for n-th exception
fn exception_stub(comptime n: u8) InterruptStub {
    // Have to bump this, otherwise compilation fails
    @setEvalBranchQuota(2000);
    comptime var buffer = std.mem.zeroes([3]u8);
    _ = std.fmt.formatIntBuf(buffer[0..], n, 10, .lower, std.fmt.FormatOptions{});

    // Can I return function directly?
    return struct {
        pub fn f() callconv(.Naked) noreturn {
            // Clear direction flag
            asm volatile ("cld");

            // Push fake error code
            if (comptime !has_error_code(n)) {
                asm volatile ("push $0");
            }

            // Push interrupt number
            asm volatile (".byte 0x6a");
            switch (n) {
                0 => asm volatile (".byte 0x0"),
                1 => asm volatile (".byte 0x1"),
                2 => asm volatile (".byte 0x2"),
                3 => asm volatile (".byte 0x3"),
                4 => asm volatile (".byte 0x4"),
                5 => asm volatile (".byte 0x5"),
                6 => asm volatile (".byte 0x6"),
                7 => asm volatile (".byte 0x7"),
                8 => asm volatile (".byte 0x8"),
                9 => asm volatile (".byte 0x9"),
                10 => asm volatile (".byte 0xa"),
                11 => asm volatile (".byte 0xb"),
                12 => asm volatile (".byte 0xc"),
                13 => asm volatile (".byte 0xd"),
                14 => asm volatile (".byte 0xe"),
                15 => asm volatile (".byte 0xf"),
                16 => asm volatile (".byte 0x10"),
                17 => asm volatile (".byte 0x11"),
                18 => asm volatile (".byte 0x12"),
                19 => asm volatile (".byte 0x13"),
                20 => asm volatile (".byte 0x14"),
                21 => asm volatile (".byte 0x15"),
                22 => asm volatile (".byte 0x16"),
                23 => asm volatile (".byte 0x17"),
                24 => asm volatile (".byte 0x18"),
                25 => asm volatile (".byte 0x19"),
                26 => asm volatile (".byte 0x1a"),
                27 => asm volatile (".byte 0x1b"),
                28 => asm volatile (".byte 0x1c"),
                29 => asm volatile (".byte 0x1d"),
                30 => asm volatile (".byte 0x1e"),
                31 => asm volatile (".byte 0x1f"),
                32 => asm volatile (".byte 0x20"),
                33 => asm volatile (".byte 0x21"),
                34 => asm volatile (".byte 0x22"),
                35 => asm volatile (".byte 0x23"),
                36 => asm volatile (".byte 0x24"),
                37 => asm volatile (".byte 0x25"),
                38 => asm volatile (".byte 0x26"),
                39 => asm volatile (".byte 0x27"),
                40 => asm volatile (".byte 0x28"),
                41 => asm volatile (".byte 0x29"),
                42 => asm volatile (".byte 0x2a"),
                43 => asm volatile (".byte 0x2b"),
                44 => asm volatile (".byte 0x2c"),
                45 => asm volatile (".byte 0x2d"),
                46 => asm volatile (".byte 0x2e"),
                47 => asm volatile (".byte 0x2f"),
                48 => asm volatile (".byte 0x30"),
                49 => asm volatile (".byte 0x31"),
                50 => asm volatile (".byte 0x32"),
                51 => asm volatile (".byte 0x33"),
                52 => asm volatile (".byte 0x34"),
                53 => asm volatile (".byte 0x35"),
                54 => asm volatile (".byte 0x36"),
                55 => asm volatile (".byte 0x37"),
                56 => asm volatile (".byte 0x38"),
                57 => asm volatile (".byte 0x39"),
                58 => asm volatile (".byte 0x3a"),
                59 => asm volatile (".byte 0x3b"),
                60 => asm volatile (".byte 0x3c"),
                61 => asm volatile (".byte 0x3d"),
                62 => asm volatile (".byte 0x3e"),
                63 => asm volatile (".byte 0x3f"),
                64 => asm volatile (".byte 0x40"),
                65 => asm volatile (".byte 0x41"),
                66 => asm volatile (".byte 0x42"),
                67 => asm volatile (".byte 0x43"),
                68 => asm volatile (".byte 0x44"),
                69 => asm volatile (".byte 0x45"),
                70 => asm volatile (".byte 0x46"),
                71 => asm volatile (".byte 0x47"),
                72 => asm volatile (".byte 0x48"),
                73 => asm volatile (".byte 0x49"),
                74 => asm volatile (".byte 0x4a"),
                75 => asm volatile (".byte 0x4b"),
                76 => asm volatile (".byte 0x4c"),
                77 => asm volatile (".byte 0x4d"),
                78 => asm volatile (".byte 0x4e"),
                79 => asm volatile (".byte 0x4f"),
                80 => asm volatile (".byte 0x50"),
                81 => asm volatile (".byte 0x51"),
                82 => asm volatile (".byte 0x52"),
                83 => asm volatile (".byte 0x53"),
                84 => asm volatile (".byte 0x54"),
                85 => asm volatile (".byte 0x55"),
                86 => asm volatile (".byte 0x56"),
                87 => asm volatile (".byte 0x57"),
                88 => asm volatile (".byte 0x58"),
                89 => asm volatile (".byte 0x59"),
                90 => asm volatile (".byte 0x5a"),
                91 => asm volatile (".byte 0x5b"),
                92 => asm volatile (".byte 0x5c"),
                93 => asm volatile (".byte 0x5d"),
                94 => asm volatile (".byte 0x5e"),
                95 => asm volatile (".byte 0x5f"),
                96 => asm volatile (".byte 0x60"),
                97 => asm volatile (".byte 0x61"),
                98 => asm volatile (".byte 0x62"),
                99 => asm volatile (".byte 0x63"),
                100 => asm volatile (".byte 0x64"),
                101 => asm volatile (".byte 0x65"),
                102 => asm volatile (".byte 0x66"),
                103 => asm volatile (".byte 0x67"),
                104 => asm volatile (".byte 0x68"),
                105 => asm volatile (".byte 0x69"),
                106 => asm volatile (".byte 0x6a"),
                107 => asm volatile (".byte 0x6b"),
                108 => asm volatile (".byte 0x6c"),
                109 => asm volatile (".byte 0x6d"),
                110 => asm volatile (".byte 0x6e"),
                111 => asm volatile (".byte 0x6f"),
                112 => asm volatile (".byte 0x70"),
                113 => asm volatile (".byte 0x71"),
                114 => asm volatile (".byte 0x72"),
                115 => asm volatile (".byte 0x73"),
                116 => asm volatile (".byte 0x74"),
                117 => asm volatile (".byte 0x75"),
                118 => asm volatile (".byte 0x76"),
                119 => asm volatile (".byte 0x77"),
                120 => asm volatile (".byte 0x78"),
                121 => asm volatile (".byte 0x79"),
                122 => asm volatile (".byte 0x7a"),
                123 => asm volatile (".byte 0x7b"),
                124 => asm volatile (".byte 0x7c"),
                125 => asm volatile (".byte 0x7d"),
                126 => asm volatile (".byte 0x7e"),
                127 => asm volatile (".byte 0x7f"),
                128 => asm volatile (".byte 0x80"),
                129 => asm volatile (".byte 0x81"),
                130 => asm volatile (".byte 0x82"),
                131 => asm volatile (".byte 0x83"),
                132 => asm volatile (".byte 0x84"),
                133 => asm volatile (".byte 0x85"),
                134 => asm volatile (".byte 0x86"),
                135 => asm volatile (".byte 0x87"),
                136 => asm volatile (".byte 0x88"),
                137 => asm volatile (".byte 0x89"),
                138 => asm volatile (".byte 0x8a"),
                139 => asm volatile (".byte 0x8b"),
                140 => asm volatile (".byte 0x8c"),
                141 => asm volatile (".byte 0x8d"),
                142 => asm volatile (".byte 0x8e"),
                143 => asm volatile (".byte 0x8f"),
                144 => asm volatile (".byte 0x90"),
                145 => asm volatile (".byte 0x91"),
                146 => asm volatile (".byte 0x92"),
                147 => asm volatile (".byte 0x93"),
                148 => asm volatile (".byte 0x94"),
                149 => asm volatile (".byte 0x95"),
                150 => asm volatile (".byte 0x96"),
                151 => asm volatile (".byte 0x97"),
                152 => asm volatile (".byte 0x98"),
                153 => asm volatile (".byte 0x99"),
                154 => asm volatile (".byte 0x9a"),
                155 => asm volatile (".byte 0x9b"),
                156 => asm volatile (".byte 0x9c"),
                157 => asm volatile (".byte 0x9d"),
                158 => asm volatile (".byte 0x9e"),
                159 => asm volatile (".byte 0x9f"),
                160 => asm volatile (".byte 0xa0"),
                161 => asm volatile (".byte 0xa1"),
                162 => asm volatile (".byte 0xa2"),
                163 => asm volatile (".byte 0xa3"),
                164 => asm volatile (".byte 0xa4"),
                165 => asm volatile (".byte 0xa5"),
                166 => asm volatile (".byte 0xa6"),
                167 => asm volatile (".byte 0xa7"),
                168 => asm volatile (".byte 0xa8"),
                169 => asm volatile (".byte 0xa9"),
                170 => asm volatile (".byte 0xaa"),
                171 => asm volatile (".byte 0xab"),
                172 => asm volatile (".byte 0xac"),
                173 => asm volatile (".byte 0xad"),
                174 => asm volatile (".byte 0xae"),
                175 => asm volatile (".byte 0xaf"),
                176 => asm volatile (".byte 0xb0"),
                177 => asm volatile (".byte 0xb1"),
                178 => asm volatile (".byte 0xb2"),
                179 => asm volatile (".byte 0xb3"),
                180 => asm volatile (".byte 0xb4"),
                181 => asm volatile (".byte 0xb5"),
                182 => asm volatile (".byte 0xb6"),
                183 => asm volatile (".byte 0xb7"),
                184 => asm volatile (".byte 0xb8"),
                185 => asm volatile (".byte 0xb9"),
                186 => asm volatile (".byte 0xba"),
                187 => asm volatile (".byte 0xbb"),
                188 => asm volatile (".byte 0xbc"),
                189 => asm volatile (".byte 0xbd"),
                190 => asm volatile (".byte 0xbe"),
                191 => asm volatile (".byte 0xbf"),
                192 => asm volatile (".byte 0xc0"),
                193 => asm volatile (".byte 0xc1"),
                194 => asm volatile (".byte 0xc2"),
                195 => asm volatile (".byte 0xc3"),
                196 => asm volatile (".byte 0xc4"),
                197 => asm volatile (".byte 0xc5"),
                198 => asm volatile (".byte 0xc6"),
                199 => asm volatile (".byte 0xc7"),
                200 => asm volatile (".byte 0xc8"),
                201 => asm volatile (".byte 0xc9"),
                202 => asm volatile (".byte 0xca"),
                203 => asm volatile (".byte 0xcb"),
                204 => asm volatile (".byte 0xcc"),
                205 => asm volatile (".byte 0xcd"),
                206 => asm volatile (".byte 0xce"),
                207 => asm volatile (".byte 0xcf"),
                208 => asm volatile (".byte 0xd0"),
                209 => asm volatile (".byte 0xd1"),
                210 => asm volatile (".byte 0xd2"),
                211 => asm volatile (".byte 0xd3"),
                212 => asm volatile (".byte 0xd4"),
                213 => asm volatile (".byte 0xd5"),
                214 => asm volatile (".byte 0xd6"),
                215 => asm volatile (".byte 0xd7"),
                216 => asm volatile (".byte 0xd8"),
                217 => asm volatile (".byte 0xd9"),
                218 => asm volatile (".byte 0xda"),
                219 => asm volatile (".byte 0xdb"),
                220 => asm volatile (".byte 0xdc"),
                221 => asm volatile (".byte 0xdd"),
                222 => asm volatile (".byte 0xde"),
                223 => asm volatile (".byte 0xdf"),
                224 => asm volatile (".byte 0xe0"),
                225 => asm volatile (".byte 0xe1"),
                226 => asm volatile (".byte 0xe2"),
                227 => asm volatile (".byte 0xe3"),
                228 => asm volatile (".byte 0xe4"),
                229 => asm volatile (".byte 0xe5"),
                230 => asm volatile (".byte 0xe6"),
                231 => asm volatile (".byte 0xe7"),
                232 => asm volatile (".byte 0xe8"),
                233 => asm volatile (".byte 0xe9"),
                234 => asm volatile (".byte 0xea"),
                235 => asm volatile (".byte 0xeb"),
                236 => asm volatile (".byte 0xec"),
                237 => asm volatile (".byte 0xed"),
                238 => asm volatile (".byte 0xee"),
                239 => asm volatile (".byte 0xef"),
                240 => asm volatile (".byte 0xf0"),
                241 => asm volatile (".byte 0xf1"),
                242 => asm volatile (".byte 0xf2"),
                243 => asm volatile (".byte 0xf3"),
                244 => asm volatile (".byte 0xf4"),
                245 => asm volatile (".byte 0xf5"),
                246 => asm volatile (".byte 0xf6"),
                247 => asm volatile (".byte 0xf7"),
                248 => asm volatile (".byte 0xf8"),
                249 => asm volatile (".byte 0xf9"),
                250 => asm volatile (".byte 0xfa"),
                251 => asm volatile (".byte 0xfb"),
                252 => asm volatile (".byte 0xfc"),
                253 => asm volatile (".byte 0xfd"),
                254 => asm volatile (".byte 0xfe"),
                255 => asm volatile (".byte 0xff"),
            }

            // Call common interrupt entry
            asm volatile ("call common_entry");

            // Pop interrupt number and maybe error code
            asm volatile ("add $0x10, %%rsp");

            // Return from interrupt
            asm volatile ("iretq");
            unreachable;
        }
    }.f;
}

comptime {
    asm (
        \\.global common_entry;
        \\.type common_entry, @function;
        \\ common_entry:
        \\ push %rax
        \\ push %rcx
        \\ push %rdx
        \\ push %rdi
        \\ push %rsi
        \\ push %r8
        \\ push %r9
        \\ push %r10
        \\ push %r11
        \\ // Stack layout:
        \\ // [interrupt frame]
        \\ // [error code]
        \\ // [interrupt number]
        \\ // [return address to stub]
        \\ // [saved rax]
        \\ // [saved rcx]
        \\ // [saved rdx]
        \\ // [saved rdi]
        \\ // [saved rsi]
        \\ // [saved  r8]
        \\ // [saved  r9]
        \\ // [saved r10]
        \\ // [saved r11] <- rsp
        \\ xor %edi, %edi
        \\ movb 80(%rsp), %dil // load u8 interrupt number
        \\ movl 88(%rsp), %esi // load error code
        \\ lea 96(%rsp), %rdx
        \\ call hello_handler
        \\ pop %r11
        \\ pop %r10
        \\ pop %r9
        \\ pop %r8
        \\ pop %rsi
        \\ pop %rdi
        \\ pop %rdx
        \\ pop %rcx
        \\ pop %rax
        \\ ret
    );
}

fn keyboard_echo() void {
    const scancode = @intToEnum(keyboard.Scancode, in(u8, 0x60));
    if (scancode.to_ascii()) |c| {
        switch (c) {
            else => {},
        }
    }
    pic.Master.send_eoi();
}

pub const IrqRegistration = struct {
    func: fn () void,
    next: ?*IrqRegistration,

    pub fn new(func: fn () void) @This() {
        return .{ .func = func, .next = null };
    }
};

var handlers = [_]?*IrqRegistration{null} ** 256;

pub fn register_irq_handler(irq: u8, reg: *IrqRegistration) !void {
    if (handlers[irq]) |registration| {
        reg.next = registration;
        handlers[irq] = reg;
    }
    handlers[irq] = reg;
}

pub fn unregister_irq_handler(irq: u8, reg: *IrqRegistration) !void {
    var current = handlers[irq];
    if (current) |registration| {
        if (registration == reg) {
            handlers[irq] = reg.next;
            reg.next = null;
            return;
        }
    }

    while (current) |registation| {
        if (registation.next) |next_registration| {
            if (next_registration == reg) {
                registation.next = reg.next;
                reg.next = null;
                return;
            }
        }
    }
    @panic("Tried to unregister invalid registration");
}

fn handle_page_fault(addr: u64) void {
    logger.info("#PF at {x}\n", .{addr});
}

export fn hello_handler(interrupt_num: u8, error_code: u64, frame: *InterruptFrame) callconv(.C) void {
    _ = error_code;
    switch (interrupt_num) {
        @enumToInt(CpuException.Breakpoint) => {
            logger.log("BREAKPOINT\n", .{});
            logger.log("======================\n", .{});
            logger.log("{x}\n", .{frame});
            logger.log("======================\n", .{});
        },
        @enumToInt(CpuException.GeneralProtectionFault) => {
            @panic("General Protection Fault");
        },
        @enumToInt(CpuException.PageFault) => {
            logger.log("{}\n", .{frame});
            handle_page_fault(CR2.read());
        },
        0x20...0xff => {
            var handler = handlers[interrupt_num];
            if (handler == null) {
                logger.err("Received interrupt {}\n", .{interrupt_num});
                @panic("Unknown interrupt");
            }
            while (handler) |registration| {
                registration.func();
                handler = registration.next;
            }
        },
        else => {
            logger.err("Got exception: {}\n", .{interrupt_num});
            logger.err("{}\n", .{frame});
            @panic("Unhandled exception");
        },
    }
}

const exception_stubs = init: {
    @setEvalBranchQuota(100000);
    var stubs: [256]InterruptStub = undefined;

    for (stubs) |*pt, i| {
        pt.* = exception_stub(i);
    }

    break :init stubs;
};

pub fn switch_task(from: *kernel.task.Task, to: *kernel.task.Task) void {
    main_tss.rsp[0] = @ptrToInt(to.stack.ptr) + to.stack.len;
    asm_switch_task(&from.regs, &to.regs);
}

fn syscall_entry() callconv(.Naked) void {
    comptime {
        std.debug.assert(@offsetOf(kernel.task.Task, "regs") == 0);
        std.debug.assert(@offsetOf(TaskRegs, "stack_bottom") == 8);
    }
    asm volatile (
        \\ // Switch to kernel GS
        \\ swapgs
        \\ // Save userspace stack
        \\ mov %%rsp, %%gs:0x8
        \\ // Load kernel stack from task
        \\ mov %%gs:0x0, %%rsp // rsp == *CoreBlock
        \\ mov 0(%%rsp), %%rsp // rsp == *Task
        \\ mov 8(%%rsp), %%rsp // rsp == kernel_rsp
        \\ push %%rcx
        \\ push %%r11
        \\ call handle_syscall
        \\ pop %%r11
        \\ pop %%rcx
        \\ // Switch to user GS
        \\ swapgs
        \\ // Go back to userspace
        \\ sysretq
    );
}

comptime {
    asm (
        \\.global handle_syscall;
        \\.type handle_syscall, @function;
    );
}
export fn handle_syscall() callconv(.C) u64 {
    kernel.syscall.syscall_dispatch();
    return 0;
}

pub fn exit_to_userspace(rip: u64, rsp: u64) noreturn {
    const flags: u64 = 0;
    asm volatile (
        \\ swapgs
        \\ sysretq
        :
        : [rip] "{rcx}" (rip),
          [rsp] "{rsp}" (rsp),
          [flags] "{r11}" (flags),
    );
    unreachable;
}

fn setup_syscall() void {
    if (!syscall_supported()) {
        @panic("Syscall not supported");
    }

    EFER.write(EFER.read() | 1);

    main_tss.rsp[0] = @ptrToInt(&stack[0]) + stack.len;
    // Setup sysret instruction
    // Stack segment — IA32_STAR[63:48] + 8.
    // Target code segment — Reads a non-NULL selector from IA32_STAR[63:48] + 16.
    const sysret_selector = @as(u64, user_base.raw);
    const syscall_selector = @as(u64, null_entry.raw);
    IA32_STAR.write((sysret_selector << 48) | (syscall_selector << 32));
    IA32_LSTAR.write(@ptrToInt(syscall_entry));
}

pub var null_entry: gdt.SegmentSelector = undefined;
pub var kernel_code: gdt.SegmentSelector = undefined;
pub var kernel_data: gdt.SegmentSelector = undefined;
pub var user_base: gdt.SegmentSelector = undefined;
pub var user_code: gdt.SegmentSelector = undefined;
pub var user_data: gdt.SegmentSelector = undefined;

// Used by PIT
pub const IRQ_0 = 0x20;
// Used by APIC timer
pub const IRQ_1 = 0x21;
pub const IRQ_2 = 0x22;
pub const IRQ_3 = 0x23;
pub const IRQ_4 = 0x24;
pub const IRQ_5 = 0x25;
pub const IRQ_6 = 0x26;
pub const IRQ_7 = 0x27;
pub const IRQ_8 = 0x28;

pub fn init_cpu() !void {
    cpu_phys_bits = get_maxphyaddr();
    const Entry = GDT.Entry;

    null_entry = main_gdt.add_entry(Entry.nil);
    // kernel data must be just after code - required by syscall instruction
    kernel_data = main_gdt.add_entry(Entry.KernelData);
    kernel_code = main_gdt.add_entry(Entry.KernelCode);

    // user data must be just user code - required by syscall instruction
    user_base = main_gdt.add_entry(Entry.nil);
    user_data = main_gdt.add_entry(Entry.UserData);
    user_code = main_gdt.add_entry(Entry.UserCode);

    // Kinda ugly, refactor this
    logger.log("TSS is at {*}\n", .{&main_tss});
    const tss_base = main_gdt.add_entry(Entry.TaskState(&main_tss)[0]);
    _ = main_gdt.add_entry(Entry.TaskState(&main_tss)[1]);

    main_gdt.load();

    set_ds(null_entry.raw);
    set_es(null_entry.raw);
    set_fs(null_entry.raw);
    set_gs(null_entry.raw);
    set_ss(kernel_data.raw);

    main_gdt.reload_cs(kernel_code);

    ltr(tss_base.raw);

    for (exception_stubs) |ptr, i| {
        const addr: u64 = @ptrToInt(ptr);
        const dpl: gdt.PrivilegeLevel = switch (i) {
            @enumToInt(CpuException.Breakpoint) => .Ring3,
            else => .Ring0,
        };
        main_idt.set_entry(@intCast(u16, i), IDT.Entry.new(addr, kernel_code, 0, dpl));
    }

    main_idt.load();

    GSBASE.write(@ptrToInt(&boot_cpu_gsstruct));

    setup_syscall();
}

pub fn init() void {
    pic.init();
    framebuffer.init();
    pit.init();
    trampoline.init();
    acpi.init();
    apic.init();
    timer.init();
    pci.init();
    smp.init();
}
