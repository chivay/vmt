const builtin = @import("builtin");
const std = @import("std");
const Arch = std.Target.Cpu.Arch;
const CrossTarget = std.zig.CrossTarget;
const CpuFeature = std.Target.Cpu.Feature;

pub fn build(kernel: *std.build.LibExeObjStep) void {
    const builder = kernel.builder;
    var kernel_tls = builder.step("kernel", "Build kernel ELF");

    const cross_target = CrossTarget{
        .cpu_arch = Arch.x86_64,
        .cpu_model = CrossTarget.CpuModel.baseline,
        .cpu_features_sub = std.Target.x86.featureSet(&[_]std.Target.x86.Feature{
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
    kernel.code_model = std.builtin.CodeModel.kernel;
    kernel.want_lto = true;

    kernel.setLinkerScriptPath(.{ .path = "kernel/arch/x86/linker.ld" });
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

    const memory = builder.option([]const u8, "vm-memory", "VM memory e.g. 1G, 128M") orelse "1G";
    const cpus = builder.option([]const u8, "vm-cpus", "number of vCPUs") orelse "1";
    const display = builder.option([]const u8, "qemu-display", "type of QEMU display") orelse "none";
    const use_uefi = builder.option(bool, "vm-uefi", "use UEFI") orelse false;

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
        display,
        "-m",
        memory,
        "-M",
        "q35",
        "-smp",
        cpus,
    });

    if (use_uefi) {
        qemu.addArgs(&[_][]const u8{
            "-bios",
            "/usr/share/edk2-ovmf/x64/OVMF.fd",
        });
    }

    qemu.step.dependOn(&iso.step);
    qemu_tls.dependOn(&qemu.step);

    builder.default_step = kernel_tls;
}
