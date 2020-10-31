const std = @import("std");
const kernel = @import("root");

const printk = kernel.printk;

const x86 = @import("../x86.zig");

pub fn KiB(comptime bytes: u64) u64 {
    return bytes * 1024;
}

pub fn MiB(comptime bytes: u64) u64 {
    return KiB(bytes) * 1024;
}

pub fn GiB(comptime bytes: u64) u64 {
    return KiB(bytes) * 1024;
}

pub fn TiB(comptime bytes: u64) u64 {
    return KiB(bytes) * 1024;
}

pub extern var kernel_end: [*]u8;

pub fn get_kernel_end() u64 {
    return @ptrToInt(&kernel_end);
}

pub const IdentityMapping = struct {
    pub const VIRT_START = 0xffffffff80000000;
    pub const SIZE = GiB(10);
    pub const VIRT_END = VIRT_START + SIZE;

    pub fn virt_to_phys(addr: u64) u64 {
        std.debug.assert(addr >= VIRT_START and addr < VIRT_END);
        return addr - VIRT_START;
    }

    pub fn phys_to_virt(addr: u64) u64 {
        std.debug.assert(addr < SIZE);
        return addr + VIRT_START;
    }
};

pub const FrameAllocator = struct {
    initialized: bool,
    // next physical address to allocate
    next_free: u64,
    limit: u64,
    freelist: std.SinglyLinkedList(void),

    const PAGE_SIZE = 0x1000;

    const Self = @This();

    const OutOfMemory = error.OutOfMemory;

    pub fn init(self: *Self) *FrameAllocator {
        if (self.initialized) {
            return self;
        }

        self.next_free = IdentityMapping.virt_to_phys(get_kernel_end());
        self.limit = self.next_free + GiB(1);
        self.initialized = true;

        return self;
    }

    pub fn alloc_frame(self: *Self) !u64 {
        // Try allocating from freelist
        if (self.freelist.popFirst()) |node| {
            const virt_addr = @ptrToInt(node);
            const phys_addr = IdentityMapping.virt_to_phys(virt_addr);
            return phys_addr;
        }
        // No free pages in list
        return self.alloc_pool(1);
    }

    pub fn alloc_pool(self: *Self, n: u64) !u64 {
        const page = self.next_free;
        const allocation_size = PAGE_SIZE * n;
        self.next_free += allocation_size;
        if (self.next_free >= self.limit) {
            self.next_free -= allocation_size;
            return OutOfMemory;
        }
        std.debug.assert(std.mem.isAligned(page, PAGE_SIZE));
        return page;
    }

    pub fn free_frame(self: *Self, addr: u64) void {
        std.debug.assert(std.mem.isAligned(addr, PAGE_SIZE));
        const virt_addr = IdentityMapping.phys_to_virt(addr);
        const node = @intToPtr(*@TypeOf(self.freelist).Node, virt_addr);
        self.freelist.prepend(node);
    }
};

var main_allocator: FrameAllocator = std.mem.zeroes(FrameAllocator);

pub fn frameAllocator() *FrameAllocator {
    return main_allocator.init();
}

pub const MemoryRange = struct {
    base: u64,
    size: u64,
};

pub fn detect_memory() ?MemoryRange {
    if (x86.multiboot.info_pointer) |mbinfo| {
        return detect_multiboot_memory(mbinfo);
    }

    return null;
}

fn bit_set(value: var, comptime bit: usize) bool {
    return ((value >> bit) & 1) != 0;
}

fn detect_multiboot_memory(mb_info: *x86.multiboot.Info) ?MemoryRange {
    if (!bit_set(mb_info.flags, 6)) {
        @panic("Missing memory map!");
    }

    const MemEntry = packed struct {
        // at -4 offset
        size: u32,
        // at 0 offset
        base_addr: u64,
        length: u64,
        type_: u32,
    };

    var best_slot: ?MemoryRange = null;

    var offset = mb_info.mmap_addr;
    const mmap_end = mb_info.mmap_addr + mb_info.mmap_length;

    printk("BIOS memory map:\n", .{});
    while (offset < mmap_end) {
        const entry = @intToPtr(*MemEntry, x86.mm.IdentityMapping.phys_to_virt(offset));

        const start = entry.base_addr;
        const end = start + entry.length - 1;
        const status = switch (entry.type_) {
            1 => "Available",
            3 => "ACPI Mem",
            4 => "Preserved on hibernation",
            5 => "Defective",
            else => "Reserved",
        };
        printk("[{x:0>10}-{x:0>10}] {}\n", .{ start, end, status });
        offset += entry.size + @sizeOf(@TypeOf(entry.size));

        const this_slot = MemoryRange{ .base = entry.base_addr, .size = entry.length };

        if (best_slot) |slot| {
            if (this_slot.size > slot.size) {
                best_slot = this_slot;
            }
        } else {
            best_slot = this_slot;
        }
    }

    return best_slot;
}
