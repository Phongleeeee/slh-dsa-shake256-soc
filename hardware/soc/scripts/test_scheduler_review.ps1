$ErrorActionPreference='Stop'
$soc=Split-Path $PSScriptRoot -Parent
$root=Split-Path (Split-Path $soc -Parent) -Parent
$out=Join-Path $soc 'output_portable/review_scheduler'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Push-Location $out
try {
    & 'D:\2025.1\Vivado\bin\xvlog.bat' --sv (Join-Path $root 'hardware/rtl/dma/dma_axi_scheduler.sv') (Join-Path $root 'hardware/rtl/iommu/pseudoLRU.sv') (Join-Path $root 'hardware/rtl/iommu/dma_iommu_tlb.sv') (Join-Path $soc 'sim/tb_dma_scheduler_review.sv') (Join-Path $soc 'sim/tb_iommu_range_review.sv') (Join-Path $soc 'sim/tb_iommu_maintenance_review.sv')
    if($LASTEXITCODE) { throw 'Scheduler review compile failed' }
    & 'D:\2025.1\Vivado\bin\xelab.bat' tb_dma_scheduler_review -s scheduler_review
    if($LASTEXITCODE) { throw 'Scheduler review elaborate failed' }
    $lines=& 'D:\2025.1\Vivado\bin\xsim.bat' scheduler_review -runall -log scheduler_review.log 2>&1
    $lines | ForEach-Object { Write-Host $_ }
    if($LASTEXITCODE -or ($lines -join "`n") -match 'Fatal:' -or ($lines -join "`n") -notmatch 'DMA SCHEDULER REVIEW TEST PASSED') { throw 'Scheduler model mismatch' }
    & 'D:\2025.1\Vivado\bin\xelab.bat' tb_iommu_range_review -s iommu_range_review
    if($LASTEXITCODE) { throw 'IOMMU review elaborate failed' }
    $lines=& 'D:\2025.1\Vivado\bin\xsim.bat' iommu_range_review -runall -log iommu_range_review.log 2>&1
    $lines | ForEach-Object { Write-Host $_ }
    if($LASTEXITCODE -or ($lines -join "`n") -match 'Fatal:' -or ($lines -join "`n") -notmatch 'IOMMU RANGE REVIEW TEST PASSED') { throw 'IOMMU range model mismatch' }
    & 'D:\2025.1\Vivado\bin\xelab.bat' tb_iommu_maintenance_review -s iommu_maintenance_review
    if($LASTEXITCODE) { throw 'Maintenance review elaborate failed' }
    $lines=& 'D:\2025.1\Vivado\bin\xsim.bat' iommu_maintenance_review -runall -log iommu_maintenance_review.log 2>&1
    $lines | ForEach-Object { Write-Host $_ }
    if($LASTEXITCODE -or ($lines -join "`n") -match 'Fatal:' -or ($lines -join "`n") -notmatch 'IOMMU MAINTENANCE REVIEW TEST PASSED') { throw 'IOMMU maintenance mismatch' }
} finally { Pop-Location }
