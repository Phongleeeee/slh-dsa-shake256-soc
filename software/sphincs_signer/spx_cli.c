/* Educational SPHINCS+-SHAKE command-line frontend.
 * Algorithm source: third_party/sphincsplus/ref, built unchanged.
 * This is software only. Do not use this CLI for production key management.
 */
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <share.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "api.h"
#include "context.h"
#include "thash.h"

#define MAX_MESSAGE_BYTES (64u * 1024u * 1024u)

static void clear_bytes(void *p, size_t n)
{
    volatile unsigned char *v = (volatile unsigned char *)p;
    while (n--) *v++ = 0;
}

static int read_file(const char *path, unsigned char **out, size_t *len,
                     size_t max_len)
{
    FILE *f;
    long n;
    unsigned char *buf;
    if (fopen_s(&f, path, "rb") != 0) return -1;
    if (fseek(f, 0, SEEK_END) != 0 || (n = ftell(f)) < 0 ||
        (unsigned long)n > max_len || fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return -1;
    }
    buf = (unsigned char *)malloc(n ? (size_t)n : 1u);
    if (!buf) {
        fclose(f);
        return -1;
    }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        fclose(f);
        free(buf);
        return -1;
    }
    if (fclose(f) != 0) {
        free(buf);
        return -1;
    }
    *out = buf;
    *len = (size_t)n;
    return 0;
}

/* O_EXCL prevents accidental overwrite of existing keys, messages or sigs. */
static int write_new(const char *path, const unsigned char *data, size_t len)
{
    int fd;
    size_t offset = 0;
    if (_sopen_s(&fd, path, _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY,
                 _SH_DENYRW, _S_IREAD | _S_IWRITE) != 0) return -1;
    while (offset < len) {
        unsigned int chunk = (len - offset > 0x7fffffffU)
                           ? 0x7fffffffU : (unsigned int)(len - offset);
        int written = _write(fd, data + offset, chunk);
        if (written <= 0) {
            _close(fd);
            _unlink(path);
            return -1;
        }
        offset += (size_t)written;
    }
    if (_close(fd) != 0) {
        _unlink(path);
        return -1;
    }
    return 0;
}

static void usage(const char *program)
{
    fprintf(stderr,
        "Usage:\n"
        "  %s selftest\n"
        "  %s thash-selftest\n"
        "  %s keygen <public-key.bin> <secret-key.bin>\n"
        "  %s sign <secret-key.bin> <message.bin> <signature.bin>\n"
        "  %s verify <public-key.bin> <message.bin> <signature.bin>\n"
        "Keys/signatures are raw binary and specific to this executable's "
        "parameter set.\n", program, program, program, program, program);
}

static int matches_hex(const unsigned char *data, const char *hex, size_t n)
{
    static const char digits[] = "0123456789abcdef";
    size_t i;
    for (i = 0; i < n; ++i) {
        if (digits[data[i] >> 4] != hex[2*i] ||
            digits[data[i] & 15] != hex[2*i+1]) return 0;
    }
    return 1;
}

static int do_thash_selftest(void)
{
#if SPX_N == 32
    spx_ctx ctx = {0};
    uint32_t addr[8] = {0};
    unsigned char in[64], out[32];
    size_t i;
    for (i = 0; i < 32; ++i) {
        ctx.pub_seed[i] = (unsigned char)i;
        ((unsigned char *)addr)[i] = (unsigned char)(0xa0 + i);
    }
    for (i = 0; i < 64; ++i) in[i] = (unsigned char)(0x40 + i);
    thash(out, in, 1, &ctx, addr);
    if (!matches_hex(out,
          "de45664b8ef32752620549297ddf7785bfb572ee2c98399246b116bedf9def29",
          32)) return 1;
    thash(out, in, 2, &ctx, addr);
    if (!matches_hex(out,
          "788fe72d289d2d532c84467e9620fa7143f1c956ab0f8ff98702ef6613080c5a",
          32)) return 1;
    puts("THASH SELFTEST PASS: 1 and 2 blocks match FPGA XSim vectors");
    return 0;
#else
    fputs("thash-selftest uses 32-byte SPHINCS+-SHAKE-256f inputs.\n", stderr);
    return 2;
#endif
}

static int do_selftest(void)
{
    static const unsigned char message[] = "SPHINCS+ SHAKE256 VC707 project";
    unsigned char seed[CRYPTO_SEEDBYTES];
    unsigned char pk[CRYPTO_PUBLICKEYBYTES];
    unsigned char wrong_pk[CRYPTO_PUBLICKEYBYTES];
    unsigned char sk[CRYPTO_SECRETKEYBYTES];
    unsigned char changed[sizeof(message)];
    unsigned char *sig = (unsigned char *)malloc(CRYPTO_BYTES);
    size_t siglen = 0;
    size_t i;
    int okay = 0;
    if (!sig) return 1;
    for (i = 0; i < sizeof(seed); ++i) seed[i] = (unsigned char)i;
    if (crypto_sign_seed_keypair(pk, sk, seed) != 0) goto end;
    if (crypto_sign_signature(sig, &siglen, message, sizeof(message) - 1,
                              sk) != 0 || siglen != CRYPTO_BYTES) goto end;
    if (crypto_sign_verify(sig, siglen, message, sizeof(message) - 1,
                           pk) != 0) goto end;
    if (crypto_sign_verify(sig, siglen - 1, message, sizeof(message) - 1,
                           pk) == 0) goto end;
    memcpy(wrong_pk, pk, sizeof(pk));
    wrong_pk[0] ^= 1;
    if (crypto_sign_verify(sig, siglen, message, sizeof(message) - 1,
                           wrong_pk) == 0) goto end;
    memcpy(changed, message, sizeof(message));
    changed[0] ^= 1;
    if (crypto_sign_verify(sig, siglen, changed, sizeof(message) - 1,
                           pk) == 0) goto end;
    sig[0] ^= 1;
    if (crypto_sign_verify(sig, siglen, message, sizeof(message) - 1,
                           pk) == 0) goto end;
    okay = 1;
end:
    clear_bytes(sk, sizeof(sk));
    clear_bytes(seed, sizeof(seed));
    clear_bytes(sig, CRYPTO_BYTES);
    free(sig);
    if (okay) {
        printf("SELFTEST PASS: keygen/sign/verify; rejects wrong key, length, "
               "message and signature (%u-byte signature)\n",
               (unsigned)CRYPTO_BYTES);
        return 0;
    }
    fprintf(stderr, "SELFTEST FAIL\n");
    return 1;
}

static int do_keygen(const char *pk_path, const char *sk_path)
{
    unsigned char pk[CRYPTO_PUBLICKEYBYTES];
    unsigned char sk[CRYPTO_SECRETKEYBYTES];
    int result = 1;
    if (strcmp(pk_path, sk_path) == 0) {
        fprintf(stderr, "Public and secret key paths must differ.\n");
        return 1;
    }
    if (crypto_sign_keypair(pk, sk) != 0) goto end;
    /* Write the secret key first; neither output is overwritten. */
    if (write_new(sk_path, sk, sizeof(sk)) != 0) {
        fprintf(stderr, "Cannot create secret key (already exists?).\n");
        goto end;
    }
    if (write_new(pk_path, pk, sizeof(pk)) != 0) {
        fprintf(stderr, "Cannot create public key. Secret key was written "
                        "to %s; keep it private.\n", sk_path);
        goto end;
    }
    printf("KEYGEN PASS: public key %u bytes, secret key %u bytes\n",
           (unsigned)sizeof(pk), (unsigned)sizeof(sk));
    result = 0;
end:
    clear_bytes(sk, sizeof(sk));
    return result;
}

static int do_sign(const char *sk_path, const char *msg_path,
                   const char *sig_path)
{
    unsigned char *sk = NULL, *msg = NULL, *sig = NULL;
    size_t sklen = 0, msglen = 0, siglen = 0;
    int result = 1;
    if (read_file(sk_path, &sk, &sklen, CRYPTO_SECRETKEYBYTES) != 0 ||
        sklen != CRYPTO_SECRETKEYBYTES) {
        fprintf(stderr, "Secret key is missing or has the wrong size.\n");
        goto end;
    }
    if (read_file(msg_path, &msg, &msglen, MAX_MESSAGE_BYTES) != 0) {
        fprintf(stderr, "Message is missing or exceeds 64 MiB.\n");
        goto end;
    }
    sig = (unsigned char *)malloc(CRYPTO_BYTES);
    if (!sig || crypto_sign_signature(sig, &siglen, msg, msglen, sk) != 0 ||
        siglen != CRYPTO_BYTES || write_new(sig_path, sig, siglen) != 0) {
        fprintf(stderr, "Signing or writing signature failed.\n");
        goto end;
    }
    printf("SIGN PASS: %u-byte detached signature\n", (unsigned)siglen);
    result = 0;
end:
    if (sk) { clear_bytes(sk, sklen); free(sk); }
    if (sig) { clear_bytes(sig, CRYPTO_BYTES); free(sig); }
    free(msg);
    return result;
}

static int do_verify(const char *pk_path, const char *msg_path,
                     const char *sig_path)
{
    unsigned char *pk = NULL, *msg = NULL, *sig = NULL;
    size_t pklen = 0, msglen = 0, siglen = 0;
    int valid = 0;
    if (read_file(pk_path, &pk, &pklen, CRYPTO_PUBLICKEYBYTES) != 0 ||
        pklen != CRYPTO_PUBLICKEYBYTES ||
        read_file(msg_path, &msg, &msglen, MAX_MESSAGE_BYTES) != 0 ||
        read_file(sig_path, &sig, &siglen, CRYPTO_BYTES) != 0 ||
        siglen != CRYPTO_BYTES) {
        fprintf(stderr, "Public key, message or signature missing/wrong size.\n");
        goto end;
    }
    valid = crypto_sign_verify(sig, siglen, msg, msglen, pk) == 0;
end:
    free(pk);
    free(msg);
    free(sig);
    puts(valid ? "VALID SIGNATURE" : "INVALID SIGNATURE");
    return valid ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "selftest") == 0) return do_selftest();
    if (argc == 2 && strcmp(argv[1], "thash-selftest") == 0)
        return do_thash_selftest();
    if (argc == 4 && strcmp(argv[1], "keygen") == 0)
        return do_keygen(argv[2], argv[3]);
    if (argc == 5 && strcmp(argv[1], "sign") == 0)
        return do_sign(argv[2], argv[3], argv[4]);
    if (argc == 5 && strcmp(argv[1], "verify") == 0)
        return do_verify(argv[2], argv[3], argv[4]);
    usage(argv[0]);
    return 2;
}
