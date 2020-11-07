const std = @import("std");
const kernel = @import("root");
const printk = kernel.printk;
const mm = kernel.mm;
const x86 = @import("../x86.zig");

const PhysicalAddress = mm.PhysicalAddress;
const VirtualAddress = mm.VirtualAddress;

pub const VirtAddrType = u64;
pub const PhysAddrType = u64;

pub extern var kernel_end: [*]u8;

pub fn get_kernel_end() mm.VirtualAddress {
    return mm.VirtualAddress.new(@ptrToInt(&kernel_end));
}

var identity_mapping: mm.IdentityMapping = undefined;

pub fn identityMapping() *mm.IdentityMapping {
    return &identity_mapping;
}

var kernel_vm: mm.VirtualMemory = undefined;

var main_allocator: mm.FrameAllocator = undefined;

pub fn frameAllocator() *mm.FrameAllocator {
    return &main_allocator;
}

pub fn detect_memory() ?mm.MemoryRange {
    if (x86.multiboot.info_pointer) |mbinfo| {
        return detect_multiboot_memory(mbinfo);
    }

    return null;
}

fn bit_set(value: var, comptime bit: BitStruct) bool {
    return (value & (1 << bit.shift)) != 0;
}

fn detect_multiboot_memory(mb_info: *x86.multiboot.Info) ?mm.MemoryRange {
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

    var best_slot: ?mm.MemoryRange = null;

    var offset = mm.PhysicalAddress.new(mb_info.mmap_addr);
    const mmap_end = mm.PhysicalAddress.new(mb_info.mmap_addr + mb_info.mmap_length);

    printk("BIOS memory map:\n", .{});
    while (offset.lt(mmap_end)) {
        const entry = x86.mm.identityMapping().to_virt(offset).into_pointer(*MemEntry);

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
        offset = offset.add(entry.size + @sizeOf(@TypeOf(entry.size)));

        const this_slot = mm.MemoryRange{ .base = mm.PhysicalAddress.new(start), .size = entry.length };

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

const mask: u64 = ~@as(u64, 0xfff);

pub const PT = struct {
    root: PhysicalAddress,
    base: ?VirtualAddress,
    phys2virt: fn (PhysicalAddress) VirtualAddress = kernel.mm.identityTranslate,

    const EntryType = u64;
    const IdxType = u9;
    const MaxIndex = std.math.maxInt(IdxType);
    const TableFormat = [512]EntryType;

    const PRESENT = BIT(0);
    const WRITABLE = BIT(1);
    const USER = BIT(2);
    const WRITE_THROUGH = BIT(3);
    const CACHE_DISABLE = BIT(4);
    const ACCESSED = BIT(5);
    const DIRTY = BIT(6);
    const GLOBAL = BIT(8);
    const NO_EXECUTE = BIT(63);

    const Self = @This();

    fn get_table(self: Self) *TableFormat {
        return self.phys2virt(self.root).into_pointer(*TableFormat);
    }

    pub fn get_page(self: Self, idx: IdxType) ?PhysicalAddress {
        const entry = self.get_table()[idx];

        if (bit_set(entry, PRESENT)) {
            return PhysicalAddress.new(entry & mask);
        }
        return null;
    }

    pub fn get_entry(self: Self, idx: IdxType) EntryType {
        return self.get_table()[idx];
    }

    pub fn set_entry(self: Self, idx: IdxType, entry: EntryType) void {
        self.get_table()[idx] = entry;
    }

    pub fn init(pt: PhysicalAddress, base: ?VirtualAddress) PT {
        return .{ .root = pt, .base = base };
    }

    fn walk(self: @This(), func: PageTableVisitor) void {
        var i: PT.IdxType = 0;
        while (true) : (i += 1) {
            const page = self.get_page(i);
            if (page) |entry| {
                const virt = self.base.?.add(i * mm.KiB(4));
                func(virt, entry, PageKind.Page4K);
            }

            if (i == PT.MaxIndex) {
                break;
            }
        }
    }
};

pub const PageKind = enum {
    Page4K,
    Page2M,
    Page1G,
};

pub const PD = struct {
    root: PhysicalAddress,
    base: ?VirtualAddress,
    phys2virt: fn (PhysicalAddress) VirtualAddress = kernel.mm.identityTranslate,

    const EntryType = u64;
    const IdxType = u9;
    const MaxIndex = std.math.maxInt(IdxType);
    const TableFormat = [512]EntryType;

    const PRESENT = BIT(0);
    const WRITABLE = BIT(1);
    const USER = BIT(2);
    const WRITE_THROUGH = BIT(3);
    const CACHE_DISABLE = BIT(4);
    const ACCESSED = BIT(5);
    const DIRTY = BIT(6);
    const PAGE_2M = BIT(7);
    const GLOBAL = BIT(8);
    const NO_EXECUTE = BIT(63);

    const Self = @This();

    const EntryKind = enum {
        Missing,
        Page2M,
        PageTable,
    };

    fn get_table(self: Self) *TableFormat {
        return self.phys2virt(self.root).into_pointer(*TableFormat);
    }

    pub fn get_pt(self: Self, idx: IdxType) ?PT {
        const entry = self.get_table()[idx];

        if (bit_set(entry, PRESENT) and !bit_set(entry, PAGE_2M)) {
            // present
            const virt_base = self.base.?.add(idx * mm.MiB(2));
            return PT.init(PhysicalAddress.new(entry & mask), virt_base);
        }
        return null;
    }

    pub fn get_page_2m(self: Self, idx: IdxType) ?PhysicalAddress {
        const entry = self.get_table()[idx];

        if (bit_set(entry, PRESENT) and bit_set(entry, PAGE_2M)) {
            return PhysicalAddress.new(entry & mask);
        }
        return null;
    }

    pub fn get_entry(self: Self, idx: IdxType) EntryType {
        return self.get_table()[idx];
    }

    pub fn get_entry_kind(self: Self, idx: IdxType) EntryKind {
        const entry = self.get_table()[idx];
        const is_present = bit_set(entry, PRESENT);
        const is_2m = bit_set(entry, PAGE_2M);

        if (is_present and is_2m) {
            return EntryKind.Page2M;
        } else if (is_present) {
            return EntryKind.PageTable;
        }

        return EntryKind.Missing;
    }

    pub fn set_entry(self: Self, idx: IdxType, entry: EntryType) void {
        self.get_table()[idx] = entry;
    }

    pub fn init(pd: PhysicalAddress, base: VirtualAddress) PD {
        return .{ .root = pd, .base = base };
    }

    fn walk(self: Self, func: PageTableVisitor) void {
        var i: PD.IdxType = 0;
        while (true) : (i += 1) {
            switch (self.get_entry_kind(i)) {
                .PageTable => {
                    const entry = self.get_pt(i).?;
                    entry.walk(func);
                },
                .Page2M => {
                    const entry = self.get_page_2m(i).?;
                    func(self.base.?.add(i * mm.MiB(2)), entry, PageKind.Page2M);
                },
                else => {},
            }

            if (i == PD.MaxIndex) {
                break;
            }
        }
    }
};

pub const PDPT = struct {
    root: PhysicalAddress,
    base: ?VirtualAddress,
    phys2virt: fn (PhysicalAddress) VirtualAddress = kernel.mm.identityTranslate,

    const IdxType = u9;
    const EntryType = u64;
    const MaxIndex = std.math.maxInt(IdxType);
    const TableFormat = [MaxIndex + 1]EntryType;

    const PRESENT = BIT(0);
    const WRITABLE = BIT(1);
    const USER = BIT(2);
    const WRITE_THROUGH = BIT(3);
    const CACHE_DISABLE = BIT(4);
    const ACCESSED = BIT(5);
    const DIRTY = BIT(6);
    const PAGE_1G = BIT(7);
    const GLOBAL = BIT(8);
    const NO_EXECUTE = BIT(63);

    const Self = @This();

    fn get_table(self: Self) *TableFormat {
        return self.phys2virt(self.root).into_pointer(*TableFormat);
    }

    fn get_entry(self: Self, idx: IdxType) EntryType {
        return self.get_table()[idx];
    }

    pub fn set_entry(self: Self, idx: IdxType, entry: EntryType) void {
        self.get_table()[idx] = entry;
    }

    pub fn get_pd(self: Self, idx: IdxType) ?PD {
        const entry = self.get_entry(idx);

        if (bit_set(entry, PRESENT) and !bit_set(entry, PAGE_1G)) {
            // present
            const virt_base = self.base.?.add(mm.GiB(1) * idx);
            return PD.init(PhysicalAddress.new(entry & mask), virt_base);
        }
        return null;
    }

    pub fn init(pdp: PhysicalAddress, base: ?VirtualAddress) PDPT {
        return .{ .root = pdp, .base = base };
    }

    fn walk(self: Self, func: PageTableVisitor) void {
        var i: PDPT.IdxType = 0;
        while (true) : (i += 1) {
            const pd = self.get_pd(i);
            if (pd) |entry| {
                entry.walk(func);
            }

            if (i == PDPT.MaxIndex) {
                break;
            }
        }
    }
};

const BitStruct = struct {
    shift: comptime_int,

    pub fn v(comptime self: @This()) comptime_int {
        return 1 << self.shift;
    }
};

pub fn BIT(comptime n: comptime_int) BitStruct {
    return .{ .shift = n };
}

pub const PML4 = struct {
    root: PhysicalAddress,
    // Missing base implies 4 level paging scheme
    base: ?VirtualAddress,
    phys2virt: fn (PhysicalAddress) VirtualAddress = kernel.mm.identityTranslate,

    const IdxType = u9;
    const EntryType = u64;
    const MaxIndex = std.math.maxInt(IdxType);

    const TableFormat = [MaxIndex + 1]EntryType;

    const PRESENT = BIT(0);
    const WRITABLE = BIT(1);
    const USER = BIT(2);
    const WRITE_THROUGH = BIT(3);
    const CACHE_DISABLE = BIT(4);
    const ACCESSED = BIT(5);

    const NO_EXECUTE = BIT(63);

    const Self = @This();

    pub fn init(pml4: PhysicalAddress, base: ?VirtualAddress) PML4 {
        return .{ .root = pml4, .base = base };
    }

    fn get_table(self: Self) *TableFormat {
        return self.phys2virt(self.root).into_pointer(*TableFormat);
    }

    /// Some special handling for 48-bit paging
    fn get_virt_base(self: Self, idx: IdxType) VirtualAddress {
        const offset = idx * mm.GiB(512);
        // Easy case, we know the base
        if (self.base) |base| {
            return base.add(offset);
        }

        // Compute high bits
        if (bit_set(offset, BIT(47))) {
            return VirtualAddress.new(0xffff000000000000).add(offset);
        }
        return VirtualAddress.new(offset);
    }

    pub fn get_pdp(self: @This(), idx: IdxType) ?PDPT {
        const entry = self.get_entry(idx);
        if (bit_set(entry, PRESENT)) {
            const virt_base = self.get_virt_base(idx);
            return PDPT.init(PhysicalAddress.new(entry & mask), virt_base);
        }
        return null;
    }

    pub fn get_entry(self: @This(), idx: IdxType) EntryType {
        return self.get_table()[idx];
    }

    pub fn set_entry(self: Self, idx: IdxType, entry: EntryType) void {
        self.get_table()[idx] = entry;
    }

    fn walk(self: Self, func: PageTableVisitor) void {
        var i: PML4.IdxType = 0;
        while (true) : (i += 1) {
            const pdp = self.get_pdp(i);
            if (pdp) |entry| {
                entry.walk(func);
            }

            if (i == PML4.MaxIndex) {
                break;
            }
        }
    }
};

const PageTableVisitor = fn (VirtualAddress, PhysicalAddress, PageKind) void;
fn visitor(virt: VirtualAddress, phys: PhysicalAddress, pk: PageKind) void {
    printk("{} -> {} ({})\n", .{ virt, phys, pk });
}

pub const VirtualMemoryImpl = struct {
    allocator: *mm.FrameAllocator,
    pml4: PML4,

    const Self = @This();

    const Error = error{
        InvalidSize,
        UnalignedAddress,
        MappingExists,
    };

    pub fn init(frame_allocator: *mm.FrameAllocator) !VirtualMemoryImpl {
        const frame = try frame_allocator.alloc_zero_frame();

        return VirtualMemoryImpl{
            .allocator = frame_allocator,
            .pml4 = PML4.init(frame, null),
        };
    }

    pub fn switch_to(self: Self) void {
        x86.CR3.write(self.pml4.root.value);
    }

    fn map_page_2mb(
        self: Self,
        where: VirtualAddress,
        what: PhysicalAddress,
    ) !void {
        if (!where.isAligned(mm.MiB(2)) or !what.isAligned(mm.MiB(2))) {
            return Error.UnalignedAddress;
        }
        const pml4_index_ = (where.value >> 39) & 0x1ff;
        const pdpt_index_ = (where.value >> 30) & 0x1ff;
        const pd_index_ = (where.value >> 21) & 0x1ff;
        std.debug.assert(pml4_index_ <= PML4.MaxIndex);
        std.debug.assert(pdpt_index_ <= PDPT.MaxIndex);
        std.debug.assert(pd_index_ <= PD.MaxIndex);

        const pml4_index = @intCast(PML4.IdxType, pml4_index_);
        const pdpt_index = @intCast(PDPT.IdxType, pdpt_index_);
        const pd_index = @intCast(PD.IdxType, pd_index_);

        if (self.pml4.get_pdp(pml4_index) == null) {
            printk("Allocated PML4[{}] missing \n", .{pml4_index});
            const frame = try self.allocator.alloc_zero_frame();
            printk("Allocated PML4[{}] = {}\n", .{ pml4_index, frame });
            const v = frame.value | PML4.WRITABLE.v() | PML4.PRESENT.v();
            self.pml4.set_entry(pml4_index, v);
        }
        const pdpt = self.pml4.get_pdp(pml4_index).?;

        if (pdpt.get_pd(pdpt_index) == null) {
            printk("Allocated PML4[{}] PD[{}] missing \n", .{ pml4_index, pdpt_index });
            const frame = try self.allocator.alloc_zero_frame();
            printk("Allocated PML4[{}] PD[{}] = {}\n", .{ pml4_index, pdpt_index, frame });
            const v = frame.value | PDPT.WRITABLE.v() | PDPT.PRESENT.v();
            pdpt.set_entry(pdpt_index, v);
        }

        const pd = pdpt.get_pd(pdpt_index).?;
        if (pd.get_entry_kind(pd_index) != PD.EntryKind.Missing) {
            return Error.MappingExists;
        }
        pd.set_entry(pd_index, what.value | PD.WRITABLE.v() | PD.PRESENT.v() | PD.PAGE_2M.v());
    }

    pub fn map_addr(
        self: Self,
        where: VirtualAddress,
        what: PhysicalAddress,
        length: usize,
    ) !void {
        switch (length) {
            mm.KiB(4) => @panic("Unimplemented"),
            mm.MiB(2) => return self.map_page_2mb(where, what),
            mm.GiB(1) => @panic("Unimplemented"),
            else => return Error.InvalidSize,
        }
    }

    pub fn identity_map(
        self: Self,
        where: VirtualAddress,
        what: PhysicalAddress,
        size: usize,
    ) !void {
        const unit = mm.MiB(2);
        var left = size;
        var done: usize = 0;
        while (left != 0) : ({
            left -= unit;
            done += unit;
        }) {
            mm.kernel_vm.map_addr(
                where.add(done),
                what.add(done),
                unit,
            ) catch |err| {
                printk("{}\n", .{err});
                @panic("Failed to setup identity mapping");
            };
        }
    }
};

var kernel_vm_impl: VirtualMemoryImpl = undefined;

const IDENTITY_MAPPING_START = VirtualAddress.new(0xffff800000000000);
// -2GiB
const KERNEL_IMAGE_START = VirtualAddress.new(0xffffffff80000000);

fn dump_pt(pt: *const PT) void {
    printk("    PT@{x}:\n", .{pt.root.value});

    var i: PT.IdxType = 0;
    while (true) : (i += 1) {
        const page = pt.get_page(i);
        if (page) |entry| {
            printk("  [{:3}] {x:0>16}\n", .{ i, entry.value });
        }

        if (i == PT.MaxIndex) {
            break;
        }
    }
}

fn dump_pd(pd: *const PD) void {
    const indent = " " ** 4;
    printk(indent ++ "PD@{x}:\n", .{pd.root.value});

    var i: PD.IdxType = 0;
    while (true) : (i += 1) {
        switch (pd.get_entry_kind(i)) {
            .PageTable => {
                const entry = pd.get_pt(i).?;
                printk(indent ++ "[{:3}] {x:0>16}\n", .{ i, entry.root.value });
                dump_pt(&entry);
            },
            .Page2M => {
                const entry = pd.get_page_2m(i).?;
                printk(indent ++ "[{:3}] {x} - 2MiB\n", .{ i, entry });
            },
            else => {},
        }

        if (i == PD.MaxIndex) {
            break;
        }
    }
}

fn dump_pdpt(pdpt: *const PDPT) void {
    printk("  PDPT@{x}:\n", .{pdpt.root.value});

    var i: PDPT.IdxType = 0;
    while (true) : (i += 1) {
        const pd = pdpt.get_pd(i);
        if (pd) |entry| {
            printk("  [{:3}] {x:0>16}\n", .{ i, entry.root.value });
            dump_pd(&entry);
        }

        if (i == PDPT.MaxIndex) {
            break;
        }
    }
}

fn dump_mm() void {
    const base = PhysicalAddress.new(x86.CR3.read() & mask);
    const paging = PML4.init(base);
    printk("PML4@{x}:\n", .{base});

    var i: PML4.IdxType = 0;
    while (true) : (i += 1) {
        const pdp = paging.get_pdp(i);
        if (pdp) |entry| {
            printk("[{:3}] {x:0>16}\n", .{ i, entry.root.value });
            dump_pdpt(&entry);
        }

        if (i == PML4.MaxIndex) {
            break;
        }
    }
}

fn setup_kernel_vm() !void {
    // Initialize generic kernel VM
    mm.kernel_vm = mm.VirtualMemory.init(&kernel_vm_impl);

    // Initial 1GiB mapping
    printk("Identity mapping 1GiB from 0 phys\n", .{});
    const initial_mapping_size = mm.GiB(1);
    try kernel_vm_impl.identity_map(
        IDENTITY_MAPPING_START,
        PhysicalAddress.new(0x0),
        initial_mapping_size,
    );

    // Map kernel image
    printk("Mapping kernel image\n", .{});
    const kern_end = VirtualAddress.new(@ptrToInt(&kernel_end));
    const kernel_size = VirtualAddress.span(KERNEL_IMAGE_START, kern_end);
    mm.kernel_vm.map_addr(
        KERNEL_IMAGE_START,
        PhysicalAddress.new(0),
        std.mem.alignForward(kernel_size, mm.MiB(2)),
    ) catch |err| {
        printk("{}\n", .{err});
        @panic("Failed to remap kernel");
    };

    //kernel_vm_impl.pml4.walk(visitor);

    identityMapping().virt_start = IDENTITY_MAPPING_START;
    identityMapping().size = initial_mapping_size;

    // switch to new virtual memory
    mm.kernel_vm.switch_to();
    printk("Survived switching to kernel VM\n", .{});

    printk("Mapping rest of identity\n", .{});
    try kernel_vm_impl.identity_map(
        IDENTITY_MAPPING_START.add(initial_mapping_size),
        PhysicalAddress.new(0 + initial_mapping_size),
        mm.GiB(63),
    );

    //mm.kernel_vm.switch_to();
}

pub fn init() void {
    const mem = x86.mm.detect_memory();
    if (mem == null) {
        @panic("Unable to find any free memory!");
    }
    var free_memory = mem.?;

    // Ensure we don't overwrite kernel
    const kend = x86.mm.identityMapping().to_phys(x86.mm.get_kernel_end());
    // Move beginning to after kernel
    const begin = kend.max(free_memory.base);
    const adjusted_memory = mm.MemoryRange.from_range(begin, free_memory.get_end());

    printk("Detected {}MiB of free memory\n", .{adjusted_memory.size / 1024 / 1024});

    //dump_mm();

    // Initialize physical memory allocator
    main_allocator = mm.FrameAllocator.new(adjusted_memory);
    // Initialize x86 VM implementation
    kernel_vm_impl = VirtualMemoryImpl.init(&main_allocator) catch |err| {
        @panic("Failed to initialize VM implementation");
    };

    setup_kernel_vm() catch |err| {
        @panic("Failed to initialize kernel VM implementation");
    };

    printk("Finished mapping! :)\n", .{});
}
