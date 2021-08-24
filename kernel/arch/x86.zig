const std = @import("std");
const assert = std.debug.assert;
pub usingnamespace @import("x86/asm.zig");

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

comptime {
    // Force multiboot evaluation to make multiboot_entry present
    _ = multiboot;
}

pub var logger = kernel.logging.logger("x86"){};

const GDT = gdt.GlobalDescriptorTable(8);
const IDT = InterruptDescriptorTable;

pub var main_gdt align(64) = GDT.new();
pub var main_tss align(64) = std.mem.zeroes(gdt.TSS);
pub var main_idt align(64) = std.mem.zeroes(IDT);

/// Physical-address width supported by the processor. <= 52
pub var cpu_phys_bits: u6 = undefined;

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

        pub fn new(addr: u64, code_selector: gdt.SegmentSelector, _: u3, dpl: u2) Entry {
            return .{
                .raw = .{
                    .reserved__ = 0,
                    .offset_low = @intCast(u16, addr & 0xffff),
                    .offset_high = @intCast(u32, addr >> 32),
                    .offset_mid = @intCast(u16, (addr >> 16) & 0xffff),
                    .ist = 0,
                    .type_attr = 0b10001110 | (@as(u8, dpl) << 5),
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
    kernel.kmain();

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
        : [ret] "={rax}" (-> u64)
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
                else => asm volatile (".byte 0x0"),
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

export fn hello_handler(interrupt_num: u8, error_code: u64, frame: *InterruptFrame) callconv(.C) void {
    _ = error_code;
    switch (interrupt_num) {
        @enumToInt(CpuException.Breakpoint) => {
            logger.log("BREAKPOINT\n", .{});
            logger.log("======================\n", .{});
            logger.log("{x}\n", .{frame});
            logger.log("======================\n", .{});
        },
        0x31 => {
            logger.log("{x}\n", .{frame});
            keyboard_echo();
        },
        @enumToInt(CpuException.GeneralProtectionFault) => {
            @panic("General Protection Fault");
        },
        @enumToInt(CpuException.PageFault) => {
            logger.log("#PF at {x}!\n", .{CR2.read()});
            hang();
        },
        else => {
            const ex = @intToEnum(CpuException, interrupt_num);
            logger.log("Received unknown interrupt {}\n", .{ex});
            logger.log("{x}\n", .{frame});
            hang();
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
    kernel.syscall_dispatch();
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
          [flags] "{r11}" (flags)
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
        const dpl: u2 = if (i == 3) 3 else 0;
        main_idt.set_entry(@intCast(u16, i), IDT.Entry.new(addr, kernel_code, 0, dpl));
    }

    main_idt.load();

    GSBASE.write(@ptrToInt(&boot_cpu_gsstruct));

    setup_syscall();

    //pic.remap(0x30, 0x38);
    //// enable only keyboard interrupt
    //pic.Master.data_write(0xfd);
    //pic.Slave.data_write(0xff);
}

pub fn init() void {
    framebuffer.init();
    trampoline.init();
    acpi.init();
    apic.init();
    pci.init();
    smp.init();
}
