pub fn MMIORegion(comptime base: u64, comptime T: type) type {
    return struct {
        pub fn Subregion(comptime offset: u64) type {
            return MMIORegion(base + offset, T);
        }

        pub fn Reg(comptime offset: u64) type {
            return struct {
                const addr = base + offset;
                pub fn read() T {
                    return @as(*volatile T, @ptrFromInt(addr)).*;
                }

                pub fn write(value: T) void {
                    @as(*volatile T, @ptrFromInt(addr)).* = value;
                }
            };
        }
    };
}

pub fn MMIORegister(comptime T: type) type {
    return struct {
        mmio_region: *const DynamicMMIORegion,
        offset: u64,

        pub fn read(self: @This()) T {
            return @as(*volatile T, @ptrFromInt(self.mmio_region.base + self.offset)).*;
        }

        pub fn write(self: @This(), value: T) void {
            @as(*volatile T, @ptrFromInt(self.mmio_region.base + self.offset)).* = value;
        }
    };
}

pub const DynamicMMIORegion = struct {
    base: u64,

    pub fn init(base: u64) DynamicMMIORegion {
        return DynamicMMIORegion{ .base = base };
    }

    pub fn Reg(self: *const @This(), comptime T: type, offset: u64) MMIORegister(T) {
        const Struct = MMIORegister(T);
        return Struct{ .mmio_region = self, .offset = offset };
    }
};
