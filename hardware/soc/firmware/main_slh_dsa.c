#include <stddef.h>
#include <stdint.h>
#include "soc.h"
#include "slh_dsa.h"

#define SLH_256F_PUBLIC_KEY_BYTES 64u
#define SLH_256F_SECRET_KEY_BYTES 128u
#define SLH_256F_SIGNATURE_BYTES  49856u

static uint8_t signature[SLH_256F_SIGNATURE_BYTES];
static uint8_t public_key[SLH_256F_PUBLIC_KEY_BYTES];
static uint8_t secret_key[SLH_256F_SECRET_KEY_BYTES];

static void uart_puts(const char *text)
{
    while (*text != '\0') soc_uart_putc(*text++);
}

static int dma_wait(volatile uint32_t *dma)
{
    uint32_t timeout = 10000000u;
    while (timeout-- != 0u) {
        uint32_t status = dma[SOC_DMA_STATUS >> 2];
        if ((status & SOC_DMA_ERROR) != 0u) return -1;
        if ((status & SOC_DMA_DONE) != 0u) return 0;
    }
    return -1;
}

static int dma_copy(volatile uint32_t *dma, uint32_t source,
                    uint32_t destination, uint32_t length)
{
    dma[SOC_DMA_CONTROL >> 2] = SOC_DMA_CLEAR;
    dma[SOC_DMA_SRC >> 2] = source;
    dma[SOC_DMA_DST >> 2] = destination;
    dma[SOC_DMA_LENGTH >> 2] = length;
    dma[SOC_DMA_CONFIG >> 2] =
        SOC_DMA_CONFIG_WORD(SOC_DMA_TYPE_M2M, SOC_DMA_MODE_BURST, 4u);
    dma[SOC_DMA_CONTROL >> 2] = SOC_DMA_START;
    return dma_wait(dma);
}

static int dma_memory_selftest(void)
{
    volatile uint32_t *dma = soc_mmio(SOC_DMA_BASE);
    volatile uint32_t *source = soc_mmio(0x00010000u);
    volatile uint32_t *result = soc_mmio(0x00020000u);
    static const uint32_t pattern[4] = {
        0x534c482du, 0x4453412du, 0x52414d21u, 0x444d4121u
    };
    unsigned int i;

    /* IOMMU identity mappings for the two internal RAM pages. */
    dma[SOC_DMA_PT_INDEX >> 2] = 0u;
    dma[SOC_DMA_PT_VPN >> 2] = 0x10u;
    dma[SOC_DMA_PT_PPN >> 2] = 0x10u;
    dma[SOC_DMA_PT_FLAGS >> 2] = 7u;
    dma[SOC_DMA_PT_INDEX >> 2] = 1u;
    dma[SOC_DMA_PT_VPN >> 2] = 0x20u;
    dma[SOC_DMA_PT_PPN >> 2] = 0x20u;
    dma[SOC_DMA_PT_FLAGS >> 2] = 7u;
#ifdef SLH_USE_EXT_MEMORY
    dma[SOC_DMA_PT_INDEX >> 2] = 2u;
    dma[SOC_DMA_PT_VPN >> 2] = 0x80000u;
    dma[SOC_DMA_PT_PPN >> 2] = 0x80000u;
    dma[SOC_DMA_PT_FLAGS >> 2] = 7u;
#endif
    dma[SOC_DMA_TLB_CTRL >> 2] = 1u;

    for (i = 0; i < 4u; ++i) {
        source[i] = pattern[i];
        result[i] = 0u;
    }

    /* An extension is optional. The portable path uses only RAM1/RAM2. */
#ifdef SLH_USE_EXT_MEMORY
    if (dma_copy(dma, 0x00010000u, 0x80000000u, 16u) != 0) return -1;
    if (dma_copy(dma, 0x80000000u, 0x00020000u, 16u) != 0) return -1;
#else
    if (dma_copy(dma, 0x00010000u, 0x00020000u, 16u) != 0) return -1;
    for (i = 0; i < 4u; ++i)
        if (result[i] != pattern[i]) return -1;
    for (i = 0; i < 4u; ++i) source[i] = 0u;
    if (dma_copy(dma, 0x00020000u, 0x00010000u, 16u) != 0) return -1;
    for (i = 0; i < 4u; ++i)
        if (source[i] != pattern[i]) return -1;
#endif
    for (i = 0; i < 4u; ++i)
        if (result[i] != pattern[i]) return -1;
    return 0;
}

int main(void)
{
    static const uint8_t message[] =
        "VC707 full FIPS 205 SLH-DSA-SHAKE-256f hardware/software test";
    static const uint8_t context[] = "DO-AN-VC707";
    uint8_t seeds[96];
    uint8_t addrnd[32];
    size_t signature_size;
    unsigned int i;

    soc_gpio_write(4u);
    uart_puts("SLH-DSA-256f FULL SELFTEST START\r\n");
    if (dma_memory_selftest() != 0) goto fail;
#ifdef SLH_USE_EXT_MEMORY
    uart_puts("DMA DDR3 ROUNDTRIP PASS\r\n");
#else
    uart_puts("DMA RAM1 -> RAM2 -> RAM1 PASS\r\n");
#endif
    if (slh_accel_probe(soc_mmio(SOC_SHAKE_BASE)) != 0) goto fail;

    /* Reproducible self-test inputs only.  Production key generation must
     * replace these bytes with the conditioned VC707 entropy/DRBG service. */
    for (i = 0; i < sizeof(seeds); ++i) seeds[i] = (uint8_t)i;
    for (i = 0; i < sizeof(addrnd); ++i)
        addrnd[i] = (uint8_t)(0xa0u + i);

    if (slh_keygen_internal(secret_key, public_key,
                            seeds, seeds + 32, seeds + 64,
                            &slh_dsa_shake_256f) != 0)
        goto fail;
    uart_puts("KEYGEN PASS\r\n");

    signature_size = slh_sign(signature, message, sizeof(message) - 1u,
                              context, sizeof(context) - 1u, secret_key,
                              addrnd, &slh_dsa_shake_256f);
    if (signature_size != SLH_256F_SIGNATURE_BYTES) goto fail;
    uart_puts("SIGN PASS\r\n");

    if (!slh_verify(message, sizeof(message) - 1u,
                    signature, signature_size,
                    context, sizeof(context) - 1u,
                    public_key, &slh_dsa_shake_256f))
        goto fail;

    signature[signature_size - 1u] ^= 1u;
    if (slh_verify(message, sizeof(message) - 1u,
                   signature, signature_size,
                   context, sizeof(context) - 1u,
                   public_key, &slh_dsa_shake_256f))
        goto fail;
    signature[signature_size - 1u] ^= 1u;

    if (slh_accel_zeroize(soc_mmio(SOC_SHAKE_BASE), 1000000u) != 0)
        goto fail;
    uart_puts("VERIFY + NEGATIVE TEST PASS\r\n");
    uart_puts("FULL SLH-DSA SELFTEST PASS\r\n");
    soc_gpio_write(1u);
    for (;;) {}

fail:
    (void)slh_accel_zeroize(soc_mmio(SOC_SHAKE_BASE), 1000000u);
    uart_puts("FULL SLH-DSA SELFTEST FAIL\r\n");
    soc_gpio_write(2u);
    for (;;) {}
}
