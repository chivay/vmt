const std = @import("std");
const builtin = @import("builtin");

pub const SpinLock = struct {
    state: State,

    const State = enum {
        Unlocked,
        Locked,
    };

    pub const Held = struct {
        spinlock: *SpinLock,

        pub inline fn release(self: Held) void {
            @atomicStore(State, &self.spinlock.state, .Unlocked, .release);
        }
    };

    pub fn init() SpinLock {
        return SpinLock{ .state = .Unlocked };
    }

    pub inline fn tryAcquire(self: *SpinLock) ?Held {
        return switch (@atomicRmw(State, &self.state, .Xchg, .Locked, .acquire)) {
            .Unlocked => Held{ .spinlock = self },
            .Locked => null,
        };
    }

    pub inline fn acquire(self: *SpinLock) Held {
        while (true) {
            if (self.tryAcquire()) |held| {
                return held;
            }
            std.atomic.spinLoopHint();
        }
    }
};
