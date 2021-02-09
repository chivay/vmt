const std = @import("std");
const kernel = @import("root");
const printk = kernel.printk;
const logger = @import("../x86.zig").logger.childOf(@typeName(@This()));
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

pub fn hexdump(bytes: []const u8) void {
    logger.log("{x}\n", .{bytes});
}

fn parse_fadt(header: *SDTHeader) void {
    logger.log("Parsing FADT\n", .{});
    const data = @intToPtr(*FADTData, @ptrToInt(header) + @sizeOf(SDTHeader));
    //logger.log("{x}\n", .{data});
}

const MCFGEntry = packed struct {
    base_address: u64,
    pci_segment_group: u16,
    start_bus: u8,
    end_bus: u8,
    reserved: u32,
};

fn mmio_read(comptime T: type, addr: PhysicalAddress) T {
    const mmio_addr = @ptrCast(*volatile T, addr.value);
    return mmio_addr.*;
}

pub var mcfg_entry: ?*MCFGEntry = null;

fn parse_mcfg(header: *SDTHeader) void {
    logger.log("Parsing MCFG\n", .{});
    // 8 bytes of reserved field
    const data_length = header.length - @sizeOf(SDTHeader) - 8;
    var data = @intToPtr([*]u8, @ptrToInt(header) + @sizeOf(SDTHeader) + 8)[0..data_length];
    while (data.len >= @sizeOf(MCFGEntry)) : (data = data[@sizeOf(MCFGEntry)..]) {
        const entry = @ptrCast(*MCFGEntry, data);
        mcfg_entry = entry;
    }
}

const MADTLapicEntry = packed struct {
    madt_header: MADTHeader,
    processor_uid: u8,
    apic_id: u8,
    flags: u32,
};

const MADTEntryType = enum(u8) {
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

fn intToEnumSafe(comptime T: type, value: std.meta.Tag(T)) ?T {
    const enumInfo = switch (@typeInfo(T)) {
        .Enum => |enumInfo| enumInfo,
        else => @compileError("Invalid type"),
    };

    comptime if (enumInfo.is_exhaustive) {
        return @intToEnum(T, value);
    };

    inline for (enumInfo.fields) |enumField| {
        if (value == enumField.value) {
            return @intToEnum(T, value);
        }
    }
    return null;
}

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

const MADTLapic = packed struct {
    header: MADTHeader,
    acpi_processor_uid: u8,
    apic_uid: u8,
    flags: u32,
};

fn parse_apic(header: *SDTHeader) void {
    logger.log("Parsing MADT\n", .{});
    //logger.log("{}\n", .{header});
    const data_length = header.length - @sizeOf(SDTHeader);
    var data = @intToPtr([*]u8, @ptrToInt(header) + @sizeOf(SDTHeader))[0..data_length];

    var madt_info_slice = data[0..@sizeOf(MADTInfo)];

    const madt_info: *MADTInfo = @ptrCast(*MADTInfo, madt_info_slice);
    //logger.log("{x}\n", .{madt_info});

    var madt_header: *MADTHeader = undefined;
    var entry_data = data[@sizeOf(MADTInfo)..];
    while (entry_data.len >= @sizeOf(MADTHeader)) : ({
        entry_data = entry_data[madt_header.record_length..];
    }) {
        madt_header = @ptrCast(*MADTHeader, entry_data);
        const typ = intToEnumSafe(MADTEntryType, madt_header.entry_type);
        if (typ == null) continue;
        const typ_enum = typ.?;
        switch (typ_enum) {
            .LocalApic => {
                const lapic = @ptrCast(*MADTLapic, entry_data);
                //logger.log("{}\n", .{lapic});
            },
            else => {
                //logger.log("{}\n", .{typ});
            },
        }
    }
}
fn parse_hpet(header: *SDTHeader) void {
    logger.log("Parsing HPET\n", .{});
}

pub fn parse_table(addr: PhysicalAddress) void {
    const header = mm.directMapping().to_virt(addr).into_pointer(*SDTHeader);
    if (std.mem.eql(u8, header.signature[0..], "FACP")) {
        parse_fadt(header);
    } else if (std.mem.eql(u8, header.signature[0..], "MCFG")) {
        parse_mcfg(header);
    } else if (std.mem.eql(u8, header.signature[0..], "HPET")) {
        parse_hpet(header);
    } else if (std.mem.eql(u8, header.signature[0..], "APIC")) {
        parse_apic(header);
    } else {
        logger.log("Unknown signature {e}\n", .{header.signature});
    }
}

fn parse_rsdt(rsdt: *SDTHeader) void {
    var ptr_slice = @ptrCast([*]u8, rsdt)[@sizeOf(SDTHeader)..rsdt.length];

    const PointerType = u32;
    const pointerSize = @sizeOf(PointerType);

    while (ptr_slice.len >= pointerSize) : (ptr_slice = ptr_slice[pointerSize..]) {
        const addr = PhysicalAddress.new(std.mem.readIntSliceNative(
            PointerType,
            ptr_slice[0..pointerSize],
        ));
        parse_table(addr);
    }
}

pub fn init() void {
    logger.log("Initializing ACPI\n", .{});

    const rsdp = find_rsdp();
    if (rsdp == null) {
        logger.log("Failed to find a RSDP\n", .{});
        return;
    }
    logger.log("Valid RSDP found\n", .{});
    const rsdt = mm.directMapping().to_virt(rsdp.?.get_rsdt()).into_pointer(*SDTHeader);
    parse_rsdt(rsdt);
}
