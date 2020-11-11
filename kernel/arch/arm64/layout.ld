PHDRS {
    boot PT_LOAD;
    text PT_LOAD FLAGS(5);
    rodata PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
} 

SECTIONS
{
    . = 0x80000;
    .boot :
    {
        KEEP(*(.text.boot))
    } :boot

    .text :
    {
        *(.text)
        *(.text.*)
    } :text
    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    } :rodata

    .data :
    {
        *(.data)
        *(.data.*)
    } :data

    .bss :
    {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        __bss_end = .;
    } :data
}
