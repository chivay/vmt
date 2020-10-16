const x86 = @import("arch.zig").x86;
const std = @import("std");
const builtin = @import("builtin");
const VGAConsole = x86.vga.VGAConsole;

var vga_console: ?VGAConsole = null;

pub fn printk(comptime fmt: []const u8, args: var) void {
    var vgacon: *VGAConsole = &vga_console.?;
    const com1 = x86.serial.SerialPort(1);
    vgacon.outStream().print(fmt, args) catch |err| {};
    com1.outStream().print(fmt, args) catch |err| {};
}

const GDT = x86.GlobalDescriptorTable(8);
const IDT = x86.InterruptDescriptorTable;
const TSS = x86.TSS;

var main_gdt align(64) = GDT.new();
var main_tss align(64) = std.mem.zeroes(TSS);
var main_idt align(64) = std.mem.zeroes(IDT);

var kernel_stack align(0x1000) = std.mem.zeroes([0x1000]u8);
var user_stack align(0x1000) = std.mem.zeroes([0x1000]u8);

fn hello_handler(frame: *x86.InterruptFrame) callconv(.C) void {
    printk("Hello from interrupt\n", .{});
    printk("RIP: {x}:{x}\n", .{ frame.cs, frame.rip });
}

fn init_cpu() void {
    const Entry = x86.GDTEntry;

    const null_entry = main_gdt.add_entry(Entry.nil);
    const kernel_code = main_gdt.add_entry(Entry.KernelCode);
    const kernel_data = main_gdt.add_entry(Entry.KernelData);
    const user_code = main_gdt.add_entry(Entry.UserCode);
    const user_data = main_gdt.add_entry(Entry.UserData);

    // Kinda ugly, refactor this
    const tss_base = main_gdt.add_entry(Entry.TaskState(&main_tss)[0]);
    _ = main_gdt.add_entry(Entry.TaskState(&main_tss)[1]);

    main_gdt.load();

    x86.set_ds(null_entry.raw);
    x86.set_es(null_entry.raw);
    x86.set_fs(null_entry.raw);
    x86.set_gs(null_entry.raw);
    x86.set_ss(kernel_data.raw);

    main_gdt.reload_cs(kernel_code);

    x86.ltr(tss_base.raw);

    const isr = @ptrToInt(interrupt_entry);
    printk("ISR: {x}\n", .{isr});

    var i: u16 = 0;
    while (i < main_idt.entries.len) : (i += 1) {
        main_idt.set_entry(i, x86.IDTEntry.new(isr, kernel_code, 0));
    }

    main_idt.load();
    @breakpoint();
}

const interrupt_entry = x86.InterruptHandler(hello_handler).handler;

pub fn panic(msg: []const u8, return_trace: ?*builtin.StackTrace) noreturn {
    printk("{}\n", .{msg});
    x86.hang();
}

export fn kmain() void {
    vga_console = VGAConsole.init();

    printk("Booting the kernel...\n", .{});
    printk("CR3: 0x{x}\n", .{x86.CR3.read()});
    printk("CPU Vendor: {}\n", .{x86.get_vendor_string()});

    init_cpu();
}
