const std = @import("std");
const kernel = @import("root");
const arch = kernel.arch;
const mm = kernel.mm;

pub var logger = kernel.logging.logger("task"){};

pub const Task = struct {
    regs: arch.TaskRegs,
    vm: *mm.VirtualMemory,
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
        task.vm = try mm.getKernelVM().clone();
        return task;
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, stream: anytype) !void {
        _ = fmt;
        try stream.writeAll(@typeName(Self));
        try stream.writeAll("{");
        try std.fmt.formatType(self.regs, fmt, options, stream, 1);
        try stream.writeAll("}");
    }
};

pub fn switch_task(to: *Task) void {
    const core_block = kernel.getCoreBlock();

    const prev_task = core_block.current_task;
    const next_task = to;
    std.debug.assert(prev_task != next_task);

    // Ensure we'll get scheduled sometime
    scheduler().addTask(prev_task);

    // Swap tasks
    core_block.current_task = next_task;
    defer core_block.current_task = prev_task;
    core_block.current_task.vm.switch_to();

    arch.switch_task(prev_task, next_task);
}

pub var init_task = Task{
    .vm = mm.getKernelVM(),
    .regs = std.mem.zeroes(kernel.arch.TaskRegs),
    .stack = &[_]u8{},
    .next = .{.data = .{}},
};

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

    pub fn yield(self: *Self) void {
        const next_task: *Task = self.reschedule();
        switch_task(next_task);
    }
};

var sched = Scheduler{ .task_list = std.TailQueue(void){} };

pub fn scheduler() *Scheduler {
    return &sched;
}
