const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;
const Arch = std.Target.Cpu.Arch;
const CpuFeature = std.Target.Cpu.Feature;

fn build_x86_64(kernel: *std.build.LibExeObjStep) void {
    const builder = kernel.builder;

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
    kernel.code_model = builtin.CodeModel.kernel;

    kernel.setLinkerScriptPath("kernel/arch/x86/linker.ld");
    kernel.addAssemblyFile("kernel/arch/x86/boot.S");
    kernel.setOutputDir("build/x86_64");

    const trampolines = builder.addAssemble("trampolines", "kernel/arch/x86/trampolines.S");
    trampolines.setOutputDir("build/x86_64");
    kernel.step.dependOn(&trampolines.step);

    var iso_tls = builder.step("iso", "Build multiboot ISO");

    var iso = builder.addSystemCommand(&[_][]const u8{"scripts/mkiso.sh"});
    iso.addArtifactArg(kernel);
    iso_tls.dependOn(&iso.step);

    var qemu_tls = builder.step("qemu", "Run QEMU");
    var qemu = builder.addSystemCommand(&[_][]const u8{"qemu-system-x86_64"});
    qemu.addArgs(&[_][]const u8{
        "-enable-kvm",
        "-cdrom",
        "build/x86_64/kernel.iso",
        "-serial",
        "stdio",
        "-display",
        "none",
        "-m",
        "1G",
        "-M",
        "q35",
        "-smp",
        "4",
    });

    qemu.step.dependOn(&iso.step);
    qemu_tls.dependOn(&qemu.step);

    builder.default_step = qemu_tls;
}

fn build_arm64(kernel: *std.build.LibExeObjStep) void {
    const cross_target = CrossTarget{
        .cpu_arch = Arch.aarch64,
        .cpu_model = CrossTarget.CpuModel{ .explicit = &std.Target.aarch64.cpu.cortex_a53 },
        .os_tag = std.Target.Os.Tag.freestanding,
        .abi = std.Target.Abi.none,
    };
    kernel.addAssemblyFile("kernel/arch/arm64/boot.S");
    kernel.setLinkerScriptPath("kernel/arch/arm64/layout.ld");
    kernel.code_model = builtin.CodeModel.small;
    kernel.setTarget(cross_target);
    kernel.setOutputDir("build/arm64");
}

fn buildArch(kernel: *std.build.LibExeObjStep, arch: std.Target.Cpu.Arch) void {
    switch (arch) {
        Arch.x86_64 => {
            build_x86_64(kernel);
        },
        Arch.aarch64 => {
            build_arm64(kernel);
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
    kernel.strip = false;

    const arch = Arch.x86_64;
    buildArch(kernel, arch);

    b.default_step.dependOn(&kernel.step);
}
