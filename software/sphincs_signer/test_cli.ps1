param()

$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot 'build\slh_dsa_shake_256f.exe'
if (-not (Test-Path -LiteralPath $app)) { throw 'Build first: .\build.cmd' }

$testRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testDir = Join-Path $testRoot ('slh-dsa-test-' + [guid]::NewGuid().ToString('N'))
$message = Join-Path $PSScriptRoot '..\..\docs\DE_TAI_SPHINCS_SHAKE256.md'
$differentMessage = Join-Path $PSScriptRoot '..\..\hardware\README.md'
$pk = Join-Path $testDir 'signer.slpk'
$sk = Join-Path $testDir 'signer.slsk'
$sig = Join-Path $testDir 'document.slsig'
$detSig = Join-Path $testDir 'document-deterministic.slsig'
$prehashSig = Join-Path $testDir 'document-prehash.slsig'

New-Item -ItemType Directory -Path $testDir | Out-Null
try {
    & $app info
    if ($LASTEXITCODE -ne 0) { throw 'info failed' }
    & $app selftest
    if ($LASTEXITCODE -ne 0) { throw 'selftest failed' }
    & $app thash-selftest
    if ($LASTEXITCODE -ne 0) { throw 'thash cross-check failed' }
    & $app keygen $pk $sk
    if ($LASTEXITCODE -ne 0) { throw 'keygen failed' }
    & $app inspect $pk
    if ($LASTEXITCODE -ne 0) { throw 'public-key inspect failed' }
    & $app inspect $sk
    if ($LASTEXITCODE -ne 0) { throw 'private-key inspect failed' }

    & $app sign $sk $message $sig --context 'SHAKE256-VC707-DEMO'
    if ($LASTEXITCODE -ne 0) { throw 'hedged sign failed' }
    & $app verify $pk $message $sig
    if ($LASTEXITCODE -ne 0) { throw 'valid hedged signature rejected' }
    & $app verify $pk $differentMessage $sig
    if ($LASTEXITCODE -eq 0) { throw 'wrong message accepted' }

    & $app sign $sk $message $detSig --context 'SHAKE256-VC707-DEMO' --deterministic
    if ($LASTEXITCODE -ne 0) { throw 'deterministic sign failed' }
    & $app verify $pk $message $detSig
    if ($LASTEXITCODE -ne 0) { throw 'valid deterministic signature rejected' }

    & $app sign $sk $message $prehashSig --context 'SHAKE256-VC707-DEMO' --prehash SHAKE-256
    if ($LASTEXITCODE -ne 0) { throw 'pre-hash sign failed' }
    & $app verify $pk $message $prehashSig
    if ($LASTEXITCODE -ne 0) { throw 'valid pre-hash signature rejected' }
    & $app inspect $prehashSig
    if ($LASTEXITCODE -ne 0) { throw 'signature inspect failed' }

    Write-Output 'FIPS 205 PRODUCT WORKFLOW PASS (pure hedged, pure deterministic, pre-hash)'
} finally {
    $resolved = [IO.Path]::GetFullPath($testDir)
    if (-not $resolved.StartsWith($testRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unsafe temporary path'
    }
    if (Test-Path -LiteralPath $resolved) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
exit 0
