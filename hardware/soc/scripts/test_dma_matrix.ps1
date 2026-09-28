param([string]$VivadoBin='D:\2025.1\Vivado\bin')
$ErrorActionPreference='Stop'
$soc=Split-Path $PSScriptRoot -Parent
$root=Split-Path (Split-Path $soc -Parent) -Parent
$out=Join-Path $soc 'output_portable/dma_matrix_review'
New-Item -ItemType Directory -Force -Path $out | Out-Null
# Use the same behavioral AXI fixture as the original standalone regression.
# Production SoC AXI/XPM is exercised separately by test_soc.ps1.
$files=@(Get-Content (Join-Path $root 'hardware/manifests/soc_common.f') |
    Where-Object { $_ -match '^hardware/rtl/(dma|iommu)/' } |
    ForEach-Object { Join-Path $root $_ })
$files+=Get-ChildItem (Join-Path $root 'hardware/rtl/axi/test_models') -Filter '*.v' | ForEach-Object FullName
$files+=Join-Path $soc 'sim/dma/tb_dma_mmu_axi_top.sv'
$files+=Join-Path $soc 'sim/tb_dma_matrix_review.sv'
$files+=Join-Path $soc 'sim/tb_dma_fifo_review.sv'
Push-Location $out
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --sv $files
    if($LASTEXITCODE) { throw 'DMA matrix compile failed' }
    & (Join-Path $VivadoBin 'xelab.bat') tb_dma_matrix_review -s dma_matrix_review
    if($LASTEXITCODE) { throw 'DMA matrix elaboration failed' }
    $lines=& (Join-Path $VivadoBin 'xsim.bat') dma_matrix_review -runall -log dma_matrix_review.log 2>&1
    $lines | ForEach-Object { Write-Host $_ }
    if($LASTEXITCODE -or ($lines -join "`n") -match '(?m)^(Fatal:|Error:|ERROR)' -or
       ($lines -join "`n") -notmatch 'DMA MATRIX REVIEW TEST PASSED') { throw 'DMA matrix regression failed' }
    & (Join-Path $VivadoBin 'xelab.bat') tb_dma_fifo_review -s dma_fifo_review
    if($LASTEXITCODE) { throw 'DMA FIFO model elaboration failed' }
    $lines=& (Join-Path $VivadoBin 'xsim.bat') dma_fifo_review -runall -log dma_fifo_review.log 2>&1
    $lines | ForEach-Object { Write-Host $_ }
    if($LASTEXITCODE -or ($lines -join "`n") -match '(?m)^(Fatal:|Error:|ERROR)' -or
       ($lines -join "`n") -notmatch 'DMA FIFO REVIEW TEST PASSED') { throw 'DMA FIFO model failed' }
} finally { Pop-Location }
