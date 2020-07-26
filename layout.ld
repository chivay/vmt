ENTRY(_start)

SECTIONS
{
    . = 1M;

    kernel_phys_start = .;
    .mbheader :
    {
        boot.o (.multiboot)
    }
    .boot :
    {
        boot.o (.text)
    }
    .bootdata :
    {
        boot.o (.data)
        boot.o (.rodata)
    }
    .bootbss : 
    {
        boot.o (.bss)
        boot.o (COMMON)
    }

    . = ALIGN(0x1000);
    kernel_boot_end = .;

    /* This is where the fun begins */

    . += 0xFFFFFFFF80000000;
    kernel_virt_start = .;

    .text : AT(kernel_boot_end)
    {
        *(.text)
    }
    
    . = ALIGN(0x1000);

    .data : AT((LOADADDR(.text) + SIZEOF(.text) + 0xFFF) & 0xFFFFFFFFFFFFF000)
    {
        *(.data)
    }

    . = ALIGN(0x1000);
    
    .rodata : AT((LOADADDR(.data) + SIZEOF(.data) + 0xFFF) & 0xFFFFFFFFFFFFF000)
    {
        *(.rodata)
    }

    . = ALIGN(0x1000);

    .bss : AT((LOADADDR(.rodata) + SIZEOF(.rodata) + 0xFFF) & 0xFFFFFFFFFFFFF000)
    {
        *(.bss)
    }
    kernel_virt_end = .;
    _kernel_phys_end = (LOADADDR(.bss) + SIZEOF(.bss));
}
