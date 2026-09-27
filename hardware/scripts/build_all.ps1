param([string]$VivadoBin = 'D:\2025.1\Vivado\bin')

$ErrorActionPreference = 'Stop'
$vivado = Join-Path $VivadoBin 'vivado.bat'
if (-not (Test-Path -LiteralPath $vivado)) { throw "Missing Vivado: $vivado" }
& (Join-Path $PSScriptRoot 'run_tests.ps1') -VivadoBin $VivadoBin
if ($LASTEXITCODE -ne 0) { throw 'Hardware tests failed' }
& $vivado -mode batch -nolog -nojournal -notrace -source (Join-Path $PSScriptRoot 'create_project.tcl')
if ($LASTEXITCODE -ne 0) { throw 'Project creation failed' }
& $vivado -mode batch -nolog -nojournal -notrace -source (Join-Path $PSScriptRoot 'build_bitstream.tcl')
if ($LASTEXITCODE -ne 0) { throw 'Bitstream build failed' }
& (Join-Path $PSScriptRoot 'build_ip.ps1') -VivadoBin $VivadoBin
if ($LASTEXITCODE -ne 0) { throw 'Reusable IP build failed' }
Write-Host 'BUILD COMPLETE: firmware bitstream + packaged AXI4-Lite IP'
