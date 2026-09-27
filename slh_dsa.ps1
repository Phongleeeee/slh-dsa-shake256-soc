param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArguments
)

$ErrorActionPreference = 'Stop'
$signer = Join-Path $PSScriptRoot 'software\sphincs_signer'
$app = Join-Path $signer 'build\slh_dsa_shake_256f.exe'
if (-not (Test-Path -LiteralPath $app)) {
    & (Join-Path $signer 'build.cmd') fips205
    if ($LASTEXITCODE -ne 0) { throw 'FIPS 205 signer build failed' }
}
& $app @CliArguments
exit $LASTEXITCODE
