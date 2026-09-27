/* Windows RNG adapter for the unmodified SPHINCS+ reference sources.
 * The upstream ref/randombytes.c expects /dev/urandom and cannot run here.
 */
#include <windows.h>
#include <bcrypt.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

#include "randombytes.h"

void randombytes(unsigned char *out, unsigned long long len)
{
    while (len != 0) {
        ULONG chunk = len > ULONG_MAX ? ULONG_MAX : (ULONG)len;
        if (BCryptGenRandom(NULL, out, chunk,
                            BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0) {
            abort();
        }
        out += chunk;
        len -= chunk;
    }
}
