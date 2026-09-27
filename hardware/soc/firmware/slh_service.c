#include "slh_service.h"
#include "slh_dsa.h"
#include "sha3_api.h"
#include <string.h>
#ifdef SLH_NATIVE_TEST
#define PRIVATE
#else
#define PRIVATE __attribute__((section(".vault")))
#endif
static uint8_t secret[128] PRIVATE;
static uint8_t last_seed_hash[32] PRIVATE;
static unsigned have_seed_hash PRIVATE;
static unsigned key_valid PRIVATE;
static uint8_t public_key[64], signature[SLH_SERVICE_SIGNATURE];
static uint8_t message[SLH_SERVICE_MAX_MESSAGE], context[255];
static size_t message_size,message_received,context_size,sig_received;
static unsigned message_open,sig_valid,sig_upload;
static slh_metrics last_metrics;
static uint32_t last_op,last_mode;
void slh_secure_clear(void *p,size_t n) { volatile uint8_t *v=p; while(n--) *v++=0; }
static uint32_t get32(const uint8_t *p) { return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24; }
static void put32(uint8_t *p,uint32_t x) { unsigned i; for(i=0;i<4;i++) p[i]=(uint8_t)(x>>(8*i)); }
static void put64(uint8_t *p,uint64_t x) { unsigned i; for(i=0;i<8;i++) p[i]=(uint8_t)(x>>(8*i)); }
uint32_t slh_crc32(uint32_t crc,const uint8_t *data,size_t n) {
    unsigned b; while(n--) { crc^=*data++; for(b=0;b<8;b++) crc=(crc>>1)^((0u-(crc&1u))&0xedb88320u); } return crc;
}
static void clear_transfer(void) {
    slh_secure_clear(message,sizeof(message)); slh_secure_clear(context,sizeof(context));
    slh_secure_clear(signature,sizeof(signature));
    message_size=message_received=context_size=sig_received=0;
    message_open=sig_valid=sig_upload=0;
}
void slh_service_init(void) {
    clear_transfer(); slh_secure_clear(secret,sizeof(secret));
    slh_secure_clear(public_key,sizeof(public_key));
    slh_secure_clear(last_seed_hash,sizeof(last_seed_hash));
    have_seed_hash=key_valid=0; memset(&last_metrics,0,sizeof(last_metrics)); last_op=last_mode=0;
}
static uintptr_t keygen_job(void *arg) {
    const uint8_t *s=arg;
    return (uintptr_t)slh_keygen_internal(secret,public_key,s,s+32,s+64,&slh_dsa_shake_256f);
}
static uintptr_t sign_job(void *arg) {
    return slh_sign(signature,message,message_size,context,context_size,secret,arg,&slh_dsa_shake_256f);
}
static uintptr_t verify_job(void *arg) {
    return (uintptr_t)slh_verify(message,message_size,signature,SLH_SERVICE_SIGNATURE,context,context_size,arg,&slh_dsa_shake_256f);
}
static uintptr_t run(uint8_t op,uintptr_t (*job)(void *),void *arg) {
    uint64_t start; uintptr_t result;
    slh_hw_reset_metrics(); last_mode=slh_hw_get_mode(); start=slh_platform_cycles();
    result=slh_crypto_call(job,arg);
    slh_platform_scrub(); slh_hw_get_metrics(&last_metrics);
    last_metrics.cycles=slh_platform_cycles()-start; last_op=op; return result;
}
int slh_service_command(uint8_t op,const uint8_t *in,size_t n,uint8_t *out,size_t *outn) {
    size_t offset,count; uintptr_t result; unsigned i; uint8_t nonzero=0;
    *outn=0;
    if(n>SLH_SERVICE_MAX_PACKET) return S_BOUNDS;
    switch(op) {
    case S_INFO:
        if(n) return S_BAD_REQUEST;
        put32(out,0x00030001); put32(out+4,slh_platform_clock());
        put32(out+8,SLH_SERVICE_MAX_MESSAGE); put32(out+12,SLH_SERVICE_SIGNATURE);
        put32(out+16,slh_hw_get_mode()); put32(out+20,key_valid);
        // bit0 F/H, bit1 DMA stream, bit2 host entropy, bit3 volatile key.
        // No board-TRNG or encrypted-UART capability is advertised.
        put32(out+24,15); *outn=28; return S_SUCCESS;
    case S_PING: return n ? S_BAD_REQUEST : S_SUCCESS;
    case S_KEYGEN:
        if(n!=96) return S_BAD_REQUEST;
        for(i=0;i<96;i++) nonzero|=in[i];
        if(!nonzero) return S_ENTROPY;
        // Reject reuse within this boot. Hash stored only in the private vault.
        { uint8_t h[32]; sha3_var_t v;
          shake256_init(&v); shake_update(&v,in,96); shake_out(&v,h,32);
          slh_secure_clear(&v,sizeof(v));
          if(have_seed_hash && !memcmp(h,last_seed_hash,32)) { slh_secure_clear(h,32); return S_ENTROPY; }
          memcpy(last_seed_hash,h,32); have_seed_hash=1; slh_secure_clear(h,32); }
        key_valid=0; clear_transfer(); slh_secure_clear(secret,128);
        result=run(op,keygen_job,(void *)in);
        if(result || last_metrics.failures) { slh_secure_clear(secret,128); slh_secure_clear(public_key,64); return S_CRYPTO; }
        key_valid=1; memcpy(out,public_key,64); *outn=64; return S_SUCCESS;
    case S_PK:
        if(n) return S_BAD_REQUEST;
        if(!key_valid) return S_BAD_STATE;
        memcpy(out,public_key,64); *outn=64; return S_SUCCESS;
    case S_MSG_BEGIN:
        if(n<5 || n!=5u+in[4]) return S_BAD_REQUEST;
        count=get32(in); if(count>SLH_SERVICE_MAX_MESSAGE) return S_BOUNDS;
        clear_transfer(); message_size=count; context_size=in[4];
        memcpy(context,in+5,context_size); message_open=1; return S_SUCCESS;
    case S_MSG_CHUNK:
        if(!message_open || n<4) return S_BAD_STATE;
        offset=get32(in); count=n-4;
        if(offset!=message_received || count>message_size-message_received) return S_BOUNDS;
        memcpy(message+offset,in+4,count); message_received+=count; return S_SUCCESS;
    case S_SIGN:
        if(n!=32) return S_BAD_REQUEST;
        if(!key_valid || !message_open || message_received!=message_size) return S_BAD_STATE;
        for(i=0;i<32;i++) nonzero|=in[i]; if(!nonzero) return S_ENTROPY;
        sig_valid=sig_upload=0;
        result=run(op,sign_job,(void *)in);
        if(result!=SLH_SERVICE_SIGNATURE || last_metrics.failures) { slh_secure_clear(signature,sizeof(signature)); return S_CRYPTO; }
        sig_valid=1; put32(out,SLH_SERVICE_SIGNATURE); *outn=4; return S_SUCCESS;
    case S_SIG_READ:
        if(n!=8) return S_BAD_REQUEST;
        if(!sig_valid) return S_BAD_STATE;
        offset=get32(in); count=get32(in+4);
        if(count>SLH_SERVICE_MAX_PACKET || offset>SLH_SERVICE_SIGNATURE || count>SLH_SERVICE_SIGNATURE-offset) return S_BOUNDS;
        memcpy(out,signature+offset,count); *outn=count; return S_SUCCESS;
    case S_SIG_BEGIN:
        if(n!=4 || get32(in)!=SLH_SERVICE_SIGNATURE) return S_BAD_REQUEST;
        slh_secure_clear(signature,sizeof(signature)); sig_valid=0; sig_upload=1; sig_received=0; return S_SUCCESS;
    case S_SIG_CHUNK:
        if(!sig_upload || n<4) return S_BAD_STATE;
        offset=get32(in); count=n-4;
        if(offset!=sig_received || count>SLH_SERVICE_SIGNATURE-sig_received) return S_BOUNDS;
        memcpy(signature+offset,in+4,count); sig_received+=count;
        if(sig_received==SLH_SERVICE_SIGNATURE) { sig_upload=0; sig_valid=1; }
        return S_SUCCESS;
    case S_VERIFY:
        if(n!=64) return S_BAD_REQUEST;
        if(!sig_valid || !message_open || message_received!=message_size) return S_BAD_STATE;
        result=run(op,verify_job,(void *)in);
        if(last_metrics.failures) return S_CRYPTO;
        put32(out,(uint32_t)result); *outn=4; return S_SUCCESS;
    case S_ZEROIZE:
        if(n) return S_BAD_REQUEST;
        slh_service_init(); slh_platform_scrub(); return S_SUCCESS;
    case S_MODE:
        if(n!=4 || get32(in)>2) return S_BAD_REQUEST;
        slh_hw_set_mode(get32(in)); return S_SUCCESS;
    case S_STATS:
        if(n) return S_BAD_REQUEST;
        put32(out,last_op); put32(out+4,last_mode); put64(out+8,last_metrics.cycles);
        put32(out+16,last_metrics.f); put32(out+20,last_metrics.h); put32(out+24,last_metrics.prf);
        put32(out+28,last_metrics.dma); put32(out+32,last_metrics.failures); put32(out+36,last_metrics.software);
        *outn=40; return S_SUCCESS;
    default: return S_BAD_REQUEST;
    }
}
