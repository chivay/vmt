const std = @import("std");
pub const elf = @import("lib/elf.zig");
pub const SpinLock = @import("lib/spinlock.zig").SpinLock;

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
