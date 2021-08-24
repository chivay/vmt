const x86 = @import("../x86.zig");
const std = @import("std");
const kernel = @import("root");
const mm = kernel.mm;

pub var logger = @TypeOf(x86.logger).childOf(@typeName(@This())){};

var framebuffer: ?[]u8 = undefined;

pub fn init() void {
    var fb = x86.multiboot.get_framebuffer() orelse {
        logger.info("Missing framebuffer info\n", .{});
        return;
    };

    if (fb.type != 1) {
        logger.info("Not a RGB framebuffer. Ignoring\n", .{});
        return;
    }

    const fb_addr = mm.PhysicalAddress.new(fb.addr);
    logger.info("Framebuffer at {}\n", .{fb_addr});
    logger.info("Framebuffer dimensions: {}x{} ({} bpp)\n", .{
        fb.width,
        fb.height,
        fb.bpp,
    });

    const length = fb.pitch * fb.height;
    const buffer = kernel.mm.kernel_vm.map_io(fb_addr, length) catch unreachable;
    framebuffer = buffer.as_bytes();
    std.mem.set(u8, framebuffer.?, 0x41);
}
