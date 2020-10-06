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

export fn kmain() void {
    vga_console = VGAConsole.init();

    printk("Booting the kernel...\n", .{});
    printk("CR3: 0x{x}\n", .{x86.read_cr3()});
    printk("CPU Vendor: {}\n", .{x86.get_vendor_string()});
}
