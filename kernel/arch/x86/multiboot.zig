pub var info_pointer: ?*Info = null;

pub const AoutSymbolTable = packed struct {
    tabsize: u32,
    strsize: u32,
    addr: u32,
    reserved: u32,
};

pub const ElfSectionHeaderTable = packed struct {
    num: u32,
    size: u32,
    addr: u32,
    shndx: u32,
};

pub const Info = packed struct {
    flags: u32,

    mem_lower: u32,
    mem_uppper: u32,

    boot_device: u32,

    cmdline: u32,

    mods_count: u32,
    mods_addr: u32,

    u: packed union {
        aout_sym: AoutSymbolTable,
        elf_sec: ElfSectionHeaderTable,
    },

    mmap_length: u32,
    mmap_addr: u32,

    drives_length: u32,
    drives_addr: u32,

    config_table: u32,

    boot_loader_name: u32,

    apm_table: u32,

    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
};
