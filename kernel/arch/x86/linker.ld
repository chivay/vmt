ENTRY(multiboot_start)

PHDRS {
    headers PT_LOAD PHDRS FILEHDR;
    boot PT_LOAD;

    text PT_LOAD FLAGS(5);   /* R-X */
    rodata PT_LOAD FLAGS(4); /* R-- */
    data PT_LOAD FLAGS(6);   /* RW  */
}

KERNEL_BASE = 1M;
KERNEL_VIRT_BASE = 0xFFFFFFFF80000000;

SECTIONS
{
    . = KERNEL_BASE + SIZEOF_HEADERS;

    kernel_boot_start = .;
    .multiboot : { KEEP(*(.multiboot)) } :headers
    .boot.text : { *(.boot.text) } :boot
    .boot.data : { *(.boot.data) } :boot
    .boot.bss : { *(.boot.bss) } :boot
    kernel_boot_end = .;

    . += KERNEL_VIRT_BASE;

    . = ALIGN(0x1000);
    .text : AT(kernel_boot_end)
    {
        *(.text)
        *(.text.*)
    } :text

    . = ALIGN(0x1000);
    .rodata : AT(ADDR(.rodata) - KERNEL_VIRT_BASE)
    { 
        *(.rodata)
        *(.rodata.*)
    } :rodata

    .debuginfo : AT(ADDR(.debuginfo) - KERNEL_VIRT_BASE)
    { 
        *(.rodata)
        *(.rodata.*)
    } :rodata

    . = ALIGN(0x1000);
    .data : AT(ADDR(.data) - KERNEL_VIRT_BASE)
    {
        *(.data)
        *(.data.*)
    } :data

    . = ALIGN(0x1000);
    .bss : AT(ADDR(.bss) - KERNEL_VIRT_BASE)
    {
        *(.bss)
        *(.bss.*)
    } :data

    . = ALIGN(0x1000);

    kernel_end = .;

    /DISCARD/ : { *(.comment) }
}
