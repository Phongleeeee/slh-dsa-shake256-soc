#include "slh_hw_accel.h"
#include "soc.h"
#include "slh_service.h"
#include <string.h>

static unsigned hash_mode=1;
static slh_metrics metrics;
static uint32_t dma_packet[33], dma_digest[8];
static unsigned dma_pages_ready;
void slh_hw_set_mode(unsigned mode) { hash_mode=mode; }
unsigned slh_hw_get_mode(void) { return hash_mode; }
void slh_hw_reset_metrics(void) { memset(&metrics,0,sizeof(metrics)); }
void slh_hw_get_metrics(slh_metrics *m) { *m=metrics; }
uint64_t slh_platform_cycles(void) {
    uint32_t h,l,h2;
    do { __asm__ volatile("rdcycleh %0":"=r"(h)); __asm__ volatile("rdcycle %0":"=r"(l)); __asm__ volatile("rdcycleh %0":"=r"(h2)); } while(h!=h2);
    return (uint64_t)h<<32|l;
}
uint32_t slh_platform_clock(void) { return soc_mmio(SOC_TIMER_BASE)[0x1c/4]; }
static int dma_hash_transfer(unsigned type,uint32_t source,uint32_t dest,uint32_t n) {
    volatile uint32_t *d=soc_mmio(SOC_DMA_BASE); unsigned timeout=1000000;
    d[SOC_DMA_CONTROL/4]=SOC_DMA_CLEAR; d[SOC_DMA_SRC/4]=source;
    d[SOC_DMA_DST/4]=dest; d[SOC_DMA_LENGTH/4]=n;
    d[SOC_DMA_CONFIG/4]=SOC_DMA_CONFIG_WORD(type,SOC_DMA_MODE_BURST,4u);
    d[SOC_DMA_CONTROL/4]=SOC_DMA_START;
    while(timeout--) { uint32_t s=d[SOC_DMA_STATUS/4]; if(s&SOC_DMA_ERROR) return -1; if(s&SOC_DMA_DONE) return 0; }
    return -1;
}
static void map_dma_page(unsigned entry,const void *p) {
    volatile uint32_t *d=soc_mmio(SOC_DMA_BASE); uint32_t page=(uint32_t)(uintptr_t)p>>12;
    d[SOC_DMA_PT_INDEX/4]=entry; d[SOC_DMA_PT_VPN/4]=page;
    d[SOC_DMA_PT_PPN/4]=page; d[SOC_DMA_PT_FLAGS/4]=7;
}
static int run_dma_hash(const uint8_t *seed,const uint8_t *adrs,const uint8_t *in,unsigned two,uint8_t *out) {
    volatile uint32_t *stream=soc_mmio(0x34000); unsigned i,t=1000000; int rc=-1;
    dma_packet[0]=two; memcpy(dma_packet+1,seed,32); memcpy(dma_packet+9,adrs,32);
    memcpy(dma_packet+17,in,two ? 64 : 32);
    if(!dma_pages_ready) {
        map_dma_page(2,dma_packet); map_dma_page(3,(uint8_t *)dma_packet+sizeof(dma_packet)-1);
        map_dma_page(4,dma_digest); map_dma_page(5,(uint8_t *)dma_digest+sizeof(dma_digest)-1);
        soc_mmio(SOC_DMA_BASE)[SOC_DMA_TLB_CTRL/4]=1; dma_pages_ready=1;
    }
    stream[0]=1;
    if(dma_hash_transfer(2,(uint32_t)(uintptr_t)dma_packet,0,two ? 132 : 100)) goto end;
    if(dma_hash_transfer(1,0,(uint32_t)(uintptr_t)dma_digest,32)) goto end;
    while(t-- && stream[1]&1u) {}
    if(stream[1]!=2u) goto end;
    for(i=0;i<8;i++) {
        uint32_t w=dma_digest[i]; unsigned j;
        for(j=0;j<4;j++) out[4*i+j]=(uint8_t)(w>>(8*j));
    }
    metrics.dma++; rc=0;
end:
    if(rc) { stream[0]=2; metrics.failures++; }
    slh_secure_clear(dma_packet,sizeof(dma_packet)); slh_secure_clear(dma_digest,sizeof(dma_digest));
    return rc;
}
void slh_platform_scrub(void) {
    if(slh_accel_zeroize(soc_mmio(SOC_SHAKE_BASE),1000000u)) metrics.failures++;
    slh_secure_clear(dma_packet,sizeof(dma_packet)); slh_secure_clear(dma_digest,sizeof(dma_digest));
    // Crypto runs on its own private stack; the service stack is below vault.
    slh_secure_clear((void *)0x2e000,8192);
}

static uint32_t load32_le(const uint8_t *p)
{
    return ((uint32_t)p[0]) | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void store32_le(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

static int run_hash(const uint8_t pk_seed[32], const uint8_t adrs[32],
                    const uint8_t *input, int two_blocks,
                    uint8_t output[32])
{
    volatile uint32_t *base = soc_mmio(SOC_SHAKE_BASE);
    uint32_t seed_words[8];
    uint32_t adrs_words[8];
    uint32_t input_words[16] = {0};
    uint32_t digest_words[8];
    unsigned int i;

    for (i = 0; i < 8; ++i) {
        seed_words[i] = load32_le(pk_seed + 4u*i);
        adrs_words[i] = load32_le(adrs + 4u*i);
    }
    for (i = 0; i < (two_blocks ? 16u : 8u); ++i)
        input_words[i] = load32_le(input + 4u*i);

    if (slh_accel_start(base, seed_words, adrs_words, input_words,
                        two_blocks) != 0)
        return -1;
    if (slh_accel_finish(base, digest_words, 1000000u) != 0)
        return -1;
    for (i = 0; i < 8; ++i)
        store32_le(output + 4u*i, digest_words[i]);
    return 0;
}

int slh_hw_f(const uint8_t pk_seed[32], const uint8_t adrs[32],
             const uint8_t input[32], uint8_t output[32])
{
    int rc;
    if(!hash_mode) { metrics.software++; return -1; }
    metrics.f++;
    if(hash_mode==2) return run_dma_hash(pk_seed,adrs,input,0,output);
    rc=run_hash(pk_seed,adrs,input,0,output); if(rc) metrics.failures++; return rc;
}

int slh_hw_h(const uint8_t pk_seed[32], const uint8_t adrs[32],
             const uint8_t left[32], const uint8_t right[32],
             uint8_t output[32])
{
    uint8_t input[64];
    unsigned int i;
    for (i = 0; i < 32; ++i) {
        input[i] = left[i];
        input[32u+i] = right[i];
    }
    if(!hash_mode) { metrics.software++; return -1; }
    metrics.h++;
    if(hash_mode==2) { int rc=run_dma_hash(pk_seed,adrs,input,1,output); slh_secure_clear(input,64); return rc; }
    { int rc=run_hash(pk_seed, adrs, input, 1, output); slh_secure_clear(input,64); if(rc) metrics.failures++; return rc; }
}

int slh_hw_prf(const uint8_t seed[32],const uint8_t adrs[32],const uint8_t sk[32],uint8_t out[32]) {
    int rc;
    if(!hash_mode) { metrics.software++; return -1; }
    metrics.prf++; rc=run_hash(seed,adrs,sk,0,out);
    if(rc) metrics.failures++; return rc;
}
