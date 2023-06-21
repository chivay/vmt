const std = @import("std");
const kernel = @import("root");

const SinglyLinkedList = std.SinglyLinkedList;
pub const PrintkSink = *const fn ([]const u8) void;

pub const SinkNode: type = SinglyLinkedList(PrintkSink).Node;

var printk_sinks = SinglyLinkedList(PrintkSink){ .first = null };

pub fn register_sink(sink: *SinkNode) void {
    printk_sinks.prepend(sink);
}

var printk_spinlock = kernel.lib.Spinlock.init();

fn do_printk(buffer: []const u8) void {
    var sink = printk_sinks.first;
    while (sink != null) : (sink = sink.?.next) {
        sink.?.data(buffer);
    }
}

var printk_buffer: [0x10000]u8 = undefined;
var fbs = std.io.fixedBufferStream(&printk_buffer);
var out_stream = fbs.writer();

pub fn printk(comptime fmt: []const u8, args: anytype) void {
    const lock = printk_spinlock.acquire();
    defer lock.release();

    fbs.reset();
    std.fmt.format(out_stream, fmt, args) catch {};
    do_printk(fbs.getWritten());
}

pub const LogLevel = enum(u8) {
    Critical = 0,
    Error = 1,
    Warning = 2,
    Info = 3,
    Debug = 4,
};

pub fn logger(comptime prefix: []const u8) type {
    return struct {
        pub const Level = LogLevel;
        const PREFIX = prefix;

        log_level: LogLevel = LogLevel.Info,

        pub fn log(self: @This(), comptime fmt: []const u8, args: anytype) void {
            self.log_raw(LogLevel.Info, fmt, args);
        }

        pub fn setLevel(self: *@This(), level: LogLevel) void {
            self.log_level = level;
        }

        fn log_raw(self: @This(), comptime level: LogLevel, comptime fmt: []const u8, args: anytype) void {
            if ((@enumToInt(level) <= @enumToInt(self.log_level))) {
                printk("[" ++ @tagName(level) ++ "] " ++ PREFIX ++ ": " ++ fmt, args);
            }
        }

        pub fn info(self: @This(), comptime fmt: []const u8, args: anytype) void {
            self.log_raw(LogLevel.Info, fmt, args);
        }

        pub fn debug(self: @This(), comptime fmt: []const u8, args: anytype) void {
            self.log_raw(LogLevel.Debug, fmt, args);
        }

        pub fn err(self: @This(), comptime fmt: []const u8, args: anytype) void {
            self.log_raw(LogLevel.Error, fmt, args);
        }

        pub fn warning(self: @This(), comptime fmt: []const u8, args: anytype) void {
            self.log_raw(LogLevel.Warning, fmt, args);
        }

        pub fn critical(self: @This(), comptime fmt: []const u8, args: anytype) void {
            self.log_raw(LogLevel.Critical, fmt, args);
        }

        pub fn childOf(comptime child_prefix: []const u8) type {
            return logger(PREFIX ++ "." ++ child_prefix);
        }
    };
}
