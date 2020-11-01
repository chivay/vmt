const builtin = @import("builtin");

pub const x86 = @import("arch/x86.zig");

usingnamespace switch (builtin.arch) {
    .x86_64 => @import("arch/x86.zig"),
    else => @compileError("Unknown architecture!"),
};
