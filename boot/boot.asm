; Misc constants
STACK_SIZE equ 0x1000

IA32_EFER equ 0xC0000080

; Multiboot constants
MBALIGN  equ  1<<0
MEMINFO  equ  1<<1
FLAGS    equ  MBALIGN | MEMINFO
MAGIC    equ  0x1BADB002
CHECKSUM equ -(MAGIC + FLAGS)
 
section .multiboot
align 4
	dd MAGIC
	dd FLAGS
	dd CHECKSUM 

section .bss
stack:
align 8
    resb STACK_SIZE

section .data
GDT64:
    .null: equ $ - GDT64
    dw 0xffff
    dw 0
    db 0
    db 0
    db 1
    db 0
    .code: equ $ - GDT64
    dw 0
    dw 0
    db 0
    db 10011010b
    db 10101111b
    db 0
    .data: equ $ - GDT64
    dw 0
    dw 0
    db 0
    db 10010010b
    db 00000000b
    db 0
    .ptr:
    dw $ - GDT64 - 1
    dq GDT64


section .text
[bits 32]
global _start
_start:
    ; EAX = 0x2badb002 - when loaded by Multiboot compliant bootloader
    ; EBX = 32 bit physical address of MB info structure
    ; CS - read/execute code segment with 0 offset limit 0xffffffff
    ; DS/ES/FS/GS/SS - read/write data segment with 0 offset limit 0xffffffff
    ; A20 gate enabled
    ; CR0 - PG cleared, PE set
    ; EFLAGS - VM cleared, IF cleared
    ; ESP - required to create own stack
    ; GDTR - might be invalid, create your own GDT
    ; IDTR - don't enable interrupts until it's set up

    ; set up stack
    mov esp, stack + STACK_SIZE

    call initialize_page_tables


    ; set PAE - Physical Address Extension bit in CR4
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; set LME - Long Mode Enable bit in EFER MSR
    mov ecx, IA32_EFER
    rdmsr
    or eax, 1 << 8
    wrmsr   

    ; set PG - Paging bit in CR0
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax


;.hang:
;    hlt
;    jmp .hang
;
    lgdt [GDT64.ptr]
    jmp GDT64.code:start64

section .bss

; 4-level paging structure
ENTRY_SIZE equ 8
NUM_ENTRIES equ 512
PAGE_SIZE equ 0x1000
; ENTRY_SIZE * NUM_ENTRIES == 0x1000

ENTRY_PRESENT  equ (1 << 0)
ENTRY_WRITABLE equ (1 << 1)
ENTRY_1GB      equ (1 << 7)

PAGE_4K equ (ENTRY_PRESENT | ENTRY_WRITABLE)
PAGE_1G equ (ENTRY_PRESENT | ENTRY_WRITABLE | ENTRY_1GB)

ONE_GIBIBYTE equ (1024 * 1024 * 1024)

align 0x1000
pml4t:
    resb 512 * ENTRY_SIZE
pdpt_low:
    resb 512 * ENTRY_SIZE
pdpt_high:
    resb 512 * ENTRY_SIZE

section .text
initialize_page_tables:
    ; CR3 -> 
    mov eax, pml4t
    mov cr3, eax

    mov DWORD [pml4t     + 0 * ENTRY_SIZE],   pdpt_low + (ENTRY_PRESENT | ENTRY_WRITABLE)
    mov DWORD [pml4t     + 511 * ENTRY_SIZE], pdpt_high + (ENTRY_PRESENT | ENTRY_WRITABLE)

    ; let's be lazy

    ; identity map first 1GiB
    mov DWORD [ pdpt_low + 0 * ENTRY_SIZE], 0x0 + PAGE_1G

    ; map first GiB to -2GiB of high memory
    mov DWORD [ pdpt_high + 510 * ENTRY_SIZE], 0x0 + PAGE_1G

    ret


[bits 64]
extern kernel_main
start64:
    mov ax, GDT64.data
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov fs, ax
    mov ss, ax

    call kernel_main

    cli
.hang:
    hlt
    jmp .hang
