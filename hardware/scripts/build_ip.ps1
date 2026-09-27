param(
    [string]$VivadoBin = 'D:\2025.1\Vivado\bin',
    [double]$TargetMHz = 300.0
)

$ErrorActionPreference = 'Stop'
$vivado = Join-Path $VivadoBin 'vivado.bat'
if (-not (Test-Path -LiteralPath $vivado)) { throw "Missing Vivado: $vivado" }

& (Join-Path $PSScriptRoot 'package_ip.ps1') -VivadoBin $VivadoBin
if ($LASTEXITCODE -ne 0) { throw 'IP packaging failed' }
$oldPeriod = $env:SLH_IP_PERIOD_NS
try {
    $env:SLH_IP_PERIOD_NS = (1000.0 / $TargetMHz).ToString(
        '0.000000', [Globalization.CultureInfo]::InvariantCulture)
    & $vivado -mode batch -nolog -nojournal -notrace `
        -source (Join-Path $PSScriptRoot 'build_ip_ooc.tcl')
    if ($LASTEXITCODE -ne 0) { throw 'IP out-of-context implementation failed' }
} finally {
    $env:SLH_IP_PERIOD_NS = $oldPeriod
}
Write-Host "IP COMPLETE: packaged AXI4-Lite core passed $TargetMHz MHz implementation"
