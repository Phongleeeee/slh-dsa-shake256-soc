# Inventory only. Run after final build/review; this does not approve a release.
param([switch]$Replace)
$ErrorActionPreference='Stop'
$socDir=Split-Path $PSScriptRoot -Parent
$rootDir=Split-Path (Split-Path $socDir -Parent) -Parent
$projectDir=Join-Path $socDir 'build_portable'
$manifestPath=Join-Path $socDir 'output_portable/release_manifest.json'
if((Test-Path -LiteralPath $manifestPath) -and -not $Replace) {
    throw 'Manifest exists. Recheck the build before explicitly using -Replace.'
}
[xml]$project=Get-Content -LiteralPath (Join-Path $projectDir 'portable_slh_soc.xpr') -Raw
$paths=@()
foreach($set in $project.Project.FileSets.FileSet) {
    if($set.Name -in @('sources_1','constrs_1')) {
        foreach($file in $set.File) {
            $paths += [IO.Path]::GetFullPath(([string]$file.Path).Replace('$PPRDIR',$projectDir))
        }
    }
}
# Source inventory includes the algorithm library and host, not user keys/data.
foreach($relative in @('hardware/soc/firmware','hardware/soc/scripts','hardware/soc/sim',
        'hardware/soc/sim/dma','hardware/scripts','hardware/manifests','tools',
        'third_party/slhdsa-c','software/sphincs_signer')) {
    $paths += Get-ChildItem -LiteralPath (Join-Path $rootDir $relative) -File |
        Where-Object Extension -in @('.c','.h','.S','.ld','.cs','.ps1','.cmd','.v','.sv','.tcl','.py','.f') |
        ForEach-Object FullName
}
$paths += Get-ChildItem -LiteralPath (Join-Path $rootDir 'hardware/rtl/axi/test_models') -File -Filter '*.v' | ForEach-Object FullName
$paths += Join-Path $rootDir 'hardware/rtl/cpu/tools/makehex.py'
foreach($relative in @('firmware/slh_dsa_portable.bin','firmware/slh_dsa_portable.elf',
        'output_portable/portable_slh_soc_vc707.bit','output_portable/portable_soc_routed.dcp',
        'output_portable/timing_summary.rpt','output_portable/utilization.rpt',
        'output_portable/critical_paths.rpt','output_portable/ip_timing/summary.csv',
        'output_portable/drc.rpt','output_portable/bitstream_drc.rpt','output_portable/methodology.rpt',
        'output_portable/dma_audit_20260928_soc_final.log',
        'output_portable/dma_audit_20260928_baseline_final.log',
        'output_portable/dma_audit_20260928_review_final.log',
        'output_portable/dma_audit_20260928_shake_final.log',
        'output_portable/dma_audit_20260928_build.log',
        'output_portable/dma_audit_20260928_artifact_check.log',
        'output_portable/dma_audit_20260928_project_promote.log',
        'output_portable/dma_matrix_review/dma_matrix_review.log',
        'output_portable/dma_matrix_review/dma_fifo_review.log',
        'output_portable/dma_matrix_review/matrix_cases.csv',
        'output_portable/review_acvp_provenance.json')) {
    $paths += Join-Path $socDir $relative
}
$paths += Join-Path $rootDir 'software/sphincs_signer/build/slh_dsa_shake_256f.exe'
$entries=@(foreach($path in ($paths | Sort-Object -Unique)) {
    $item=Get-Item -LiteralPath $path
    if(-not $item.FullName.StartsWith($rootDir+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Inventory path outside workspace: $path"
    }
    [ordered]@{Path=$item.FullName.Substring($rootDir.Length+1).Replace('\','/');
        Bytes=$item.Length;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
})
$manifest=[ordered]@{Format='SLH-REVIEW-INVENTORY-1';CreatedUtc=[DateTime]::UtcNow.ToString('o');
    Scope='Source/artifact identity only; not a signed release, board test or certification.';Files=$entries}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Host "SOURCE/ARTIFACT INVENTORY WRITTEN: $($entries.Count) files"
