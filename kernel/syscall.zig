const kernel = @import("root");

pub var logger = kernel.logging.logger("main"){};

var sys_no: u32 = 0;

pub fn syscall_dispatch() void {
    logger.log("syscall entry {}\n", .{sys_no});
    sys_no += 1;
    kernel.task.scheduler().yield();
}
