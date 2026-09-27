$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$socDir = Split-Path -Parent $scriptDir
$rootDir = Split-Path -Parent (Split-Path -Parent $socDir)
$fwDir = Join-Path $socDir 'firmware'

$gcc = Get-Command riscv32-unknown-elf-gcc -ErrorAction SilentlyContinue
if (-not $gcc) { $gcc = Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue }

if (-not $gcc) {
    Write-Host 'Khong tim thay RISC-V GCC; dang tao boot KAT RV32I bang Python.'
    python (Join-Path $fwDir 'gen_soc_boot.py')
    exit $LASTEXITCODE
}

$prefix = $gcc.Source -replace 'gcc(\.exe)?$', ''
$objcopy = "${prefix}objcopy.exe"
if (-not (Test-Path $objcopy)) { $objcopy = "${prefix}objcopy" }
$elf = Join-Path $fwDir 'soc_firmware.elf'
$bin = Join-Path $fwDir 'soc_firmware.bin'
$mem = Join-Path $fwDir 'soc_boot.mem'
$linkerFlag = "-Wl,-T,$(Join-Path $fwDir 'link.ld')"

$gccArgs = @(
    '-march=rv32i', '-mabi=ilp32', '-Os', '-ffreestanding', '-fno-builtin',
    '-nostdlib', '-Wl,--gc-sections', $linkerFlag,
    (Join-Path $fwDir 'start.S'), (Join-Path $fwDir 'main.c'), '-o', $elf
)
& $gcc.Source @gccArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $objcopy -O binary $elf $bin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python (Join-Path $rootDir 'hardware\rtl\cpu\tools\makehex.py') $bin 16384 | Set-Content -Encoding ascii $mem
Write-Host "Da tao firmware: $mem"
