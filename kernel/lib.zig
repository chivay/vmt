const std = @import("std");
pub const Spinlock = @import("lib/spinlock.zig").SpinLock;
pub const Mutex = @import("lib/mutex.zig").Mutex;

pub fn bit_set(value: anytype, comptime bit: BitStruct) bool {
    return (value & (1 << bit.shift)) != 0;
}

const BitStruct = struct {
    shift: comptime_int,

    pub fn v(comptime self: @This()) comptime_int {
        return 1 << self.shift;
    }
};

pub fn BIT(comptime n: comptime_int) BitStruct {
    return .{ .shift = n };
}

pub fn intToEnumSafe(comptime T: type, value: std.meta.Tag(T)) ?T {
    const enumInfo = switch (@typeInfo(T)) {
        .Enum => |enumInfo| enumInfo,
        else => @compileError("Invalid type"),
    };

    comptime if (enumInfo.is_exhaustive) {
        return @as(T, @enumFromInt(value));
    };

    inline for (enumInfo.fields) |enumField| {
        if (value == enumField.value) {
            return @enumFromInt(value);
        }
    }
    return null;
}

pub inline fn KiB(bytes: u64) u64 {
    return bytes * 1024;
}

pub inline fn MiB(bytes: u64) u64 {
    return KiB(bytes) * 1024;
}

pub inline fn GiB(bytes: u64) u64 {
    return MiB(bytes) * 1024;
}

pub inline fn TiB(bytes: u64) u64 {
    return GiB(bytes) * 1024;
}
