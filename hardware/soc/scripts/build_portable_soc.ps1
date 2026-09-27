param([double]$ClockMHz = 296.296296, [switch]$ReuseSynthesis,
      [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$ExperimentName)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ReuseSynthesis) {
    & (Join-Path $scriptDir 'build_slh_firmware.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Firmware compilation failed.' }
}
$priorClock = $env:PORTABLE_SOC_MHZ
$priorReuse = $env:PORTABLE_SOC_REUSE_SYNTH
$priorExperiment = $env:PORTABLE_SOC_EXPERIMENT
try {
    $env:PORTABLE_SOC_MHZ = [string]$ClockMHz
    $env:PORTABLE_SOC_REUSE_SYNTH = if ($ReuseSynthesis) { '1' } else { '0' }
    $env:PORTABLE_SOC_EXPERIMENT = $ExperimentName
    $buildLog = if ($ExperimentName) {
        Join-Path $scriptDir "..\output_portable\experiments\$ExperimentName\portable_build.log"
    } else { Join-Path $scriptDir '..\output_portable\portable_build.log' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $buildLog) | Out-Null
    & 'D:\2025.1\Vivado\bin\vivado.bat' -mode batch -log $buildLog -nojournal -notrace -source (Join-Path $scriptDir 'build_portable_soc.tcl')
    if ($LASTEXITCODE -ne 0) { throw 'Portable implementation failed. Check timing reports.' }
} finally {
    $env:PORTABLE_SOC_MHZ = $priorClock
    $env:PORTABLE_SOC_REUSE_SYNTH = $priorReuse
    $env:PORTABLE_SOC_EXPERIMENT = $priorExperiment
}
