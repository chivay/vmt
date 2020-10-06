const x86 = @import("../x86.zig");
const io = @import("std").io;

pub fn SerialPort(comptime id: u8) type {
    const PORT_BASES = [_]u16{ 0x3f8, 0x2f8, 0x3e8, 0x2e8A };

    if (id < 1 or id > PORT_BASES.len) {
        @compileError("Serial port id outside of range");
    }

    return struct {
        const PORT_BASE = PORT_BASES[id - 1];

        const SerialError = error{SerialError};
        pub const OutStream = io.OutStream(bool, SerialError, write);

        pub fn outStream() OutStream {
            return .{ .context = true };
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

        pub inline fn write_char(c: u8) void {
            x86.out(u8, PORT_BASE, c);
        }

        pub fn write(a: bool, data: []const u8) SerialError!usize {
            for (data) |c| {
                @This().write_char(c);
            }
            return data.len;
        }
    };
}
