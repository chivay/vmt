const std = @import("std");
pub const Spinlock = @import("lib/spinlock.zig").SpinLock;
pub const Mutex = @import("lib/mutex.zig").Mutex;

pub fn intToEnumSafe(comptime T: type, value: std.meta.Tag(T)) ?T {
    const enumInfo = switch (@typeInfo(T)) {
        .Enum => |enumInfo| enumInfo,
        else => @compileError("Invalid type"),
    };

    comptime if (enumInfo.is_exhaustive) {
        return @intToEnum(T, value);
    };

    inline for (enumInfo.fields) |enumField| {
        if (value == enumField.value) {
            return @intToEnum(T, value);
        }
    }
    return null;
}

pub fn KiB(bytes: u64) callconv(.Inline) u64 {
    return bytes * 1024;
}

pub fn MiB(bytes: u64) callconv(.Inline) u64 {
    return KiB(bytes) * 1024;
}

pub fn GiB(bytes: u64) callconv(.Inline) u64 {
    return MiB(bytes) * 1024;
}

pub fn TiB(bytes: u64) callconv(.Inline) u64 {
    return GiB(bytes) * 1024;
}
