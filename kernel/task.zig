const std = @import("std");
const kernel = @import("root");
const arch = kernel.arch;
const mm = kernel.mm;

pub const Task = struct {
    regs: arch.TaskRegs,
    stack: []u8,
    next: NextNode,

    const Self = @This();
    pub const NextNode = std.TailQueue(void).Node;
    pub fn create(func: fn () noreturn) !*Task {
        var task = try mm.memoryAllocator().alloc(Task);
        var stack = try mm.memoryAllocator().alloc([arch.KERNEL_STACK_SIZE]u8);
        task.regs = arch.TaskRegs.setup(func, stack);
        task.stack = stack;
        task.next = NextNode{ .next = null, .data = {} };
        return task;
    }
};

pub fn switch_task(from: *Task, to: *Task) void {
    arch.asm_switch_task(&from.regs, &to.regs);
}

pub var init_task: Task = std.mem.zeroes(Task);

pub const Scheduler = struct {
    task_list: std.TailQueue(void),

    const Self = @This();

    pub fn addTask(self: *Self, task: *Task) void {
        self.task_list.append(&task.next);
    }

    pub fn reschedule(self: *Self) *Task {
        if (self.task_list.popFirst()) |node| {
            var task: *Task = @fieldParentPtr(Task, "next", node);
            return task;
        }
        @panic("Nothing to schedule!");
    }

    pub fn yield(self: *@This()) void {
        const next_task: *Task = self.reschedule();
        const core_block = kernel.getCoreBlock();

        const prev_task = core_block.current_task;
        core_block.current_task = next_task;

        self.addTask(core_block.current_task);
        switch_task(prev_task, next_task);
    }
};

var sched = Scheduler{ .task_list = std.TailQueue(void){} };

pub fn scheduler() *Scheduler {
    return &sched;
}
