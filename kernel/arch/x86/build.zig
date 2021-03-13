const builtin = @import("builtin");
const std = @import("std");
const Arch = std.Target.Cpu.Arch;
const CrossTarget = std.zig.CrossTarget;
const CpuFeature = std.Target.Cpu.Feature;

pub usingnamespace CpuFeature.feature_set_fns(std.Target.x86.Feature);

pub fn build(kernel: *std.build.LibExeObjStep) void {
    const builder = kernel.builder;
    var kernel_tls = builder.step("kernel", "Build kernel ELF");

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
    kernel.want_lto = false;

    kernel.setLinkerScriptPath("kernel/arch/x86/linker.ld");
    kernel.addAssemblyFile("kernel/arch/x86/boot.S");
    kernel.setOutputDir("build/x86_64");

    kernel_tls.dependOn(&kernel.step);

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
        "-s",
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

    builder.default_step = kernel_tls;
}
