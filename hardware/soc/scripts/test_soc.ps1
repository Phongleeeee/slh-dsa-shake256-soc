param([string[]]$Top)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$socDir = Split-Path -Parent $scriptDir
$rootDir = Split-Path -Parent (Split-Path -Parent $socDir)
$simDir = Join-Path $socDir 'output_portable\sim_regression'
New-Item -ItemType Directory -Force -Path $simDir | Out-Null

$xvlog = 'D:\2025.1\Vivado\bin\xvlog.bat'
$xelab = 'D:\2025.1\Vivado\bin\xelab.bat'
$xsim  = 'D:\2025.1\Vivado\bin\xsim.bat'
$files = @(Get-Content -LiteralPath (Join-Path $rootDir 'hardware/manifests/soc_common.f') |
    Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') } |
    ForEach-Object { Join-Path $rootDir $_.Trim() })
$files += @(
    (Join-Path $socDir 'sim\tb_dma_axi_mem_router.v'),
    (Join-Path $socDir 'sim\tb_axi_slh_peripherals.v'),
    (Join-Path $socDir 'sim\tb_picorv32_slh_soc.v'),
    (Join-Path $socDir 'sim\tb_portable_slh_firmware.v'),
    (Join-Path $socDir 'sim\tb_slh_dma_stream.v'),
    (Join-Path $socDir 'sim\tb_slh_dma_stream_review.v'),
    (Join-Path $socDir 'sim\tb_iommu_secure.v'),
    (Join-Path $socDir 'sim\tb_portable_service_boot.v'),
    (Join-Path $socDir 'sim\tb_portable_service_uart.v')
)

Push-Location $simDir
try {
    python (Join-Path $scriptDir 'gen_hash_review_vectors.py') (Join-Path $simDir 'review_hash_vectors.mem')
    if ($LASTEXITCODE -ne 0) { throw 'Independent hash vector generation failed.' }
    & $xvlog --sv -d FMAX_FANOUT $files
    if ($LASTEXITCODE -ne 0) { throw 'SoC RTL compilation failed.' }
    $tops = if ($Top) { $Top } else { @('tb_dma_axi_mem_router', 'tb_axi_slh_peripherals', 'tb_picorv32_slh_soc', 'tb_portable_slh_firmware', 'tb_slh_dma_stream', 'tb_slh_dma_stream_review', 'tb_iommu_secure', 'tb_portable_service_boot', 'tb_portable_service_uart') }
    foreach ($testTop in $tops) {
        $snapshot = "${testTop}_sim"
        & $xelab $testTop -s $snapshot
        if ($LASTEXITCODE -ne 0) { throw "SoC elaboration failed: $testTop" }
        $simOutput = & $xsim $snapshot -runall -log "${testTop}.log" 2>&1
        $simOutput | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0 -or ($simOutput -join "`n") -match 'Fatal:') {
            throw "Mo phong $testTop that bai."
        }
        if (($simOutput -join "`n") -notmatch 'TEST PASSED') {
            throw "Mo phong $testTop khong in ket qua TEST PASSED."
        }
    }
} finally {
    Pop-Location
}
