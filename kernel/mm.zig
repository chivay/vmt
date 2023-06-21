const std = @import("std");
const arch = @import("root").arch;
const kernel = @import("kernel.zig");

const logger = @TypeOf(kernel.logger).childOf(@typeName(@This())){};

pub fn directMapping() *DirectMapping {
    return arch.mm.directMapping();
}

pub fn directTranslate(phys: PhysicalAddress) VirtualAddress {
    const virt = directMapping().to_virt(phys);
    return virt;
}

pub fn frameAllocator() *FrameAllocator {
    return arch.mm.frameAllocator();
}

pub fn getKernelVM() *VirtualMemory {
    return &kernel_vm;
}

const Dumper = struct {
    const Self = @This();
    const Mapping = struct {
        virt: VirtualAddress,
        phys: PhysicalAddress,
        size: usize,
    };

    prev: ?Mapping = null,

    pub fn walk(self: *Self, virt: VirtualAddress, phys: PhysicalAddress, page_size: usize) void {
        if (self.prev == null) {
            self.prev = Mapping{ .virt = virt, .phys = phys, .size = page_size };
            return;
        }
        const prev = self.prev.?;
        // Check if we can merge mapping
        const next_virt = prev.virt.add(prev.size);
        const next_phys = prev.phys.add(prev.size);
        if (next_virt.eq(virt) and next_phys.eq(phys)) {
            self.prev.?.size += page_size;
            return;
        }
        logger.log("{} -> {} (0x{x} bytes)\n", .{ prev.virt, prev.phys, prev.size });
        self.prev = Mapping{ .virt = virt, .phys = phys, .size = page_size };
    }

    pub fn done(self: @This()) void {
        if (self.prev) |prev| {
            logger.log("{} -> {} (0x{x} bytes)\n", .{ prev.virt, prev.phys, prev.size });
        }
    }
};

pub fn dump_vm_mappings(vm: *VirtualMemory) void {
    var visitor = Dumper{};
    vm.vm_impl.walk(Dumper, &visitor);
}

fn AddrWrapper(comptime name: []const u8, comptime T: type) type {
    return struct {
        const Type = T;
        const Self = @This();

        value: Type,

        pub fn new(value: Type) Self {
            return .{ .value = value };
        }

        pub fn into_pointer(self: Self, comptime P: type) P {
            return @intToPtr(P, self.value);
        }

        pub fn add(self: Self, val: Type) Self {
            return .{ .value = self.value + val };
        }

        pub fn sub(self: Self, val: Type) Self {
            return .{ .value = self.value - val };
        }

        pub fn le(self: Self, other: Self) bool {
            return self.value <= other.value;
        }

        pub fn lt(self: Self, other: Self) bool {
            return self.value < other.value;
        }

        pub fn eq(self: Self, other: Self) bool {
            return self.value == other.value;
        }

        pub fn span(from: Self, to: Self) usize {
            return to.value - from.value;
        }

        pub fn max(self: Self, other: Self) Self {
            return if (other.value > self.value) other else self;
        }

        pub fn alignForward(self: Self, val: anytype) Self {
            return Self.new(std.mem.alignForward(T, self.value, val));
        }

        pub fn format(self: Self, fmt: []const u8, options: std.fmt.FormatOptions, stream: anytype) !void {
            _ = fmt;
            try stream.writeAll(name);
            try stream.writeAll("{");
            try std.fmt.formatInt(self.value, 16, .lower, options, stream);
            try stream.writeAll("}");
        }

        pub fn isAligned(self: Self, val: anytype) bool {
            return std.mem.isAligned(self.value, val);
        }
    };
}

test "AddrWrapper" {
    const expect = std.testing.expect;

    const Addr = AddrWrapper("TestAddr", u64);

    const v1 = Addr.new(0x1000);
    const v2 = Addr.new(0x2000);

    try expect(v1.add(0x1000).eq(v2));
    try expect(v2.sub(0x1000).eq(v1));

    try expect(v1.le(v1));
    try expect(v2.eq(v2));

    try expect(Addr.span(v1, v2) == 0x1000);

    try expect(v1.max(v2).eq(v2));
}

pub const VirtualAddress = AddrWrapper("VirtualAddress", arch.mm.VirtAddrType);
pub const PhysicalAddress = AddrWrapper("PhysicalAddress", arch.mm.PhysAddrType);

pub const DirectMapping = struct {
    /// Simple mapping from boot time
    virt_start: VirtualAddress,
    size: usize,

    pub fn init(start: VirtualAddress, size: usize) DirectMapping {
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

var kernel_vm: VirtualMemory = undefined;

pub const VirtualMemory = struct {
    vm_impl: *arch.mm.VirtualMemoryImpl,
    const Self = @This();

    pub const Protection = struct {
        read: bool,
        write: bool,
        execute: bool,
        user: bool,

        pub const RWX = Protection{
            .read = true,
            .write = true,
            .execute = true,
            .user = false,
        };
        pub const RW = Protection{
            .read = true,
            .write = true,
            .execute = false,
            .user = false,
        };
        pub const R = Protection{
            .read = true,
            .write = false,
            .execute = false,
            .user = false,
        };
    };

    pub fn alloc_new() !*VirtualMemory {
        var vm = try memoryAllocator().alloc(VirtualMemory);
        var arch_vm = try memoryAllocator().alloc(arch.mm.VirtualMemoryImpl);
        arch_vm.* = try arch.mm.VirtualMemoryImpl.init(frameAllocator());
        vm.* = VirtualMemory.init(arch_vm);
        return vm;
    }

    pub fn clone(source: *VirtualMemory) !*VirtualMemory {
        var vm = try memoryAllocator().alloc(VirtualMemory);
        var arch_vm = try arch.mm.VirtualMemoryImpl.clone(source.vm_impl);
        vm.* = VirtualMemory.init(arch_vm);
        return vm;
    }

    pub fn destroy(self: *@This()) void {
        _ = self;
    }

    pub fn init(vm_impl: *arch.mm.VirtualMemoryImpl) VirtualMemory {
        return .{ .vm_impl = vm_impl };
    }

    pub fn map_memory(self: Self, where: VirtualAddress, what: PhysicalAddress, length: usize, protection: Protection) !VirtualMemoryRange {
        return self.vm_impl.map_memory(where, what, length, protection);
    }

    pub fn map_io(self: Self, what: PhysicalAddress, length: usize) !VirtualMemoryRange {
        return self.vm_impl.map_io(what, length);
    }

    pub fn unmap(self: Self, range: VirtualMemoryRange) !void {
        return self.vm_impl.unmap(range);
    }

    pub fn switch_to(self: Self) void {
        self.vm_impl.switch_to();
    }
};

pub const MemoryAllocator = struct {
    frame_allocator: *FrameAllocator,
    freelist: std.SinglyLinkedList(void),
    main_chunk: ?[]align(0x10) u8,

    const Self = @This();
    const max_alloc = 0x1000;

    pub fn new(frame_allocator: *FrameAllocator) MemoryAllocator {
        return .{
            .frame_allocator = frame_allocator,
            .freelist = std.SinglyLinkedList(void){ .first = null },
            .main_chunk = null,
        };
    }

    pub fn alloc_bytes(self: *Self, size: usize) ![]align(0x10) u8 {
        var real_size = std.mem.alignForward(usize, size, 0x10);

        if (self.main_chunk == null or self.main_chunk.?.len < real_size) {
            const frame = (try self.frame_allocator.alloc_frame());
            const virt = directTranslate(frame);

            var main_chunk: []align(0x10) u8 = undefined;
            main_chunk.ptr = virt.into_pointer([*]align(0x10) u8);
            main_chunk.len = 0x1000;
            self.main_chunk = main_chunk;
        }

        if (real_size <= self.main_chunk.?.len) {
            var result = self.main_chunk.?[0..real_size];
            var rest = self.main_chunk.?[real_size..];
            self.main_chunk = @alignCast(16, rest);
            return result;
        }
        return error{OutOfMemory}.OutOfMemory;
    }

    pub fn alloc(self: *Self, comptime T: type) !*T {
        const buffer = try self.alloc_bytes(@sizeOf(T));
        return @ptrCast(*T, buffer);
    }
    pub fn free(_: *u8) void {}
};

pub const FrameAllocator = struct {
    // next physical address to allocate
    next_free: PhysicalAddress,
    limit: PhysicalAddress,
    freelist: std.SinglyLinkedList(void),

    const PAGE_SIZE = 0x1000;

    const Self = @This();

    const OutOfMemory = error.OutOfMemory;

    pub fn new(memory: PhysicalMemoryRange) FrameAllocator {
        return .{
            .next_free = memory.base.alignForward(PAGE_SIZE),
            .limit = memory.get_end(),
            .freelist = std.SinglyLinkedList(void){ .first = null },
        };
    }

    pub fn alloc_zero_frame(self: *Self) !PhysicalAddress {
        const frame = try self.alloc_frame();
        const buf = directMapping().to_virt(frame).into_pointer(*[PAGE_SIZE]u8);
        @memset(buf, 0);

        return frame;
    }

    pub fn alloc_zero_aligned(self: *Self, alignment: usize, n: usize) !PhysicalAddress {
        const frame = try self.alloc_aligned(alignment, n);
        const buf = directMapping().to_virt(frame).into_pointer([*]u8);
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
            const phys_addr = directMapping().to_phys(virt_addr);
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
        const virt_addr = directMapping().to_virt(addr);
        const node = virt_addr.into_pointer(*@TypeOf(self.freelist).Node);
        self.freelist.prepend(node);
    }
};

pub const PhysicalMemoryRange = MemoryRange(PhysicalAddress);
pub const VirtualMemoryRange = MemoryRange(VirtualAddress);

pub fn MemoryRange(comptime T: type) type {
    return struct {
        const Self = @This();
        base: T,
        size: usize,

        pub fn sized(base: T, size: usize) Self {
            return .{ .base = base, .size = size };
        }

        pub fn get_end(self: Self) T {
            return self.base.add(self.size);
        }

        pub fn from_range(start: T, end: T) Self {
            std.debug.assert(start.lt(end));
            const size = T.span(start, end);
            return .{ .base = start, .size = size };
        }

        pub fn as_bytes(self: Self) []u8 {
            const ptr = @intToPtr([*]u8, self.base.value);
            return ptr[0..(self.size)];
        }
    };
}

var memory_allocator: MemoryAllocator = undefined;

pub fn memoryAllocator() *MemoryAllocator {
    return &memory_allocator;
}

pub fn init() void {
    arch.mm.init();
    memory_allocator = MemoryAllocator.new(frameAllocator());
}
