const std = @import("std");
const builtin = @import("builtin");

pub const printk = @import("printk.zig").printk;

pub const printk_mod = @import("printk.zig");
pub const mm = @import("mm.zig");
pub const arch = @import("arch.zig");

pub fn panic(msg: []const u8, return_trace: ?*builtin.StackTrace) noreturn {
    printk("PANIK: {}\n", .{msg});
    arch.hang();
}

pub fn kmain() void {
    arch.init_cpu() catch |err| {
        @panic("Failed to initialize the CPU");
    };
    printk("CPU initialized\n", .{});

    arch.mm.init();

    arch.x86.acpi.init();

    printk("Idling...\n", .{});
    arch.enable_interrupts();
    arch.idle();
}
