// Boot environment defined by
// https://github.com/raspberrypi/tools/blob/master/armstubs/armstub8.S

.section ".text.boot"
.global _start
_start:
    mov sp, 0x10000
    b zero_bss

// Zero out bss
zero_bss:
    ldr x0, =__bss_start
    ldr x1, =__bss_end

    b .loop

.step:
    str xzr, [x0, 0]
    add x0, x0, 8
.loop:
    cmp x0, x1
    b.lt .step

    b entry
