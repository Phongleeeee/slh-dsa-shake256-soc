// Executes the exact service engine on a native CPU. NOT an FPGA test.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <io.h>
#include "slh_service.h"
#include "slh_hw_accel.h"
#include "sha3_api.h"
static unsigned mode;
static slh_metrics metrics;
// Test-only fault injection: fail one accelerator request and let the
// algorithm's software fallback run, to check the service still fails closed.
static unsigned fail_next;
void slh_test_fail_next(unsigned enable) { fail_next=enable; }
void slh_hw_set_mode(unsigned m) { mode=m; }
unsigned slh_hw_get_mode(void) { return mode; }
void slh_hw_reset_metrics(void) { memset(&metrics,0,sizeof(metrics)); }
void slh_hw_get_metrics(slh_metrics *m) { *m=metrics; }
uint64_t slh_platform_cycles(void) { LARGE_INTEGER t; QueryPerformanceCounter(&t); return (uint64_t)t.QuadPart; }
uint32_t slh_platform_clock(void) { LARGE_INTEGER f; QueryPerformanceFrequency(&f); return (uint32_t)f.QuadPart; }
void slh_platform_scrub(void) {}
uintptr_t slh_crypto_call(uintptr_t (*fn)(void *),void *arg) { return fn(arg); }
static int hash(const uint8_t *seed,const uint8_t *adrs,const uint8_t *input,size_t n,uint8_t *out) {
    sha3_var_t x;
    if(!mode) { metrics.software++; return -1; }
    if(fail_next) { fail_next=0; metrics.failures++; return -1; }
    shake256_init(&x); shake_update(&x,seed,32); shake_update(&x,adrs,32);
    shake_update(&x,input,n); shake_out(&x,out,32); slh_secure_clear(&x,sizeof(x)); return 0;
}
int slh_hw_f(const uint8_t *s,const uint8_t *a,const uint8_t *in,uint8_t *out) { if(mode) { metrics.f++; if(mode==2) metrics.dma++; } return hash(s,a,in,32,out); }
int slh_hw_h(const uint8_t *s,const uint8_t *a,const uint8_t *l,const uint8_t *r,uint8_t *out) { uint8_t in[64]; int rc; memcpy(in,l,32); memcpy(in+32,r,32); if(mode) { metrics.h++; if(mode==2) metrics.dma++; } rc=hash(s,a,in,64,out); slh_secure_clear(in,64); return rc; }
int slh_hw_prf(const uint8_t *s,const uint8_t *a,const uint8_t *in,uint8_t *out) { if(mode) metrics.prf++; return hash(s,a,in,32,out); }
static void require(int ok,const char *what) { if(!ok) { fprintf(stderr,"FAIL: %s\n",what); exit(1); } }
static uint32_t get32(const uint8_t *p) { return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24; }
static void put32(uint8_t *p,uint32_t v) { unsigned i; for(i=0;i<4;i++) p[i]=(uint8_t)(v>>(8*i)); }
static int wire(void) {
    uint8_t h[20],p[1024],out[1024]; size_t n,outn; unsigned status; uint32_t crc;
    _setmode(_fileno(stdin),_O_BINARY); _setmode(_fileno(stdout),_O_BINARY);
    slh_service_init();
    for(;;) {
        unsigned matched=0; int c;
        // Like the UART receiver, resynchronize after optional pipe preamble.
        while(matched<4) { c=fgetc(stdin); if(c==EOF) return 0;
            if(c=="SLH3"[matched]) h[matched++]=(uint8_t)c; else matched=(c=='S') ? 1u : 0u; }
        if(fread(h+4,1,16,stdin)!=16) return 3;
        n=get32(h+12); if(n>1024 || memcmp(h,"SLH3",4) || h[4]!=1) return 2;
        if(fread(p,1,n,stdin)!=n) return 3;
        crc=slh_crc32(0xffffffff,h,16); crc=slh_crc32(crc,p,n)^0xffffffff;
        if(crc!=get32(h+16)) return 4;
        status=(unsigned)slh_service_command(h[5],p,n,out,&outn);
        if(h[5]==S_INFO && !status) out[27]|=128; // native-only capability
        slh_secure_clear(p,sizeof(p));
        h[5]|=128; h[6]=(uint8_t)status; put32(h+12,(uint32_t)outn);
        crc=slh_crc32(0xffffffff,h,16); crc=slh_crc32(crc,out,outn)^0xffffffff; put32(h+16,crc);
        fwrite(h,1,20,stdout); fwrite(out,1,outn,stdout); fflush(stdout);
    } return 0;
}
int main(int argc,char **argv) {
    uint8_t in[1024],out[1024],pk[64],saved[49856]; size_t n; unsigned i,m;
    if(argc>1 && !strcmp(argv[1],"--wire")) return wire();
    require((slh_crc32(0xffffffff,(const uint8_t *)"123456789",9)^0xffffffff)==0xcbf43926,"CRC-32 KAT");
    slh_service_init();
    require(slh_service_command(S_PK,NULL,0,out,&n)==S_BAD_STATE,"no key after reset");
    memset(in,0,96); require(slh_service_command(S_KEYGEN,in,96,out,&n)==S_ENTROPY,"zero entropy rejected");
    for(i=0;i<96;i++) in[i]=(uint8_t)i;
    require(!slh_service_command(S_KEYGEN,in,96,out,&n) && n==64,"keygen"); memcpy(pk,out,64);
    require(slh_service_command(S_KEYGEN,in,96,out,&n)==S_ENTROPY,"reused seed rejected");
    for(m=0;m<3;m++) {
        put32(in,m); require(!slh_service_command(S_MODE,in,4,out,&n),"mode");
        put32(in,3); in[4]=3; memcpy(in+5,"CTX",3);
        require(!slh_service_command(S_MSG_BEGIN,in,8,out,&n),"message begin");
        put32(in,1); memcpy(in+4,"abc",3);
        require(slh_service_command(S_MSG_CHUNK,in,7,out,&n)==S_BOUNDS,"gap rejected");
        put32(in,0); require(!slh_service_command(S_MSG_CHUNK,in,7,out,&n),"message chunk");
        memset(in,0xa5,32); require(!slh_service_command(S_SIGN,in,32,out,&n),"sign");
        for(i=0;i<49856;i+=512) {
            unsigned k=49856-i>512 ? 512 : 49856-i; put32(in,i); put32(in+4,k);
            require(!slh_service_command(S_SIG_READ,in,8,out,&n) && n==k,"signature read");
            if(m==0) memcpy(saved+i,out,k); else require(!memcmp(saved+i,out,k),"all modes same signature");
        }
        require(!slh_service_command(S_VERIFY,pk,64,out,&n) && get32(out)==1,"valid verify");
        pk[0]^=1; require(!slh_service_command(S_VERIFY,pk,64,out,&n) && get32(out)==0,"wrong key rejected"); pk[0]^=1;
    }
    put32(in,49856); require(!slh_service_command(S_SIG_BEGIN,in,4,out,&n),"signature upload begin");
    saved[49855]^=1;
    for(i=0;i<49856;i+=512) { unsigned k=49856-i>512 ? 512 : 49856-i;
        put32(in,i); memcpy(in+4,saved+i,k); require(!slh_service_command(S_SIG_CHUNK,in,k+4,out,&n),"signature upload"); }
    require(!slh_service_command(S_VERIFY,pk,64,out,&n) && get32(out)==0,"tampered signature rejected");
    put32(in,16385); in[4]=0; require(slh_service_command(S_MSG_BEGIN,in,5,out,&n)==S_BOUNDS,"message bound");
    require(!slh_service_command(S_ZEROIZE,NULL,0,out,&n),"zeroize");
    require(slh_service_command(S_PK,NULL,0,out,&n)==S_BAD_STATE,"key erased");
    require(slh_service_command(255,NULL,0,out,&n)==S_BAD_REQUEST,"unknown opcode");
    puts("NATIVE SERVICE ENGINE TEST PASSED (software/emulated acceleration, NOT FPGA)"); return 0;
}
