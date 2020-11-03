const std = @import("std");
const kernel = @import("root");
const printk = kernel.printk;
const mm = kernel.mm;
const x86 = @import("../x86.zig");

const PhysicalAddress = mm.PhysicalAddress;

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
        return identityMapping().to_virt(self.root).into_pointer(*TableFormat);
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

    pub fn init(pt: PhysicalAddress) PT {
        return .{ .root = pt };
    }
};

pub const PD = struct {
    root: PhysicalAddress,

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
        return identityMapping().to_virt(self.root).into_pointer(*TableFormat);
    }

    pub fn get_pt(self: Self, idx: IdxType) ?PT {
        const entry = self.get_table()[idx];

        if (bit_set(entry, PRESENT) and !bit_set(entry, PAGE_2M)) {
            // present
            return PT.init(PhysicalAddress.new(entry & mask));
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

    pub fn init(pd: PhysicalAddress) PD {
        return .{ .root = pd };
    }
};

pub const PDPT = struct {
    root: PhysicalAddress,

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
        return identityMapping().to_virt(self.root).into_pointer(*TableFormat);
    }

    fn get_entry(self: Self, idx: IdxType) EntryType {
        return self.get_table()[idx];
    }

    pub fn get_pd(self: Self, idx: IdxType) ?PD {
        const entry = self.get_entry(idx);

        if (bit_set(entry, PRESENT) and !bit_set(entry, PAGE_1G)) {
            // present
            return PD.init(PhysicalAddress.new(entry & mask));
        }
        return null;
    }

    pub fn init(pdp: PhysicalAddress) PDPT {
        return .{ .root = pdp };
    }
};

const BitStruct = struct {
    shift: comptime_int,
};

pub fn BIT(comptime n: comptime_int) BitStruct {
    return .{ .shift = n };
}

pub const PML4 = struct {
    root: PhysicalAddress,

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

    fn get_table(self: @This()) *TableFormat {
        return identityMapping().to_virt(self.root).into_pointer(*TableFormat);
    }

    pub fn get_pdp(self: @This(), idx: IdxType) ?PDPT {
        const entry = self.get_entry(idx);
        if (bit_set(entry, PRESENT)) {
            return PDPT.init(PhysicalAddress.new(entry & mask));
        }
        return null;
    }

    fn get_entry(self: @This(), idx: IdxType) EntryType {
        return self.get_table()[idx];
    }

    pub fn init(pml4: PhysicalAddress) PML4 {
        return .{ .root = pml4 };
    }
};

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

    dump_mm();

    main_allocator = mm.FrameAllocator.new(adjusted_memory);
    kernel_vm = mm.VirtualMemory.init(&main_allocator);

    const addr = mm.frameAllocator().alloc_frame();
    printk("{x}\n", .{addr});
}
