const std = @import("std");
const kernel = @import("root");
const x86 = @import("../x86.zig");
var logger = @TypeOf(x86.logger).childOf(@typeName(@This())){};

const apic = x86.apic;

const DCR = 64;

pub fn getTimerHz() u32 {
    return 20;
}

fn calibrateApic(sleep_ms: u32) u32 {
    apic.setDCR(DCR);
    apic.setTimerLVT(0xff, .Masked, .OneShot);

    const maxint = std.math.maxInt(u32);
    apic.setInitialCount(maxint);
    apic.setCurrentCount(maxint);

    x86.pit.sleep(sleep_ms);
    const msTicks = maxint - apic.getCurrentCount();

    return msTicks;
}

fn irq_handler() void {
    logger.debug("Tick\n", .{});
    const eoi = apic.lapic.Reg(u32, 0xb0);
    eoi.write(0);
}

var reg = x86.IrqRegistration.new(irq_handler);

pub fn init() void {
    logger.log_level = .Debug;
    logger.info("Initializing TSC timer\n", .{});

    const calibration_time = 100;
    const ticks = calibrateApic(calibration_time);

    logger.info("TSC did {} ticks in {}ms\n", .{ DCR * ticks, calibration_time });

    const ticks_in_second = ticks * 1000 / calibration_time;
    const counter = ticks_in_second / getTimerHz();

    const interrupt_number = x86.IRQ_1;
    x86.register_irq_handler(interrupt_number, &reg) catch unreachable;

    apic.setTimerLVT(interrupt_number, .NotMasked, .Periodic);
    apic.setInitialCount(counter);
}
