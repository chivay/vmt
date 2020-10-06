const x86 = @import("arch.zig").x86;
const std = @import("std");
const VGAConsole = x86.vga.VGAConsole;

var console: ?VGAConsole = null;

pub fn printk(comptime fmt: []const u8, args: var) void {
    var con: *VGAConsole = &console.?;
    con.outStream().print(fmt, args) catch |err| {};
}

export fn kmain() void {
    console = VGAConsole.init();
    printk("Booting the kernel...\n", .{});
    printk("CR3: 0x{x}\n", .{x86.read_cr3()});
    printk("CPU Vendor: {}\n", .{x86.get_vendor_string()});
    const cpuid_info = x86.cpuid(0x0, 0x0);
}
