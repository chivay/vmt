
# Misc constants
.set STACK_SIZE, 0x20000
.set IA32_EFER, 0xC0000080

# Multiboot constants
.set MBALIGN,  1<<0
.set MEMINFO,  1<<1
.set FLAGS,  MBALIGN | MEMINFO
.set MAGIC,  0x1BADB002
.set CHECKSUM, -(MAGIC + FLAGS)


.section .multiboot, "a"
.align 4
.long MAGIC
.long FLAGS
.long CHECKSUM

.section .boot.bss, "a", @nobits

# 4-level paging structure
.set ENTRY_SIZE,  8
.set NUM_ENTRIES, 512
.set PAGE_SIZE, 0x1000

.set ENTRY_PRESENT,  (1 << 0)
.set ENTRY_WRITABLE, (1 << 1)
.set ENTRY_LARGE,      (1 << 7)

.set NORMAL_ENTRY,  (ENTRY_PRESENT | ENTRY_WRITABLE)
.set LARGE_ENTRY, (ENTRY_PRESENT | ENTRY_WRITABLE | ENTRY_LARGE)


.align 0x1000
pml4t:
    .skip 512 * ENTRY_SIZE

.align 0x1000
pdpt:
    .skip 512 * ENTRY_SIZE

.align 0x1000
pdpt_high:
    .skip 512 * ENTRY_SIZE

.align 0x1000
pdt:
    .skip 512 * ENTRY_SIZE

.section .boot.text, "ax"

initialize_page_tables:
.type initialize_page_tables, @function
    .code32
    movl $pml4t, %eax
    movl %eax, %cr3

    movl $pdpt + (NORMAL_ENTRY), pml4t
    movl $pdpt_high + (NORMAL_ENTRY), pml4t + 511 * 8

    movl $pdt + (NORMAL_ENTRY), pdpt
    movl $pdt + (NORMAL_ENTRY), pdpt_high + 510 * 8

    # Map first 16 MiB in low and high memory
    movl $0x000000 + (LARGE_ENTRY), pdt + 0 * 8
    movl $0x200000 + (LARGE_ENTRY), pdt + 1 * 8
    movl $0x400000 + (LARGE_ENTRY), pdt + 2 * 8
    movl $0x600000 + (LARGE_ENTRY), pdt + 3 * 8
    movl $0x800000 + (LARGE_ENTRY), pdt + 4 * 8
    movl $0xa00000 + (LARGE_ENTRY), pdt + 5 * 8
    movl $0xc00000 + (LARGE_ENTRY), pdt + 6 * 8
    movl $0xe00000 + (LARGE_ENTRY), pdt + 7 * 8

    ret

fixup_page_tables:
.type initialize_page_tables, @function
    .code64

    ret

.global multiboot_start
.type multiboot_start, @function
multiboot_start:
    .code32
    # EAX = 0x2badb002 - when loaded by Multiboot compliant bootloader
    # EBX = 32 bit physical address of MB info structure
    # CS - read/execute code segment with 0 offset limit 0xffffffff
    # DS/ES/FS/GS/SS - read/write data segment with 0 offset limit 0xffffffff
    # A20 gate enabled
    # CR0 - PG cleared, PE set
    # EFLAGS - VM cleared, IF cleared
    # ESP - required to create own stack
    # GDTR - might be invalid, create your own GDT
    # IDTR - don't enable interrupts until it's set up
    # set up stack

    movl $STACK_SIZE + stack, %esp
    call initialize_page_tables

    # set PAE - Physical Address Extension bit in CR4
    movl %cr4, %eax
    orl $(1<<5), %eax
    movl %eax, %cr4

    # set LME - Long Mode Enable bit in EFER MSR
    movl $IA32_EFER, %ecx
    rdmsr
    orl $(1<<8), %eax
    wrmsr   

    # set PG - Paging bit in CR0
    movl %cr0, %eax
    orl $(1<<31), %eax
    movl %eax, %cr0


    lgdt (GDT64_PTR)
    ljmp $GDT64_CODE_SEG, $START64_ADDR


.section .boot.bss, "a", @nobits
.align 16
    .lcomm stack_begin, STACK_SIZE
.global stack
stack:

.section .boot.data, "a"
GDT64:
    GDT64_NULL:
    .word 0xffff
    .word 0
    .byte 0
    .byte 0
    .byte 1
    .byte 0

    GDT64_CODE:
    .set GDT64_CODE_SEG, GDT64_CODE - GDT64
    .word 0
    .word 0
    .byte 0
    .byte 0b10011010
    .byte 0b10101111
    .byte 0

    GDT64_DATA:
    .set GDT64_DATA_SEG, GDT64_DATA - GDT64
    .word 0
    .word 0
    .byte 0
    .byte 0b10010010
    .byte 0b00000000
    .byte 0

    GDT64_PTR:
    .set GDT64_PTR_SEG, GDT64_PTR - GDT64_NULL - 1
    .word GDT64_PTR_SEG 
    .quad GDT64



################################################################################
# 64 BIT WORLD
################################################################################

.section .boot.text, "ax"
start64:
.global start64
.type start64, @function
.set START64_ADDR, start64
    .code64

    mov $GDT64_DATA_SEG, %ax

    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss

    # Switch stack to high memory
    mov $0xFFFFFFFF80000000, %rax
    add %rax, %rsp
    
    #movl $0xb8000, %edi
    #movq $0x1f201f201f201f20, %rax
    #mov $500, %ecx
    #rep stosq

    mov %ebx, %edi
    call multiboot_entry

    cli
    hlt
