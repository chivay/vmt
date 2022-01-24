const x86 = @import("../x86.zig");

fn PIC(port_base: u32) type {
    return struct {
        const COMMAND_PORT = port_base;
        const DATA_PORT = port_base + 1;

        const Self = @This();

        pub fn command(cmd: u8) void {
            x86.out(u8, COMMAND_PORT, cmd);
        }

        pub fn data_write(data: u8) void {
            x86.out(u8, DATA_PORT, data);
        }
        pub fn data_read() u8 {
            return x86.in(u8, DATA_PORT);
        }

        pub fn set_mask(mask: u8) void {
            Self.data_write(mask);
        }

        pub fn send_eoi() void {
            Self.command(PIC_EOI);
        }

        pub fn disable() void {
            Self.set_mask(0xff);
        }
    };
}

const PIC_EOI = 0x20;
const ICW1_ICW4 = 1;
const ICW4_8086 = 1;
const ICW1_INIT = 0x10;

pub const Master = PIC(0x20);
pub const Slave = PIC(0xa0);

pub fn disable() void {
    Master.disable();
    Slave.disable();
}

pub fn remap(offset1: u8, offset2: u8) void {
    const master_mask = Master.data_read();
    const slave_mask = Slave.data_read();

    Master.command(ICW1_INIT | ICW1_ICW4);
    Slave.command(ICW1_INIT | ICW1_ICW4);

    Master.data_write(offset1);
    Slave.data_write(offset2);

    Master.data_write(4);
    Slave.data_write(2);

    Master.data_write(ICW4_8086);
    Slave.data_write(ICW4_8086);

    Master.data_write(master_mask);
    Slave.data_write(slave_mask);
}

pub fn init() void {
    remap(x86.IRQ_0, x86.IRQ_8);
    Master.data_write(0x00);
    Slave.data_write(0x00);
}
