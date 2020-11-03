const std = @import("std");
const arch = @import("root").arch;

pub fn identityMapping() *IdentityMapping {
    return arch.mm.identityMapping();
}

pub fn identityTranslate(phys: PhysicalAddress) VirtualAddress {
    return identityMapping().to_virt(phys);
}

pub fn frameAllocator() *FrameAllocator {
    return arch.mm.frameAllocator();
}

pub fn KiB(comptime bytes: u64) u64 {
    return bytes * 1024;
}

pub fn MiB(comptime bytes: u64) u64 {
    return KiB(bytes) * 1024;
}

pub fn GiB(comptime bytes: u64) u64 {
    return MiB(bytes) * 1024;
}

pub fn TiB(comptime bytes: u64) u64 {
    return GiB(bytes) * 1024;
}

pub const VirtualAddress = struct {
    const Type = arch.mm.VirtAddrType;

    value: Type,

    pub fn new(value: Type) VirtualAddress {
        return .{ .value = value };
    }

    pub fn into_pointer(self: @This(), comptime T: type) T {
        return @intToPtr(T, self.value);
    }

    pub fn add(self: @This(), val: Type) VirtualAddress {
        return .{ .value = val + self.value };
    }

    pub fn sub(self: @This(), val: Type) VirtualAddress {
        return .{ .value = val + self.value };
    }

    pub fn le(self: @This(), other: VirtualAddress) bool {
        return self.value <= other.value;
    }

    pub fn lt(self: @This(), other: VirtualAddress) bool {
        return self.value < other.value;
    }

    pub fn span(from: VirtualAddress, to: VirtualAddress) usize {
        return to.value - from.value;
    }

    pub fn format(self: @This(), fmt: []const u8, options: std.fmt.FormatOptions, stream: var) !void {
        try stream.writeAll(@typeName(@This()));
        try stream.writeAll("{");
        try std.fmt.formatInt(self.value, 16, false, options, stream);
        try stream.writeAll("}");
    }

    pub fn isAligned(self: @This(), val: var) bool {
        return std.mem.isAligned(self.value, val);
    }
};

pub const PhysicalAddress = struct {
    const Type = arch.mm.PhysAddrType;

    value: Type,

    pub fn new(value: Type) PhysicalAddress {
        return .{ .value = value };
    }

    pub fn add(self: @This(), val: Type) PhysicalAddress {
        return .{ .value = val + self.value };
    }

    pub fn sub(self: @This(), val: Type) PhysicalAddress {
        return .{ .value = val + self.value };
    }

    pub fn span(from: PhysicalAddress, to: PhysicalAddress) usize {
        return to.value - from.value;
    }

    pub fn max(self: @This(), other: PhysicalAddress) PhysicalAddress {
        if (other.value > self.value) {
            return other;
        }
        return self;
    }

    pub fn isAligned(self: @This(), val: var) bool {
        return std.mem.isAligned(self.value, val);
    }

    pub fn alignForward(self: @This(), val: var) PhysicalAddress {
        return PhysicalAddress.new(std.mem.alignForward(self.value, val));
    }

    pub fn lt(self: @This(), other: PhysicalAddress) bool {
        return self.value < other.value;
    }

    pub fn le(self: @This(), other: PhysicalAddress) bool {
        return self.value <= other.value;
    }

    pub fn format(self: @This(), fmt: []const u8, options: std.fmt.FormatOptions, stream: var) !void {
        try stream.writeAll(@typeName(@This()));
        try stream.writeAll("{");
        try std.fmt.formatInt(self.value, 16, false, options, stream);
        try stream.writeAll("}");
    }
};

pub const IdentityMapping = struct {
    /// Simple mapping from boot time
    virt_start: VirtualAddress,
    size: usize,

    pub fn init(start: VirtualAddress, size: usize) IdentityMapping {
        return .{
            .virt_start = start,
            .size = size,
        };
    }

    pub fn set_size(self: @This(), value: usize) void {
        self.size = value;
    }

    pub fn set_base(self: @This(), value: VirtualAddress) void {
        self.virt_start = value;
    }

    fn virt_end(self: @This()) VirtualAddress {
        return self.virt_start.add(self.size);
    }

    pub fn to_phys(self: @This(), addr: VirtualAddress) PhysicalAddress {
        std.debug.assert(self.virt_start.le(addr) and addr.lt(self.virt_end()));
        return PhysicalAddress.new(addr.value - self.virt_start.value);
    }

    pub fn to_virt(self: @This(), addr: PhysicalAddress) VirtualAddress {
        std.debug.assert(addr.value < self.size);
        return VirtualAddress.new(addr.value + self.virt_start.value);
    }
};

pub var kernel_vm: VirtualMemory = undefined;
pub const VirtualMemory = struct {
    vm_impl: *arch.mm.VirtualMemoryImpl,
    const Self = @This();

    pub fn init(vm_impl: *arch.mm.VirtualMemoryImpl) VirtualMemory {
        return .{ .vm_impl = vm_impl };
    }

    pub fn map_addr(self: Self, where: VirtualAddress, what: PhysicalAddress, length: usize) !void {
        return self.vm_impl.map_addr(where, what, length);
    }
    pub fn switch_to(self: Self) void {
        self.vm_impl.switch_to();
    }
};

pub const FrameAllocator = struct {
    // next physical address to allocate
    next_free: PhysicalAddress,
    limit: PhysicalAddress,
    freelist: std.SinglyLinkedList(void),

    const PAGE_SIZE = 0x1000;

    const Self = @This();

    const OutOfMemory = error.OutOfMemory;

    pub fn new(memory: MemoryRange) FrameAllocator {
        return .{
            .next_free = memory.base.alignForward(PAGE_SIZE),
            .limit = memory.get_end(),
            .freelist = std.SinglyLinkedList(void).init(),
        };
    }

    pub fn alloc_zero_frame(self: *Self) !PhysicalAddress {
        const frame = try self.alloc_frame();
        const buf = identityMapping().to_virt(frame).into_pointer(*[PAGE_SIZE]u8);
        std.mem.set(u8, buf, 0);

        return frame;
    }

    pub fn alloc_zero_aligned(self: *Self, alignment: usize, n: usize) !PhysicalAddress {
        const frame = try self.alloc_aligned(alignment, n);
        const buf = identityMapping().to_virt(frame).into_pointer([*]u8);
        std.mem.set(u8, buf[0..(n * PAGE_SIZE)], 0);

        return frame;
    }

    pub fn alloc_aligned(self: *Self, alignment: usize, n: usize) !PhysicalAddress {
        // Skip until we have aligned page
        while (!self.next_free.isAligned(alignment)) {
            const frame = try self.alloc_pool(1);
            self.free_frame(frame);
        }
        return self.alloc_pool(n);
    }

    pub fn alloc_frame(self: *Self) !PhysicalAddress {
        // Try allocating from freelist
        if (self.freelist.popFirst()) |node| {
            const virt_addr = VirtualAddress.new(@ptrToInt(node));
            const phys_addr = identityMapping().to_phys(virt_addr);
            return phys_addr;
        }
        // No free pages in list
        return self.alloc_pool(1);
    }

    pub fn alloc_pool(self: *Self, n: u64) !PhysicalAddress {
        const page = self.next_free;
        const allocation_size = PAGE_SIZE * n;
        self.next_free = self.next_free.add(allocation_size);
        if (self.limit.le(self.next_free)) {
            self.next_free = self.next_free.sub(allocation_size);
            return OutOfMemory;
        }
        std.debug.assert(page.isAligned(PAGE_SIZE));
        return page;
    }

    pub fn free_frame(self: *Self, addr: PhysicalAddress) void {
        std.debug.assert(std.mem.isAligned(addr.value, PAGE_SIZE));
        const virt_addr = identityMapping().to_virt(addr);
        const node = virt_addr.into_pointer(*@TypeOf(self.freelist).Node);
        self.freelist.prepend(node);
    }
};

pub const MemoryRange = struct {
    base: PhysicalAddress,
    size: u64,

    pub fn get_end(self: @This()) PhysicalAddress {
        return self.base.add(self.size);
    }

    pub fn from_range(start: PhysicalAddress, end: PhysicalAddress) MemoryRange {
        std.debug.assert(start.lt(end));
        const size = PhysicalAddress.span(start, end);
        return .{ .base = start, .size = size };
    }
};

pub fn init() void {
    arch.mm.init();
}
