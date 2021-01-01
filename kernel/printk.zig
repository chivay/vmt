const std = @import("std");

const SinglyLinkedList = std.SinglyLinkedList;
pub const PrintkSink = fn ([]const u8) void;

pub const SinkNode: type = SinglyLinkedList(PrintkSink).Node;

var printk_sinks = SinglyLinkedList(PrintkSink){ .first = null };

pub fn register_sink(sink: *SinkNode) void {
    printk_sinks.prepend(sink);
}

fn do_printk(buffer: []const u8) void {
    var sink = printk_sinks.first;
    while (sink != null) : (sink = sink.?.next) {
        sink.?.data(buffer);
    }
}

var printk_buffer: [0x1000]u8 = undefined;
var fbs = std.io.fixedBufferStream(&printk_buffer);
var out_stream = fbs.outStream();

pub fn printk(comptime fmt: []const u8, args: anytype) void {
    fbs.reset();
    std.fmt.format(out_stream, fmt, args) catch |err| {};
    do_printk(fbs.getWritten());
}

pub const LogLevel = enum {
    Critical = 0,
    Error = 1,
    Warning = 2,
    Info = 3,
    Debug = 4,
};

pub fn logger(comptime prefix: []const u8) type {
    return struct {
        const PREFIX = prefix;
        const log_level = LogLevel.Info;

        pub fn log(comptime fmt: []const u8, args: anytype) void {
            log_raw(LogLevel.Info, fmt, args);
        }

        fn log_raw(comptime level: LogLevel, comptime fmt: []const u8, args: anytype) void {
            if (comptime (@enumToInt(level) >= @enumToInt(log_level))) {
                printk("[" ++ @tagName(level) ++ "] " ++ PREFIX ++ ": " ++ fmt, args);
            }
        }

        pub fn info(comptime fmt: []const u8, args: anytype) void {
            log_raw(LogLevel.Info, fmt, args);
        }

        pub fn debug(comptime fmt: []const u8, args: anytype) void {
            log_raw(LogLevel.Debug, fmt, args);
        }

        pub fn err(comptime fmt: []const u8, args: anytype) void {
            log_raw(LogLevel.Error, fmt, args);
        }

        pub fn warning(comptime fmt: []const u8, args: anytype) void {
            log_raw(LogLevel.Warning, fmt, args);
        }

        pub fn critical(comptime fmt: []const u8, args: anytype) void {
            log_raw(LogLevel.Critical, fmt, args);
        }

        pub fn childOf(child_prefix: []const u8) type {
            return logger(PREFIX ++ "." ++ child_prefix);
        }
    };
}
