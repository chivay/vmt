const std = @import("std");
const kernel = @import("root");
const printk = kernel.printk;
const mm = kernel.mm;
const x86 = @import("../x86.zig");

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

fn bit_set(value: var, comptime bit: usize) bool {
    return ((value >> bit) & 1) != 0;
}

fn detect_multiboot_memory(mb_info: *x86.multiboot.Info) ?mm.MemoryRange {
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

    var best_slot: ?mm.MemoryRange = null;

    var offset = mm.PhysicalAddress.new(mb_info.mmap_addr);
    const mmap_end = mm.PhysicalAddress.new(mb_info.mmap_addr + mb_info.mmap_length);

    printk("BIOS memory map:\n", .{});
    while (offset.lt(mmap_end)) {
        const entry = x86.mm.identityMapping().to_virt(offset).into_pointer(MemEntry);

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

    main_allocator = mm.FrameAllocator.new(adjusted_memory);
    kernel_vm = mm.VirtualMemory.init(&main_allocator);

    const addr = mm.frameAllocator().alloc_frame();
    printk("{x}\n", .{addr});
}
