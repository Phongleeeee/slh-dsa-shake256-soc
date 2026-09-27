$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir 'build_firmware.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$vivado = 'D:\2025.1\Vivado\bin\vivado.bat'
if (-not (Test-Path $vivado)) {
    $found = Get-Command vivado -ErrorAction SilentlyContinue
    if (-not $found) { throw 'Khong tim thay Vivado. Hay sua duong dan trong build_soc.ps1.' }
    $vivado = $found.Source
}
& $vivado -mode batch -source (Join-Path $scriptDir 'build_soc.tcl')
exit $LASTEXITCODE

