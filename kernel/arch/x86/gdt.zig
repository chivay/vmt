const std = @import("std");
const assert = std.debug.assert;
const x86 = @import("../x86.zig");

pub const TSS = packed struct {
    _reserved1: u32,
    rsp: [3]u64,
    _reserved2: u32,
    _reserved3: u32,
    ist: [8]u64,
    _reserved4: u16,
    io_map_addr: u16,
};

comptime {
    assert(@sizeOf(TSS) == 104);
}

pub const PrivilegeLevel = enum(u2) {
    Ring0 = 0,
    Ring3 = 3,
};

pub const SegmentSelector = struct {
    raw: u16,

    pub fn new(_index: u16, _rpl: PrivilegeLevel) SegmentSelector {
        return .{ .raw = _index << 3 | @enumToInt(_rpl) };
    }

    pub fn index(self: @This()) u16 {
        return self.raw >> 3;
    }

    pub fn rpl(self: @This()) SegmentSelector {
        return @intToEnum(PrivilegeLevel, self.raw & 0b11);
    }
};

pub fn GlobalDescriptorTable(n: u16) type {
    return packed struct {
        entries: [n]Entry align(0x10),
        free_slot: u16,

        pub const Entry = packed struct {
            raw: u64,

            const WRITABLE = 1 << 41;
            const CONFORMING = 1 << 42;
            const EXECUTABLE = 1 << 43;
            const USER = 1 << 44;
            const RING_3 = 3 << 45;
            const PRESENT = 1 << 47;
            const LONG_MODE = 1 << 53;
            const DEFAULT_SIZE = 1 << 54;
            const GRANULARITY = 1 << 55;

            const LIMIT_LO = 0xffff;
            const LIMIT_HI = 0xf << 48;

            const ORDINARY = USER | PRESENT | WRITABLE | LIMIT_LO | LIMIT_HI | GRANULARITY;

            pub const nil = Entry{ .raw = 0 };
            pub const KernelData = Entry{ .raw = ORDINARY | DEFAULT_SIZE };
            pub const KernelCode = Entry{ .raw = ORDINARY | EXECUTABLE | LONG_MODE };
            pub const UserCode = Entry{ .raw = KernelCode.raw | RING_3 };
            pub const UserData = Entry{ .raw = KernelData.raw | RING_3 };

            pub fn TaskState(tss: *TSS) [2]Entry {
                var high: u64 = 0;
                var ptr = @ptrToInt(tss);

                var low: u64 = 0;
                low |= PRESENT;
                // 64 bit available TSS;
                low |= 0b1001 << 40;
                // set limit
                low |= (@sizeOf(TSS) - 1) & 0xffff;
                low |= ((ptr >> 24) & 0xff) << 56;

                // set pointer
                // 0..24 bits
                low |= (ptr & 0xffffff) << 16;

                // high bits part
                high |= ptr >> 32;
                return [2]Entry{ .{ .raw = low }, .{ .raw = high } };
            }
        };

        const Self = @This();

        pub fn new() Self {
            var gdt = Self{ .entries = std.mem.zeroes([n]Entry), .free_slot = 0 };
            return gdt;
        }

        pub fn add_entry(self: *Self, entry: Entry) SegmentSelector {
            assert(self.free_slot < n);
            self.entries[self.free_slot] = entry;
            self.free_slot += 1;

            const dpl = @intToEnum(PrivilegeLevel, @intCast(u2, (entry.raw >> 45) & 0b11));
            return SegmentSelector.new(self.free_slot - 1, dpl);
        }

        pub fn load(self: Self) void {
            const descriptor = packed struct {
                size: u16,
                base: u64,
            }{
                .base = @ptrToInt(&self.entries),
                .size = @sizeOf(@TypeOf(self.entries)) - 1,
            };

            x86.lgdt(@ptrToInt(&descriptor));
        }

        pub fn reload_cs(self: Self, selector: SegmentSelector) void {
            __reload_cs(selector.raw);
        }
    };
}

extern fn __reload_cs(selector: u32) void;
comptime {
    asm (
        \\ .global __reload_cs;
        \\ .type __reload_cs, @function;
        \\ __reload_cs:
        \\ pop %rsi
        \\ push %rdi
        \\ push %rsi
        \\ lretq
    );
}
