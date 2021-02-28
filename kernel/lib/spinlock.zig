const builtin = @import("builtin");

pub const SpinLock = struct {
    state: State,

    const State = enum {
        Unlocked,
        Locked,
    };

    pub const Held = struct {
        spinlock: *SpinLock,

        pub fn release(self: Held) callconv(.Inline) void {
            @atomicStore(State, &self.spinlock.state, .Unlocked, .Release);
        }
    };

    pub fn init() SpinLock {
        return SpinLock{ .state = .Unlocked };
    }

    pub fn tryAcquire(self: *SpinLock) callconv(.Inline) ?Held {
        return switch (@atomicRmw(State, &self.state, .Xchg, .Locked, .Acquire)) {
            .Unlocked => Held{ .spinlock = self },
            .Locked => null,
        };
    }

    pub fn acquire(self: *SpinLock) callconv(.Inline) Held {
        while (true) {
            if (self.tryAcquire()) |held| {
                return held;
            }
        }
    }
};
