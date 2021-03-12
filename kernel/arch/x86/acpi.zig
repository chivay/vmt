const std = @import("std");
const kernel = @import("root");
const printk = kernel.printk;
const logger = @TypeOf(@import("../x86.zig").logger).childOf(@typeName(@This())){};
const mm = kernel.mm;

const PhysicalAddress = kernel.mm.PhysicalAddress;

const RSDP = extern struct {
    // "RSD PTR "
    signature: [8]u8,
    // Includes only 0-19 bytes, summing to zero
    checksum: u8,
    // OEM identifier
    oemid: [6]u8,
    // Revision of the structure, current value 2
    revision: u8,
    // Physical address of the RSDT
    rsdt_address: u32,
    length: u32,
    xsdt_address: u64,
    extended_checksum: u8,

    // zig compiler workaound
    reserveda: [3]u8,

    pub fn get_rsdt(self: @This()) PhysicalAddress {
        std.debug.assert(self.signature_ok());
        std.debug.assert(self.checksum_ok());
        return PhysicalAddress.new(self.rsdt_address);
    }

    pub fn signature_ok(self: @This()) bool {
        return std.mem.eql(u8, self.signature[0..], "RSD PTR ");
    }

    fn sum_field(self: @This(), comptime field: []const u8) u8 {
        var total: u8 = 0;
        const bytes = std.mem.asBytes(&@field(self, field));
        for (bytes) |c| {
            total = total +% c;
        }
        return total;
    }

    pub fn checksum_ok(self: @This()) bool {
        return self.calc_checksum() == 0;
    }

    pub fn calc_checksum(self: @This()) u8 {
        var total: u8 = 0;
        total = total +% self.sum_field("signature");
        total = total +% self.sum_field("checksum");
        total = total +% self.sum_field("oemid");
        total = total +% self.sum_field("revision");
        total = total +% self.sum_field("rsdt_address");

        return total;
    }
};

comptime {
    const Struct = RSDP;
    // Zig compiler is a little broken for packed structs :<
    //std.debug.assert(@sizeOf(Struct) == 36);
    std.debug.assert(@byteOffsetOf(Struct, "signature") == 0);
    std.debug.assert(@byteOffsetOf(Struct, "checksum") == 8);
    std.debug.assert(@byteOffsetOf(Struct, "oemid") == 9);
    std.debug.assert(@byteOffsetOf(Struct, "revision") == 15);
    std.debug.assert(@byteOffsetOf(Struct, "rsdt_address") == 16);
    std.debug.assert(@byteOffsetOf(Struct, "length") == 20);
}

const SDTHeader = packed struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    // Zig compiler bug workaround - fields can only have a power of 2 size
    oemid_a: [4]u8,
    oemid_b: [2]u8,
    oemtableid: [8]u8,
    oemrevision: u32,
    creatorid: u32,
    creatorrevision: u32,
};

comptime {
    const Struct = SDTHeader;
    std.debug.assert(@sizeOf(Struct) == 36);
    std.debug.assert(@byteOffsetOf(Struct, "signature") == 0);
    std.debug.assert(@byteOffsetOf(Struct, "length") == 4);
    std.debug.assert(@byteOffsetOf(Struct, "revision") == 8);
    std.debug.assert(@byteOffsetOf(Struct, "checksum") == 9);
    std.debug.assert(@byteOffsetOf(Struct, "oemid_a") == 10);
    std.debug.assert(@byteOffsetOf(Struct, "oemtableid") == 16);
    std.debug.assert(@byteOffsetOf(Struct, "oemrevision") == 24);
    std.debug.assert(@byteOffsetOf(Struct, "creatorid") == 28);
    std.debug.assert(@byteOffsetOf(Struct, "creatorrevision") == 32);
}

const FADTData = packed struct {
    firmware_ctrl: u32,
    dsdt: u32,
    reserved: u8,
    preferred_pm_profile: u8,
    sci_int: u16,
    smi_cmd: u32,
    acpi_enable: u8,
    acpi_disable: u8,
    s4bios_req: u8,
    pstate_cnt: u8,
    pm1a_evt_blk: u32,
    pm1b_evt_blk: u32,
    pm1a_cnt_blk: u32,
    pm1b_cnt_blk: u32,
    pm2_cnt_blk: u32,
    pm2_tmr_blk: u32,
    gpe0_blk: u32,
    gpe1_blk: u32,
    pm1_evt_len: u8,
    pm1_cnt_len: u8,
    pm2_cnt_len: u8,
    pm_tmr_len: u8,
    gpe0_blk_len: u8,
    gpe1_blk_len: u8,
    gpe1_base: u8,
    cst_cnt: u8,
    p_lvl2_lat: u16,
    p_lvl3_lat: u16,
    flush_size: u16,
    flush_stride: u16,
    duty_offset: u8,
    duty_width: u8,
    day_alrm: u8,
    mon_alrm: u8,
    century: u8,
    iapc_boot_arch: u16,
    reserved_: u8,
    flags: u32,
    // Zig bug workaround
    reset_reg_low: u64,
    reset_reg_high: u32,
    reset_value: u8,
    arm_boot_arch: u16,
    fadt_minor_version: u8,
    x_firmware_ctrl: u64,
    x_dsdt: u64,
    // TODO rest
};

fn find_rsdp() ?*RSDP {
    var base = PhysicalAddress.new(0);
    const limit = PhysicalAddress.new(mm.MiB(2));

    // Use correct method (?)
    while (base.lt(limit)) : (base = base.add(16)) {
        //logger.log("Searching... {}", .{base});
        const candidate = mm.directMapping().to_virt(base).into_pointer(*RSDP);
        if (candidate.signature_ok()) {
            if (candidate.checksum_ok()) {
                return candidate;
            }
            logger.log("{*} signature OK, checksum mismatch\n", .{candidate});
        }
    }
    return null;
}

const MCFGEntry = packed struct {
    base_address: u64,
    pci_segment_group: u16,
    start_bus: u8,
    end_bus: u8,
    reserved: u32,
};

pub const MCFGIterator = struct {
    data: []const u8,

    pub fn empty() MCFGIterator {
        return .{ .data = &[_]u8{} };
    }

    pub fn next(self: *@This()) ?*const MCFGEntry {
        if (self.data.len < @sizeOf(MCFGEntry)) return null;
        const entry = @ptrCast(*const MCFGEntry, self.data);
        self.data = self.data[@sizeOf(MCFGEntry)..];
        return entry;
    }

    pub fn init(header: *SDTHeader) MCFGIterator {
        const data_length = header.length - @sizeOf(SDTHeader) - 8;
        var data = @intToPtr([*]u8, @ptrToInt(header) + @sizeOf(SDTHeader) + 8)[0..data_length];
        return .{ .data = data };
    }
};

pub const MADTLapicEntry = packed struct {
    madt_header: MADTHeader,
    processor_uid: u8,
    apic_id: u8,
    flags: u32,
};

pub const MADTEntryType = enum(u8) {
    LocalApic = 0,
    IoApic = 1,
    InterruptSourceOverrride = 2,
    NmiSource = 3,
    LocalApicNmi = 4,
    LocalApicAddressOverride = 5,
    IoSapic = 6,
    LocalSapic = 7,
    PlatformInterruptSources = 8,
    ProcessorLocalx2Apic = 9,
    Localx2ApicNmi = 0xa,
    _,
};

const MADTInfo = packed struct {
    lapic_address: u32,
    // The 8259 vectors must be disabled (that is, masked) when
    // enabling the ACPI APIC operation.
    flags: u32,
};

const MADTHeader = packed struct {
    entry_type: u8,
    record_length: u8,
};

pub const MADTLapic = packed struct {
    header: MADTHeader,
    acpi_processor_uid: u8,
    apic_uid: u8,
    flags: u32,
};

pub const MADTIterator = struct {
    data: []const u8,

    pub fn next(self: *@This()) ?*const MADTHeader {
        if (self.data.len >= @sizeOf(MADTHeader)) {
            const madt_header = @ptrCast(*const MADTHeader, self.data.ptr);
            self.data = self.data[madt_header.record_length..];
            return madt_header;
        }
        return null;
    }

    pub fn empty() MADTIterator {
        return .{ .data = &[_]u8{} };
    }

    pub fn init(header: *SDTHeader) MADTIterator {
        const data_length = header.length - @sizeOf(SDTHeader);
        var data = @intToPtr([*]u8, @ptrToInt(header) + @sizeOf(SDTHeader))[0..data_length];

        var madt_info_slice = data[0..@sizeOf(MADTInfo)];

        const madt_info: *MADTInfo = @ptrCast(*MADTInfo, madt_info_slice);
        //logger.log("{x}\n", .{madt_info});

        var madt_header: *MADTHeader = undefined;
        var entry_data = data[@sizeOf(MADTInfo)..];

        return .{ .data = entry_data };
    }
};

pub fn iterMADT() MADTIterator {
    if (getTable("APIC")) |table| {
        return MADTIterator.init(table);
    }
    return MADTIterator.empty();
}

pub fn iterMCFG() MCFGIterator {
    if (getTable("MCFG")) |table| {
        return MCFGIterator.init(table);
    }
    return MCFGIterator.empty();
}

const SDTIterator = struct {
    data: []const u8,

    pub fn next(self: *@This()) ?*SDTHeader {
        const PointerType = u32;
        const pointerSize = @sizeOf(PointerType);

        if (self.data.len >= pointerSize) {
            const addr = PhysicalAddress.new(std.mem.readIntSliceNative(
                PointerType,
                self.data[0..pointerSize],
            ));
            self.data = self.data[pointerSize..];
            return mm.directMapping().to_virt(addr).into_pointer(*SDTHeader);
        }
        return null;
    }

    pub fn init(rsdt: *SDTHeader) SDTIterator {
        return .{ .data = @ptrCast([*]u8, rsdt)[@sizeOf(SDTHeader)..rsdt.length] };
    }
};

pub fn iterSDT() SDTIterator {
    return SDTIterator.init(rsdt_root);
}

pub fn getTable(name: []const u8) ?*SDTHeader {
    var sdt_it = iterSDT();
    while (sdt_it.next()) |table| {
        if (std.mem.eql(u8, name, &table.signature)) {
            return table;
        }
    }
    return null;
}

var rsdt_root: *SDTHeader = undefined;

pub fn init() void {
    logger.log("Initializing ACPI\n", .{});

    const rsdp = find_rsdp();
    if (rsdp == null) {
        logger.log("Failed to find a RSDP\n", .{});
        return;
    }
    logger.log("Valid RSDP found\n", .{});
    rsdt_root = mm.directMapping().to_virt(rsdp.?.get_rsdt()).into_pointer(*SDTHeader);

    var sdt_it = iterSDT();
    while (sdt_it.next()) |table| {
        logger.info("Found table {e}\n", .{std.fmt.fmtSliceEscapeLower(&table.signature)});
    }
}
