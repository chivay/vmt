pub const arch = @import("arch.zig");
pub const lib = @import("lib.zig");
pub const logging = @import("logging.zig");
pub const main = @import("main.zig");
pub const mm = @import("mm.zig");
pub const mmio = @import("mmio.zig");
pub const syscall = @import("syscall.zig");
pub const task = @import("task.zig");

pub const logger = logging.logger("kernel"){};

const std = @import("std");

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    logger.critical("PANIK: {s}\n", .{msg});

    var it = std.debug.StackIterator.init(@returnAddress(), null);
    logger.critical("Stack trace:\n", .{});
    while (it.next()) |return_address| {
        logger.critical("=> {x}\n", .{return_address});
    }
    arch.hang();
}

pub fn getCoreBlock() *arch.CoreBlock {
    return arch.getCoreBlock();
}

comptime {
    _ = arch.x86.multiboot;
}
