const builtin = @import("builtin");

pub const x86 = @import("arch/x86.zig");
pub const arm64 = @import("arch/arm64.zig");

pub usingnamespace switch (builtin.cpu.arch) {
    .x86_64 => @import("arch/x86.zig"),
    .aarch64 => @import("arch/arm64.zig"),
    else => @compileError("Unknown architecture!"),
};
