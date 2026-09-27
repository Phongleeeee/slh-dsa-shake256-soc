param([string]$VivadoBin = 'D:\2025.1\Vivado\bin')
$project = Join-Path $PSScriptRoot 'hardware\soc\build_portable\portable_slh_soc.xpr'
if (-not (Test-Path -LiteralPath $project)) {
    throw 'Chay hardware\soc\scripts\build_portable_soc.ps1 truoc.'
}
Start-Process -FilePath (Join-Path $VivadoBin 'vivado.bat') -ArgumentList ('"' + $project + '"') -WindowStyle Hidden
