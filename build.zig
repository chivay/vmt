const builtin = @import("builtin");
const std = @import("std");
const Build = std.Build;
const CrossTarget = std.zig.CrossTarget;
const Arch = std.Target.Cpu.Arch;

pub fn build(b: *Build) void {
    //const optimize = b.standardOptimizeOption(.{});
    const arch = b.option(Arch, "arch", "Target architecture") orelse Arch.x86_64;

    switch (arch) {
        Arch.x86_64 => {
            @import("kernel/arch/x86/build.zig").build(b);
        },
        //Arch.aarch64 => {
        //    @import("kernel/arch/arm64/build.zig").build(b);
        //},
        else => {
            std.debug.print("Invalid architecture", .{});
        },
    }
}
