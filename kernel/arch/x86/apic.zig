const x86 = @import("../x86.zig");
const logger = x86.logger.childOf(@typeName(@This()));
const APIC_MSR = x86.APIC_BASE;

pub fn apic_enabled() bool {
    return (APIC_MSR.read() & (1 << 11)) != 0;
}

pub fn init() void {
    logger.log("Initializing APIC\n", .{});
    if (!apic_enabled()) {
        @panic("APIC is disabled!");
    }
    // TODO remap APIC
    logger.log("APIC is at {x}\n", .{APIC_MSR.read()});

    const apic_id = (x86.cpuid(1, 0).ebx >> 24) & 0xff;
    logger.log("LAPIC ID {x}\n", .{apic_id});

    const pat = x86.cpuid(1, 0).eax;
    logger.log("CPUID.1.EAX: {x}\n", .{pat});
}
