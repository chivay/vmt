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
    //std.debug.assert(@sizeOf(Struct) == 36);
    std.debug.assert(@byteOffsetOf(Struct, "signature") == 0);
    std.debug.assert(@byteOffsetOf(Struct, "checksum") == 8);
    std.debug.assert(@byteOffsetOf(Struct, "oemid") == 9);
    std.debug.assert(@byteOffsetOf(Struct, "revision") == 15);
    std.debug.assert(@byteOffsetOf(Struct, "rsdt_address") == 16);
    std.debug.assert(@byteOffsetOf(Struct, "length") == 20);
}

const SDTHeader = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oemid: [6]u8,
    oemtableid: [8]u8,
    oemrevision: u32,
    creatorid: u32,
    creatorrevision: u32,
};

comptime {
    const Struct = SDTHeader;
    //std.debug.assert(@sizeOf(Struct) == 36);
    std.debug.assert(@byteOffsetOf(Struct, "signature") == 0);
    std.debug.assert(@byteOffsetOf(Struct, "length") == 4);
    std.debug.assert(@byteOffsetOf(Struct, "revision") == 8);
    std.debug.assert(@byteOffsetOf(Struct, "checksum") == 9);
    std.debug.assert(@byteOffsetOf(Struct, "oemid") == 10);
    std.debug.assert(@byteOffsetOf(Struct, "oemtableid") == 16);
    std.debug.assert(@byteOffsetOf(Struct, "oemrevision") == 24);
    std.debug.assert(@byteOffsetOf(Struct, "creatorid") == 28);
    std.debug.assert(@byteOffsetOf(Struct, "creatorrevision") == 32);
}

comptime {
    std.debug.assert(@sizeOf(SDTHeader) == 36);
}

const RSDT = extern struct {
    header: SDTHeader,

    pub fn get_pointers(self: @This()) []u32 {
        const entries = (self.header.length - @sizeOf(@TypeOf(self.header))) / @sizeOf(u32);
        const array = @intToPtr([*]u32, @ptrToInt(&self) + @sizeOf(SDTHeader));

        return array[0..entries];
    }
};

fn find_rsdp() ?*RSDP {
    var base = PhysicalAddress.new(0);
    const limit = PhysicalAddress.new(mm.MiB(2));

    // Use correct method (?)
    while (base.lt(limit)) : (base = base.add(16)) {
        //logger.log("Searching... {}", .{base});
        const candidate = mm.identityMapping().to_virt(base).into_pointer(*RSDP);
        if (candidate.signature_ok()) {
            if (candidate.checksum_ok()) {
                return candidate;
            }
            logger.log("{*} signature OK, checksum mismatch\n", .{candidate});
        }
    }
    return null;
}

pub fn init() void {
    logger.log("Initializing ACPI\n", .{});

    const rsdp = find_rsdp();
    if (rsdp == null) {
        logger.log("Failed to find a RSDP\n", .{});
        return;
    }
    logger.log("Valid RSDP found\n", .{});

    const rsdt = mm.identityMapping().to_virt(rsdp.?.get_rsdt()).into_pointer(*RSDT);
    logger.log("RSDT:\n{*}\n", .{rsdt});
    const pointers = rsdt.get_pointers();
}
