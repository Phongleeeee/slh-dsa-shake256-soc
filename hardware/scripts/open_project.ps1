param([string]$VivadoBin = 'D:\2025.1\Vivado\bin')
$project = Join-Path $PSScriptRoot '..\build\vivado\sphincs_shake256_vc707.xpr'
if (-not (Test-Path -LiteralPath $project)) {
    throw 'Project not found. Run build_all.ps1 first.'
}
& (Join-Path $VivadoBin 'vivado.bat') $project
