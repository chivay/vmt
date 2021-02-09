const x86 = @import("../x86.zig");
const io = @import("std").io;

pub fn SerialPort(comptime id: u8) type {
    const PORT_BASES = [_]u16{ 0x3f8, 0x2f8, 0x3e8, 0x2e8A };

    if (id < 1 or id > PORT_BASES.len) {
        @compileError("Serial port id outside of range");
    }

    return struct {
        const PORT_BASE = PORT_BASES[id - 1];

        const Self = @This();

        const SerialError = error{SerialError};
        pub const Writer = io.Writer(Self, SerialError, write);

        pub fn writer() Writer {
            return .{ .context = Self{} };
        }

        pub fn init() void {
            // Disable interrupts
            x86.out(u8, PORT_BASE + 1, 0x00);
            // Enable DLAB
            x86.out(u8, PORT_BASE + 3, 0x80);
            // Set divisor to 1
            x86.out(u8, PORT_BASE + 0, 0x01);
            x86.out(u8, PORT_BASE + 1, 0x00);
            // 8 bits, no parity, 1 stop bit
            x86.out(u8, PORT_BASE + 3, 0x03);

            x86.out(u8, PORT_BASE + 2, 0xc7);
            //x86.out(u8, PORT_BASE + 4, 0x0b);
        }

        pub inline fn write_char(self: Self, c: u8) void {
            while (x86.in(u8, PORT_BASE + 5) & 0x20 == 0) {}
            x86.out(u8, PORT_BASE, c);
        }

        pub fn write(self: Self, data: []const u8) SerialError!usize {
            for (data) |c| {
                self.write_char(c);
            }
            return data.len;
        }
    };
}
