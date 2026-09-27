"""Boundary/state/fault regression of the real service C engine on a native CPU.

The independent oracle DLL is the unaccelerated implementation already checked
against NIST ACVP. Hook modes here are emulated; RTL has a separate hashlib KAT.
No physical FPGA performance is measured by this program.
"""
import ctypes as C
import random
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
N = 49856
lib = C.CDLL(str(ROOT / 'hardware/soc/output_portable/review_native/service_review.dll'))
oracle = C.CDLL(str(ROOT / 'software/sphincs_signer/build/fips205/slh_acvp_bridge.dll'))
lib.slh_service_command.argtypes = [C.c_uint8, C.c_void_p, C.c_size_t, C.c_void_p, C.POINTER(C.c_size_t)]
lib.slh_service_command.restype = C.c_int
lib.slh_test_fail_next.argtypes = [C.c_uint]
oracle.acvp_keygen_internal.argtypes = [C.c_void_p] * 5
oracle.acvp_keygen_internal.restype = C.c_int
oracle.acvp_sign.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t, C.c_void_p,
                           C.c_void_p, C.c_size_t, C.c_void_p, C.c_int, C.c_char_p]
oracle.acvp_sign.restype = C.c_size_t
checks = 0
def check(ok, label):
    global checks
    if not ok:
        raise AssertionError(label)
    checks += 1

def u32(n): return struct.pack('<I', n)
def word(b): return struct.unpack('<I', b)[0]

def cmd(op, payload=b'', expected=0):
    # Check that even malformed commands never touch outside the response area.
    out = C.create_string_buffer(b'\xa5' * 1056, 1056)
    src = C.create_string_buffer(payload, max(1, len(payload)))
    size = C.c_size_t(0xdead)
    rc = lib.slh_service_command(op, src, len(payload), C.byref(out, 16), C.byref(size))
    check(out.raw[:16] == b'\xa5' * 16 and out.raw[-16:] == b'\xa5' * 16, f'output guards op={op}')
    check(size.value <= 1024 and (not rc or size.value == 0), f'output length op={op}')
    if expected is not None:
        check(rc == expected, f'op={op}, length={len(payload)}, status={rc}, expected={expected}')
    return rc, out.raw[16:16+size.value]

def upload_message(msg, ctx, rng):
    cmd(3, u32(len(msg)) + bytes([len(ctx)]) + ctx)
    offset = 0
    while offset < len(msg):
        n = min(len(msg)-offset, rng.choice([1, 3, 135, 136, 137, 511, 512, 1020]))
        cmd(4, u32(offset) + msg[offset:offset+n])
        offset += n

def upload_sig(sig, rng):
    cmd(8, u32(N))
    offset = 0
    while offset < len(sig):
        n = min(len(sig)-offset, rng.choice([31, 511, 1020]))
        cmd(9, u32(offset) + sig[offset:offset+n])
        offset += n

def read_sig():
    return b''.join(cmd(6, u32(i)+u32(min(1024, N-i)))[1] for i in range(0, N, 1024))

def main():
    rng = random.Random(0x534c4833)
    lib.slh_service_init()
    # Isolated empty-state calls, including truncated lengths and unsigned offsets.
    for i in range(5000):
        op = rng.randrange(1, 256)
        length = rng.choice([0, 1, 3, 4, 5, 8, 31, 32, 63, 64, 95, 97, 260, 1024, 1025])
        payload = rng.randbytes(length)
        rc, _ = cmd(op, payload, None)
        check(0 <= rc <= 5, 'status enumeration')
    lib.slh_service_init()
    cmd(10, expected=2)
    cmd(5, bytes([1])*32, 2)
    cmd(7, bytes(64), 2)
    cmd(6, bytes(8), 2)
    cmd(2, bytes(96), 3)
    cmd(12, u32(3), 1)
    cmd(3, u32(16385)+b'\0', 5)
    cmd(3, u32(1)+b'\xff', 1)
    cmd(8, u32(N-1), 1)
    print('PASS: 5000 seeded malformed/state commands, bounds and output guards', flush=True)

    seed = rng.randbytes(96)
    sk = C.create_string_buffer(128)
    ref_pk = C.create_string_buffer(64)
    check(oracle.acvp_keygen_internal(sk, ref_pk, seed[:32], seed[32:64], seed[64:]) == 0, 'oracle keygen')
    cases = [(0,0), (1,1), (31,0), (32,11), (63,32), (64,255),
             (135,0), (136,1), (137,255), (255,11), (256,0),
             (511,1), (512,255), (513,32), (4095,11), (4096,0),
             (4097,255), (16383,1), (16384,255)]
    messages = [(rng.randbytes(a), rng.randbytes(b), rng.randbytes(32)) for a,b in cases]
    reference = []
    for msg,ctx,rnd in messages:
        sig = C.create_string_buffer(N)
        check(oracle.acvp_sign(sig,msg,len(msg),sk,ctx,len(ctx),rnd,1,None) == N, 'reference signature')
        reference.append(sig.raw)
    for mode in range(3):
        lib.slh_service_init()
        cmd(12, u32(mode))
        _, pk = cmd(2, seed)
        check(pk == ref_pk.raw, 'keygen byte equality')
        cmd(2, seed, 3)
        for ix, ((msg,ctx,rnd), expected_sig) in enumerate(zip(messages,reference)):
            upload_message(msg,ctx,rng)
            check(cmd(5,rnd)[1] == u32(N), 'signature size')
            sig = read_sig()
            check(sig == expected_sig, f'byte-equal signature mode={mode}, case={ix}')
            check(cmd(7,pk)[1] == u32(1), 'valid verify')
            # Mutations across R, FORS, WOTS+, auth path, and final byte.
            for pos in [0, 31, 32, 11199, 11200, N-1] if ix in (0,18) else [N-1]:
                bad = bytearray(sig); bad[pos] ^= 1
                upload_sig(bad,rng)
                check(cmd(7,pk)[1] == u32(0), f'signature corruption at {pos}')
            upload_sig(sig,rng)
            badpk = bytearray(pk); badpk[(ix*7)%64] ^= 1
            check(cmd(7,bytes(badpk))[1] == u32(0), 'wrong public key')
            cmd(6,u32(0xffffffff)+u32(1),5)
            cmd(6,u32(N)+u32(1),5)
            cmd(6,u32(0)+u32(1025),5)
            check(cmd(6,u32(N)+u32(0))[1] == b'', 'end-exclusive zero read')
        print(f'PASS: mode={mode}, 19 message/context boundaries, exact signatures and negative verify', flush=True)

    # Incomplete upload, restart, and zeroization must invalidate prior results.
    upload_message(b'abc',b'',rng)
    cmd(8,u32(N)); cmd(9,u32(1)+b'x',5); cmd(7,pk,2)
    cmd(9,u32(0)+b'x'); cmd(9,u32(0)+b'y',5); cmd(7,pk,2)
    cmd(3,u32(2)+b'\0'); cmd(4,u32(0)+b'a'); cmd(5,b'\x01'*32,2)
    cmd(4,u32(1)+b'bc',5); cmd(4,u32(0xffffffff),5)
    cmd(4,u32(1)+b'b'); cmd(5,bytes(32),3)

    # Force fallback in each crypto operation. Reporting success is forbidden.
    cmd(12,u32(2)); lib.slh_test_fail_next(1); cmd(5,b'\x01'*32,4)
    cmd(6,u32(0)+u32(32),2)
    check(word(cmd(13)[1][32:36]) == 1, 'failed-sign metric')
    cmd(5,b'\x01'*32); lib.slh_test_fail_next(1); cmd(7,pk,4)
    check(word(cmd(13)[1][32:36]) == 1, 'failed-verify metric')
    lib.slh_test_fail_next(1); cmd(2,rng.randbytes(96),4); cmd(10,expected=2)
    cmd(11); cmd(10,expected=2); cmd(5,b'\x01'*32,2)
    cleared = cmd(13)[1]
    check(cleared[:4] == bytes(4) and cleared[8:] == bytes(32), 'zeroized metrics')
    print('PASS: incomplete transfers, rollover bounds, injected accelerator failures and zeroize', flush=True)

    # Historical stats must retain the mode which actually executed the job.
    cmd(12,u32(2)); cmd(2,rng.randbytes(96)); before=cmd(13)[1]
    cmd(12,u32(0)); after=cmd(13)[1]
    check(before == after, 'STATS changes its historical mode when MODE changes')
    print(f'SERVICE REVIEW PASSED: {checks} assertions; native/emulated hooks, NOT FPGA', flush=True)

if __name__ == '__main__':
    main()
