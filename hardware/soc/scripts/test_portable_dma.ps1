$ErrorActionPreference = 'Stop'
$socDir = Split-Path -Parent $PSScriptRoot
$rootDir = Split-Path -Parent (Split-Path -Parent $socDir)
$outDir = Join-Path $socDir 'output_portable\dma_regression'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$files = @(
    'hardware/rtl/iommu/pseudoLRU.sv',
    'hardware/rtl/iommu/dma_iommu_tlb.sv',
    'hardware/rtl/dma/dma_descriptor_fifo.sv',
    'hardware/rtl/dma/dma_completion_fifo.sv',
    'hardware/rtl/dma/dma_access_controller.sv',
    'hardware/rtl/dma/dma_axil_regs.sv',
    'hardware/rtl/dma/dma_axi_scheduler.sv',
    'hardware/rtl/dma/axi_cdma.v',
    'hardware/rtl/dma/axi_dma_rd.v',
    'hardware/rtl/dma/axi_dma_wr.v',
    'hardware/rtl/axi/test_models/priority_encoder.v',
    'hardware/rtl/axi/test_models/arbiter.v',
    'hardware/rtl/axi/test_models/axi_register_wr.v',
    'hardware/rtl/axi/test_models/axi_register_rd.v',
    'hardware/rtl/axi/test_models/axi_crossbar_addr.v',
    'hardware/rtl/axi/test_models/axi_crossbar_wr.v',
    'hardware/rtl/axi/test_models/axi_crossbar_rd.v',
    'hardware/rtl/axi/test_models/axi_crossbar.v',
    'hardware/rtl/axi/test_models/axi_ram.v',
    'hardware/rtl/dma/dma_mmu_axi_top.sv'
) | ForEach-Object { Join-Path $rootDir $_ }
$files += Join-Path $socDir 'sim/dma/tb_dma_mmu_axi_top.sv'
$files += Join-Path $socDir 'sim/tb_portable_dma_regression.sv'
Push-Location $outDir
try {
    & 'D:\2025.1\Vivado\bin\xvlog.bat' --sv $files
    if ($LASTEXITCODE -ne 0) { throw 'DMA compile failed.' }
    & 'D:\2025.1\Vivado\bin\xelab.bat' tb_portable_dma_regression -s portable_dma_regression
    if ($LASTEXITCODE -ne 0) { throw 'DMA elaboration failed.' }
    $result = & 'D:\2025.1\Vivado\bin\xsim.bat' portable_dma_regression -runall -log dma_regression.log 2>&1
    $result | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or ($result -join "`n") -match 'Fatal:' -or
        ($result -join "`n") -notmatch 'PORTABLE DMA/IOMMU ROBUSTNESS TEST PASSED') {
        throw 'DMA robustness regression failed.'
    }
} finally { Pop-Location }
