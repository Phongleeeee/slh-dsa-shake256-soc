#include "soc.h"

static void uart_puts(const char *s)
{
    while (*s != '\0') soc_uart_putc(*s++);
}

static int dma_selftest(void)
{
    volatile uint32_t *dma = soc_mmio(SOC_DMA_BASE);
    volatile uint32_t *src = soc_mmio(0x00010000u);
    volatile uint32_t *dst = soc_mmio(0x00020000u);
    static const uint32_t pattern[4] = {
        0x13579bdfu, 0x2468ace0u, 0x534c482du, 0x444d4121u
    };
    unsigned int i;

    // Identity-map the source and destination pages in the DMA-side IOMMU.
    dma[SOC_DMA_PT_INDEX >> 2] = 0u;
    dma[SOC_DMA_PT_VPN >> 2] = 0x10u;
    dma[SOC_DMA_PT_PPN >> 2] = 0x10u;
    dma[SOC_DMA_PT_FLAGS >> 2] = 7u; // valid + read + write
    dma[SOC_DMA_PT_INDEX >> 2] = 1u;
    dma[SOC_DMA_PT_VPN >> 2] = 0x20u;
    dma[SOC_DMA_PT_PPN >> 2] = 0x20u;
    dma[SOC_DMA_PT_FLAGS >> 2] = 7u;
    dma[SOC_DMA_TLB_CTRL >> 2] = 1u;

    for (i = 0; i < 4; ++i) {
        src[i] = pattern[i];
        dst[i] = 0u;
    }

    dma[SOC_DMA_CONTROL >> 2] = SOC_DMA_CLEAR;
    dma[SOC_DMA_SRC >> 2] = 0x00010000u;
    dma[SOC_DMA_DST >> 2] = 0x00020000u;
    dma[SOC_DMA_LENGTH >> 2] = 16u;
    dma[SOC_DMA_CONFIG >> 2] =
        SOC_DMA_CONFIG_WORD(SOC_DMA_TYPE_M2M, SOC_DMA_MODE_BURST, 4u);
    dma[SOC_DMA_CONTROL >> 2] = SOC_DMA_START;

    for (;;) {
        uint32_t status = dma[SOC_DMA_STATUS >> 2];
        if ((status & SOC_DMA_ERROR) != 0u) return -1;
        if ((status & SOC_DMA_DONE) != 0u) break;
    }
    for (i = 0; i < 4; ++i)
        if (dst[i] != pattern[i]) return -1;
    return 0;
}

int main(void)
{
    static const uint32_t pub_seed[8] = {
        0x03020100u, 0x07060504u, 0x0b0a0908u, 0x0f0e0d0cu,
        0x13121110u, 0x17161514u, 0x1b1a1918u, 0x1f1e1d1cu
    };
    static const uint32_t adrs[8] = {
        0xa3a2a1a0u, 0xa7a6a5a4u, 0xabaaa9a8u, 0xafaeadacu,
        0xb3b2b1b0u, 0xb7b6b5b4u, 0xbbbab9b8u, 0xbfbebdbcu
    };
    static const uint32_t input[16] = {
        0x43424140u, 0x47464544u, 0x4b4a4948u, 0x4f4e4d4cu,
        0x53525150u, 0x57565554u, 0x5b5a5958u, 0x5f5e5d5cu,
        0, 0, 0, 0, 0, 0, 0, 0
    };
    static const uint32_t expected[8] = {
        0x4b6645deu, 0x5227f38eu, 0x29490562u, 0x8577df7du,
        0xee72b5bfu, 0x9239982cu, 0xbe16b146u, 0x29ef9ddfu
    };
    volatile uint32_t *shake = soc_mmio(SOC_SHAKE_BASE);
    uint32_t digest[8];
    unsigned int i;

    soc_gpio_write(4u);
    uart_puts("SLH-SOC BOOT\r\n");

    if (dma_selftest() != 0)
        goto fail;
    uart_puts("DMA M2M PASS\r\n");
    soc_gpio_write(12u);

    if (slh_accel_start(shake, pub_seed, adrs, input, 0) != 0)
        goto fail;
    soc_gpio_write(8u);
    if (slh_accel_finish(shake, digest, 1000000u) != 0)
        goto fail;
    for (i = 0; i < 8; ++i)
        if (digest[i] != expected[i]) goto fail;
    if (slh_accel_zeroize(shake, 1000000u) != 0)
        goto fail;

    uart_puts("SHAKE F KAT PASS\r\n");
    soc_gpio_write(1u);
    for (;;) {}

fail:
    uart_puts("SHAKE F KAT FAIL\r\n");
    soc_gpio_write(2u);
    for (;;) {}
}
