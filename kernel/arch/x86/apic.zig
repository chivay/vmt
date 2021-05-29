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

pub fn set_timer_divider(power: u8) void {
    const divider = lapic.Reg(u32, 0x3e0);
    const value: u32 = switch (power) {
        1 => 0b1011,
        2 => 0b0000,
        4 => 0b0001,
        8 => 0b0010,
        16 => 0b0011,
        32 => 0b1000,
        64 => 0b1001,
        128 => 0b1010,
        else => @panic("Invalid APIC divider"),
    };
    divider.write(value);
}

pub fn set_initial_count(value: u32) void {
    const reg = lapic.Reg(u32, 0x380);
    reg.write(value);
}

pub fn set_current_count(value: u32) void {
    const reg = lapic.Reg(u32, 0x390);
    reg.write(value);
}

pub fn get_current_count() u32 {
    const reg = lapic.Reg(u32, 0x390);
    return reg.read();
}

pub fn set_timer_lvt(vector: u8, mask: u1, mode: u2) void {
    const reg = lapic.Reg(u32, 0x320);
    const value = vector | (@as(u32, mask) << 16) | (@as(u32, mode) << 17);
    reg.write(value);
}

pub var lapic: MMIORegion = undefined;

var counter: u32 = 0;
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
    const error_status = lapic.Reg(u32, 0x280);
    const svr = lapic.Reg(u32, 0xf0);

    set_timer_divider(16);
    set_timer_lvt(0x20, 0, 0);

    set_initial_count(0xffffffff);
    set_current_count(0xffffffff);
    x86.pit.sleep(100);
    const msTicks = 0xffffffff - get_current_count();
    logger.info("Ticks in 100ms: {}\n", .{msTicks});

    var reg = x86.IrqRegistration{
        .func = struct {
            pub fn f() void {
                counter += 1;
                logger.info("test\n", .{});
                const eoi = lapic.Reg(u32, 0xb0);
                eoi.write(0);
            }
        }.f,
        .next = null,
    };
    x86.register_irq_handler(0x20, &reg) catch unreachable;

    set_timer_lvt(0x20, 0, 0b01);
    set_initial_count(msTicks * 10);

    x86.enable_interrupts();
    x86.idle();

    //logger.debug("ID reg: {x}\n", .{id_register.read()});
    //logger.debug("Version: {x}\n", .{version_register.read() & 0xff});
}
