    .section .text.start
    .globl _start
_start:
    lui  sp, 0x2d
    addi sp, sp, -16
    la   t0, __bss_start
    la   t1, __bss_end
0:
    bgeu t0, t1, 1f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    0b
1:
    la t0, __vault_start
    la t1, __vault_end
3:
    bgeu t0, t1, 4f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 3b
4:
    call main
2:
    j 2b
