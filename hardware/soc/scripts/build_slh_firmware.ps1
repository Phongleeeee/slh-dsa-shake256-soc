param([switch]$ExternalMemory, [switch]$Selftest)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$socDir = Split-Path -Parent $scriptDir
$rootDir = Split-Path -Parent (Split-Path -Parent $socDir)
$fwDir = Join-Path $socDir 'firmware'
$slhDir = Join-Path $rootDir 'third_party\slhdsa-c'

$gcc = Get-Command riscv32-unknown-elf-gcc -ErrorAction SilentlyContinue
if (-not $gcc) { $gcc = Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue }
if (-not $gcc) {
    $vivadoGcc = 'D:\2025.1\gnu\riscv\nt\riscv64-unknown-elf\bin\riscv64-unknown-elf-gcc.exe'
    if (Test-Path $vivadoGcc) { $gcc = Get-Item $vivadoGcc }
}
if (-not $gcc) {
    throw 'Can RISC-V GCC de build full SLH-DSA firmware (riscv32-unknown-elf-gcc). Boot DMA/SHAKE KAT van build duoc bang Python.'
}

$gccPath = if ($gcc.PSObject.Properties.Name -contains 'Source') {
    $gcc.Source
} else {
    $gcc.FullName
}
$prefix = $gccPath -replace 'gcc(\.exe)?$', ''
$objcopy = "${prefix}objcopy.exe"
if (-not (Test-Path $objcopy)) { $objcopy = "${prefix}objcopy" }
$stem = if ($ExternalMemory) { 'slh_dsa_firmware' }
        elseif ($Selftest) { 'slh_dsa_portable_selftest' }
        else { 'slh_dsa_portable' }
$elf = Join-Path $fwDir "$stem.elf"
$bin = Join-Path $fwDir "$stem.bin"
$mem = Join-Path $fwDir "$stem.mem"

$sources = @(
    (Join-Path $fwDir 'start.S'),
    (Join-Path $fwDir $(if ($Selftest -or $ExternalMemory) { 'main_slh_dsa.c' } else { 'main_slh_service.c' })),
    (Join-Path $fwDir 'slh_service.c'),
    (Join-Path $fwDir 'crypto_stack.S'),
    (Join-Path $fwDir 'slh_hw_accel.c'),
    (Join-Path $fwDir 'minilib.c'),
    (Join-Path $slhDir 'slh_dsa.c'),
    (Join-Path $slhDir 'slh_shake.c'),
    (Join-Path $slhDir 'sha3_api.c'),
    (Join-Path $slhDir 'sha3_f1600.c')
)
$compilerArgs = @(
    '-march=rv32i_zicsr', '-mabi=ilp32', '-O2', '-ffreestanding',
    '-fno-builtin', '-fdata-sections', '-ffunction-sections', '-nostdlib',
    '-DSLH_RV32_HW_ACCEL=1', "-I$fwDir", "-I$slhDir",
    "-Wl,-T,$(Join-Path $fwDir 'link_slh_dsa.ld')", '-Wl,--gc-sections',
    '-Wl,--build-id=none'
)
if ($ExternalMemory) { $compilerArgs += '-DSLH_USE_EXT_MEMORY=1' }
$compilerArgs += $sources + @('-lgcc', '-o', $elf)

& $gccPath @compilerArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $objcopy -O binary $elf $bin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ((Get-Item -LiteralPath $bin).Length -gt 65536) {
    throw 'Firmware binary exceeds the 64 KiB initialized RAM.'
}
python (Join-Path $rootDir 'hardware\rtl\cpu\tools\makehex.py') $bin 16384 |
    Set-Content -Encoding ascii $mem
if ($LASTEXITCODE -ne 0) { throw 'Firmware memory-image generation failed.' }
Write-Host "Da tao full SLH-DSA firmware: $mem"
