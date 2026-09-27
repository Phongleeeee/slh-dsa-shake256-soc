param()

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'build_acvp.cmd')
if ($LASTEXITCODE -ne 0) { throw 'ACVP bridge build failed' }
python (Join-Path $PSScriptRoot 'run_acvp_256f.py')
if ($LASTEXITCODE -ne 0) { throw 'NIST ACVP SLH-DSA-SHAKE-256f tests failed' }
