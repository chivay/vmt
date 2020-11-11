const kernel = @import("root");

pub const logger = kernel.printk_mod.logger("arm64");

const BCM2837 = @import("arm64/platform/BCM2837.zig");

const Node = kernel.printk_mod.SinkNode;
var uart_node = Node{ .data = format_to_uart };
fn format_to_uart(buffer: []const u8) void {
    for (buffer) |c| {
        while (!UART.can_send()) {}
        UART.send_byte(c);
    }
}

pub const Watchdog = struct {
    const PM = BCM2837.PM;

    pub fn start(timeout: u32) void {
        const wdog = PM.PASSWORD | (timeout & 0xfffff);
        const rstc = PM.PASSWORD | (PM.RSTC.read() & 0xffffffcf) | 0x00000020;
        PM.WDOG.write(wdog);
        PM.RSTC.write(rstc);
    }
};

pub const UART = struct {
    const MINI_UART = BCM2837.MINI_UART;

    fn send_byte(c: u8) void {
        MINI_UART.IO.write(c);
    }

    fn recv_byte() u8 {
        return @truncate(u8, MINI_UART.IO.read(c));
    }

    fn can_send() bool {
        return (MINI_UART.LSR.read() & (1 << 5)) != 0;
    }

    fn can_recv() bool {
        return (MINI_UART.LSR.read() & 1) != 0;
    }
};

export fn entry() noreturn {
    kernel.printk_mod.register_sink(&uart_node);
    logger.log("Witam z Raspberry Pi :)", .{});
    Watchdog.start(16 * 10);
    hang();
}

pub fn hang() noreturn {
    while (true) {}
}
