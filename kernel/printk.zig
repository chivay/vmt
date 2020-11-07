const std = @import("std");

const SinglyLinkedList = std.SinglyLinkedList;
pub const PrintkSink = fn ([]const u8) void;

pub const SinkNode: type = SinglyLinkedList(PrintkSink).Node;

var printk_sinks = SinglyLinkedList(PrintkSink).init();

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

pub fn printk(comptime fmt: []const u8, args: var) void {
    fbs.reset();
    std.fmt.format(out_stream, fmt, args) catch |err| {};
    do_printk(fbs.getWritten());
}

pub const LogLevel = enum {
    CRITICAL,
    ERROR,
    WARNING,
    INFO,
    DEBUG,
};

pub fn logger(comptime prefix: []const u8) type {
    return struct {
        const PREFIX = prefix;

        pub fn log(comptime fmt: []const u8, args: var) void {
            printk(PREFIX ++ ": " ++ fmt, args);
        }

        pub fn childOf(child_prefix: []const u8) type {
            return logger(PREFIX ++ "." ++ child_prefix);
        }
    };
}
