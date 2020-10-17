ENTRY(multiboot_start)

SECTIONS
{

    . = 1M;
    kernel_boot_start = .;
    .multiboot : { KEEP(*(.multiboot)) }
    .boot.text : { *(.boot.text) }
    .boot.data : { *(.boot.data) }
    .boot.bss : { *(.boot.bss) }
    . = ALIGN(0x1000);
    kernel_boot_end = .;
    . += 0xFFFFFFFF80000000;

    .text : AT(kernel_boot_end) ALIGN(0x1000) { *(.text) }

    .data : AT((LOADADDR(.text) + SIZEOF(.text) + 0xFFF) & 0xFFFFFFFFFFFFF000) ALIGN(0x1000) { *(.data) }

    .rodata : AT((LOADADDR(.data) + SIZEOF(.data) + 0xFFF) & 0xFFFFFFFFFFFFF000) ALIGN(0x1000) { *(.rodata) }

    .bss : AT((LOADADDR(.rodata) + SIZEOF(.rodata) + 0xFFF) & 0xFFFFFFFFFFFFF000) ALIGN(0x1000) { *(.bss) }
    . = ALIGN(0x1000);
    kernel_end = .;
}
