const std = @import("std");
const kernel = @import("root");
const mm = kernel.mm;
const x86 = kernel.arch.x86;
const lib = kernel.lib;

const PhysicalAddress = mm.PhysicalAddress;
const VirtualAddress = mm.VirtualAddress;

const paging = @import("paging.zig");

const PML4 = paging.PML4;
const PDPT = paging.PDPT;
const PD = paging.PD;
const PT = paging.PT;
const PageKind = paging.PageKind;

pub const VirtAddrType = u64;
pub const PhysAddrType = u64;

const BIT = kernel.lib.BIT;
const bit_set = kernel.lib.bit_set;

const logger = kernel.logging.logger(@typeName(@This())){};

const KERNEL_MEMORY_MAP = [_]mm.VirtualMemoryRange{
    DIRECT_MAPPING,
    DYNAMIC_MAPPING,
    KERNEL_IMAGE,
};

const DIRECT_MAPPING = mm.VirtualMemoryRange.sized(
    VirtualAddress.new(0xffff800000000000),
    lib.GiB(64),
);

const DYNAMIC_MAPPING = mm.VirtualMemoryRange.sized(
    VirtualAddress.new(0xffff900000000000),
    lib.TiB(1),
);

const KERNEL_IMAGE = mm.VirtualMemoryRange.sized(
    VirtualAddress.new(0xffffffff80000000),
    lib.GiB(1),
);

pub extern var kernel_end: [*]u8;

pub fn get_kernel_end() mm.VirtualAddress {
    return mm.VirtualAddress.new(@intFromPtr(&kernel_end));
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
    return x86.multiboot.get_multiboot_memory();
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

    pub fn clone(source: *VirtualMemoryImpl) !*VirtualMemoryImpl {
        var arch_vm = try kernel.mm.memoryAllocator().alloc(VirtualMemoryImpl);
        arch_vm.allocator = source.allocator;

        const frame = try arch_vm.allocator.alloc_zero_frame();
        arch_vm.pml4 = PML4.init(frame, null);
        arch_vm.dynamic_next = source.dynamic_next;
        arch_vm.dynamic_end = source.dynamic_end;

        var ctx = struct {
            arch_vm: *VirtualMemoryImpl,
            pub fn walk(self: *@This(), virt: VirtualAddress, phys: PhysicalAddress, page_size: usize) void {
                // TODO: fix those mappings
                switch (page_size) {
                    0x1000 => self.arch_vm.map_page_4kb(virt, phys, &MapOptions{
                        .writable = true,
                        .write_through = false,
                        .cache_disable = false,
                        .no_execute = false,
                        .user = false,
                    }) catch unreachable,
                    0x200000 => self.arch_vm.map_page_2mb(virt, phys, &MapOptions{
                        .writable = true,
                        .write_through = false,
                        .cache_disable = false,
                        .no_execute = false,
                        .user = false,
                    }) catch unreachable,
                    else => @panic("wtf"),
                }
            }

            pub fn done(self: *@This()) void {
                _ = self;
            }
        }{ .arch_vm = arch_vm };
        source.walk(@TypeOf(ctx), &ctx);

        return arch_vm;
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
        if (!where.isAligned(lib.KiB(4)) or !what.isAligned(lib.KiB(4))) {
            return Error.UnalignedAddress;
        }

        const pml4_index = PML4.get_slot(where);
        const pdpt_index = PDPT.get_slot(where);
        const pd_index = PD.get_slot(where);
        const pt_index = PT.get_slot(where);

        const pdpt = try self.pml4.get_pdpt_alloc(self.allocator, pml4_index);
        const pd = try pdpt.get_pd_alloc(self.allocator, pdpt_index);
        const pt = try pd.get_pt_alloc(self.allocator, pd_index);

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
        if (!where.isAligned(lib.KiB(4))) {
            return Error.UnalignedAddress;
        }

        const pml4_index = PML4.get_slot(where);
        const pdpt_index = PDPT.get_slot(where);
        const pd_index = PD.get_slot(where);
        const pt_index = PT.get_slot(where);

        const pdpt = self.pml4.get_pdpt(pml4_index) orelse return Error.MappingNotExists;
        const pd = pdpt.get_pd(pdpt_index) orelse return Error.MappingNotExists;
        const pt = pd.get_pt(pd_index) orelse return Error.MappingNotExists;

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
        if (!where.isAligned(lib.MiB(2)) or !what.isAligned(lib.MiB(2))) {
            return Error.UnalignedAddress;
        }

        const pml4_index = PML4.get_slot(where);
        const pdpt_index = PDPT.get_slot(where);
        const pd_index = PD.get_slot(where);

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
        if (!where.isAligned(lib.MiB(2))) {
            return Error.UnalignedAddress;
        }

        const pml4_index = PML4.get_slot(where);
        const pdpt_index = PDPT.get_slot(where);
        const pd_index = PD.get_slot(where);

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
            lib.KiB(4) => return self.map_page_4kb(where, what, options),
            lib.MiB(2) => return self.map_page_2mb(where, what, options),
            lib.GiB(1) => @panic("Unimplemented"),
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
        var left = std.mem.alignForward(usize, size, PageKind.Page4K.size());

        var done: usize = 0;
        var unit: PageKind = undefined;
        while (left != 0) : ({
            left -= unit.size();
            done += unit.size();
        }) {
            const where_addr = where.add(done);
            const what_addr = what.add(done);

            const use_2mb = init: {
                if (!where_addr.isAligned(lib.MiB(2))) {
                    break :init false;
                }
                if (!what_addr.isAligned(lib.MiB(2))) {
                    break :init false;
                }
                if (left < lib.MiB(2)) {
                    break :init false;
                }
                break :init true;
            };

            if (use_2mb) {
                unit = PageKind.Page2M;
            } else {
                unit = PageKind.Page4K;
            }

            logger.debug("Mapping {} to {} ({})\n", .{ what_addr, where_addr, unit });
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
        protection: kernel.mm.VirtualMemory.Protection,
    ) !mm.VirtualMemoryRange {
        const options = MapOptions{
            .writable = protection.write,
            .user = protection.user,
            .write_through = false,
            .cache_disable = true,
            .no_execute = !protection.execute,
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
        const pml4_index = PML4.get_slot(where);
        const pdpt_index = PDPT.get_slot(where);
        const pd_index = PD.get_slot(where);
        const pt_index = PT.get_slot(where);

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
        while (left.size >= lib.KiB(4)) {
            const kind = self.get_page_kind(left.base) orelse {
                logger.err("Tried to unmap page at {}, but there's none\n", left.base);
                return Error.MappingNotExists;
            };
            switch (kind) {
                .Page4K => {
                    if (!left.base.isAligned(lib.KiB(4))) {
                        left.base.value = std.mem.alignBackward(left.base.value, lib.KiB(4));
                    }
                    _ = self.unmap_page_4kb(left.base) catch |err| {
                        logger.err("Failed to unmap 4KiB page at {}\n", left.base);
                        return err;
                    };
                    left.base = left.base.add(lib.KiB(4));
                    left.size -= lib.KiB(4);
                },
                .Page2M => {
                    if (!left.base.isAligned(lib.MiB(2))) {
                        left.base.value = std.mem.alignBackward(left.base.value, lib.MiB(2));
                    }
                    _ = self.unmap_page_2mb(left.base) catch |err| {
                        logger.err("Failed to unmap 2MiB page at {}\n", left.base);
                        return err;
                    };
                    left.base = left.base.add(lib.MiB(2));
                    left.size -= lib.MiB(2);
                },
                .Page1G => @panic("Unimplemented"),
            }
        }
        paging.flushTlb();
    }
};

pub var kernel_vm_impl: VirtualMemoryImpl = undefined;

fn map_kernel_image(vm: *mm.VirtualMemory) !void {
    const kern_end = VirtualAddress.new(@intFromPtr(&kernel_end));
    const kernel_size = VirtualAddress.span(KERNEL_IMAGE.base, kern_end);
    _ = vm.map_memory(
        KERNEL_IMAGE.base,
        PhysicalAddress.new(0),
        std.mem.alignForward(usize, kernel_size, lib.MiB(2)),
        mm.VirtualMemory.Protection.RWX,
    ) catch |err| {
        logger.log("{}\n", .{err});
        @panic("Failed to remap kernel");
    };
}

fn map_direct_memory(vm: *mm.VirtualMemory) !void {
    _ = try vm.map_memory(
        DIRECT_MAPPING.base,
        PhysicalAddress.new(0),
        lib.GiB(64),
        mm.VirtualMemory.Protection.RWX,
    );
}

pub fn map_kernel_regions(vm: *mm.VirtualMemory) !void {
    try map_kernel_image(vm);
    try map_direct_memory(vm);
}

fn setup_kernel_vm() !void {
    // Initialize generic kernel VM
    mm.getKernelVM().* = mm.VirtualMemory.init(&kernel_vm_impl);

    // Initial 1GiB mapping
    logger.debug("Identity mapping 1GiB from 0 phys\n", .{});
    const initial_mapping_size = lib.GiB(1);
    _ = try mm.getKernelVM().map_memory(
        DIRECT_MAPPING.base,
        PhysicalAddress.new(0x0),
        initial_mapping_size,
        mm.VirtualMemory.Protection.RWX,
    );

    // Map kernel image
    logger.debug("Mapping kernel image\n", .{});
    try map_kernel_image(mm.getKernelVM());

    logger.debug("Switching to new virtual memory\n", .{});
    mm.getKernelVM().switch_to();
    logger.debug("Survived switching to kernel VM\n", .{});

    // switch to new virtual memory
    directMapping().virt_start = DIRECT_MAPPING.base;
    directMapping().size = initial_mapping_size;

    kernel.mm.dump_vm_mappings(mm.getKernelVM());

    logger.debug("Mapping rest of direct memory\n", .{});
    _ = try mm.getKernelVM().map_memory(
        DIRECT_MAPPING.base.add(initial_mapping_size),
        PhysicalAddress.new(0 + initial_mapping_size),
        lib.GiB(63),
        mm.VirtualMemory.Protection.RWX,
    );

    directMapping().virt_start = DIRECT_MAPPING.base;
    directMapping().size = lib.GiB(64);
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
    kernel_vm_impl = VirtualMemoryImpl.init(&main_allocator) catch {
        @panic("Failed to initialize VM implementation");
    };

    setup_kernel_vm() catch {
        @panic("Failed to initialize kernel VM implementation");
    };

    logger.log("Memory subsystem initialized\n", .{});
}
