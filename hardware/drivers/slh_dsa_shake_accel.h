#ifndef SLH_DSA_SHAKE_ACCEL_H
#define SLH_DSA_SHAKE_ACCEL_H

#include <stdint.h>

/* AXI4-Lite register map for slh_dsa_shake_axi_lite.v, interface v2. */
#define SLH_ACCEL_CONTROL       0x00u
#define SLH_ACCEL_STATUS        0x04u
#define SLH_ACCEL_PUB_SEED      0x08u
#define SLH_ACCEL_ADRS          0x28u
#define SLH_ACCEL_INPUT         0x48u
#define SLH_ACCEL_DIGEST        0x88u
#define SLH_ACCEL_ID            0xA8u
#define SLH_ACCEL_IRQ_ENABLE    0xACu
#define SLH_ACCEL_IRQ_STATUS    0xB0u
#define SLH_ACCEL_CAPABILITIES  0xB4u

#define SLH_ACCEL_CONTROL_START        (1u << 0)
#define SLH_ACCEL_CONTROL_TWO_BLOCKS   (1u << 1)
#define SLH_ACCEL_CONTROL_CLEAR_STATUS (1u << 2)
#define SLH_ACCEL_CONTROL_ZEROIZE      (1u << 3)

#define SLH_ACCEL_STATUS_READY          (1u << 0)
#define SLH_ACCEL_STATUS_DONE           (1u << 1)
#define SLH_ACCEL_STATUS_BUSY           (1u << 2)
#define SLH_ACCEL_STATUS_ERROR          (1u << 3)
#define SLH_ACCEL_STATUS_CONFIG_F_VALID (1u << 4)
#define SLH_ACCEL_STATUS_CONFIG_H_VALID (1u << 5)
#define SLH_ACCEL_STATUS_ZEROIZING      (1u << 6)

#define SLH_ACCEL_IRQ_DONE          (1u << 0)
#define SLH_ACCEL_IRQ_ERROR         (1u << 1)
#define SLH_ACCEL_EXPECTED_ID       0x534C4802u
#define SLH_ACCEL_EXPECTED_CAPS     0x0001003Fu

static inline void slh_accel_write(volatile uint32_t *base,
                                   uint32_t offset, uint32_t value)
{
    base[offset >> 2] = value;
}

static inline uint32_t slh_accel_read(volatile uint32_t *base,
                                      uint32_t offset)
{
    return base[offset >> 2];
}

static inline int slh_accel_probe(volatile uint32_t *base)
{
    return slh_accel_read(base, SLH_ACCEL_ID) == SLH_ACCEL_EXPECTED_ID &&
           slh_accel_read(base, SLH_ACCEL_CAPABILITIES) ==
               SLH_ACCEL_EXPECTED_CAPS ? 0 : -1;
}

/* Buffers use the RTL little-endian byte order: byte zero is bits 7:0 of
 * word zero. Input is 32 bytes for F or 64 bytes for H. Input registers are
 * intentionally write-only and cannot be read back from software. */
static inline int slh_accel_start(volatile uint32_t *base,
                                  const uint32_t pub_seed[8],
                                  const uint32_t adrs[8],
                                  const uint32_t input[16],
                                  int two_blocks)
{
    uint32_t status;
    unsigned int i;
    if (slh_accel_probe(base) != 0) return -1;
    status = slh_accel_read(base, SLH_ACCEL_STATUS);
    if ((status & SLH_ACCEL_STATUS_READY) == 0) return -2;

    slh_accel_write(base, SLH_ACCEL_IRQ_STATUS,
                    SLH_ACCEL_IRQ_DONE | SLH_ACCEL_IRQ_ERROR);
    for (i = 0; i < 8; ++i)
        slh_accel_write(base, SLH_ACCEL_PUB_SEED + 4u*i, pub_seed[i]);
    for (i = 0; i < 8; ++i)
        slh_accel_write(base, SLH_ACCEL_ADRS + 4u*i, adrs[i]);
    for (i = 0; i < (two_blocks ? 16u : 8u); ++i)
        slh_accel_write(base, SLH_ACCEL_INPUT + 4u*i, input[i]);

    status = slh_accel_read(base, SLH_ACCEL_STATUS);
    if ((status & (two_blocks ? SLH_ACCEL_STATUS_CONFIG_H_VALID :
                               SLH_ACCEL_STATUS_CONFIG_F_VALID)) == 0)
        return -3;
    slh_accel_write(base, SLH_ACCEL_IRQ_ENABLE,
                    SLH_ACCEL_IRQ_DONE | SLH_ACCEL_IRQ_ERROR);
    slh_accel_write(base, SLH_ACCEL_CONTROL,
                    SLH_ACCEL_CONTROL_START |
                    (two_blocks ? SLH_ACCEL_CONTROL_TWO_BLOCKS : 0u));
    return 0;
}

static inline int slh_accel_finish(volatile uint32_t *base,
                                   uint32_t digest[8],
                                   uint32_t maximum_polls)
{
    uint32_t status;
    uint32_t poll;
    unsigned int i;
    for (poll = 0; poll < maximum_polls; ++poll) {
        status = slh_accel_read(base, SLH_ACCEL_STATUS);
        if ((status & SLH_ACCEL_STATUS_ERROR) != 0) {
            slh_accel_write(base, SLH_ACCEL_IRQ_STATUS,
                            SLH_ACCEL_IRQ_ERROR);
            return -1;
        }
        if ((status & SLH_ACCEL_STATUS_DONE) != 0) {
            for (i = 0; i < 8; ++i)
                digest[i] = slh_accel_read(base,
                                           SLH_ACCEL_DIGEST + 4u*i);
            slh_accel_write(base, SLH_ACCEL_IRQ_STATUS,
                            SLH_ACCEL_IRQ_DONE);
            return 0;
        }
    }
    return -2;
}

/* Abort any live request and erase all data-bearing registers. ZEROIZE also
 * disables interrupts, so slh_accel_start enables them again on next use. */
static inline int slh_accel_zeroize(volatile uint32_t *base,
                                    uint32_t maximum_polls)
{
    uint32_t status;
    uint32_t poll;
    slh_accel_write(base, SLH_ACCEL_CONTROL, SLH_ACCEL_CONTROL_ZEROIZE);
    for (poll = 0; poll < maximum_polls; ++poll) {
        status = slh_accel_read(base, SLH_ACCEL_STATUS);
        if ((status & (SLH_ACCEL_STATUS_READY |
                       SLH_ACCEL_STATUS_BUSY |
                       SLH_ACCEL_STATUS_CONFIG_F_VALID |
                       SLH_ACCEL_STATUS_CONFIG_H_VALID)) ==
            SLH_ACCEL_STATUS_READY)
            return 0;
    }
    return -1;
}

#endif
