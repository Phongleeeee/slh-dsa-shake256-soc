#include "slh_service.h"
#include "soc.h"
#include "slh_hw_accel.h"
#include <string.h>
// All host payloads (including entropy) land directly in DMA-inaccessible RAM.
static uint8_t packet[SLH_SERVICE_MAX_PACKET] __attribute__((section(".vault")));
static uint8_t response[SLH_SERVICE_MAX_PACKET];
static void text(const char *p) { while(*p) soc_uart_putc(*p++); }
static uint32_t get32(const uint8_t *p) { return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24; }
static void put32(uint8_t *p,uint32_t x) { unsigned i; for(i=0;i<4;i++) p[i]=(uint8_t)(x>>(8*i)); }
static int byte(unsigned timeout,uint8_t *b) {
    volatile uint32_t *u=soc_mmio(SOC_UART_BASE);
    while(timeout--) {
        uint32_t s=u[SOC_UART_STATUS/4];
        if(s&24u) { u[SOC_UART_IRQ_STATUS/4]=6; return -1; }
        if(s&4u) { *b=(uint8_t)u[SOC_UART_DATA/4]; return 0; }
    } return -1;
}
static void send(uint8_t op,uint32_t seq,unsigned status,const uint8_t *data,size_t n) {
    uint8_t h[20]={'S','L','H','3',1,0,0,0}; unsigned i; uint32_t crc;
    h[5]=op|128u; h[6]=(uint8_t)status; put32(h+8,seq); put32(h+12,(uint32_t)n);
    crc=slh_crc32(0xffffffff,h,16); crc=slh_crc32(crc,data,n)^0xffffffff; put32(h+16,crc);
    for(i=0;i<20;i++) soc_uart_putc(h[i]);
    for(i=0;i<n;i++) soc_uart_putc(data[i]);
}
static int dma_selftest(void) {
    volatile uint32_t *d=soc_mmio(SOC_DMA_BASE),*a=soc_mmio(0x10000),*b=soc_mmio(0x20000);
    unsigned i,pass,t; uint32_t status;
    for(i=0;i<2;i++) { d[SOC_DMA_PT_INDEX/4]=i; d[SOC_DMA_PT_VPN/4]=i ? 0x20 : 0x10;
        d[SOC_DMA_PT_PPN/4]=i ? 0x20 : 0x10; d[SOC_DMA_PT_FLAGS/4]=7; }
    d[SOC_DMA_TLB_CTRL/4]=1;
    for(i=0;i<4;i++) { a[i]=0xa5010000+i; b[i]=0; }
    for(pass=0;pass<2;pass++) {
        d[SOC_DMA_CONTROL/4]=SOC_DMA_CLEAR;
        d[SOC_DMA_SRC/4]=pass ? 0x20000 : 0x10000;
        d[SOC_DMA_DST/4]=pass ? 0x10000 : 0x20000;
        d[SOC_DMA_LENGTH/4]=16; d[SOC_DMA_CONFIG/4]=SOC_DMA_CONFIG_WORD(0,0,4);
        d[SOC_DMA_CONTROL/4]=SOC_DMA_START; t=1000000;
        do { status=d[SOC_DMA_STATUS/4]; } while(t-- && !(status&(SOC_DMA_DONE|SOC_DMA_ERROR)));
        if(!(status&SOC_DMA_DONE) || status&SOC_DMA_ERROR) return -1;
        for(i=0;i<4;i++) if((pass ? a[i] : b[i])!=0xa5010000+i) return -1;
        if(!pass) for(i=0;i<4;i++) a[i]=0;
    } return 0;
}
int main(void) {
    uint8_t h[20],ch; unsigned matched=0,i; size_t n,outn=0,last_n=0;
    uint32_t crc,seq,last_seq=0,last_crc=0; uint8_t last_op=0; int status,last_status=0,have_last=0;
    soc_gpio_write(4); text("SLH-DSA-256f SERVICE START\r\n");
    if(dma_selftest()) { text("DMA FAIL\r\n"); soc_gpio_write(2); for(;;) {} }
    text("DMA RAM1 -> RAM2 -> RAM1 PASS\r\n");
    {
        uint8_t seed[32],adrs[32],input[64],digest[32]; unsigned k;
        static const uint8_t expected_f[32]={0xde,0x45,0x66,0x4b,0x8e,0xf3,0x27,0x52,0x62,0x05,0x49,0x29,0x7d,0xdf,0x77,0x85,0xbf,0xb5,0x72,0xee,0x2c,0x98,0x39,0x92,0x46,0xb1,0x16,0xbe,0xdf,0x9d,0xef,0x29};
        for(k=0;k<32;k++) { seed[k]=(uint8_t)k; adrs[k]=(uint8_t)(160+k); }
        for(k=0;k<64;k++) input[k]=(uint8_t)(64+k);
        slh_hw_set_mode(2);
        if(slh_hw_f(seed,adrs,input,digest) || memcmp(digest,expected_f,32)) {
            text("DMA F/H STREAM KAT FAIL\r\n"); soc_gpio_write(2); for(;;) {}
        }
        slh_hw_set_mode(1); text("DMA F/H STREAM KAT PASS\r\n");
    }
    slh_service_init(); slh_platform_scrub(); soc_gpio_write(1);
    text("SLH3 READY: volatile key; trusted UART; no board TRNG\r\n");
    for(;;) {
        if(byte(1000000,&ch)) { matched=0; continue; }
        if(ch!=(uint8_t)"SLH3"[matched]) { matched=(ch=='S') ? 1u : 0u; continue; }
        if(++matched<4) continue; matched=0; memcpy(h,"SLH3",4);
        for(i=4;i<20;i++) if(byte(1000000,&h[i])) break;
        if(i!=20) goto bad_frame;
        n=get32(h+12); seq=get32(h+8);
        if(h[4]!=1 || h[5]&128 || h[6] || h[7] || n>sizeof(packet)) goto bad_frame;
        for(i=0;i<n;i++) if(byte(1000000,&packet[i])) break;
        if(i!=n) goto bad_frame;
        crc=slh_crc32(0xffffffff,h,16); crc=slh_crc32(crc,packet,n)^0xffffffff;
        if(crc!=get32(h+16)) goto bad_frame;
        if(have_last && seq==last_seq && h[5]==last_op && crc==last_crc) {
            // Complete cleanup BEFORE the reply. A host may send the next
            // frame immediately after receiving it; RX has only one byte.
            slh_secure_clear(packet,sizeof(packet));
            send(last_op,last_seq,last_status,response,last_n); continue;
        }
        status=slh_service_command(h[5],packet,n,response,&outn);
        slh_secure_clear(packet,sizeof(packet));
        send(h[5],seq,(unsigned)status,response,outn);
        last_seq=seq; last_crc=crc; last_op=h[5]; last_n=outn; last_status=status; have_last=1;
        continue;
bad_frame:
        slh_secure_clear(packet,sizeof(packet)); slh_service_init(); slh_platform_scrub();
        have_last=0; // malformed transport fails closed, invalidates volatile key
    }
}
