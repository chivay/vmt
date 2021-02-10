const kernel = @import("root");
const mm = kernel.mm;
const x86 = @import("../x86.zig");
const APIC_MSR = x86.APIC_BASE;

var logger = @TypeOf(x86.logger).childOf(@typeName(@This())){};

pub fn apic_enabled() bool {
    return (APIC_MSR.read() & (1 << 11)) != 0;
}

pub fn init() void {
    logger.log("Initializing APIC\n", .{});
    if (!apic_enabled()) {
        @panic("APIC is disabled!");
    }

    const maxphyaddr = x86.cpuid(0x80000008, 0).eax & 0xff;
    logger.log("Maxphy is {}\n", .{maxphyaddr});
    const one: u64 = 1;
    const mask: u64 = ((one << @intCast(u6, maxphyaddr)) - 1) - ((1 << 12) - 1);

    const apic_base = mm.PhysicalAddress.new(((APIC_MSR.read() & mask)));
    logger.debug("LAPIC is at {}\n", .{apic_base});

    const apic_id = (x86.cpuid(1, 0).ebx >> 24) & 0xff;
    logger.log("LAPIC ID {x}\n", .{apic_id});

    const io_region = mm.kernel_vm.map_io(apic_base, 0x1000) catch |err| {
        logger.err("Failed to map IO memory for APIC");
        return;
    };

    const lapic = kernel.mmio.DynamicMMIORegion.init(io_region.base.value);
    const id_register = lapic.Reg(u32, 0x20);
    const version_register = lapic.Reg(u32, 0x30);

    logger.debug("ID reg: {x}\n", .{id_register.read()});
    logger.debug("Version reg: {x}\n", .{version_register.read()});
}
