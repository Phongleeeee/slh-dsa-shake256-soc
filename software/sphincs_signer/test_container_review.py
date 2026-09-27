"""Exercise actual Windows CLI containers with generated test-only keys.
All artifacts remain in a new review directory; no user key is read/modified.
"""
import random
import subprocess
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXE = ROOT / 'software/sphincs_signer/build/slh_dsa_shake_256f.exe'
OUT = ROOT / 'hardware/soc/output_portable/review_containers' / uuid.uuid4().hex
OUT.mkdir(parents=True)
checks = 0
failures = []
def run(args, okay=True, label=''):
    global checks
    p = subprocess.run([str(EXE), *map(str,args)], capture_output=True, timeout=30)
    checks += 1
    if (p.returncode == 0) != okay:
        failures.append(label or str(args[0]))
    return p

pk,sk,msg,sig = (OUT/n for n in ['test.slpk','test.slsk','message.bin','signature.slsig'])
msg.write_bytes(bytes(range(136)))
run(['keygen',pk,sk])
run(['sign',sk,msg,sig,'--context-hex','000102ff'])
run(['verify',pk,msg,sig])
original_sig=sig.read_bytes();original_pk=pk.read_bytes();original_sk=sk.read_bytes()
for name,options in [('det',['--deterministic']),('ph-shake',['--prehash','SHAKE-256']),('ph-sha2',['--prehash','SHA2-256'])]:
    target=OUT/(name+'.slsig')
    run(['sign',sk,msg,target,*options]);run(['verify',pk,msg,target])
# Existing output must be preserved even when sign/keygen fail.
run(['sign',sk,msg,sig],False,'signature overwrite')
run(['keygen',pk,sk],False,'key overwrite')
assert sig.read_bytes()==original_sig and pk.read_bytes()==original_pk and sk.read_bytes()==original_sk
bad=OUT/'mutated.slsig'
def reject_sig(data,label):
    bad.write_bytes(data);run(['verify',pk,msg,bad],False,label)
for size in [0,1,7,8,32,63,64,len(original_sig)-1]:
    reject_sig(original_sig[:size],f'truncation {size}')
reject_sig(original_sig+b'x','trailing byte')
for offset in [0,7,8,9,10,12,13,14,17,18,25,26,57,64,67]:
    b=bytearray(original_sig);b[offset]^=0x80
    reject_sig(b,f'signature header/context field {offset}')
# Unknown flag bits and reserved bytes must be rejected for container version 1.
for offset in [11,58,59,60,61,62,63]:
    b=bytearray(original_sig);b[offset]^=0x80
    reject_sig(b,f'unknown/reserved signature byte {offset}')
rng=random.Random(205)
for offset in [68,99,100,len(original_sig)-1]+[rng.randrange(68,len(original_sig)) for _ in range(64)]:
    b=bytearray(original_sig);b[offset]^=1<<rng.randrange(8)
    reject_sig(b,f'cryptographic signature byte {offset}')
badpk=OUT/'mutated.slpk'
for offset in list(range(32))+[32,63,64,95]:
    b=bytearray(original_pk);b[offset]^=0x80;badpk.write_bytes(b)
    run(['verify',badpk,msg,sig],False,f'public key byte {offset}')
badsk=OUT/'mutated.slsk'
for offset in [11,16,31,32,len(original_sk)-1]:
    b=bytearray(original_sk);b[offset]^=0x80;badsk.write_bytes(b)
    # inspect validates the container; sign also checks the DPAPI blob.
    run(['sign',badsk,msg,OUT/f'forbidden-{offset}.slsig'],False,f'private key byte {offset}')
print(f'CONTAINER REVIEW: checks={checks}, failures={len(failures)}, artifacts={OUT}',flush=True)
if failures:
    print('FAILED:', '; '.join(failures),flush=True)
    raise SystemExit(1)
print('WINDOWS CONTAINER MUTATION/EXCLUSIVE WRITE/DPAPI REVIEW PASSED',flush=True)
