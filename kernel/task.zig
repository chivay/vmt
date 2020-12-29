const std = @import("std");
const kernel = @import("root");
const arch = kernel.arch;
const mm = kernel.mm;

pub const Task = struct {
    pub const NextNode = std.TailQueue(void).Node;

    regs: arch.TaskRegs,
    next: NextNode,

    pub fn create(func: fn () noreturn) !*Task {
        var task = try mm.memoryAllocator().alloc(Task);
        var stack = try mm.memoryAllocator().alloc([0x1000]u8);
        task.regs = arch.TaskRegs.setup(func, stack);
        task.next = NextNode{ .next = null, .data = {} };
        return task;
    }
};

pub fn switch_task(from: *Task, to: *Task) void {
    current_task = to;
    arch.x86.asm_switch_task(&from.regs, &to.regs);
}

var init_task: Task = undefined;
var current_task: *Task = &init_task;

pub const Scheduler = struct {
    task_list: std.TailQueue(void),

    pub fn addTask(self: *@This(), task: *Task) void {
        self.task_list.prepend(&task.next);
    }

    pub fn reschedule(self: *@This()) *Task {
        if (self.task_list.popFirst()) |node| {
            var task: *Task = @fieldParentPtr(Task, "next", node);
            self.task_list.append(&task.next);
            return task;
        }
        @panic("Nothing to schedule!");
    }

    pub fn yield(self: *@This()) void {
        const next_task: *Task = self.reschedule();
        switch_task(current_task, next_task);
    }
};

var sched = Scheduler{ .task_list = std.TailQueue(void){} };

pub fn scheduler() *Scheduler {
    return &sched;
}
