param(
    [string]$BootMem = "",
    [string]$BitstreamName = "picorv32_slh_dma_ddr_vc707.bit"
)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$socDir = Split-Path -Parent $scriptDir
$rootDir = (Resolve-Path (Join-Path $socDir '..\..')).Path

if ([string]::IsNullOrWhiteSpace($BootMem)) {
    $BootMem = Join-Path $socDir 'firmware\soc_boot.mem'
}
$env:SOC_BOOT_MEM = (Resolve-Path $BootMem).Path
$env:SOC_BITSTREAM_NAME = $BitstreamName
try {
    $vivado = 'D:\2025.1\Vivado\bin\vivado.bat'
    if (-not (Test-Path $vivado)) {
        $found = Get-Command vivado -ErrorAction SilentlyContinue
        if (-not $found) { throw 'Khong tim thay Vivado trong PATH hoac D:\2025.1\Vivado\bin.' }
        $vivado = $found.Source
    }
    & $vivado -mode batch -source (Join-Path $scriptDir 'build_soc_ddr.tcl')
    if ($LASTEXITCODE -ne 0) { throw "Vivado DDR build failed with code $LASTEXITCODE" }
} finally {
    Remove-Item Env:SOC_BOOT_MEM -ErrorAction SilentlyContinue
    Remove-Item Env:SOC_BITSTREAM_NAME -ErrorAction SilentlyContinue
}
