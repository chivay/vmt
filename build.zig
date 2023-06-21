const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;
const Arch = std.Target.Cpu.Arch;

fn buildArch(b: *Builder, kernel: *std.build.LibExeObjStep, arch: std.Target.Cpu.Arch) void {
    switch (arch) {
        Arch.x86_64 => {
            @import("kernel/arch/x86/build.zig").build(b, kernel);
        },
        //Arch.aarch64 => {
        //    @import("kernel/arch/arm64/build.zig").build(b, kernel);
        //},
        else => {
            std.debug.print("Invalid architecture", .{});
        },
    }
}

pub fn build(b: *Builder) void {
    const optimize = b.standardOptimizeOption(.{});

    const arch = b.option(Arch, "arch", "Target architecture") orelse Arch.x86_64;

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = .{.path = "kernel/kernel.zig"},
        .optimize = optimize,
    });
    kernel.strip = b.option(bool, "strip", "Strip kernel executable") orelse false;

    buildArch(b, kernel, arch);

    // Build kernel ELF by default
    b.default_step.dependOn(&kernel.step);
}
