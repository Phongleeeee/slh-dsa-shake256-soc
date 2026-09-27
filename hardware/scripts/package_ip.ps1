param([string]$VivadoBin = 'D:\2025.1\Vivado\bin')

$ErrorActionPreference = 'Stop'
$vivado = Join-Path $VivadoBin 'vivado.bat'
if (-not (Test-Path -LiteralPath $vivado)) { throw "Missing Vivado: $vivado" }
& $vivado -mode batch -nolog -nojournal -notrace `
    -source (Join-Path $PSScriptRoot 'package_ip.tcl')
if ($LASTEXITCODE -ne 0) { throw 'Vivado IP packaging failed' }
$component = Join-Path $PSScriptRoot '..\output\ip_repo\slh_dsa_shake_accel_2.0\component.xml'
if (-not (Test-Path -LiteralPath $component)) { throw 'component.xml not produced' }
Write-Host "PACKAGED IP: $component"
