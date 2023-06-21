const kernel = @import("root");
const arch = kernel.arch;
const mm = kernel.mm;
const task = kernel.task;

const logger = kernel.logging.logger(@typeName(@This())){};

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
    //arch.init_cpu() catch {
    //    @panic("Failed to initialize the CPU");
    //};

    mm.init();
    arch.init();

    const Task = task.Task;

    var taskA = Task.create(&usermode) catch {
        @panic("Failed to allocate a task");
    };
    var taskB = Task.create(&usermode) catch {
        @panic("Failed to allocate a task");
    };
    var taskC = Task.create(&worker2) catch {
        @panic("Failed to allocate a task");
    };

    var scheduler = task.scheduler();
    scheduler.addTask(taskA);
    scheduler.addTask(taskB);
    scheduler.addTask(taskC);

    logger.info("Enabling interrupts\n", .{});

    //arch.enable_interrupts();
    arch.idle();
}

pub fn usermode() noreturn {
    arch.setup_userspace() catch {};
    logger.info("Entering userspace\n", .{});
    arch.enter_userspace();
    unreachable;
}
