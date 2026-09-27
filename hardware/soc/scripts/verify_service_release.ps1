# Read-only identification of the accepted release, not a board/signature test.
$ErrorActionPreference='Stop'
$socDir=Split-Path $PSScriptRoot -Parent
$expected=@{
    'output_portable\portable_slh_soc_vc707.bit'='5A4A7141CE0CD8CCB08B63852720DEE289C95118EC46A67EBE46DBC95C2B6C6A'
    'firmware\slh_dsa_portable.bin'='0829A5F52211569E1B21972C3437082CBDB01935CEA8904A653749C2C0E7C2AD'
}
foreach($relative in $expected.Keys) {
    $actual=(Get-FileHash -LiteralPath (Join-Path $socDir $relative) -Algorithm SHA256).Hash
    if($actual -ne $expected[$relative]) { throw "Release changed: $relative. Rebuild/recheck and update acceptance; do not assume the old evidence covers it." }
    Write-Host "ACCEPTED HASH: $relative"
}
$manifestPath=Join-Path $socDir 'output_portable/release_manifest.json'
if(-not (Test-Path -LiteralPath $manifestPath)) { throw 'Missing reviewed source/artifact inventory.' }
if(Test-Path -LiteralPath $manifestPath) {
    $rootDir=Split-Path (Split-Path $socDir -Parent) -Parent
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if($manifest.Format -ne 'SLH-REVIEW-INVENTORY-1') { throw 'Unknown release inventory format.' }
    foreach($entry in $manifest.Files) {
        $path=[IO.Path]::GetFullPath((Join-Path $rootDir $entry.Path))
        if(-not $path.StartsWith($rootDir+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Release inventory path outside workspace.'
        }
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.SHA256) {
            throw "Reviewed source/artifact changed: $($entry.Path)"
        }
    }
    Write-Host "SOURCE/ARTIFACT INVENTORY MATCH: $($manifest.Files.Count) files"
}
$timing=Get-Content -LiteralPath (Join-Path $socDir 'output_portable\timing_summary.rpt') -Raw
$row=[regex]::Match($timing,'(?m)^\s+(?<wns>-?\d+\.\d+)\s+(?<tns>-?\d+\.\d+)\s+(?<setup>\d+)\s+\d+\s+(?<whs>-?\d+\.\d+)\s+(?<ths>-?\d+\.\d+)\s+(?<hold>\d+)\s+\d+')
if(-not $row.Success -or $timing -notmatch 'All user specified timing constraints are met' -or
   [double]::Parse($row.Groups['wns'].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0 -or
   [double]::Parse($row.Groups['whs'].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0 -or
   [int]$row.Groups['setup'].Value -ne 0 -or [int]$row.Groups['hold'].Value -ne 0) {
    throw 'Published timing report does not pass setup/hold.'
}
Write-Host "ACCEPTED RELEASE IDENTIFICATION PASS: 296.296296 MHz (setup at boundary), WNS=$($row.Groups['wns'].Value) ns, WHS=$($row.Groups['whs'].Value) ns"
Write-Host 'This is not FPGA keygen/sign/verify acceptance, entropy qualification or a cryptographic release signature.'
