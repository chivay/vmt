const std = @import("std");
const kernel = @import("root");
const mm = kernel.mm;
const x86 = @import("../x86.zig");

const BIT = kernel.BIT;
const bit_set = kernel.bit_set;

const PhysicalAddress = mm.PhysicalAddress;
const VirtualAddress = mm.VirtualAddress;

const mask: u64 = ~@as(u64, 0xfff);

pub fn get_pml4_slot(addr: VirtualAddress) PML4.IdxType {
    const pml4_index_ = (addr.value >> 39) & 0x1ff;
    std.debug.assert(pml4_index_ <= PML4.MaxIndex);
    return @intCast(PML4.IdxType, pml4_index_);
}

pub fn get_pdpt_slot(addr: VirtualAddress) PDPT.IdxType {
    const pdpt_index = (addr.value >> 30) & 0x1ff;
    std.debug.assert(pdpt_index <= PDPT.MaxIndex);
    return @intCast(PDPT.IdxType, pdpt_index);
}

pub fn get_pd_slot(addr: VirtualAddress) PD.IdxType {
    const pd_index = (addr.value >> 21) & 0x1ff;
    std.debug.assert(pd_index <= PD.MaxIndex);
    return @intCast(PD.IdxType, pd_index);
}

pub fn get_pt_slot(addr: VirtualAddress) PT.IdxType {
    const pt_index = (addr.value >> 12) & 0x1ff;
    std.debug.assert(pt_index <= PT.MaxIndex);
    return @intCast(PT.IdxType, pt_index);
}

pub const PT = struct {
    root: PhysicalAddress,
    base: ?VirtualAddress,
    phys2virt: fn (PhysicalAddress) VirtualAddress = kernel.mm.directTranslate,

    const EntryType = u64;
    const IdxType = u9;
    const MaxIndex = std.math.maxInt(IdxType);
    const TableFormat = [512]EntryType;

    pub const EntryKind = enum {
        Missing,
        Page4K,
    };

    pub const PRESENT = BIT(0);
    pub const WRITABLE = BIT(1);
    pub const USER = BIT(2);
    pub const WRITE_THROUGH = BIT(3);
    pub const CACHE_DISABLE = BIT(4);
    pub const ACCESSED = BIT(5);
    pub const DIRTY = BIT(6);
    pub const GLOBAL = BIT(8);
    pub const NO_EXECUTE = BIT(63);

    const Self = @This();

    pub fn to_pfn(entry: EntryType) u64 {
        return (x86.get_phy_mask() >> 12) & (entry >> 12);
    }

    fn get_table(self: Self) *TableFormat {
        return self.phys2virt(self.root).into_pointer(*TableFormat);
    }

    pub fn get_entry_kind(self: Self, idx: IdxType) EntryKind {
        const entry = self.get_table()[idx];
        const is_present = bit_set(entry, PRESENT);

        if (is_present) {
            return EntryKind.Page4K;
        }
        return EntryKind.Missing;
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

    fn walk(self: Self, comptime T: type, context: *T) void {
        var i: PT.IdxType = 0;
        while (true) : (i += 1) {
            const page = self.get_page(i);
            if (page) |entry| {
                const virt = self.base.?.add(i * mm.KiB(4));
                context.walk(virt, entry, PageKind.Page4K.size());
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

    pub fn size(self: @This()) usize {
        return switch (self) {
            .Page4K => mm.KiB(4),
            .Page2M => mm.MiB(2),
            .Page1G => mm.GiB(1),
        };
    }
};

pub const PD = struct {
    root: PhysicalAddress,
    base: ?VirtualAddress,
    phys2virt: fn (PhysicalAddress) VirtualAddress = kernel.mm.directTranslate,

    const EntryType = u64;
    const IdxType = u9;
    const MaxIndex = std.math.maxInt(IdxType);
    const TableFormat = [512]EntryType;

    pub const PRESENT = BIT(0);
    pub const WRITABLE = BIT(1);
    pub const USER = BIT(2);
    pub const WRITE_THROUGH = BIT(3);
    pub const CACHE_DISABLE = BIT(4);
    pub const ACCESSED = BIT(5);
    pub const DIRTY = BIT(6);
    pub const PAGE_2M = BIT(7);
    pub const GLOBAL = BIT(8);
    pub const NO_EXECUTE = BIT(63);

    const Self = @This();

    pub const EntryKind = enum {
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

    pub fn get_pt_alloc(self: Self, allocator: *mm.FrameAllocator, idx: IdxType) !PT {
        if (self.get_pt(idx) == null) {
            const frame = try allocator.alloc_zero_frame();
            const v = frame.value | PD.WRITABLE.v() | PD.PRESENT.v();
            self.set_entry(idx, v);
        }
        return self.get_pt(idx).?;
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

    fn walk(self: Self, comptime T: type, context: *T) void {
        var i: PD.IdxType = 0;
        while (true) : (i += 1) {
            switch (self.get_entry_kind(i)) {
                .PageTable => {
                    const entry = self.get_pt(i).?;
                    entry.walk(T, context);
                },
                .Page2M => {
                    const entry = self.get_page_2m(i).?;
                    context.walk(self.base.?.add(i * mm.MiB(2)), entry, PageKind.Page2M.size());
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
    phys2virt: fn (PhysicalAddress) VirtualAddress = kernel.mm.directTranslate,

    const IdxType = u9;
    const EntryType = u64;
    const MaxIndex = std.math.maxInt(IdxType);
    const TableFormat = [MaxIndex + 1]EntryType;

    pub const PRESENT = BIT(0);
    pub const WRITABLE = BIT(1);
    pub const USER = BIT(2);
    pub const WRITE_THROUGH = BIT(3);
    pub const CACHE_DISABLE = BIT(4);
    pub const ACCESSED = BIT(5);
    pub const DIRTY = BIT(6);
    pub const PAGE_1G = BIT(7);
    pub const GLOBAL = BIT(8);
    pub const NO_EXECUTE = BIT(63);

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

    pub fn get_pd_alloc(self: Self, allocator: *mm.FrameAllocator, idx: IdxType) !PD {
        if (self.get_pd(idx) == null) {
            const frame = try allocator.alloc_zero_frame();
            const v = frame.value | PDPT.WRITABLE.v() | PDPT.PRESENT.v();
            self.set_entry(idx, v);
        }
        return self.get_pd(idx).?;
    }

    pub fn init(pdp: PhysicalAddress, base: ?VirtualAddress) PDPT {
        return .{ .root = pdp, .base = base };
    }

    fn walk(self: Self, comptime T: type, context: *T) void {
        var i: PDPT.IdxType = 0;
        while (true) : (i += 1) {
            const pd = self.get_pd(i);
            if (pd) |entry| {
                entry.walk(T, context);
            }

            if (i == PDPT.MaxIndex) {
                break;
            }
        }
    }
};

pub const PML4 = struct {
    root: PhysicalAddress,
    // Missing base implies 4 level paging scheme
    base: ?VirtualAddress,
    phys2virt: fn (PhysicalAddress) VirtualAddress = kernel.mm.directTranslate,

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

    pub fn get_pdp_alloc(self: @This(), allocator: *mm.FrameAllocator, idx: IdxType) !PDPT {
        if (self.get_pdp(idx) == null) {
            const frame = try allocator.alloc_zero_frame();
            const v = frame.value | PML4.WRITABLE.v() | PML4.PRESENT.v();
            self.set_entry(idx, v);
        }
        return self.get_pdp(idx).?;
    }

    pub fn get_entry(self: @This(), idx: IdxType) EntryType {
        return self.get_table()[idx];
    }

    pub fn set_entry(self: Self, idx: IdxType, entry: EntryType) void {
        self.get_table()[idx] = entry;
    }

    pub fn walk(self: Self, comptime T: type, context: *T) void {
        var i: PML4.IdxType = 0;
        while (true) : (i += 1) {
            const pdp = self.get_pdp(i);
            if (pdp) |entry| {
                entry.walk(T, context);
            }

            if (i == PML4.MaxIndex) {
                break;
            }
        }
        context.done();
    }
};
