const std = @import("std");
const builtin = @import("builtin");

pub const logging = @import("logging.zig");
pub const mm = @import("mm.zig");
pub const arch = @import("arch.zig");
pub const mmio = @import("mmio.zig");
pub const task = @import("task.zig");
pub const lib = @import("lib.zig");
const Task = task.Task;

pub const logger = logging.logger("kernel"){};

pub fn panic(msg: []const u8, return_trace: ?*std.builtin.StackTrace) noreturn {
    logger.critical("PANIK: {s}\n", .{msg});

    var it = std.debug.StackIterator.init(@returnAddress(), null);
    logger.critical("Stack trace:\n", .{});
    while (it.next()) |return_address| {
        logger.critical("=> {x}\n", .{return_address});
    }
    arch.hang();
}

var sys_no: u32 = 0;
pub fn syscall_dispatch() void {
    logger.log("syscall entry {}\n", .{sys_no});
    sys_no += 1;
    task.scheduler().yield();
}

pub fn getCoreBlock() *arch.CoreBlock {
    return arch.getCoreBlock();
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

    var taskA = Task.create(worker) catch |err| {
        @panic("Failed to allocate a task");
    };
    var taskB = Task.create(worker2) catch |err| {
        @panic("Failed to allocate a task");
    };

    var scheduler = task.scheduler();
    scheduler.addTask(&task.init_task);
    scheduler.addTask(taskA);
    scheduler.addTask(taskB);

    //arch.enable_interrupts();
    arch.enter_userspace() catch |err| {
        @panic("Failed to enter userspace");
    };
}
