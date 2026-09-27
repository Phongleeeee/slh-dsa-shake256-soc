/*
 * SLH-DSA-SHAKE-256f product prototype for Windows.
 *
 * Cryptographic implementation: pq-code-package/slhdsa-c (FIPS 205).
 * Secret keys are protected at rest with Windows DPAPI and bound to the
 * current Windows user.  The .slpk/.slsk/.slsig containers are project
 * formats, not CMS/X.509/PAdES encodings.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <dpapi.h>
#include <fcntl.h>
#include <io.h>
#include <share.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "sha3_api.h"
#include "slh_dsa.h"
#include "slh_prehash.h"

#define MAX_MESSAGE_BYTES (64u * 1024u * 1024u)
#define KEY_HEADER_SIZE 32u
#define SIG_HEADER_SIZE 64u
#define EXPECTED_PK_SIZE 64u
#define EXPECTED_SK_SIZE 128u
#define EXPECTED_SIG_SIZE 49856u
#define ALG_SLH_DSA_SHAKE_256F 1u
#define KEY_PUBLIC 1u
#define KEY_PRIVATE_DPAPI 2u
#define SIG_MODE_PURE 0u
#define SIG_MODE_PREHASH 1u
#define PH_NONE 0u
#define PH_SHAKE_256 1u
#define PH_SHA2_256 2u

static const unsigned char KEY_MAGIC[8] =
    {'S','L','H','K','E','Y','0','1'};
static const unsigned char SIG_MAGIC[8] =
    {'S','L','H','S','I','G','0','1'};
static const unsigned char DPAPI_ENTROPY[] =
    "SLH-DSA-SHAKE-256f VC707 product prototype v1";
static const slh_param_t *const PARAMS = &slh_dsa_shake_256f;

typedef struct sign_options_s {
    const unsigned char *context;
    size_t context_len;
    int deterministic;
    int mode;
    int ph_id;
} sign_options_t;

static void clear_bytes(void *p, size_t n)
{
    volatile unsigned char *v = (volatile unsigned char *)p;
    while (n-- != 0) *v++ = 0;
}

static void put_u16(unsigned char *p, uint16_t v)
{
    p[0] = (unsigned char)v;
    p[1] = (unsigned char)(v >> 8);
}

static void put_u32(unsigned char *p, uint32_t v)
{
    p[0] = (unsigned char)v;
    p[1] = (unsigned char)(v >> 8);
    p[2] = (unsigned char)(v >> 16);
    p[3] = (unsigned char)(v >> 24);
}

static void put_u64(unsigned char *p, uint64_t v)
{
    unsigned int i;
    for (i = 0; i < 8; ++i) p[i] = (unsigned char)(v >> (8 * i));
}

static uint16_t get_u16(const unsigned char *p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t get_u32(const unsigned char *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t get_u64(const unsigned char *p)
{
    uint64_t v = 0;
    int i;
    for (i = 7; i >= 0; --i) v = (v << 8) | p[i];
    return v;
}

static int constant_time_equal(const unsigned char *a,
                               const unsigned char *b, size_t n)
{
    unsigned char diff = 0;
    size_t i;
    for (i = 0; i < n; ++i) diff |= (unsigned char)(a[i] ^ b[i]);
    return diff == 0;
}

static int random_bytes(unsigned char *out, size_t len)
{
    while (len != 0) {
        ULONG chunk = len > ULONG_MAX ? ULONG_MAX : (ULONG)len;
        NTSTATUS status = BCryptGenRandom(NULL, out, chunk,
                                          BCRYPT_USE_SYSTEM_PREFERRED_RNG);
        if (status < 0) return -1;
        out += chunk;
        len -= chunk;
    }
    return 0;
}

static int read_file(const char *path, unsigned char **out, size_t *len,
                     size_t max_len)
{
    FILE *f = NULL;
    __int64 n;
    unsigned char *buf;
    if (fopen_s(&f, path, "rb") != 0) return -1;
    if (_fseeki64(f, 0, SEEK_END) != 0 || (n = _ftelli64(f)) < 0 ||
        (uint64_t)n > max_len || _fseeki64(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return -1;
    }
    buf = (unsigned char *)malloc(n != 0 ? (size_t)n : 1u);
    if (buf == NULL) {
        fclose(f);
        return -1;
    }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        fclose(f);
        clear_bytes(buf, (size_t)n);
        free(buf);
        return -1;
    }
    if (fclose(f) != 0) {
        clear_bytes(buf, (size_t)n);
        free(buf);
        return -1;
    }
    *out = buf;
    *len = (size_t)n;
    return 0;
}

/* Exclusive creation prevents accidental key/signature overwrite. */
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
    {
        /* Always close, including a failed flush. Short-circuit || would
           leave the exclusive handle open and prevent removing the file. */
        int commit_result = _commit(fd);
        int close_result = _close(fd);
        if (commit_result != 0 || close_result != 0) {
            _unlink(path);
            return -1;
        }
    }
    return 0;
}

static void public_fingerprint(unsigned char out[32],
                               const unsigned char *pk)
{
    static const unsigned char domain[] = "SLH-DSA-PK-FP-v1";
    sha3_var_t xof;
    shake256_init(&xof);
    shake_update(&xof, domain, sizeof(domain) - 1);
    shake_update(&xof, pk, EXPECTED_PK_SIZE);
    shake_out(&xof, out, 32);
    clear_bytes(&xof, sizeof(xof));
}

static void print_hex(const unsigned char *data, size_t len)
{
    size_t i;
    for (i = 0; i < len; ++i) printf("%02x", data[i]);
}

static int protect_secret(const unsigned char *sk, size_t sk_len,
                          unsigned char **protected_data,
                          size_t *protected_len)
{
    DATA_BLOB input, entropy, output;
    input.pbData = (BYTE *)sk;
    input.cbData = (DWORD)sk_len;
    entropy.pbData = (BYTE *)DPAPI_ENTROPY;
    entropy.cbData = (DWORD)(sizeof(DPAPI_ENTROPY) - 1);
    output.pbData = NULL;
    output.cbData = 0;
    if (!CryptProtectData(&input, L"SLH-DSA-SHAKE-256f private key",
                          &entropy, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN,
                          &output)) return -1;
    *protected_data = (unsigned char *)malloc(output.cbData);
    if (*protected_data == NULL) {
        SecureZeroMemory(output.pbData, output.cbData);
        LocalFree(output.pbData);
        return -1;
    }
    memcpy(*protected_data, output.pbData, output.cbData);
    *protected_len = output.cbData;
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    return 0;
}

static int unprotect_secret(const unsigned char *protected_data,
                            size_t protected_len, unsigned char *sk)
{
    DATA_BLOB input, entropy, output;
    input.pbData = (BYTE *)protected_data;
    input.cbData = (DWORD)protected_len;
    entropy.pbData = (BYTE *)DPAPI_ENTROPY;
    entropy.cbData = (DWORD)(sizeof(DPAPI_ENTROPY) - 1);
    output.pbData = NULL;
    output.cbData = 0;
    if (!CryptUnprotectData(&input, NULL, &entropy, NULL, NULL,
                            CRYPTPROTECT_UI_FORBIDDEN, &output)) return -1;
    if (output.cbData != EXPECTED_SK_SIZE) {
        SecureZeroMemory(output.pbData, output.cbData);
        LocalFree(output.pbData);
        return -1;
    }
    memcpy(sk, output.pbData, EXPECTED_SK_SIZE);
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    return 0;
}

static int make_key_container(unsigned int kind, const unsigned char *payload,
                              size_t payload_len, unsigned char **out,
                              size_t *out_len)
{
    unsigned char *buf;
    if (payload_len > UINT32_MAX) return -1;
    buf = (unsigned char *)calloc(1, KEY_HEADER_SIZE + payload_len);
    if (buf == NULL) return -1;
    memcpy(buf, KEY_MAGIC, sizeof(KEY_MAGIC));
    buf[8] = 1;
    buf[9] = (unsigned char)kind;
    buf[10] = ALG_SLH_DSA_SHAKE_256F;
    buf[11] = kind == KEY_PRIVATE_DPAPI ? 1 : 0;
    put_u32(buf + 12, (uint32_t)payload_len);
    memcpy(buf + KEY_HEADER_SIZE, payload, payload_len);
    *out = buf;
    *out_len = KEY_HEADER_SIZE + payload_len;
    return 0;
}

static int parse_key_container(const unsigned char *buf, size_t len,
                               unsigned int expected_kind,
                               const unsigned char **payload,
                               size_t *payload_len)
{
    uint32_t n;
    size_t i;
    if (len < KEY_HEADER_SIZE ||
        !constant_time_equal(buf, KEY_MAGIC, sizeof(KEY_MAGIC)) ||
        buf[8] != 1 || buf[9] != expected_kind ||
        buf[10] != ALG_SLH_DSA_SHAKE_256F) return -1;
    /* Version 1 defines exactly one flag for DPAPI and no public flags. */
    if (buf[11] != (expected_kind == KEY_PRIVATE_DPAPI ? 1 : 0)) return -1;
    for (i = 16; i < KEY_HEADER_SIZE; ++i)
        if (buf[i] != 0) return -1;
    n = get_u32(buf + 12);
    if ((size_t)n != len - KEY_HEADER_SIZE) return -1;
    if (expected_kind == KEY_PUBLIC && n != EXPECTED_PK_SIZE) return -1;
    *payload = buf + KEY_HEADER_SIZE;
    *payload_len = n;
    return 0;
}

static int load_public_key(const char *path, unsigned char pk[EXPECTED_PK_SIZE])
{
    unsigned char *buf = NULL;
    const unsigned char *payload;
    size_t len = 0, payload_len = 0;
    int rc = -1;
    if (read_file(path, &buf, &len, 1024) != 0) return -1;
    if (parse_key_container(buf, len, KEY_PUBLIC, &payload, &payload_len) == 0) {
        memcpy(pk, payload, EXPECTED_PK_SIZE);
        rc = 0;
    }
    clear_bytes(buf, len);
    free(buf);
    return rc;
}

static int load_private_key(const char *path, unsigned char sk[EXPECTED_SK_SIZE])
{
    unsigned char *buf = NULL;
    const unsigned char *payload;
    size_t len = 0, payload_len = 0;
    int rc = -1;
    if (read_file(path, &buf, &len, 64u * 1024u) != 0) return -1;
    if (parse_key_container(buf, len, KEY_PRIVATE_DPAPI,
                            &payload, &payload_len) == 0 &&
        unprotect_secret(payload, payload_len, sk) == 0) rc = 0;
    clear_bytes(buf, len);
    free(buf);
    return rc;
}

static const char *prehash_name(int id)
{
    if (id == PH_SHAKE_256) return "SHAKE-256";
    if (id == PH_SHA2_256) return "SHA2-256";
    return NULL;
}

static int parse_sign_options(int argc, char **argv, int first,
                              sign_options_t *options)
{
    int i;
    static unsigned char hex_context[255];
    memset(options, 0, sizeof(*options));
    options->mode = SIG_MODE_PURE;
    options->ph_id = PH_NONE;
    for (i = first; i < argc; ++i) {
        if (strcmp(argv[i], "--deterministic") == 0) {
            options->deterministic = 1;
        } else if (strcmp(argv[i], "--context") == 0 && i + 1 < argc) {
            options->context = (const unsigned char *)argv[++i];
            options->context_len = strlen(argv[i]);
            if (options->context_len > 255) return -1;
        } else if (strcmp(argv[i], "--context-hex") == 0 && i+1<argc) {
            const char *hex=argv[++i]; size_t j,len=strlen(hex);
            if(len>510 || (len&1)) return -1;
            for(j=0;j<len;j+=2) {
                unsigned a,b; char c=hex[j],d=hex[j+1];
                if(c>='0'&&c<='9') a=c-'0'; else if(c>='a'&&c<='f') a=c-'a'+10; else return -1;
                if(d>='0'&&d<='9') b=d-'0'; else if(d>='a'&&d<='f') b=d-'a'+10; else return -1;
                hex_context[j/2]=(unsigned char)((a<<4)|b);
            }
            options->context=hex_context; options->context_len=len/2;
        } else if (strcmp(argv[i], "--prehash") == 0 && i + 1 < argc) {
            const char *name = argv[++i];
            options->mode = SIG_MODE_PREHASH;
            if (strcmp(name, "SHAKE-256") == 0) options->ph_id = PH_SHAKE_256;
            else if (strcmp(name, "SHA2-256") == 0) options->ph_id = PH_SHA2_256;
            else return -1;
        } else {
            return -1;
        }
    }
    return 0;
}

static size_t create_signature(unsigned char *sig, const unsigned char *msg,
                               size_t msg_len, const unsigned char *sk,
                               const sign_options_t *options,
                               const unsigned char *addrnd)
{
    if (options->mode == SIG_MODE_PREHASH) {
        return hash_slh_sign(sig, msg, msg_len, options->context,
                             options->context_len,
                             prehash_name(options->ph_id), sk, addrnd, PARAMS);
    }
    return slh_sign(sig, msg, msg_len, options->context,
                    options->context_len, sk, addrnd, PARAMS);
}

static int check_signature(const unsigned char *msg, size_t msg_len,
                           const unsigned char *sig, size_t sig_len,
                           const unsigned char *pk,
                           const sign_options_t *options)
{
    if (options->mode == SIG_MODE_PREHASH) {
        return hash_slh_verify(msg, msg_len, sig, sig_len, options->context,
                               options->context_len,
                               prehash_name(options->ph_id), pk, PARAMS);
    }
    return slh_verify(msg, msg_len, sig, sig_len, options->context,
                      options->context_len, pk, PARAMS);
}

static int make_signature_container(const unsigned char *sig, size_t sig_len,
                                    uint64_t message_len,
                                    const unsigned char fingerprint[32],
                                    const sign_options_t *options,
                                    unsigned char **out, size_t *out_len)
{
    unsigned char *buf;
    size_t total;
    if (sig_len > UINT32_MAX || options->context_len > 255) return -1;
    total = SIG_HEADER_SIZE + options->context_len + sig_len;
    buf = (unsigned char *)calloc(1, total);
    if (buf == NULL) return -1;
    memcpy(buf, SIG_MAGIC, sizeof(SIG_MAGIC));
    buf[8] = 1;
    buf[9] = ALG_SLH_DSA_SHAKE_256F;
    buf[10] = (unsigned char)options->mode;
    buf[11] = options->deterministic ? 0 : 1;
    buf[12] = (unsigned char)options->context_len;
    buf[13] = (unsigned char)options->ph_id;
    put_u32(buf + 14, (uint32_t)sig_len);
    put_u64(buf + 18, message_len);
    memcpy(buf + 26, fingerprint, 32);
    if (options->context_len != 0)
        memcpy(buf + SIG_HEADER_SIZE, options->context, options->context_len);
    memcpy(buf + SIG_HEADER_SIZE + options->context_len, sig, sig_len);
    *out = buf;
    *out_len = total;
    return 0;
}

static int parse_signature_container(const unsigned char *buf, size_t len,
                                     sign_options_t *options,
                                     uint64_t *message_len,
                                     const unsigned char **fingerprint,
                                     const unsigned char **signature,
                                     size_t *signature_len)
{
    size_t ctx_len, i;
    uint32_t sig_len;
    if (len < SIG_HEADER_SIZE ||
        !constant_time_equal(buf, SIG_MAGIC, sizeof(SIG_MAGIC)) ||
        buf[8] != 1 || buf[9] != ALG_SLH_DSA_SHAKE_256F ||
        buf[10] > SIG_MODE_PREHASH || buf[11] > 1) return -1;
    for (i = 58; i < SIG_HEADER_SIZE; ++i)
        if (buf[i] != 0) return -1;
    ctx_len = buf[12];
    sig_len = get_u32(buf + 14);
    if (sig_len != EXPECTED_SIG_SIZE ||
        len != SIG_HEADER_SIZE + ctx_len + sig_len) return -1;
    memset(options, 0, sizeof(*options));
    options->mode = buf[10];
    options->deterministic = (buf[11] & 1) == 0;
    options->ph_id = buf[13];
    if ((options->mode == SIG_MODE_PURE && options->ph_id != PH_NONE) ||
        (options->mode == SIG_MODE_PREHASH &&
         prehash_name(options->ph_id) == NULL)) return -1;
    options->context = buf + SIG_HEADER_SIZE;
    options->context_len = ctx_len;
    *message_len = get_u64(buf + 18);
    *fingerprint = buf + 26;
    *signature = buf + SIG_HEADER_SIZE + ctx_len;
    *signature_len = sig_len;
    return 0;
}

static int command_keygen(const char *public_path, const char *private_path)
{
    unsigned char pk[EXPECTED_PK_SIZE], sk[EXPECTED_SK_SIZE];
    unsigned char *protected_key = NULL, *public_file = NULL;
    unsigned char *private_file = NULL;
    size_t protected_len = 0, public_len = 0, private_len = 0;
    unsigned char fp[32];
    int rc = 1;
    if (strcmp(public_path, private_path) == 0) {
        fprintf(stderr, "Public and private key paths must differ.\n");
        return 1;
    }
    if (slh_pk_sz(PARAMS) != EXPECTED_PK_SIZE ||
        slh_sk_sz(PARAMS) != EXPECTED_SK_SIZE ||
        slh_sig_sz(PARAMS) != EXPECTED_SIG_SIZE) {
        fprintf(stderr, "Unexpected SLH-DSA parameter sizes.\n");
        return 1;
    }
    if (slh_keygen(sk, pk, random_bytes, PARAMS) != 0 ||
        protect_secret(sk, sizeof(sk), &protected_key, &protected_len) != 0 ||
        make_key_container(KEY_PUBLIC, pk, sizeof(pk),
                           &public_file, &public_len) != 0 ||
        make_key_container(KEY_PRIVATE_DPAPI, protected_key, protected_len,
                           &private_file, &private_len) != 0) {
        fprintf(stderr, "Key generation or DPAPI protection failed.\n");
        goto end;
    }
    if (write_new(private_path, private_file, private_len) != 0) {
        fprintf(stderr, "Cannot create private key (already exists?).\n");
        goto end;
    }
    if (write_new(public_path, public_file, public_len) != 0) {
        _unlink(private_path);
        fprintf(stderr, "Cannot create public key; new private file removed.\n");
        goto end;
    }
    public_fingerprint(fp, pk);
    printf("KEYGEN PASS\nAlgorithm: %s\nPublic key: %u bytes\n"
           "Private key: %u bytes, protected with Windows DPAPI\nFingerprint: ",
           slh_alg_id(PARAMS), (unsigned)sizeof(pk), (unsigned)sizeof(sk));
    print_hex(fp, sizeof(fp));
    putchar('\n');
    rc = 0;
end:
    clear_bytes(sk, sizeof(sk));
    clear_bytes(pk, sizeof(pk));
    clear_bytes(fp, sizeof(fp));
    if (protected_key != NULL) {
        clear_bytes(protected_key, protected_len);
        free(protected_key);
    }
    if (private_file != NULL) {
        clear_bytes(private_file, private_len);
        free(private_file);
    }
    if (public_file != NULL) {
        clear_bytes(public_file, public_len);
        free(public_file);
    }
    return rc;
}

static int command_sign(int argc, char **argv)
{
    unsigned char sk[EXPECTED_SK_SIZE], pk[EXPECTED_PK_SIZE], addrnd[32];
    unsigned char fp[32];
    unsigned char *message = NULL, *signature = NULL, *container = NULL;
    size_t message_len = 0, signature_len = 0, container_len = 0;
    sign_options_t options;
    const unsigned char *randomizer = NULL;
    int rc = 1;
    if (parse_sign_options(argc, argv, 5, &options) != 0) {
        fprintf(stderr, "Invalid signing options.\n");
        return 2;
    }
    if (load_private_key(argv[2], sk) != 0) {
        fprintf(stderr, "Cannot unlock private key for this Windows user.\n");
        goto end;
    }
    if (read_file(argv[3], &message, &message_len, MAX_MESSAGE_BYTES) != 0) {
        fprintf(stderr, "Message is missing or exceeds 64 MiB.\n");
        goto end;
    }
    memcpy(pk, sk + 64, EXPECTED_PK_SIZE);
    public_fingerprint(fp, pk);
    if (!options.deterministic) {
        if (random_bytes(addrnd, sizeof(addrnd)) != 0) {
            fprintf(stderr, "System random generator failed.\n");
            goto end;
        }
        randomizer = addrnd;
    }
    signature = (unsigned char *)malloc(EXPECTED_SIG_SIZE);
    if (signature == NULL) goto end;
    signature_len = create_signature(signature, message, message_len, sk,
                                      &options, randomizer);
    if (signature_len != EXPECTED_SIG_SIZE ||
        make_signature_container(signature, signature_len, message_len, fp,
                                 &options, &container, &container_len) != 0 ||
        write_new(argv[4], container, container_len) != 0) {
        fprintf(stderr, "Signing or exclusive signature write failed.\n");
        goto end;
    }
    printf("SIGN PASS\nAlgorithm: %s\nMode: %s%s\nContext bytes: %u\n"
           "Signature: %u bytes\nContainer: %u bytes\n",
           slh_alg_id(PARAMS),
           options.mode == SIG_MODE_PURE ? "pure" : prehash_name(options.ph_id),
           options.deterministic ? ", deterministic" : ", hedged",
           (unsigned)options.context_len, (unsigned)signature_len,
           (unsigned)container_len);
    rc = 0;
end:
    clear_bytes(sk, sizeof(sk));
    clear_bytes(pk, sizeof(pk));
    clear_bytes(addrnd, sizeof(addrnd));
    clear_bytes(fp, sizeof(fp));
    if (signature != NULL) {
        clear_bytes(signature, EXPECTED_SIG_SIZE);
        free(signature);
    }
    if (container != NULL) {
        clear_bytes(container, container_len);
        free(container);
    }
    free(message);
    return rc;
}

static int command_verify(const char *public_path, const char *message_path,
                          const char *signature_path)
{
    unsigned char pk[EXPECTED_PK_SIZE], expected_fp[32];
    unsigned char *message = NULL, *container = NULL;
    const unsigned char *stored_fp, *signature;
    size_t message_len = 0, container_len = 0, signature_len = 0;
    uint64_t stored_message_len = 0;
    sign_options_t options;
    int valid = 0;
    if (load_public_key(public_path, pk) != 0 ||
        read_file(message_path, &message, &message_len, MAX_MESSAGE_BYTES) != 0 ||
        read_file(signature_path, &container, &container_len,
                  SIG_HEADER_SIZE + 255u + EXPECTED_SIG_SIZE) != 0 ||
        parse_signature_container(container, container_len, &options,
                                  &stored_message_len, &stored_fp, &signature,
                                  &signature_len) != 0) {
        fprintf(stderr, "Invalid public key, message or signature container.\n");
        goto end;
    }
    public_fingerprint(expected_fp, pk);
    if (stored_message_len != message_len ||
        !constant_time_equal(stored_fp, expected_fp, sizeof(expected_fp))) {
        fprintf(stderr, "Message length or public-key fingerprint mismatch.\n");
        goto end;
    }
    valid = check_signature(message, message_len, signature, signature_len,
                            pk, &options);
end:
    clear_bytes(pk, sizeof(pk));
    clear_bytes(expected_fp, sizeof(expected_fp));
    free(message);
    if (container != NULL) {
        clear_bytes(container, container_len);
        free(container);
    }
    puts(valid ? "VALID SIGNATURE" : "INVALID SIGNATURE");
    return valid ? 0 : 1;
}

static int command_thash_selftest(void)
{
    unsigned char input[128], output[32];
    size_t i;
    for (i = 0; i < 32; ++i) input[i] = (unsigned char)i;
    for (i = 0; i < 32; ++i) input[32 + i] = (unsigned char)(0xa0 + i);
    for (i = 0; i < 64; ++i) input[64 + i] = (unsigned char)(0x40 + i);
    shake256(output, sizeof(output), input, 96);
    if (!constant_time_equal(output, (const unsigned char[]){
        0xde,0x45,0x66,0x4b,0x8e,0xf3,0x27,0x52,
        0x62,0x05,0x49,0x29,0x7d,0xdf,0x77,0x85,
        0xbf,0xb5,0x72,0xee,0x2c,0x98,0x39,0x92,
        0x46,0xb1,0x16,0xbe,0xdf,0x9d,0xef,0x29}, 32)) return 1;
    shake256(output, sizeof(output), input, 128);
    if (!constant_time_equal(output, (const unsigned char[]){
        0x78,0x8f,0xe7,0x2d,0x28,0x9d,0x2d,0x53,
        0x2c,0x84,0x46,0x7e,0x96,0x20,0xfa,0x71,
        0x43,0xf1,0xc9,0x56,0xab,0x0f,0x8f,0xf9,
        0x87,0x02,0xef,0x66,0x13,0x08,0x0c,0x5a}, 32)) return 1;
    puts("THASH SELFTEST PASS: F/H vectors match FPGA XSim");
    return 0;
}

static int command_selftest(void)
{
    static const unsigned char message[] =
        "FIPS 205 SLH-DSA-SHAKE-256f VC707 product prototype";
    static const unsigned char context[] = "VC707-FIPS205";
    unsigned char seeds[96], addrnd[32], pk[EXPECTED_PK_SIZE];
    unsigned char sk[EXPECTED_SK_SIZE], changed_pk[EXPECTED_PK_SIZE];
    unsigned char *sig1 = NULL, *sig2 = NULL;
    sign_options_t pure, prehash;
    size_t i, n1, n2;
    int okay = 0;
    sig1 = (unsigned char *)malloc(EXPECTED_SIG_SIZE);
    sig2 = (unsigned char *)malloc(EXPECTED_SIG_SIZE);
    if (sig1 == NULL || sig2 == NULL) goto end;
    for (i = 0; i < sizeof(seeds); ++i) seeds[i] = (unsigned char)i;
    for (i = 0; i < sizeof(addrnd); ++i) addrnd[i] = (unsigned char)(0xa0 + i);
    if (slh_keygen_internal(sk, pk, seeds, seeds + 32, seeds + 64,
                            PARAMS) != 0) goto end;
    memset(&pure, 0, sizeof(pure));
    pure.context = context;
    pure.context_len = sizeof(context) - 1;
    pure.mode = SIG_MODE_PURE;
    n1 = create_signature(sig1, message, sizeof(message) - 1, sk,
                          &pure, addrnd);
    if (n1 != EXPECTED_SIG_SIZE ||
        !check_signature(message, sizeof(message) - 1, sig1, n1, pk, &pure))
        goto end;
    pure.context = (const unsigned char *)"wrong-context";
    pure.context_len = 13;
    if (check_signature(message, sizeof(message) - 1, sig1, n1, pk, &pure))
        goto end;
    pure.context = context;
    pure.context_len = sizeof(context) - 1;
    memcpy(changed_pk, pk, sizeof(pk));
    changed_pk[0] ^= 1;
    if (check_signature(message, sizeof(message) - 1, sig1, n1,
                        changed_pk, &pure)) goto end;
    sig1[100] ^= 1;
    if (check_signature(message, sizeof(message) - 1, sig1, n1, pk, &pure))
        goto end;
    sig1[100] ^= 1;
    n1 = create_signature(sig1, message, sizeof(message) - 1, sk, &pure, NULL);
    n2 = create_signature(sig2, message, sizeof(message) - 1, sk, &pure, NULL);
    if (n1 != EXPECTED_SIG_SIZE || n2 != n1 ||
        !constant_time_equal(sig1, sig2, n1)) goto end;
    memset(&prehash, 0, sizeof(prehash));
    prehash.context = context;
    prehash.context_len = sizeof(context) - 1;
    prehash.mode = SIG_MODE_PREHASH;
    prehash.ph_id = PH_SHAKE_256;
    n1 = create_signature(sig1, message, sizeof(message) - 1, sk,
                          &prehash, addrnd);
    if (n1 != EXPECTED_SIG_SIZE ||
        !check_signature(message, sizeof(message) - 1, sig1, n1,
                         pk, &prehash)) goto end;
    okay = 1;
end:
    clear_bytes(seeds, sizeof(seeds));
    clear_bytes(addrnd, sizeof(addrnd));
    clear_bytes(pk, sizeof(pk));
    clear_bytes(sk, sizeof(sk));
    clear_bytes(changed_pk, sizeof(changed_pk));
    if (sig1 != NULL) { clear_bytes(sig1, EXPECTED_SIG_SIZE); free(sig1); }
    if (sig2 != NULL) { clear_bytes(sig2, EXPECTED_SIG_SIZE); free(sig2); }
    if (okay) {
        puts("SELFTEST PASS: FIPS 205 keygen, pure/context, deterministic, "
             "hedged, pre-hash, verify and negative cases");
        return 0;
    }
    fputs("SELFTEST FAIL\n", stderr);
    return 1;
}

static double elapsed_ms(LARGE_INTEGER start, LARGE_INTEGER stop,
                         LARGE_INTEGER frequency)
{
    return 1000.0 * (double)(stop.QuadPart - start.QuadPart) /
           (double)frequency.QuadPart;
}

static int command_benchmark(void)
{
    static const unsigned char message[] = "SLH-DSA benchmark message";
    unsigned char pk[EXPECTED_PK_SIZE], sk[EXPECTED_SK_SIZE], addrnd[32];
    unsigned char *sig = NULL;
    LARGE_INTEGER frequency, t0, t1, t2, t3;
    size_t sig_len;
    int valid;
    if (!QueryPerformanceFrequency(&frequency) ||
        random_bytes(addrnd, sizeof(addrnd)) != 0) return 1;
    sig = (unsigned char *)malloc(EXPECTED_SIG_SIZE);
    if (sig == NULL) return 1;
    QueryPerformanceCounter(&t0);
    if (slh_keygen(sk, pk, random_bytes, PARAMS) != 0) goto fail;
    QueryPerformanceCounter(&t1);
    sig_len = slh_sign(sig, message, sizeof(message) - 1, NULL, 0,
                       sk, addrnd, PARAMS);
    QueryPerformanceCounter(&t2);
    valid = slh_verify(message, sizeof(message) - 1, sig, sig_len,
                       NULL, 0, pk, PARAMS);
    QueryPerformanceCounter(&t3);
    if (!valid || sig_len != EXPECTED_SIG_SIZE) goto fail;
    printf("BENCHMARK PASS (%s, portable C, one operation)\n"
           "keygen_ms=%.3f\nsign_ms=%.3f\nverify_ms=%.3f\n",
           slh_alg_id(PARAMS), elapsed_ms(t0, t1, frequency),
           elapsed_ms(t1, t2, frequency), elapsed_ms(t2, t3, frequency));
    clear_bytes(sk, sizeof(sk));
    clear_bytes(addrnd, sizeof(addrnd));
    clear_bytes(sig, EXPECTED_SIG_SIZE);
    free(sig);
    return 0;
fail:
    clear_bytes(sk, sizeof(sk));
    clear_bytes(addrnd, sizeof(addrnd));
    clear_bytes(sig, EXPECTED_SIG_SIZE);
    free(sig);
    return 1;
}

static int command_inspect(const char *path)
{
    unsigned char *buf = NULL;
    const unsigned char *payload, *fp, *sig;
    size_t len = 0, payload_len = 0, sig_len = 0;
    uint64_t msg_len;
    sign_options_t options;
    if (read_file(path, &buf, &len, MAX_MESSAGE_BYTES) != 0) {
        fprintf(stderr, "Cannot read container.\n");
        return 1;
    }
    if (parse_key_container(buf, len, KEY_PUBLIC, &payload, &payload_len) == 0) {
        unsigned char fingerprint[32];
        public_fingerprint(fingerprint, payload);
        printf("Type: public key\nAlgorithm: %s\nKey bytes: %u\nFingerprint: ",
               slh_alg_id(PARAMS), (unsigned)payload_len);
        print_hex(fingerprint, sizeof(fingerprint));
        putchar('\n');
        clear_bytes(fingerprint, sizeof(fingerprint));
    } else if (parse_key_container(buf, len, KEY_PRIVATE_DPAPI,
                                   &payload, &payload_len) == 0) {
        printf("Type: DPAPI-protected private key\nAlgorithm: %s\n"
               "Encrypted payload: %u bytes\n",
               slh_alg_id(PARAMS), (unsigned)payload_len);
    } else if (parse_signature_container(buf, len, &options, &msg_len, &fp,
                                         &sig, &sig_len) == 0) {
        printf("Type: detached signature\nAlgorithm: %s\nMode: %s%s\n"
               "Context bytes: %u\nMessage bytes: %llu\nSignature bytes: %u\n"
               "Public-key fingerprint: ", slh_alg_id(PARAMS),
               options.mode == SIG_MODE_PURE ? "pure" : prehash_name(options.ph_id),
               options.deterministic ? ", deterministic" : ", hedged",
               (unsigned)options.context_len, (unsigned long long)msg_len,
               (unsigned)sig_len);
        print_hex(fp, 32);
        putchar('\n');
    } else {
        fprintf(stderr, "Unknown or damaged container.\n");
        free(buf);
        return 1;
    }
    clear_bytes(buf, len);
    free(buf);
    return 0;
}

static int command_pack_public(const char *raw_path,const char *path)
{
    unsigned char *raw=NULL,*container=NULL; size_t n=0,total=0; int rc=1;
    if(read_file(raw_path,&raw,&n,EXPECTED_PK_SIZE) || n!=EXPECTED_PK_SIZE) goto end;
    if(make_key_container(KEY_PUBLIC,raw,n,&container,&total) || write_new(path,container,total)) goto end;
    puts("PUBLIC CONTAINER PASS"); rc=0;
end: free(raw); free(container); return rc;
}

static int command_pack_signature(int argc,char **argv)
{
    unsigned char *raw=NULL,*msg=NULL,*container=NULL,pk[64],fp[32];
    size_t n=0,m=0,total=0; sign_options_t options; int rc=1;
    if(parse_sign_options(argc,argv,6,&options) || options.mode!=SIG_MODE_PURE) return 2;
    if(read_file(argv[2],&raw,&n,EXPECTED_SIG_SIZE) || n!=EXPECTED_SIG_SIZE ||
       load_public_key(argv[3],pk) || read_file(argv[4],&msg,&m,MAX_MESSAGE_BYTES)) goto end;
    // Independently verify the FPGA result BEFORE publishing a container.
    if(!check_signature(msg,m,raw,n,pk,&options)) { fputs("FPGA signature verification failed.\n",stderr); goto end; }
    public_fingerprint(fp,pk);
    if(make_signature_container(raw,n,m,fp,&options,&container,&total) || write_new(argv[5],container,total)) goto end;
    puts("FPGA SIGNATURE VERIFIED + CONTAINER PASS"); rc=0;
end: free(raw); free(msg); free(container); return rc;
}

static void usage(const char *program)
{
    fprintf(stderr,
        "SLH-DSA-SHAKE-256f FIPS 205 product prototype\n\n"
        "Usage:\n"
        "  %s info\n"
        "  %s selftest\n"
        "  %s thash-selftest\n"
        "  %s benchmark\n"
        "  %s keygen <public.slpk> <private.slsk>\n"
        "  %s sign <private.slsk> <message> <signature.slsig> [options]\n"
        "  %s verify <public.slpk> <message> <signature.slsig>\n"
        "  %s inspect <container>\n\n"
        "Signing options:\n"
        "  --context <text>           FIPS 205 context, max 255 bytes\n"
        "  --deterministic            Disable hedged signing randomness\n"
        "  --prehash SHAKE-256        HashSLH-DSA with SHAKE-256\n"
        "  --prehash SHA2-256         HashSLH-DSA with SHA2-256\n",
        program, program, program, program, program, program, program, program);
}

int main(int argc, char **argv)
{
    if(argc==3 && !strcmp(argv[1],"public-fingerprint")) {
        unsigned char pk[64],fp[32]; if(load_public_key(argv[2],pk)) return 1;
        public_fingerprint(fp,pk); print_hex(fp,32); puts(""); return 0;
    }
    if(argc==4 && !strcmp(argv[1],"pack-public")) return command_pack_public(argv[2],argv[3]);
    if(argc>=6 && !strcmp(argv[1],"pack-signature")) return command_pack_signature(argc,argv);
    if (argc == 2 && strcmp(argv[1], "info") == 0) {
        printf("Algorithm: %s\nStandard: FIPS 205\nPublic key: %u bytes\n"
               "Private key: %u bytes\nSignature: %u bytes\n"
               "Private storage: Windows DPAPI, current-user scope\n",
               slh_alg_id(PARAMS), (unsigned)slh_pk_sz(PARAMS),
               (unsigned)slh_sk_sz(PARAMS), (unsigned)slh_sig_sz(PARAMS));
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "selftest") == 0)
        return command_selftest();
    if (argc == 2 && strcmp(argv[1], "thash-selftest") == 0)
        return command_thash_selftest();
    if (argc == 2 && strcmp(argv[1], "benchmark") == 0)
        return command_benchmark();
    if (argc == 4 && strcmp(argv[1], "keygen") == 0)
        return command_keygen(argv[2], argv[3]);
    if (argc >= 5 && strcmp(argv[1], "sign") == 0)
        return command_sign(argc, argv);
    if (argc == 5 && strcmp(argv[1], "verify") == 0)
        return command_verify(argv[2], argv[3], argv[4]);
    if (argc == 3 && strcmp(argv[1], "inspect") == 0)
        return command_inspect(argv[2]);
    usage(argv[0]);
    return 2;
}
