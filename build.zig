const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;
const Arch = std.Target.Cpu.Arch;

fn buildArch(kernel: *std.build.LibExeObjStep, arch: std.Target.Cpu.Arch) void {
    switch (arch) {
        Arch.x86_64 => {
            @import("kernel/arch/x86/build.zig").build(kernel);
        },
        Arch.aarch64 => {
            @import("kernel/arch/arm64/build.zig").build(kernel);
        },
        else => {
            std.debug.warn("Invalid architecture", .{});
        },
    }
}

pub fn build(b: *Builder) void {
    const kernel = b.addExecutable("kernel", "kernel/kernel.zig");

    const mode = b.standardReleaseOptions();
    kernel.setBuildMode(mode);

    kernel.strip = b.option(bool, "strip", "Strip kernel executable") orelse false;

    const arch = b.option(Arch, "arch", "Target architecture") orelse Arch.x86_64;

    buildArch(kernel, arch);

    // Build kernel ELF by default
    b.default_step.dependOn(&kernel.step);
}
