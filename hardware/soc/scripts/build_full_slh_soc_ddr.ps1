$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$socDir = Split-Path -Parent $scriptDir

& (Join-Path $scriptDir 'build_slh_firmware.ps1') -ExternalMemory
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $scriptDir 'build_soc_ddr.ps1') -BootMem (Join-Path $socDir 'firmware\slh_dsa_firmware.mem') -BitstreamName 'picorv32_full_slh_dsa_dma_ddr_vc707.bit'
exit $LASTEXITCODE
