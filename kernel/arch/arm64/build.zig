const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;
const CrossTarget = std.zig.CrossTarget;
const Arch = std.Target.Cpu.Arch;

pub fn build(kernel: *std.build.LibExeObjStep) void {
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
