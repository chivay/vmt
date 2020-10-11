ENTRY(multiboot_start)

SECTIONS
{

    . = 1M;
    kernel_boot_start = .;
    .multiboot : { KEEP(*(.multiboot)) }
    .boot.text : { *(.boot.text) }
    .boot.data : { *(.boot.data) }
    .boot.bss : { *(.boot.bss) }
    .boot.stack : { *(.boot.stack) }
    . = ALIGN(0x1000);
    kernel_boot_end = .;
    . += 0xFFFFFFFF80000000;

    .text : AT(kernel_boot_end) { *(.text) }

    . = ALIGN(0x1000);
    .data : AT((LOADADDR(.text) + SIZEOF(.text) + 0xFFF) & 0xFFFFFFFFFFFFF000) { *(.data) }

    . = ALIGN(0x1000);
    .rodata : AT((LOADADDR(.data) + SIZEOF(.data) + 0xFFF) & 0xFFFFFFFFFFFFF000) { *(.rodata) }

    . = ALIGN(0x1000);
    .bss : AT((LOADADDR(.rodata) + SIZEOF(.rodata) + 0xFFF) & 0xFFFFFFFFFFFFF000) { *(.bss) }
    . = ALIGN(0x1000);
    kernel_end = .;
}
