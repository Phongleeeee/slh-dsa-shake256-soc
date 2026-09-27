#ifndef SLH_SERVICE_H
#define SLH_SERVICE_H
#include <stdint.h>
#include <stddef.h>
#define SLH_SERVICE_MAX_PACKET 1024u
#define SLH_SERVICE_MAX_MESSAGE 16384u
#define SLH_SERVICE_SIGNATURE 49856u
enum { S_INFO=1,S_KEYGEN=2,S_MSG_BEGIN=3,S_MSG_CHUNK=4,S_SIGN=5,
       S_SIG_READ=6,S_VERIFY=7,S_SIG_BEGIN=8,S_SIG_CHUNK=9,S_PK=10,
       S_ZEROIZE=11,S_MODE=12,S_STATS=13,S_PING=14 };
enum { S_SUCCESS=0,S_BAD_REQUEST=1,S_BAD_STATE=2,S_ENTROPY=3,S_CRYPTO=4,S_BOUNDS=5 };
typedef struct { uint64_t cycles; uint32_t f,h,prf,dma,failures,software; } slh_metrics;
void slh_hw_set_mode(unsigned mode);
unsigned slh_hw_get_mode(void);
void slh_hw_reset_metrics(void);
void slh_hw_get_metrics(slh_metrics *m);
void slh_platform_scrub(void);
uint64_t slh_platform_cycles(void);
uint32_t slh_platform_clock(void);
uintptr_t slh_crypto_call(uintptr_t (*fn)(void *),void *arg);
void slh_service_init(void);
int slh_service_command(uint8_t op,const uint8_t *input,size_t size,
                        uint8_t *output,size_t *output_size);
void slh_secure_clear(void *p,size_t n);
uint32_t slh_crc32(uint32_t crc,const uint8_t *data,size_t n);
#endif
