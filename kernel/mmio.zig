pub fn MMIORegion(comptime base: u64, comptime T: type) type {
    return struct {
        pub fn Subregion(comptime offset: u64) type {
            return MMIORegion(base + offset, T);
        }

        pub fn Reg(comptime offset: u64) type {
            return struct {
                const addr = base + offset;
                pub fn read() T {
                    return @intToPtr(*volatile T, addr).*;
                }

                pub fn write(value: T) void {
                    @intToPtr(*volatile T, addr).* = value;
                }
            };
        }
    };
}
