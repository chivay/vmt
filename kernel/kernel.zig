const x86 = @import("arch.zig").x86;
const std = @import("std");
const VGAConsole = x86.vga.VGAConsole;

var vga_console: ?VGAConsole = null;

pub fn printk(comptime fmt: []const u8, args: var) void {
    var vgacon: *VGAConsole = &vga_console.?;
    const com1 = x86.serial.SerialPort(1);
    vgacon.outStream().print(fmt, args) catch |err| {};
    com1.outStream().print(fmt, args) catch |err| {};
}

const GDT = x86.GlobalDescriptorTable(32);
var main_gdt align(64) = GDT.new();
var main_tss align(64) = std.mem.zeroes(x86.TSS);

extern fn reload_cs(selector: u32) void;
comptime {
    asm (
        \\ .global reload_cs;
        \\ .type reload_cs, @function;
        \\ reload_cs:
        \\ pop %rsi
        \\ push %rdi
        \\ push %rsi
        \\ lretq
    );
}

fn init_gdt() void {
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
    reload_cs(kernel_code.raw);

    x86.ltr(tss_base.raw);
}

export fn kmain() void {
    vga_console = VGAConsole.init();

    printk("Booting the kernel...\n", .{});
    printk("CR3: 0x{x}\n", .{x86.CR3.read()});
    printk("CPU Vendor: {}\n", .{x86.get_vendor_string()});

    init_gdt();
    printk("Reloaded GDT\n", .{});
}
