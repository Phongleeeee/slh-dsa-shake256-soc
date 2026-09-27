param([double]$ClockMHz = 296.296296)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$socDir = Split-Path -Parent $scriptDir

& (Join-Path $scriptDir 'build_portable_soc.ps1') -ClockMHz $ClockMHz
exit $LASTEXITCODE
