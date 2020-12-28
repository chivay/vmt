const std = @import("std");
const builtin = @import("builtin");

pub const printk = @import("printk.zig").printk;

pub const printk_mod = @import("printk.zig");
pub const mm = @import("mm.zig");
pub const arch = @import("arch.zig");
pub const mmio = @import("mmio.zig");

pub const logger = printk_mod.logger("kernel");

pub fn panic(msg: []const u8, return_trace: ?*builtin.StackTrace) noreturn {
    logger.log("PANIK: {}\n", .{msg});
    arch.hang();
}

pub fn kmain() void {
    arch.init_cpu() catch |err| {
        @panic("Failed to initialize the CPU");
    };
    logger.log("CPU initialized\n", .{});

    arch.mm.init();
    arch.x86.acpi.init();
    arch.x86.pci.init();

    logger.log("Idling...\n", .{});
    arch.enable_interrupts();
    arch.idle();
}
