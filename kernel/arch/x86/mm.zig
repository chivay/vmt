const std = @import("std");
const kernel = @import("root");
const mm = kernel.mm;
const x86 = @import("../x86.zig");

const PhysicalAddress = mm.PhysicalAddress;
const VirtualAddress = mm.VirtualAddress;

usingnamespace @import("paging.zig");

pub const VirtAddrType = u64;
pub const PhysAddrType = u64;

const BIT = kernel.BIT;
const bit_set = kernel.bit_set;

pub var logger = @TypeOf(x86.logger).childOf(@typeName(@This())){};

const KERNEL_MEMORY_MAP = [_]mm.VirtualMemoryRange{
    DIRECT_MAPPING,
    DYNAMIC_MAPPING,
    KERNEL_IMAGE,
};

comptime {
    // Check for overlaps
    var slots = KERNEL_MEMORY_MAP.len;
    var i = 0;
}

const DIRECT_MAPPING = mm.VirtualMemoryRange.sized(
    VirtualAddress.new(0xffff800000000000),
    mm.GiB(64),
);

const DYNAMIC_MAPPING = mm.VirtualMemoryRange.sized(
    VirtualAddress.new(0xffff900000000000),
    mm.TiB(1),
);

const KERNEL_IMAGE = mm.VirtualMemoryRange.sized(
    VirtualAddress.new(0xffffffff80000000),
    mm.GiB(1),
);

pub extern var kernel_end: [*]u8;

pub fn get_kernel_end() mm.VirtualAddress {
    return mm.VirtualAddress.new(@ptrToInt(&kernel_end));
}

var direct_mapping: mm.DirectMapping = undefined;
pub fn directMapping() *mm.DirectMapping {
    return &direct_mapping;
}

var main_allocator: mm.FrameAllocator = undefined;
pub fn frameAllocator() *mm.FrameAllocator {
    return &main_allocator;
}

var kernel_vm: mm.VirtualMemory = undefined;

pub fn detect_memory() ?mm.PhysicalMemoryRange {
    if (x86.multiboot.info_pointer) |mbinfo| {
        return detect_multiboot_memory(mbinfo);
    }

    return null;
}

fn detect_multiboot_memory(mb_info: *x86.multiboot.Info) ?mm.PhysicalMemoryRange {
    if (!bit_set(mb_info.flags, BIT(6))) {
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

    var best_slot: ?mm.PhysicalMemoryRange = null;

    var offset = mm.PhysicalAddress.new(mb_info.mmap_addr);
    const mmap_end = mm.PhysicalAddress.new(mb_info.mmap_addr + mb_info.mmap_length);

    logger.log("BIOS memory map:\n", .{});
    while (offset.lt(mmap_end)) {
        const entry = x86.mm.directMapping().to_virt(offset).into_pointer(*MemEntry);

        const start = entry.base_addr;
        const end = start + entry.length - 1;
        const status = switch (entry.type_) {
            1 => "Available",
            3 => "ACPI Mem",
            4 => "Preserved on hibernation",
            5 => "Defective",
            else => "Reserved",
        };
        logger.log("[{x:0>10}-{x:0>10}] {s}\n", .{ start, end, status });
        offset = offset.add(entry.size + @sizeOf(@TypeOf(entry.size)));

        if (entry.type_ != 1) {
            continue;
        }
        const this_slot = mm.PhysicalMemoryRange{
            .base = PhysicalAddress.new(start),
            .size = entry.length,
        };

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

pub const VirtualMemoryImpl = struct {
    allocator: *mm.FrameAllocator,
    pml4: PML4,
    dynamic_next: VirtualAddress,
    dynamic_end: VirtualAddress,

    const Self = @This();

    const MapOptions = struct {
        writable: bool,
        user: bool,
        write_through: bool,
        cache_disable: bool,
        no_execute: bool,
    };

    const Error = error{
        InvalidSize,
        UnalignedAddress,
        MappingExists,
        MappingNotExists,
    };

    pub fn init(frame_allocator: *mm.FrameAllocator) !VirtualMemoryImpl {
        const frame = try frame_allocator.alloc_zero_frame();

        return VirtualMemoryImpl{
            .allocator = frame_allocator,
            .pml4 = PML4.init(frame, null),
            .dynamic_next = DYNAMIC_MAPPING.base,
            .dynamic_end = DYNAMIC_MAPPING.get_end(),
        };
    }

    pub fn switch_to(self: Self) void {
        x86.CR3.write(self.pml4.root.value);
    }

    pub fn walk(self: Self, comptime T: type, context: *T) void {
        self.pml4.walk(T, context);
    }

    fn map_page_4kb(
        self: Self,
        where: VirtualAddress,
        what: PhysicalAddress,
        options: *const MapOptions,
    ) !void {
        if (!where.isAligned(mm.KiB(4)) or !what.isAligned(mm.KiB(4))) {
            return Error.UnalignedAddress;
        }

        const pml4_index = get_pml4_slot(where);
        const pdpt_index = get_pdpt_slot(where);
        const pd_index = get_pd_slot(where);
        const pt_index = get_pt_slot(where);

        const pdpt = try self.pml4.get_pdpt_alloc(self.allocator, pml4_index);
        const pd = try pdpt.get_pd_alloc(self.allocator, pdpt_index);
        const pt = try pd.get_pt_alloc(self.allocator, pdpt_index);

        if (pt.get_entry_kind(pt_index) != PT.EntryKind.Missing) {
            return Error.MappingExists;
        }

        var flags: u64 = 0;
        if (options.writable) {
            flags |= PT.WRITABLE.v();
        }
        if (options.user) {
            flags |= PT.USER.v();
        }
        if (options.write_through) {
            flags |= PT.WRITE_THROUGH.v();
        }
        if (options.cache_disable) {
            flags |= PT.CACHE_DISABLE.v();
        }
        flags |= PD.PRESENT.v();

        pt.set_entry(pt_index, what.value | flags);
    }

    fn unmap_page_4kb(self: Self, where: VirtualAddress) !PhysicalAddress {
        if (!where.isAligned(mm.KiB(4))) {
            return Error.UnalignedAddress;
        }

        const pml4_index = get_pml4_slot(where);
        const pdpt_index = get_pdpt_slot(where);
        const pd_index = get_pd_slot(where);
        const pt_index = get_pt_slot(where);

        const pdpt = self.pml4.get_pdpt(pml4_index) orelse return Error.MappingNotExists;
        const pd = pdpt.get_pd(pdpt_index) orelse return Error.MappingNotExists;
        const pt = pd.get_pt(pdpt_index) orelse return Error.MappingNotExists;

        if (pt.get_page(pt_index)) |page| {
            pt.set_entry(pt_index, 0);
            return page;
        }
        return Error.MappingNotExists;
    }

    fn map_page_2mb(
        self: Self,
        where: VirtualAddress,
        what: PhysicalAddress,
        options: *const MapOptions,
    ) !void {
        if (!where.isAligned(mm.MiB(2)) or !what.isAligned(mm.MiB(2))) {
            return Error.UnalignedAddress;
        }

        const pml4_index = get_pml4_slot(where);
        const pdpt_index = get_pdpt_slot(where);
        const pd_index = get_pd_slot(where);

        const pdpt = try self.pml4.get_pdpt_alloc(self.allocator, pml4_index);
        const pd = try pdpt.get_pd_alloc(self.allocator, pdpt_index);

        if (pd.get_entry_kind(pd_index) != PD.EntryKind.Missing) {
            return Error.MappingExists;
        }

        var flags: u64 = 0;
        if (options.writable) {
            flags |= PD.WRITABLE.v();
        }

        if (options.user) {
            flags |= PD.USER.v();
        }

        if (options.write_through) {
            flags |= PD.WRITE_THROUGH.v();
        }

        if (options.cache_disable) {
            flags |= PD.CACHE_DISABLE.v();
        }

        flags |= PD.PRESENT.v() | PD.PAGE_2M.v();

        pd.set_entry(pd_index, what.value | flags);
    }

    fn unmap_page_2mb(self: *Self, where: VirtualAddress) !PhysicalAddress {
        if (!where.isAligned(mm.MiB(2))) {
            return Error.UnalignedAddress;
        }

        const pml4_index = get_pml4_slot(where);
        const pdpt_index = get_pdpt_slot(where);
        const pd_index = get_pd_slot(where);

        const pdpt = self.pml4.get_pdpt(pml4_index) orelse return Error.MappingNotExists;
        const pd = pdpt.get_pd(pdpt_index) orelse return Error.MappingNotExists;

        if (pd.get_page_2m(pd_index)) |phys| {
            pd.set_entry(pd_index, 0);
            return phys;
        }
        return Error.MappingNotExists;
    }

    pub fn map_addr(
        self: Self,
        where: VirtualAddress,
        what: PhysicalAddress,
        length: usize,
        options: *const MapOptions,
    ) !void {
        switch (length) {
            mm.KiB(4) => return self.map_page_4kb(where, what, options),
            mm.MiB(2) => return self.map_page_2mb(where, what, options),
            mm.GiB(1) => @panic("Unimplemented"),
            else => return Error.InvalidSize,
        }
    }

    pub fn map_range(
        self: Self,
        where: VirtualAddress,
        what: PhysicalAddress,
        size: usize,
        options: *const MapOptions,
    ) !mm.VirtualMemoryRange {
        // Align to smallest page
        var left = std.mem.alignForward(size, PageKind.Page4K.size());

        var done: usize = 0;
        var unit: PageKind = undefined;
        while (left != 0) : ({
            left -= unit.size();
            done += unit.size();
        }) {
            const where_addr = where.add(done);
            const what_addr = what.add(done);

            const use_2mb = init: {
                if (!where_addr.isAligned(mm.MiB(2))) {
                    break :init false;
                }
                if (!what_addr.isAligned(mm.MiB(2))) {
                    break :init false;
                }
                if (left < mm.MiB(2)) {
                    break :init false;
                }
                break :init true;
            };

            if (use_2mb) {
                unit = PageKind.Page2M;
            } else {
                unit = PageKind.Page4K;
            }

            logger.debug("Mapping {} to {} ({x})\n", .{ what_addr, where_addr, unit });
            self.map_addr(where_addr, what_addr, unit.size(), options) catch |err| {
                logger.log("{}\n", .{err});
                @panic("Failed to setup direct mapping");
            };
        }
        return mm.VirtualMemoryRange{ .base = where, .size = done };
    }

    pub fn map_memory(
        self: Self,
        where: VirtualAddress,
        what: PhysicalAddress,
        size: usize,
    ) !mm.VirtualMemoryRange {
        const options = MapOptions{
            .writable = true,
            .user = false,
            .write_through = false,
            .cache_disable = true,
            .no_execute = false,
        };
        return self.map_range(where, what, size, &options);
    }

    pub fn map_io(self: *Self, what: PhysicalAddress, size: usize) !mm.VirtualMemoryRange {
        const options = MapOptions{
            .writable = true,
            .user = false,
            .write_through = false,
            .cache_disable = true,
            .no_execute = false,
        };
        const range = try self.map_range(self.dynamic_next, what, size, &options);
        self.dynamic_next = self.dynamic_next.add(range.size);
        return range;
    }

    fn get_page_kind(self: *const Self, where: VirtualAddress) ?PageKind {
        const pml4_index = get_pml4_slot(where);
        const pdpt_index = get_pdpt_slot(where);
        const pd_index = get_pd_slot(where);
        const pt_index = get_pt_slot(where);

        const pdpt = self.pml4.get_pdpt(pml4_index) orelse return null;
        switch (pdpt.get_entry_kind(pdpt_index)) {
            .Missing => return null,
            .Page1G => return .Page1G,
            .PD => {
                const pd = pdpt.get_pd(pdpt_index) orelse return null;
                switch (pd.get_entry_kind(pd_index)) {
                    .Missing => return null,
                    .Page2M => return .Page2M,
                    .PageTable => {
                        const pt = pd.get_pt(pd_index) orelse return null;
                        switch (pt.get_entry_kind(pt_index)) {
                            .Page4K => return .Page4K,
                            .Missing => return null,
                        }
                    },
                }
            },
        }
        return null;
    }

    pub fn unmap(self: *Self, range: mm.VirtualMemoryRange) !void {
        logger.setLevel(.Debug);
        defer logger.setLevel(.Info);

        var left = range;
        while (left.size > mm.KiB(4)) {
            const kind = self.get_page_kind(left.base) orelse {
                logger.err("Tried to unmap page at {}, but there's none\n", left.base);
                return Error.MappingNotExists;
            };
            switch (kind) {
                .Page4K => {
                    if (!left.base.isAligned(mm.KiB(4))) {
                        left.base.value = std.mem.alignBackward(left.base.value, mm.KiB(4));
                    }
                    const page = self.unmap_page_4kb(left.base) catch |err| {
                        logger.err("Failed to unmap 4KiB page at {}\n", left.base);
                        return err;
                    };
                    left.base = left.base.add(mm.KiB(4));
                },
                .Page2M => {
                    if (!left.base.isAligned(mm.MiB(2))) {
                        left.base.value = std.mem.alignBackward(left.base.value, mm.MiB(2));
                    }
                    const page = self.unmap_page_2mb(left.base) catch |err| {
                        logger.err("Failed to unmap 2MiB page at {}\n", left.base);
                        return err;
                    };
                    left.base = left.base.add(mm.MiB(2));
                },
                .Page1G => @panic("Unimplemented"),
            }
        }
        flushTlb();
    }
};

pub var kernel_vm_impl: VirtualMemoryImpl = undefined;

fn setup_kernel_vm() !void {
    // Initialize generic kernel VM
    mm.kernel_vm = mm.VirtualMemory.init(&kernel_vm_impl);

    // Initial 1GiB mapping
    logger.debug("Identity mapping 1GiB from 0 phys\n", .{});
    const initial_mapping_size = mm.GiB(1);
    try mm.kernel_vm.map_memory(
        DIRECT_MAPPING.base,
        PhysicalAddress.new(0x0),
        initial_mapping_size,
    );

    // Map kernel image
    logger.debug("Mapping kernel image\n", .{});
    const kern_end = VirtualAddress.new(@ptrToInt(&kernel_end));
    const kernel_size = VirtualAddress.span(KERNEL_IMAGE.base, kern_end);
    mm.kernel_vm.map_memory(
        KERNEL_IMAGE.base,
        PhysicalAddress.new(0),
        std.mem.alignForward(kernel_size, mm.MiB(2)),
    ) catch |err| {
        logger.log("{}\n", .{err});
        @panic("Failed to remap kernel");
    };

    logger.debug("Switching to new virtual memory\n", .{});
    mm.kernel_vm.switch_to();
    logger.debug("Survived switching to kernel VM\n", .{});

    // switch to new virtual memory
    directMapping().virt_start = DIRECT_MAPPING.base;
    directMapping().size = initial_mapping_size;

    kernel.mm.dump_vm_mappings(&mm.kernel_vm);

    logger.debug("Mapping rest of direct memory\n", .{});
    try mm.kernel_vm.map_memory(
        DIRECT_MAPPING.base.add(initial_mapping_size),
        PhysicalAddress.new(0 + initial_mapping_size),
        mm.GiB(63),
    );

    directMapping().virt_start = DIRECT_MAPPING.base;
    directMapping().size = mm.GiB(64);
    logger.debug("VM setup done\n", .{});
}

pub fn init() void {
    const mem = x86.mm.detect_memory();
    if (mem == null) {
        @panic("Unable to find any free memory!");
    }
    var free_memory = mem.?;

    // Ensure we don't overwrite kernel
    const kend = x86.mm.directMapping().to_phys(x86.mm.get_kernel_end());
    // Move beginning to after kernel
    const begin = kend.max(free_memory.base);
    const adjusted_memory = mm.PhysicalMemoryRange.from_range(begin, free_memory.get_end());

    logger.log("Detected {}MiB of free memory\n", .{adjusted_memory.size / 1024 / 1024});

    // Initialize physical memory allocator
    main_allocator = mm.FrameAllocator.new(adjusted_memory);
    // Initialize x86 VM implementation
    kernel_vm_impl = VirtualMemoryImpl.init(&main_allocator) catch |err| {
        @panic("Failed to initialize VM implementation");
    };

    setup_kernel_vm() catch |err| {
        @panic("Failed to initialize kernel VM implementation");
    };

    logger.log("Memory subsystem initialized\n", .{});
}
