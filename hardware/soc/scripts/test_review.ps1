param([switch]$SkipSocRegression,[switch]$VerifyNistProvenance)
$ErrorActionPreference='Stop'
$soc=Split-Path $PSScriptRoot -Parent
$root=Split-Path (Split-Path $soc -Parent) -Parent
$signer=Join-Path $root 'software/sphincs_signer'
& (Join-Path $PSScriptRoot 'build_service_review.cmd')
if($LASTEXITCODE) { throw 'Review DLL build failed' }
python (Join-Path $PSScriptRoot 'test_service_review.py')
if($LASTEXITCODE) { throw 'Service boundary/state/fault regression failed' }
foreach($mode in 0..2) {
    python (Join-Path $signer 'run_acvp_256f.py') --dll (Join-Path $soc 'output_portable/review_native/service_review.dll') --mode $mode
    if($LASTEXITCODE) { throw "Native ACVP hook mode $mode failed" }
}
python (Join-Path $signer 'test_container_review.py')
if($LASTEXITCODE) { throw 'Container mutation regression failed' }
& (Join-Path $signer 'test_write_failure.cmd')
if($LASTEXITCODE) { throw 'Exclusive file-write cleanup failed' }
& (Join-Path $PSScriptRoot 'test_scheduler_review.ps1')
& (Join-Path $PSScriptRoot 'test_dma_matrix.ps1')
if($VerifyNistProvenance) {
    python (Join-Path $signer 'verify_acvp_sources.py')
    if($LASTEXITCODE) { throw 'Pinned NIST fixture identity check failed' }
}
if(-not $SkipSocRegression) {
    & (Join-Path $PSScriptRoot 'test_soc.ps1')
    & (Join-Path $PSScriptRoot 'test_portable_dma.ps1')
}
Write-Host 'EXTENDED SOFTWARE/RTL REVIEW PASSED; physical-board acceptance is separate.'
