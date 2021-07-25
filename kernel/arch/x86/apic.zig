const std = @import("std");
const kernel = @import("root");
const mm = kernel.mm;
const x86 = @import("../x86.zig");
const APIC_MSR = x86.APIC_BASE;
const MMIORegion = kernel.mmio.DynamicMMIORegion;

var logger = @TypeOf(x86.logger).childOf(@typeName(@This())){};

pub fn apicEnabled() bool {
    return (APIC_MSR.read() & (1 << 11)) != 0;
}

pub fn sendCommand(apic: *const MMIORegion, destination: u8, cmd: u20) void {
    const icr_lo = apic.Reg(u32, 0x300);
    const icr_hi = apic.Reg(u32, 0x310);

    icr_hi.write(@as(u32, destination) << 24);
    icr_lo.write(@as(u32, cmd));
    while (((icr_lo.read() >> 12) & 1) != 0) {}
}

fn getBase() mm.PhysicalAddress {
    const maxphyaddr = x86.cpuid(0x80000008, 0).eax & 0xff;
    const one: u64 = 1;
    const mask: u64 = ((one << @intCast(u6, maxphyaddr)) - 1) - ((1 << 12) - 1);
    return mm.PhysicalAddress.new(((APIC_MSR.read() & mask)));
}

pub fn getLapicId() u8 {
    return @truncate(u8, (x86.cpuid(1, 0).ebx >> 24));
}

pub var lapic: MMIORegion = undefined;

pub fn init() void {
    logger.info("Initializing APIC\n", .{});
    if (!apicEnabled()) {
        @panic("APIC is disabled!");
    }

    const apic_base = getBase();
    logger.info("LAPIC is at {}\n", .{apic_base});

    const apic_id = getLapicId();
    logger.log("LAPIC ID {x}\n", .{apic_id});

    const io_region = mm.kernel_vm.map_io(apic_base, 0x1000) catch |err| {
        logger.err("{}", .{err});
        @panic("Failed to map IO memory for APIC");
    };

    lapic = MMIORegion.init(io_region.base.value);

    const id_register = lapic.Reg(u32, 0x20);
    const version_register = lapic.Reg(u32, 0x30);

    logger.debug("ID reg: {x}\n", .{id_register.read()});
    logger.debug("Version: {x}\n", .{version_register.read() & 0xff});
}
