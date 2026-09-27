#ifndef SLH_RV32_HW_ACCEL_H
#define SLH_RV32_HW_ACCEL_H

#include <stdint.h>

/* Return zero when the hardware operation completed.  The portable SLH-DSA
 * implementation falls back to software SHAKE256 if a call fails. */
int slh_hw_f(const uint8_t pk_seed[32], const uint8_t adrs[32],
             const uint8_t input[32], uint8_t output[32]);
int slh_hw_h(const uint8_t pk_seed[32], const uint8_t adrs[32],
             const uint8_t left[32], const uint8_t right[32],
             uint8_t output[32]);
int slh_hw_prf(const uint8_t pk_seed[32],const uint8_t adrs[32],
               const uint8_t secret_seed[32],uint8_t output[32]);

#endif
