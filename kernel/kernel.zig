const x86 = @import("arch.zig").x86;
const std = @import("std");
const builtin = @import("builtin");

fn format_to_vga(comptime fmt: []const u8, args: var) void {
    x86.vga.getConsole().outStream().print(fmt, args) catch |err| {};
}

fn format_to_com1(comptime fmt: []const u8, args: var) void {
    x86.serial.SerialPort(1).outStream().print(fmt, args) catch |err| {};
}

pub fn printk(comptime fmt: []const u8, args: var) void {
    comptime var sinks = [_](fn ([]const u8, var) void){
        format_to_vga,
        format_to_com1,
    };

    inline for (sinks) |sink| {
        sink(fmt, args);
    }
}

const GDT = x86.GlobalDescriptorTable(8);
const IDT = x86.InterruptDescriptorTable;
const TSS = x86.TSS;

var main_gdt align(64) = GDT.new();
var main_tss align(64) = std.mem.zeroes(TSS);
var main_idt align(64) = std.mem.zeroes(IDT);

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

var exception_stubs = init: {
    @setEvalBranchQuota(100000);
    var stubs: [256]InterruptStub = undefined;

    for (stubs) |*pt, i| {
        pt.* = exception_stub(i);
    }

    break :init stubs;
};

fn keyboard_echo() void {
    const scancode = @intToEnum(x86.keyboard.Scancode, x86.in(u8, 0x60));
    if (scancode.to_ascii()) |c| {
        switch (c) {
            else => {},
        }
    }
    x86.pic.Master.send_eoi();
}

export fn hello_handler(interrupt_num: u8, error_code: u64, frame: *x86.InterruptFrame) callconv(.C) void {
    switch (interrupt_num) {
        // Breakpoint
        0x3 => {
            printk("BREAKPOINT\n", .{});
            printk("======================\n", .{});
            printk("{}\n", .{frame});
            printk("======================\n", .{});
        },
        0x31 => {
            keyboard_echo();
        },
        else => printk("Received unknown interrupt {}\n", .{interrupt_num}),
    }
}

fn init_cpu() !void {
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

    x86.set_ds(null_entry.raw);
    x86.set_es(null_entry.raw);
    x86.set_fs(null_entry.raw);
    x86.set_gs(null_entry.raw);
    x86.set_ss(kernel_data.raw);

    main_gdt.reload_cs(kernel_code);

    //x86.ltr(tss_base.raw);

    for (exception_stubs) |ptr, i| {
        const addr: u64 = @ptrToInt(ptr);
        main_idt.set_entry(@intCast(u16, i), IDT.Entry.new(addr, kernel_code, 0));
    }

    main_idt.load();

    x86.pic.remap(0x30, 0x38);
    // enable only keyboard interrupt
    x86.pic.Master.data_write(0xfd);
    x86.pic.Slave.data_write(0xff);
}

pub fn panic(msg: []const u8, return_trace: ?*builtin.StackTrace) noreturn {
    printk("PANIK: {}\n", .{msg});
    x86.hang();
}

fn idle() void {
    while (true) {
        x86.hlt();
    }
}

export fn multiboot_entry(mb_info: u32) callconv(.C) void {
    // Initialize multiboot info pointer
    const mb_info_virt = x86.mm.IdentityMapping.phys_to_virt(mb_info);
    const info = @intToPtr(*x86.multiboot.Info, mb_info_virt);
    x86.multiboot.info_pointer = info;

    kmain();
}

fn init_memory() void {
    const free_memory = x86.mm.detect_memory();
    if (free_memory == null) {
        @panic("Unable to find any free memory!");
    }
    printk("Detected {}MiB of free memory\n", .{free_memory.?.size / 1024 / 1024});
}

fn kmain() void {
    printk("Booting the kernel...\n", .{});
    printk("CR3: 0x{x}\n", .{x86.CR3.read()});
    printk("CPU Vendor: {}\n", .{x86.get_vendor_string()});
    printk("Kernel end: {x}\n", .{x86.mm.get_kernel_end()});

    init_cpu() catch |err| {
        @panic("Failed to initialize the CPU");
    };
    printk("CPU initialized\n", .{});

    init_memory();

    x86.acpi.init();

    printk("Idling...\n", .{});
    x86.sti();
    idle();
}
