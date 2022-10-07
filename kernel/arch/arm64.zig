const std = @import("std");
const kernel = @import("root");

pub var logger = kernel.logging.logger("arm64"){};

const BCM2837 = @import("arm64/platform/BCM2837.zig");

const Node = kernel.logging.SinkNode;
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
        return @truncate(u8, MINI_UART.IO.read());
    }

    fn can_send() bool {
        return (MINI_UART.LSR.read() & (1 << 5)) != 0;
    }

    fn can_recv() bool {
        return (MINI_UART.LSR.read() & 1) != 0;
    }
};

const MailboxChannel = enum(u8) {
    PowerManagement = 0,
    Framebuffer = 1,
    VirtualUART = 2,
    VCHIQ = 3,
    LED = 4,
    Button = 5,
    TouchScreen = 6,
    PropertyTagsARMtoVC = 8,
    PropertyTagsVCtoARM = 9,
};

const PERIPHERAL_BASE = 0x3F000000;
const MAILBOX_BASE = PERIPHERAL_BASE + 0xB880;

const MAILBOX_READ = MAILBOX_BASE + 0x0;
const MAILBOX_STATUS = MAILBOX_BASE + 0x18;
const MAILBOX_WRITE = MAILBOX_BASE + 0x20;

fn mbox_read() u32 {
    while (true) {
        while (true) {
            const stat = @intToPtr(*volatile u32, MAILBOX_STATUS).*;
            if ((stat >> 30) & 1 == 0) break;
        }
        // mbox not empty
        const val = @intToPtr(*volatile u32, MAILBOX_READ).*;
        return val;
    }
}

var mbox align(16) = [_]u32{
    80,
    0,
    0x00048003,
    8,
    0,
    1920,
    1080,
    0x00048004,
    8,
    0,
    1920,
    1080,
    0x00048005,
    4,
    0,
    24,
    0,
    0,
    0,
    0,
};

fn setup_framebuffer() void {
    while (true) {
        const val = @intToPtr(*volatile u32, MAILBOX_STATUS).*;
        if (((val >> 31) & 1) == 0) {
            break;
        }
    }

    logger.log("mbox is at {x}\r\n", .{@ptrToInt(&mbox)});
    const val: u32 = 0x40000000 + @truncate(u32, @ptrToInt(&mbox)) | @enumToInt(MailboxChannel.PropertyTagsARMtoVC);
    logger.log("Sending {x}\r\n", .{val});
    @intToPtr(*volatile u32, MAILBOX_WRITE).* = val;
    const result = mbox_read();
    logger.log("Result {x}\r\n", .{result});
    logger.log("Statu code: {x}\r\n", .{@ptrCast(*volatile u32, &mbox[1]).*});
    for (mbox) |*v| {
        logger.log("{x}\r\n", .{@ptrCast(*volatile u32, v).*});
    }
}

var mbox2 align(16) = [_]u32{
    32, // The whole buffer is 32 bytes
    0, // This is a request, so the request/response code is 0
    0x00040001, 8, 8, 4096, 0, // This tag requests a 16 byte aligned framebuffer
    0,
};

fn request_framebuffer() void {
    while (true) {
        const val = @intToPtr(*volatile u32, MAILBOX_STATUS).*;
        if (((val >> 31) & 1) == 0) {
            break;
        }
    }

    logger.log("mbox is at {x}\r\n", .{@ptrToInt(&mbox2)});
    const val: u32 = 0x40000000 + @truncate(u32, @ptrToInt(&mbox2)) | @enumToInt(MailboxChannel.PropertyTagsARMtoVC);
    logger.log("Sending {x}\r\n", .{val});
    @intToPtr(*volatile u32, MAILBOX_WRITE).* = val;
    const result = mbox_read();
    logger.log("Result {x}\r\n", .{result});
    logger.log("Status code: {x}\r\n", .{@ptrCast(*volatile u32, &mbox2[1]).*});
    for (mbox2) |*v| {
        logger.log("{x}\r\n", .{@ptrCast(*volatile u32, v).*});
    }
}

export fn entry() noreturn {
    kernel.logging.register_sink(&uart_node);
    logger.log("Hello from Raspberry Pi!\r\n", .{});
    setup_framebuffer();
    request_framebuffer();
    hang();
}

pub fn hang() noreturn {
    while (true) {}
}
