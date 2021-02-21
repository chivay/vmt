.pushsection ".smp_trampoline"

ap_startup:
.global ap_startup
.code16

    // Enter long mode.
    movl $0b10100000, %eax
    mov %eax, %cr4

    // Setup CR3
    movl $KERNEL_CR3, %eax
    movl %eax, %cr3

    // Read EFER
    movl $0xC0000080, %ecx
    rdmsr

    // Set LME
    orl $0x00000100, %eax
    wrmsr

    // Enable paging and protection
    mov %cr0, %eax
    orl $0x80000001, %eax
    mov %eax, %cr0

    lgdt (GDT64_PTR)
    ljmp $0x08, $startup64

startup64:
    .code64
    mov $0x10, %ax

    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss

    movabs $STACK, %rax
    mov %rax, %rsp

    movabs $ENTRYPOINT, %rax
    jmp *%rax

GDT64:
    GDT64_NULL:
    .quad 0

    GDT64_CODE:
    .quad 0x00209A0000000000
    .quad 0x0000920000000000

    .align 4
    .word 0

    GDT64_PTR:
    .set GDT64_PTR_SEG, GDT64_PTR - GDT64_NULL - 1
    .word GDT64_PTR_SEG
    .quad GDT64
.popsection
