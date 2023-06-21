const kernel = @import("root");

const logger = kernel.logging.logger(@typeName(@This())){};

var sys_no: u32 = 0;

pub fn syscall_dispatch() void {
    logger.log("syscall entry {}\n", .{sys_no});
    sys_no += 1;
    kernel.task.scheduler().yield();
}
