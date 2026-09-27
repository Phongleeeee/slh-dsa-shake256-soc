/* Windows DLL bridge used only by test_acvp_256f.py. */
#include <stddef.h>
#include <stdint.h>
#include "slh_dsa.h"
#include "slh_prehash.h"

#define API __declspec(dllexport)
static const slh_param_t *const P = &slh_dsa_shake_256f;

API int acvp_keygen_internal(uint8_t *sk, uint8_t *pk,
                             const uint8_t *sk_seed,
                             const uint8_t *sk_prf,
                             const uint8_t *pk_seed)
{
    return slh_keygen_internal(sk, pk, sk_seed, sk_prf, pk_seed, P);
}

/* interface_mode: 0=internal, 1=pure external, 2=pre-hash external. */
API size_t acvp_sign(uint8_t *sig, const uint8_t *msg, size_t msg_len,
                     const uint8_t *sk, const uint8_t *ctx, size_t ctx_len,
                     const uint8_t *addrnd, int interface_mode,
                     const char *prehash)
{
    if (interface_mode == 0)
        return slh_sign_internal(sig, msg, msg_len, sk, addrnd, P);
    if (interface_mode == 1)
        return slh_sign(sig, msg, msg_len, ctx, ctx_len, sk, addrnd, P);
    if (interface_mode == 2 && prehash != NULL)
        return hash_slh_sign(sig, msg, msg_len, ctx, ctx_len, prehash,
                             sk, addrnd, P);
    return 0;
}

API int acvp_verify(const uint8_t *msg, size_t msg_len,
                    const uint8_t *sig, size_t sig_len,
                    const uint8_t *pk, const uint8_t *ctx, size_t ctx_len,
                    int interface_mode, const char *prehash)
{
    if (interface_mode == 0)
        return slh_verify_internal(msg, msg_len, sig, sig_len, pk, P);
    if (interface_mode == 1)
        return slh_verify(msg, msg_len, sig, sig_len, ctx, ctx_len, pk, P);
    if (interface_mode == 2 && prehash != NULL)
        return hash_slh_verify(msg, msg_len, sig, sig_len, ctx, ctx_len,
                               prehash, pk, P);
    return 0;
}
