const std = @import("std");
const kernel = @import("root");
const x86 = @import("../x86.zig");
const logger = x86.logger.childOf(@typeName(@This()));

const PhysicalAddress = kernel.mm.PhysicalAddress;

var mmio_base: PhysicalAddress = undefined;

fn mmio_read(comptime T: type, addr: PhysicalAddress) T {
    const addr_virt = kernel.mm.identityTranslate(addr);
    const mmio_addr = @intToPtr(*volatile T, addr_virt.value);
    return mmio_addr.*;
}

fn get_config_space(bus: u8, device: u5, function: u3) PhysicalAddress {
    return mmio_base.add(@as(u64, bus) << 20 | @as(u64, device) << 15 | @as(u64, function) << 12);
}

fn enumerate_pci_devices() void {
    var bus: u8 = 0;
    while (true) : (bus += 1) {
        var device: u5 = 0;
        while (true) : (device += 1) {
            var function: u3 = 0;
            while (true) : (function += 1) {
                const conf_base = get_config_space(bus, device, function);

                const vendor_id = mmio_read(u16, conf_base.add(0));
                const device_id = mmio_read(u16, conf_base.add(2));
                if (vendor_id != 0xffff) {
                    logger.log("{x:0>2}.{x:0>2}.{} Device {x}:{x}\n", .{ bus, device, function, vendor_id, device_id });
                }

                if (function == 7) break;
            }
            if (device == 31) break;
        }
        if (bus == 255) break;
    }
}

pub fn init() void {
    logger.log("Initializing PCI\n", .{});
    if (x86.acpi.mcfg_entry) |entry| {
        mmio_base = PhysicalAddress.new(entry.base_address);
        enumerate_pci_devices();
    } else {
        logger.log("Failed to initialize PCI\n", .{});
    }
}
