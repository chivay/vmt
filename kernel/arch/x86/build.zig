const builtin = @import("builtin");
const std = @import("std");
const Arch = std.Target.Cpu.Arch;
const CrossTarget = std.zig.CrossTarget;
const CpuFeature = std.Target.Cpu.Feature;
const Builder = std.build.Builder;

pub fn build(b: *Builder, kernel: *std.build.LibExeObjStep) void {
    const builder = b;
    var kernel_tls = builder.step("kernel", "Build kernel ELF");

    const cross_target = CrossTarget{
        .cpu_arch = Arch.x86_64,
        .cpu_model = CrossTarget.CpuModel.baseline,
        .cpu_features_add = std.Target.x86.featureSet(&[_]std.Target.x86.Feature{
            .soft_float,
        }),
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
    kernel.target = cross_target;
    kernel.code_model = std.builtin.CodeModel.kernel;
    kernel.want_lto = false;

    kernel.setLinkerScriptPath(.{ .path = "kernel/arch/x86/linker.ld" });
    kernel.addAssemblyFile("kernel/arch/x86/boot.S");
    //kernel.setOutputDir("build/x86_64");

    kernel_tls.dependOn(&kernel.step);

    const trampolines = builder.addAssembly(.{
        .name = "trampolines",
        .source_file = .{ .path = "kernel/arch/x86/trampolines.S" },
        .target = cross_target,
        .optimize = .Debug,
    });
    //trampolines.setOutputDir("build/x86_64");
    kernel.step.dependOn(&trampolines.step);

    var iso_tls = builder.step("iso", "Build multiboot ISO");

    const cmdline = builder.option([]const u8, "cmdline", "kernel command line") orelse "";

    var iso = builder.addSystemCommand(&[_][]const u8{"scripts/mkiso.sh"});
    iso.addArtifactArg(kernel);
    iso.setEnvironmentVariable("CMDLINE", cmdline);
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
        "build/kernel.iso",
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
        "-d",
        "cpu_reset",
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
