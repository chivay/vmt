const std = @import("std");

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
