const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;
const Arch = std.Target.Cpu.Arch;
const CpuFeature = std.Target.Cpu.Feature;

fn build_x86_64(kernel: *std.build.LibExeObjStep) void {
    const cross_target = CrossTarget{
        .cpu_arch = Arch.x86_64,
        .cpu_model = CrossTarget.CpuModel.baseline,
        .cpu_features_sub = featureSet(&[_]std.Target.x86.Feature{
            .cmov,
            .cx8,
            .fxsr,
            .macrofusion,
            .mmx,
            .nopl,
            .slow_3ops_lea,
            .slow_incdec,
            .sse,
            .sse2,
            .vzeroupper,
            .x87,
        }),

        .os_tag = std.Target.Os.Tag.freestanding,
        .abi = std.Target.Abi.none,
    };
    kernel.setTarget(cross_target);

    kernel.setLinkerScriptPath("kernel/arch/x86/linker.ld");
    kernel.addAssemblyFile("kernel/arch/x86/boot.S");
}

fn buildArch(kernel: *std.build.LibExeObjStep, arch: std.Target.Cpu.Arch) void {
    switch (arch) {
        Arch.x86_64 => {
            build_x86_64(kernel);
        },
        else => {
            std.debug.warn("Invalid architecture", .{});
        },
    }
}

pub usingnamespace CpuFeature.feature_set_fns(std.Target.x86.Feature);

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const kernel = b.addExecutable("kernel", "kernel/kernel.zig");

    kernel.setBuildMode(mode);
    kernel.code_model = builtin.CodeModel.kernel;
    kernel.strip = true;

    const arch = Arch.x86_64;
    buildArch(kernel, arch);

    kernel.setOutputDir("build/");
    b.default_step.dependOn(&kernel.step);
}
