const std = @import("std");
const kernel = @import("root");

pub const Mutex = struct {
    locked: kernel.lib.Spinlock,

    pub const Held = struct {
        mutex: *Mutex,

        pub fn release() void {}
    };

    pub fn new() Mutex {
        return .{ .locked = kernel.lib.Spinlock.init() };
    }

    pub fn acquire(self: *@This()) Held {
        return .{ .mutex = self };
    }
};
