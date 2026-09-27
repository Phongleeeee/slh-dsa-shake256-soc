#!/usr/bin/env python3
"""Run NIST ACVP v1.1.0.40 vectors for SLH-DSA-SHAKE-256f on Windows.

The upstream CLI harness cannot carry a 49,856-byte signature through the
Windows command-line limit. This runner calls the same implementation through
a tiny DLL bridge and tests the one parameter set used by this project.
"""
from __future__ import annotations

import ctypes
import argparse
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
UPSTREAM = (HERE / "../../third_party/slhdsa-c").resolve()
sys.path.insert(0, str(UPSTREAM / "test"))

import acvp_client  # type: ignore  # upstream loader, pinned dependency

VERSION = "v1.1.0.40"
ALGORITHM = "SLH-DSA-SHAKE-256f"
PK_SIZE = 64
SK_SIZE = 128
SIG_SIZE = 49856


def blob(data: bytes):
    if not data:
        return None
    return ctypes.create_string_buffer(data, len(data))


def as_bytes(value) -> bytes:
    if value is None or value == "":
        return b""
    return bytes.fromhex(value)


def is_prehash(test: dict) -> bool:
    value = test.get("preHash", False)
    if isinstance(value, bool):
        return value
    return str(value).lower() not in ("false", "pure", "")


def interface_mode(test: dict) -> int:
    if test.get("signatureInterface", "internal") == "internal":
        return 0
    return 2 if is_prehash(test) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dll', type=Path, default=HERE / "build/fips205/slh_acvp_bridge.dll")
    parser.add_argument('--mode', type=int, choices=(0, 1, 2), help='Native hook emulation only, NOT RTL/FPGA')
    args = parser.parse_args()
    dll_path = args.dll.resolve()
    if not dll_path.exists():
        print("Missing bridge DLL. Run build_acvp.cmd first.", file=sys.stderr)
        return 2
    os.chdir(UPSTREAM)
    if not acvp_client.download_acvp_files(VERSION):
        print("Unable to download NIST ACVP vectors.", file=sys.stderr)
        return 2

    data = UPSTREAM / f"test/.acvp-data/{VERSION}/files"
    keygen = acvp_client.slhdsa_load_keygen(
        data / "SLH-DSA-keyGen-FIPS205/prompt.json",
        data / "SLH-DSA-keyGen-FIPS205/expectedResults.json",
    )
    siggen = acvp_client.slhdsa_load_siggen(
        data / "SLH-DSA-sigGen-FIPS205/prompt.json",
        data / "SLH-DSA-sigGen-FIPS205/expectedResults.json",
    )
    sigver = acvp_client.slhdsa_load_sigver(
        data / "SLH-DSA-sigVer-FIPS205/prompt.json",
        data / "SLH-DSA-sigVer-FIPS205/expectedResults.json",
        data / "SLH-DSA-sigVer-FIPS205/internalProjection.json",
    )
    keygen = [t for t in keygen if t["parameterSet"] == ALGORITHM]
    siggen = [t for t in siggen if t["parameterSet"] == ALGORITHM]
    sigver = [t for t in sigver if t["parameterSet"] == ALGORITHM]

    lib = ctypes.CDLL(str(dll_path))
    if args.mode is not None:
        lib.slh_hw_set_mode.argtypes = [ctypes.c_uint]
        lib.slh_hw_set_mode(args.mode)
        print(f'ACVP scope: native accelerator-hook mode {args.mode}, NOT RTL/FPGA', flush=True)
    lib.acvp_keygen_internal.argtypes = [ctypes.c_void_p] * 5
    lib.acvp_keygen_internal.restype = ctypes.c_int
    lib.acvp_sign.argtypes = [
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
        ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p,
    ]
    lib.acvp_sign.restype = ctypes.c_size_t
    lib.acvp_verify.argtypes = [
        ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t,
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
        ctypes.c_int, ctypes.c_char_p,
    ]
    lib.acvp_verify.restype = ctypes.c_int

    passed = 0
    failed = []

    for t in keygen:
        sk_out = ctypes.create_string_buffer(SK_SIZE)
        pk_out = ctypes.create_string_buffer(PK_SIZE)
        rc = lib.acvp_keygen_internal(
            sk_out, pk_out, blob(as_bytes(t["skSeed"])),
            blob(as_bytes(t["skPrf"])), blob(as_bytes(t["pkSeed"])),
        )
        okay = (rc == 0 and sk_out.raw == as_bytes(t["sk"]) and
                pk_out.raw == as_bytes(t["pk"]))
        if okay:
            passed += 1
        else:
            failed.append(("keyGen", t["tcId"]))

    for t in siggen:
        msg = as_bytes(t["message"])
        sk = as_bytes(t["sk"])
        ctx = as_bytes(t.get("context"))
        addrnd = as_bytes(t.get("additionalRandomness"))
        mode = interface_mode(t)
        ph = t.get("hashAlg", "").encode() if mode == 2 else None
        out = ctypes.create_string_buffer(SIG_SIZE)
        n = lib.acvp_sign(out, blob(msg), len(msg), blob(sk), blob(ctx),
                          len(ctx), blob(addrnd), mode, ph)
        okay = n == SIG_SIZE and out.raw == as_bytes(t["signature"])
        if okay:
            passed += 1
        else:
            failed.append(("sigGen", t["tcId"]))

    for t in sigver:
        msg = as_bytes(t["message"])
        sig = as_bytes(t["signature"])
        pk = as_bytes(t["pk"])
        ctx = as_bytes(t.get("context"))
        mode = interface_mode(t)
        ph = t.get("hashAlg", "").encode() if mode == 2 else None
        actual = bool(lib.acvp_verify(blob(msg), len(msg), blob(sig), len(sig),
                                      blob(pk), blob(ctx), len(ctx), mode, ph))
        expected_value = t.get("testPassed", True)
        expected = (expected_value if isinstance(expected_value, bool)
                    else str(expected_value).lower() == "true")
        if actual == expected:
            passed += 1
        else:
            failed.append(("sigVer", t["tcId"]))

    total = len(keygen) + len(siggen) + len(sigver)
    print(f"NIST ACVP {VERSION} {ALGORITHM}: PASS={passed} FAIL={len(failed)} TOTAL={total}")
    if failed:
        print("First failures:", failed[:10], file=sys.stderr)
        return 1
    print("ACVP SLH-DSA-SHAKE-256f ALL TESTS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
