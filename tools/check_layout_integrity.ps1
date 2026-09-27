$ErrorActionPreference='Stop'
$workspace=Split-Path $PSScriptRoot -Parent
$archive=Join-Path $workspace 'archive/reorganization_20260927'
$records=Get-Content -LiteralPath (Join-Path $archive 'moved_files_sha256.json') -Raw | ConvertFrom-Json
$mapping=@{}
foreach($record in $records) {
    $mapping[$record.From]=$record.To
    if((Get-FileHash -LiteralPath (Join-Path $workspace $record.To)).Hash -ne $record.SHA256) {
        throw "Moved source bytes changed: $($record.To)"
    }
}
$baseline=Get-Content -LiteralPath (Join-Path $archive 'before/hardware/soc/output_portable/release_manifest.json') -Raw | ConvertFrom-Json
$checked=0
foreach($entry in $baseline.Files) {
    if([IO.Path]::GetExtension($entry.Path) -notin @('.v','.sv','.c','.h','.S','.ld','.xdc','.bin','.bit','.dcp')) { continue }
    $path=if($mapping.ContainsKey($entry.Path)){$mapping[$entry.Path]}else{$entry.Path}
    if((Get-FileHash -LiteralPath (Join-Path $workspace $path)).Hash -ne $entry.SHA256) { throw "Accepted production bytes changed: $path" }
    $checked++
}
$projectDir=Join-Path $workspace 'hardware/soc/build_portable'
[xml]$project=Get-Content -LiteralPath (Join-Path $projectDir 'portable_slh_soc.xpr') -Raw
$fileCount=0
foreach($node in $project.SelectNodes('//File[@Path]')) {
    $path=$node.GetAttribute('Path').Replace('$PPRDIR',$projectDir)
    if($path.Contains('$') -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing/unresolved project file: $path" }
    $fileCount++
}
Write-Host "LAYOUT INTEGRITY PASS: $($records.Count) moved files byte-identical; $checked accepted code/artifacts byte-identical; $fileCount project paths exist."
