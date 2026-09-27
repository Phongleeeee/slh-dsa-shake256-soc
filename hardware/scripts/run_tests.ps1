param([string]$VivadoBin = 'D:\2025.1\Vivado\bin')

$ErrorActionPreference = 'Stop'
$hw = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sim = Join-Path $hw 'sim'
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'
$vivadoRoot = Split-Path (Split-Path $VivadoBin -Parent) -Parent
$glbl = Join-Path $vivadoRoot 'data\verilog\src\glbl.v'
foreach ($path in @($xvlog, $xelab, $xsim, $glbl)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing Vivado file: $path" }
}

Push-Location $sim
try {
    python gen_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Vector generation failed' }
    $sources = @(
        '..\rtl\sphincs_shake256\keccak_round.v',
        '..\rtl\sphincs_shake256\keccak_f1600.v',
        '..\rtl\sphincs_shake256\shake256_block_engine.v',
        '..\rtl\sphincs_shake256\spx_thash_shake256_simple_256.v',
        '..\rtl\sphincs_shake256\slh_dsa_shake_axi_lite.v',
        '..\boards\vc707\rtl\vc707_sphincs_shake256_selftest.v',
        'tb_shake256_block_engine.v',
        'tb_spx_thash_shake256_simple_256.v',
        'tb_slh_dsa_shake_axi_lite.v',
        'tb_vc707_sphincs_shake256_selftest.v',
        $glbl
    )
    & $xvlog @sources
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }

    & $xelab -debug typical tb_shake256_block_engine -s organized_shake_tb
    if ($LASTEXITCODE -ne 0) { throw 'SHAKE elaboration failed' }
    & $xsim organized_shake_tb -runall | Tee-Object -Variable shakeLog
    if ($LASTEXITCODE -ne 0 -or -not (($shakeLog -join "`n") -match 'ALL SHAKE256 REGRESSIONS PASSED')) {
        throw 'SHAKE regression failed'
    }

    & $xelab -debug typical tb_spx_thash_shake256_simple_256 -s organized_thash_tb
    if ($LASTEXITCODE -ne 0) { throw 'thash elaboration failed' }
    & $xsim organized_thash_tb -runall | Tee-Object -Variable thashLog
    if ($LASTEXITCODE -ne 0 -or -not (($thashLog -join "`n") -match 'ALL SPHINCS\+ THASH TESTS PASSED')) {
        throw 'thash regression failed'
    }

    & $xelab -debug typical tb_slh_dsa_shake_axi_lite -s organized_axi_ip_tb
    if ($LASTEXITCODE -ne 0) { throw 'AXI IP elaboration failed' }
    & $xsim organized_axi_ip_tb -runall | Tee-Object -Variable axiLog
    if ($LASTEXITCODE -ne 0 -or -not (($axiLog -join "`n") -match 'AXI SLH-DSA SHAKE IP SECURITY/PROTOCOL TESTS PASSED')) {
        throw 'AXI IP regression failed'
    }

    & $xelab -L unisims_ver -debug typical tb_vc707_sphincs_shake256_selftest glbl -s organized_board_tb
    if ($LASTEXITCODE -ne 0) { throw 'board elaboration failed' }
    & $xsim organized_board_tb -runall | Tee-Object -Variable boardLog
    if ($LASTEXITCODE -ne 0 -or -not (($boardLog -join "`n") -match 'FIRMWARE SELFTEST PASSED')) {
        throw 'board firmware regression failed'
    }
    Write-Host 'ALL ORGANIZED HARDWARE TESTS PASSED (SHAKE, THASH, AXI IP, BOARD)'
} finally {
    Pop-Location
}
