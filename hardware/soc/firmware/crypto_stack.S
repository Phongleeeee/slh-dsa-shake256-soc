    .text
    .globl slh_crypto_call
slh_crypto_call:
    addi sp, sp, -16
    sw ra, 0(sp)
    sw s0, 4(sp)
    mv s0, sp
    mv t0, a0
    mv a0, a1
    lui sp, 0x30
    addi sp, sp, -16
    jalr ra, t0, 0
    mv sp, s0
    lw ra, 0(sp)
    lw s0, 4(sp)
    addi sp, sp, 16
    ret
