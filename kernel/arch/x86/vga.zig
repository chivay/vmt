const io = @import("std").io;
const os = @import("std").os;

const x86 = @import("../x86.zig");

pub const VGADevice = struct {
    const VGA_WIDTH = 80;
    const VGA_HEIGHT = 25;

    const Color = packed enum(u4) {
        Black = 0, Blue = 1, Green = 2, Cyan = 3, Red = 4, Purple = 5, Brown = 6, Gray = 7, DarkGray = 8, LightBlue = 9, LightGreen = 10, LightCyan = 11, LightRed = 12, LightPurple = 13, Yellow = 14, White = 15
    };

    pub fn make_color(back: Color, front: Color) u8 {
        const b = @enumToInt(front);
        const f = @enumToInt(back);
        return (@as(u8, b) << 4) | @as(u8, f);
    }

    pub fn put_at(c: u8, x: u16, y: u16) void {
        if (x >= VGA_WIDTH or y >= VGA_HEIGHT) {
            return;
        }
        const screen = @intToPtr([*]u16, 0xb8000);
        const color = make_color(Color.Gray, Color.Black);
        screen[VGA_WIDTH * y + x] = ((@as(u16, c) & 0xff)) + (@as(u16, color) << 8);
    }

    pub fn clear() void {
        var i: u16 = 0;
        while (i < VGA_HEIGHT) : (i += 1) {
            var j: u16 = 0;
            while (j < VGA_WIDTH) : (j += 1) {
                put_at(' ', j, i);
            }
        }
    }

    pub fn disable_cursor() void {
        x86.out(u8, 0x3D4, 0x0A);
        x86.out(u8, 0x3D5, 0x20);
    }
};

pub const VGAConsole = struct {
    cursor_x: u16,
    cursor_y: u16,

    pub fn init() VGAConsole {
        VGADevice.clear();
        VGADevice.disable_cursor();
        return VGAConsole{
            .cursor_x = 0,
            .cursor_y = 0,
        };
    }

    const Self = @This();

    const VGAError = error{VGAError};
    pub const OutStream = io.OutStream(*VGAConsole, VGAError, write);

    pub fn outStream(self: *Self) OutStream {
        return .{ .context = self };
    }

    pub fn write_char(self: *Self, c: u8) void {
        if (c == '\n') {
            self.cursor_y += 1;
            self.cursor_x = 0;
            return;
        }

        if (c == '\r') {
            self.cursor_x = 0;
            return;
        }

        VGADevice.put_at(c, self.cursor_x, self.cursor_y);

        self.cursor_x += 1;

        if (self.cursor_x == VGADevice.VGA_WIDTH) {
            self.cursor_y += 1;
        }
        if (self.cursor_y == VGADevice.VGA_HEIGHT) {
            // TODO scroll
        }
    }

    pub fn write(self: *Self, str: []const u8) VGAError!usize {
        for (str) |c| {
            self.write_char(c);
        }

        return str.len;
    }
};
