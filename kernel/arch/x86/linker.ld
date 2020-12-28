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
    . = ALIGN(0x1000);
    kernel_boot_end = .;


    . += KERNEL_VIRT_BASE;
    .text : AT(kernel_boot_end) ALIGN(0x1000)
    {
        *(.text)
        *(.text.*)
    } :text
    .rodata : AT((LOADADDR(.text) + SIZEOF(.text) + 0xFFF) & 0xFFFFFFFFFFFFF000) ALIGN(0x1000)
    { 
        *(.rodata)
        *(.rodata.*)
    } :rodata

    .data : AT((LOADADDR(.rodata) + SIZEOF(.rodata) + 0xFFF) & 0xFFFFFFFFFFFFF000) ALIGN(0x1000)
    {
        *(.data)
        *(.data.*)
    } :data

    .bss : AT((LOADADDR(.data) + SIZEOF(.data) + 0xFFF) & 0xFFFFFFFFFFFFF000) ALIGN(0x1000)
    {
        *(.bss)
        *(.bss.*)
    } :data

    . = ALIGN(0x1000);

    kernel_end = .;

    /DISCARD/ : { *(.comment) }
}
