const MMIORegion = @import("root").mmio.MMIORegion;

// Thus a peripheral advertised here at bus address 0x7Ennnnnn is
// available at physical address 0x3Fnnnnnn.
//
pub const MMIO = MMIORegion(0x3F000000, u32);

pub const GPIO = struct {
    pub const Region = MMIO.Subregion(0x200000);
    pub const GPPUD = Region.Reg(0x94);
    pub const GPPUDCLK0 = Region.Reg(0x98);
};

pub const MINI_UART = struct {
    pub const Region = GPIO.Region.Subregion(0x15000);

    /// Auxilliary interrupt status
    pub const AUX_IRQ = Region.Reg(0x0);

    /// Auxiliary enables
    pub const AUX_ENABLES = Region.Reg(0x4);

    /// I/O data
    pub const IO = Region.Reg(0x40);

    /// Interrupt enable register
    pub const IER = Region.Reg(0x44);

    /// Interrupt identity register
    pub const IIR = Region.Reg(0x48);

    /// Line control
    pub const LCR = Region.Reg(0x4c);

    /// Modem control
    pub const MCR = Region.Reg(0x50);

    /// Line status
    pub const LSR = Region.Reg(0x54);

    /// Modem status
    pub const MSR = Region.Reg(0x58);

    /// Scratch
    pub const SCRATCH = Region.Reg(0x5c);

    /// Extra control
    pub const CNTL = Region.Reg(0x60);

    /// Extra status
    pub const STAT = Region.Reg(0x64);

    /// Baudrate
    pub const BAUD = Region.Reg(0x68);
};

pub const PL011 = struct {
    pub const Region = GPIO.Region.Subregion(0x1000);

    /// Data register
    pub const DR = Region.Reg(0x0);
    pub const RSRECR = Region.Reg(0x4);

    /// Flag register
    pub const FR = Region.Reg(0x18);

    /// Unused
    pub const ILPR = Region.Reg(0x20);

    /// Integer baud rate divisor
    pub const IBRD = Region.Reg(0x24);

    /// Fractional baud rate divisor
    pub const FBRD = Region.Reg(0x28);

    /// Line control register
    pub const LCRH = Region.Reg(0x2c);

    /// Control register
    pub const CR = Region.Reg(0x30);

    /// Interrupt FIFO level select register
    pub const IFLS = Region.Reg(0x34);

    /// Interrupt mask set clear register
    pub const IMSC = Region.Reg(0x38);

    /// Raw interrupt status register
    pub const RIS = Region.Reg(0x3c);

    /// Masked interrupt status register
    pub const MIS = Region.Reg(0x40);

    /// Interrupt clear registrer
    pub const ICR = Region.Reg(0x44);

    /// DMA control register
    pub const DMACR = Region.Reg(0x48);

    /// Test control register
    pub const ITCR = Region.Reg(0x80);

    /// Integration test input register
    pub const ITIP = Region.Reg(0x84);

    /// Integration test output register
    pub const ITOP = Region.Reg(0x88);

    /// Test data register
    pub const TDR = Region.Reg(0x8c);
};

pub const PM = struct {
    pub const Region = MMIO.Subregion(0x100000);

    pub const RSTC = Region.Reg(0x1c);
    pub const RSTS = Region.Reg(0x20);
    pub const WDOG = Region.Reg(0x24);

    pub const PASSWORD = 0x5a000000;
};
