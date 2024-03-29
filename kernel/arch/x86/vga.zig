const std = @import("std");
const io = std.io;
const kernel = @import("root");
const mm = kernel.mm;
const x86 = @import("../x86.zig");

var vga_console: ?VGAConsole = null;

pub fn getConsole() *VGAConsole {
    if (vga_console == null) {
        vga_console = VGAConsole.init();
    }
    return &vga_console.?;
}

pub const VGADevice = struct {
    const VGA_WIDTH = 80;
    const VGA_HEIGHT = 25;

    const Buffer = [VGA_HEIGHT][VGA_WIDTH]u16;

    const Color = enum(u4) {
        Black = 0,
        Blue = 1,
        Green = 2,
        Cyan = 3,
        Red = 4,
        Purple = 5,
        Brown = 6,
        Gray = 7,
        DarkGray = 8,
        LightBlue = 9,
        LightGreen = 10,
        LightCyan = 11,
        LightRed = 12,
        LightPurple = 13,
        Yellow = 14,
        White = 15,
    };

    const default_color = make_color(Color.Gray, Color.Black);

    pub fn get_buffer() *Buffer {
        const phys = mm.PhysicalAddress.new(0xb8000);
        return mm.directMapping().to_virt(phys).into_pointer(*Buffer);
    }

    pub fn make_color(back: Color, front: Color) u8 {
        const b = @intFromEnum(front);
        const f = @intFromEnum(back);
        return (@as(u8, b) << 4) | @as(u8, f);
    }

    pub fn make_entry(c: u8, color: u8) u16 {
        return (@as(u16, c) & 0xff) + (@as(u16, color) << 8);
    }

    pub fn put_at(c: u8, x: u16, y: u16) void {
        get_buffer()[y][x] = make_entry(c, default_color);
    }

    pub fn clear() void {
        var i: u16 = 0;
        while (i < VGA_HEIGHT) : (i += 1) {
            clear_row(i);
        }
    }

    fn clear_row(idx: u16) void {
        std.debug.assert(idx < VGA_HEIGHT);
        const entry = make_entry(' ', default_color);
        @memset(get_buffer()[idx][0..], entry);
    }

    pub fn scroll_row() void {
        // Copy one row up
        var i: u16 = 1;
        while (i < VGADevice.VGA_HEIGHT) : (i += 1) {
            // Copy ith row into i-1th row
            var dest = get_buffer()[i - 1][0..];
            var src = get_buffer()[i][0..];
            std.mem.copy(u16, dest, src);
        }

        clear_row(VGADevice.VGA_HEIGHT - 1);
    }

    pub fn disable_cursor() void {
        x86.out(u8, 0x3d4, 0x0a);
        x86.out(u8, 0x3d5, 0x20);
    }

    pub fn set_cursor(x: u16, y: u16) void {
        const pos = VGA_WIDTH * y + x;

        x86.out(u8, 0x3d4, 0x0f);
        x86.out(u8, 0x3d5, @intCast(pos & 0xff));
        x86.out(u8, 0x3d4, 0x0e);
        x86.out(u8, 0x3d5, @intCast((pos >> 8) & 0xff));
    }
};

pub const VGAConsole = struct {
    cursor_x: u16,
    cursor_y: u16,

    pub fn init() VGAConsole {
        VGADevice.clear();
        return VGAConsole{
            .cursor_x = 0,
            .cursor_y = 0,
        };
    }

    const Self = @This();

    const VGAError = error{VGAError};
    pub const Writer = io.Writer(*VGAConsole, VGAError, write);

    pub fn writer(self: *Self) Writer {
        return .{ .context = self };
    }

    fn ensure_scrolled(self: *Self) void {
        if (self.cursor_x >= VGADevice.VGA_WIDTH) {
            self.cursor_y += 1;
            self.cursor_x = 0;
        }
        if (self.cursor_y == VGADevice.VGA_HEIGHT) {
            self.cursor_y = VGADevice.VGA_HEIGHT - 1;
            VGADevice.scroll_row();
        }
    }

    fn write_char(self: *Self, c: u8) void {
        switch (c) {
            '\n' => {
                self.cursor_y += 1;
                self.cursor_x = 0;
            },

            '\r' => {
                self.cursor_x = 0;
            },

            else => {
                std.debug.assert(self.cursor_x < VGADevice.VGA_WIDTH);
                std.debug.assert(self.cursor_y < VGADevice.VGA_HEIGHT);
                VGADevice.put_at(c, self.cursor_x, self.cursor_y);
                self.cursor_x += 1;
            },
        }
        self.ensure_scrolled();
    }

    pub fn write(self: *Self, str: []const u8) VGAError!usize {
        for (str) |c| {
            self.write_char(c);
        }
        VGADevice.set_cursor(self.cursor_x, self.cursor_y);
        return str.len;
    }
};
