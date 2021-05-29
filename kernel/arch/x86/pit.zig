const x86 = @import("../x86.zig");
const std = @import("std");
const kernel = @import("root");

var logger = @TypeOf(x86.logger).childOf(@typeName(@This())){};

// 1193181.6666 Hz

const PIT_CHANNEL_0 = 0x40;
const PIT_CHANNEL_1 = 0x41;
const PIT_CHANNEL_2 = 0x42;
const PIT_CMD = 0x43;

fn set_frequency_value(hz: u16) void {
    const value = 1193180 / @as(u32, hz);
    logger.debug("Setting the frequency to {}Hz\n", .{hz});
    x86.out(u8, PIT_CMD, 0x36);
    x86.out(u8, PIT_CHANNEL_0, @truncate(u8, value));
    x86.out(u8, PIT_CHANNEL_0, @truncate(u8, value >> 8));
}

fn read_reload_value() u16 {
    x86.out(u8, PIT_CMD, 0b0000000);
    var value: u16 = x86.in(u8, PIT_CHANNEL_0);
    value |= @as(u16, x86.in(u8, PIT_CHANNEL_0)) << 8;
    return value;
}

var counter = std.atomic.Int(u32).init(0);

fn irq_handler() void {
    const val = counter.incr();
    //logger.info("{}\n", .{val});
}

pub fn sleep(milliseconds: u32) void {
    // ticket per second ~1000Hz
    set_frequency_value(1000);
    counter.store(0, .SeqCst);
    x86.pic.Master.set_mask(0xf0);

    x86.enable_interrupts();
    while (true) {
        if (counter.load(.SeqCst) >= milliseconds) {
            break;
        }
    }
    x86.pic.Master.set_mask(0xff);
    x86.cli();
}

var registration = x86.IrqRegistration{
    .func = irq_handler,
    .next = null,
};
pub fn init() void {
    logger.info("PIT init\n", .{});
    x86.register_irq_handler(x86.IRQ_0, &registration) catch |err| {
        @panic("Failed to register interrupt handler");
    };
    //logger.info("The value is {}\n", .{read_reload_value()});
    //logger.info("The value is {}\n", .{read_reload_value()});
    //logger.info("The value is {}\n", .{read_reload_value()});
    //logger.info("The value is {}\n", .{read_reload_value()});
    //logger.info("The value is {}\n", .{read_reload_value()});
    //logger.info("The value is {}\n", .{read_reload_value()});
    // Hz =  2299.0
}
