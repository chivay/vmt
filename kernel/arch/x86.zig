const std = @import("std");
const assert = std.debug.assert;
usingnamespace @import("x86/asm.zig");

const kernel = @import("root");
const printk = kernel.printk;
pub const vga = @import("x86/vga.zig");
pub const serial = @import("x86/serial.zig");
pub const pic = @import("x86/pic.zig");
pub const keyboard = @import("x86/keyboard.zig");
pub const mm = @import("x86/mm.zig");
pub const multiboot = @import("x86/multiboot.zig");
pub const acpi = @import("x86/acpi.zig");

const GDT = GlobalDescriptorTable(8);
const IDT = InterruptDescriptorTable;

var main_gdt align(64) = GDT.new();
var main_tss align(64) = std.mem.zeroes(TSS);
var main_idt align(64) = std.mem.zeroes(IDT);

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

        pub fn new(addr: u64, code_selector: SegmentSelector, ist: u3) Entry {
            return .{
                .raw = .{
                    .reserved__ = 0,
                    .offset_low = @intCast(u16, addr & 0xffff),
                    .offset_high = @intCast(u32, addr >> 32),
                    .offset_mid = @intCast(u16, (addr >> 16) & 0xffff),
                    .ist = 0,
                    .type_attr = 0b10001110,
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
        const init = packed struct {
                size: u16,
                base: u64,
            }{
            .base = @ptrToInt(&self.entries),
            .size = @sizeOf(@TypeOf(self.entries)) - 1,
        };

        lidt(@ptrToInt(&init));
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
};

pub const TSS = packed struct {
    _reserved1: u32,
    rsp: [3]u64,
    _reserved2: u32,
    _reserved3: u32,
    ist: [8]u64,
    _reserved4: u16,
    io_map_addr: u16,
};

comptime {
    assert(@sizeOf(TSS) == 104);
}

pub const PrivilegeLevel = enum(u2) {
    Ring0 = 0,
    Ring3 = 3,
};

pub const SegmentSelector = struct {
    raw: u16,

    pub fn new(_index: u16, _rpl: PrivilegeLevel) SegmentSelector {
        return .{ .raw = _index << 3 | @enumToInt(_rpl) };
    }

    pub fn index(self: @This()) u16 {
        return self.raw >> 3;
    }

    pub fn rpl(self: @This()) SegmentSelector {
        return @intToEnum(PrivilegeLevel, self.raw & 0b11);
    }
};

pub fn GlobalDescriptorTable(n: u16) type {
    return packed struct {
        entries: [n]Entry align(0x10),
        free_slot: u16,

        pub const Entry = packed struct {
            raw: u64,

            const WRITABLE = 1 << 41;
            const CONFORMING = 1 << 42;
            const EXECUTABLE = 1 << 43;
            const USER = 1 << 44;
            const RING_3 = 3 << 45;
            const PRESENT = 1 << 47;
            const LONG_MODE = 1 << 53;
            const DEFAULT_SIZE = 1 << 54;
            const GRANULARITY = 1 << 55;

            const LIMIT_LO = 0xffff;
            const LIMIT_HI = 0xf << 48;

            const ORDINARY = USER | PRESENT | WRITABLE | LIMIT_LO | LIMIT_HI | GRANULARITY;

            pub const nil = Entry{ .raw = 0 };
            pub const KernelData = Entry{ .raw = ORDINARY | DEFAULT_SIZE };
            pub const KernelCode = Entry{ .raw = ORDINARY | EXECUTABLE | LONG_MODE };
            pub const UserCode = Entry{ .raw = KernelCode.raw | RING_3 };
            pub const UserData = Entry{ .raw = KernelData.raw | RING_3 };

            pub fn TaskState(tss: *TSS) [2]Entry {
                var high: u64 = 0;
                var ptr = @ptrToInt(tss) - 0xffffffff00000000;

                var low: u64 = 0;
                low |= PRESENT;
                // 64 bit available TSS;
                low |= 0b1001 << 40;
                // set limit
                low |= (@sizeOf(TSS) - 1) & 0xffff;

                // set pointer
                // 0..24 bits
                low |= (ptr & 0xffffff) << 16;

                // high bits part
                high |= (ptr & 0xffffffff00000000) >> 32;
                return [2]Entry{ .{ .raw = low }, .{ .raw = high } };
            }
        };

        const Self = @This();

        pub fn new() Self {
            var gdt = Self{ .entries = std.mem.zeroes([n]Entry), .free_slot = 0 };
            return gdt;
        }

        pub fn add_entry(self: *Self, entry: Entry) SegmentSelector {
            assert(self.free_slot < n);
            self.entries[self.free_slot] = entry;
            self.free_slot += 1;

            const dpl = @intToEnum(PrivilegeLevel, @intCast(u2, (entry.raw >> 45) & 0b11));
            return SegmentSelector.new(self.free_slot - 1, dpl);
        }

        pub fn load(self: Self) void {
            const init = packed struct {
                    size: u16,
                    base: u64,
                }{
                .base = @ptrToInt(&self.entries),
                .size = @sizeOf(@TypeOf(self.entries)) - 1,
            };

            lgdt(@ptrToInt(&init));
        }

        pub fn reload_cs(self: Self, selector: SegmentSelector) void {
            __reload_cs(selector.raw);
        }
    };
}

extern fn __reload_cs(selector: u32) void;
comptime {
    asm (
        \\ .global __reload_cs;
        \\ .type __reload_cs, @function;
        \\ __reload_cs:
        \\ pop %rsi
        \\ push %rdi
        \\ push %rsi
        \\ lretq
    );
}

pub fn get_vendor_string() [12]u8 {
    const info = cpuid(0, 0);
    const vals = [_]u32{ info.ebx, info.edx, info.ecx };

    var result: [@sizeOf(@TypeOf(vals))]u8 = undefined;
    std.mem.copy(u8, &result, std.mem.asBytes(&vals));
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

fn format_to_vga(buffer: []const u8) void {
    vga.getConsole().outStream().writeAll(buffer) catch |err| {};
}

fn format_to_com1(buffer: []const u8) void {
    serial.SerialPort(1).outStream().writeAll(buffer) catch |err| {};
}

const Node = kernel.printk_mod.SinkNode;

var vga_node = Node.init(format_to_vga);
var serial_node = Node.init(format_to_com1);

var kernel_image: *std.elf.Elf64_Ehdr = undefined;

extern var KERNEL_BASE: [*]align(0x1000) u8;
extern var KERNEL_VIRT_BASE: *align(0x1000) u8;

fn parse_kernel_image() void {
    const elf_hdr = kernel.mm.PhysicalAddress.new(@ptrToInt(&KERNEL_BASE));
    kernel_image = mm.identityMapping().to_virt(elf_hdr).into_pointer(*std.elf.Elf64_Ehdr);
}

var stack: [16 * 0x1000]u8 align(0x10) = undefined;

export fn multiboot_entry(mb_info: u32) callconv(.C) noreturn {
    @call(.{ .stack = stack[0..] }, mb_entry, .{mb_info});
}

fn mb_entry(mb_info: u32) callconv(.C) noreturn {
    kernel.printk_mod.register_sink(&vga_node);
    kernel.printk_mod.register_sink(&serial_node);

    // setup identity mapping
    const VIRT_START = kernel.mm.VirtualAddress.new(@ptrToInt(&KERNEL_VIRT_BASE));
    const SIZE = kernel.mm.MiB(16);
    mm.identityMapping().* = kernel.mm.IdentityMapping.init(VIRT_START, SIZE);

    // Initialize multiboot info pointer
    const mb_phys = kernel.mm.PhysicalAddress.new(mb_info);
    const mb = mm.identityMapping().to_virt(mb_phys);
    const info = mb.into_pointer(*multiboot.Info);
    multiboot.info_pointer = info;

    parse_kernel_image();

    printk("CR3: 0x{x}\n", .{CR3.read()});
    printk("CPU Vendor: {}\n", .{get_vendor_string()});
    printk("Kernel end: {x}\n", .{mm.get_kernel_end()});

    printk("Booting the kernel...\n", .{});

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

const InterruptStub = fn () callconv(.Naked) void;

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

/// Generate stub for n-th exception
fn exception_stub(comptime n: u8) InterruptStub {
    // Have to bump this, otherwise compilation fails
    @setEvalBranchQuota(2000);
    comptime var buffer = std.mem.zeroes([3]u8);
    comptime var l = std.fmt.formatIntBuf(buffer[0..], n, 10, false, std.fmt.FormatOptions{});

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
            asm volatile ("push $" ++ buffer);

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

export fn common_entry() callconv(.Naked) void {
    asm volatile (
        \\ push %%rax
        \\ push %%rcx
        \\ push %%rdx
        \\ push %%rdi
        \\ push %%rsi
        \\ push %%r8
        \\ push %%r9
        \\ push %%r10
        \\ push %%r11
    );
    // Stack layout:
    // [interrupt frame]
    // [error code]
    // [interrupt number]
    // [return address to stub]
    // [saved rax]
    // [saved rcx]
    // [saved rdx]
    // [saved rdi]
    // [saved rsi]
    // [saved  r8]
    // [saved  r9]
    // [saved r10]
    // [saved r11] <- rsp
    asm volatile (
        \\ xor %%edi, %%edi
        \\ movb 80(%%rsp), %%dil # load u8 interrupt number
        \\ movl 88(%%rsp), %%esi # load error code
        \\ lea 96(%%rsp), %%rdx
        \\ call hello_handler
    );
    asm volatile (
        \\ pop %%r11
        \\ pop %%r10
        \\ pop %%r9
        \\ pop %%r8
        \\ pop %%rsi
        \\ pop %%rdi
        \\ pop %%rdx
        \\ pop %%rcx
        \\ pop %%rax
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
    switch (interrupt_num) {
        // Breakpoint
        0x3 => {
            printk("BREAKPOINT\n", .{});
            printk("======================\n", .{});
            printk("{}\n", .{frame});
            printk("======================\n", .{});
        },
        0x31 => {
            printk("{x}\n", .{frame});
            keyboard_echo();
        },
        else => printk("Received unknown interrupt {}\n", .{interrupt_num}),
    }
}

var exception_stubs = init: {
    @setEvalBranchQuota(100000);
    var stubs: [256]InterruptStub = undefined;

    for (stubs) |*pt, i| {
        pt.* = exception_stub(i);
    }

    break :init stubs;
};

pub fn init_cpu() !void {
    const Entry = GDT.Entry;

    const null_entry = main_gdt.add_entry(Entry.nil);
    const kernel_code = main_gdt.add_entry(Entry.KernelCode);
    const kernel_data = main_gdt.add_entry(Entry.KernelData);
    const user_code = main_gdt.add_entry(Entry.UserCode);
    const user_data = main_gdt.add_entry(Entry.UserData);

    // Kinda ugly, refactor this
    //const tss_base = main_gdt.add_entry(Entry.TaskState(&main_tss)[0]);
    //_ = main_gdt.add_entry(Entry.TaskState(&main_tss)[1]);

    main_gdt.load();

    set_ds(null_entry.raw);
    set_es(null_entry.raw);
    set_fs(null_entry.raw);
    set_gs(null_entry.raw);
    set_ss(kernel_data.raw);

    main_gdt.reload_cs(kernel_code);

    //x86.ltr(tss_base.raw);

    for (exception_stubs) |ptr, i| {
        const addr: u64 = @ptrToInt(ptr);
        main_idt.set_entry(@intCast(u16, i), IDT.Entry.new(addr, kernel_code, 0));
    }

    main_idt.load();

    pic.remap(0x30, 0x38);
    // enable only keyboard interrupt
    pic.Master.data_write(0xfd);
    pic.Slave.data_write(0xff);
}
