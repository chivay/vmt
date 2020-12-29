const std = @import("std");
const builtin = @import("builtin");

pub const printk = @import("printk.zig").printk;

pub const printk_mod = @import("printk.zig");
pub const mm = @import("mm.zig");
pub const arch = @import("arch.zig");
pub const mmio = @import("mmio.zig");
pub const task = @import("task.zig");
const Task = task.Task;

pub const logger = printk_mod.logger("kernel");

pub fn panic(msg: []const u8, return_trace: ?*builtin.StackTrace) noreturn {
    logger.log("PANIK: {}\n", .{msg});
    arch.hang();
}

pub fn worker() noreturn {
    while (true) {
        logger.log("Hello from worker!\n", .{});
        task.scheduler().yield();
    }
}

pub fn worker2() noreturn {
    while (true) {
        logger.log("Hello from worker 2!\n", .{});
        task.scheduler().yield();
    }
}

pub fn kmain() void {
    arch.init_cpu() catch |err| {
        @panic("Failed to initialize the CPU");
    };

    mm.init();
    arch.init();

    var taskA = Task.create(
        worker,
    ) catch |err| {
        @panic("Failed to allocate a task");
    };
    var taskB = Task.create(worker2) catch |err| {
        @panic("Failed to allocate a task");
    };

    var scheduler = task.scheduler();
    scheduler.addTask(taskA);
    scheduler.addTask(taskB);

    scheduler.yield();
}
