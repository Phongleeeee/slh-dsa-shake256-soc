param([string]$VivadoBin = 'D:\2025.1\Vivado\bin')

$ErrorActionPreference = 'Stop'
$signer = Join-Path $PSScriptRoot 'software\sphincs_signer'
$hardware = Join-Path $PSScriptRoot 'hardware'

Write-Host '=== BUILD SOFTWARE: FIPS 205 SLH-DSA-SHAKE-256f ==='
& (Join-Path $signer 'build.cmd') fips205
if ($LASTEXITCODE -ne 0) { throw 'Software build failed' }
& (Join-Path $signer 'build\slh_dsa_shake_256f.exe') selftest
if ($LASTEXITCODE -ne 0) { throw 'Software self-test failed' }
& (Join-Path $signer 'build\slh_dsa_shake_256f.exe') thash-selftest
if ($LASTEXITCODE -ne 0) { throw 'C/RTL thash cross-check failed' }
& (Join-Path $signer 'test_cli.ps1')
if ($LASTEXITCODE -ne 0) { throw 'File signing workflow failed' }
& (Join-Path $signer 'test_acvp.ps1')
if ($LASTEXITCODE -ne 0) { throw 'NIST ACVP validation-vector tests failed' }
& powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File (Join-Path $signer 'slh_dsa_gui.ps1') -SmokeTest
if ($LASTEXITCODE -ne 0) { throw 'Windows/FPGA GUI construction smoke test failed' }

Write-Host '=== BUILD PORTABLE SOC: VC707, INTERNAL RAM ==='
& (Join-Path $hardware 'soc\scripts\build_portable_soc.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Hardware build failed' }
& (Join-Path $hardware 'soc\scripts\test_soc.ps1')
if ($LASTEXITCODE -ne 0) { throw 'SoC regression failed' }
& (Join-Path $hardware 'soc\scripts\test_portable_dma.ps1')
if ($LASTEXITCODE -ne 0) { throw 'DMA/IOMMU robustness regression failed' }
& (Join-Path $hardware 'soc\scripts\build_service_native.cmd')
if ($LASTEXITCODE -ne 0) { throw 'Native service engine build failed' }
& (Join-Path $hardware 'soc\output_portable\service_native\service_native.exe')
if ($LASTEXITCODE -ne 0) { throw 'Native service engine regression failed' }
& (Join-Path $hardware 'soc\scripts\test_service_interop.ps1')
& (Join-Path $hardware 'soc\scripts\test_review.ps1') -SkipSocRegression
Write-Host '=== SOFTWARE + RTL/TIMING + NATIVE INTEROP TESTS PASSED ==='
Write-Host 'Real-board keygen/sign/verify and benchmark still require test_fpga_board.ps1 -Port <COM>. No board/TRNG certification is implied.'
