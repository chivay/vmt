const std = @import("std");
const assert = std.debug.assert;
usingnamespace @import("x86/asm.zig");

pub const vga = @import("x86/vga.zig");
pub const serial = @import("x86/serial.zig");
pub const pic = @import("x86/pic.zig");

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

    pub fn new(index: u16, rpl: PrivilegeLevel) SegmentSelector {
        return SegmentSelector{ .raw = index << 3 | @enumToInt(rpl) };
    }
};

pub const GDTEntry = packed struct {
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

    pub const nil = GDTEntry{ .raw = 0 };
    pub const KernelData = GDTEntry{ .raw = ORDINARY | DEFAULT_SIZE };
    pub const KernelCode = GDTEntry{ .raw = ORDINARY | EXECUTABLE | LONG_MODE };
    pub const UserCode = GDTEntry{ .raw = KernelCode.raw | RING_3 };
    pub const UserData = GDTEntry{ .raw = KernelData.raw | RING_3 };

    pub fn TaskState(tss: *TSS) [2]GDTEntry {
        var high: u64 = 0;
        var ptr = @ptrToInt(tss);

        var low: u64 = 0;
        low |= PRESENT;
        // 64 bit available TSS;
        low |= 0b1001 << 40;
        // set limit
        low |= (@sizeOf(TSS) - 1) & 0xffff;

        // set pointer
        // 0..23 bits
        low |= (ptr & 0x7fffff) << 16;

        // high bits part
        high |= (ptr & 0xffffffff00000000) >> 32;
        return [2]GDTEntry{ GDTEntry{ .raw = low }, GDTEntry{ .raw = high } };
    }
};

pub fn GlobalDescriptorTable(n: u16) type {
    return packed struct {
        entries: [n]GDTEntry align(0x10),
        free_slot: u16,

        const Self = @This();

        pub fn new() Self {
            var gdt = Self{ .entries = std.mem.zeroes([n]GDTEntry), .free_slot = 0 };
            return gdt;
        }

        pub fn add_entry(self: *Self, entry: GDTEntry) SegmentSelector {
            assert(self.free_slot < n);
            self.entries[self.free_slot] = entry;
            self.free_slot += 1;

            const dpl = @intToEnum(PrivilegeLevel, @intCast(u2, (entry.raw >> 45) & 0b11));
            return SegmentSelector.new(self.free_slot - 1, dpl);
        }

        pub fn load(self: Self) void {
            const init = packed struct {
                    size: u16,
                    base: u64,
                }{
                .base = @ptrToInt(&self.entries),
                .size = @sizeOf(@TypeOf(self.entries)) - 1,
            };

            lgdt(@ptrToInt(&init));
        }
    };
}

pub fn get_vendor_string() [12]u8 {
    const info = cpuid(0, 0);
    const vals = [_]u32{ info.ebx, info.edx, info.ecx };

    var result: [12]u8 = undefined;
    std.mem.copy(u8, result[0..], std.mem.sliceAsBytes(vals[0..]));
    return result;
}

pub fn hang() noreturn {
    while (true) {
        cli();
        hlt();
    }
}

pub fn MSR(n: u32) type {
    return struct {
        pub inline fn read() u64 {
            return rdmsr(n);
        }
        pub inline fn write(value: u64) void {
            wrmsr(n, value);
        }
    };
}

pub const APIC_BASE = MSR(0x0000_001B);
pub const EFER = MSR(0xC000_0080);
pub const LSTAR = MSR(0xC000_0082);

pub const FSBASE = MSR(0xC000_0100);
pub const GSBASE = MSR(0xC000_0101);
pub const KERNEL_GSBASE = MSR(0xC000_0102);
