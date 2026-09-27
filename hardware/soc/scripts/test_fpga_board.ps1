param([Parameter(Mandatory=$true)][string]$Port,[ValidateRange(0,2)][int]$Mode=1,
      [string]$OutputDirectory='', [switch]$Benchmark)
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$hostScript=Join-Path $root 'software\sphincs_signer\fpga_host.ps1'
$signer=Join-Path $root 'software\sphincs_signer\build\slh_dsa_shake_256f.exe'
if(-not $OutputDirectory) { $OutputDirectory=Join-Path $root ('hardware\soc\output_portable\board_tests\'+[Guid]::NewGuid().ToString('N')) }
if(Test-Path -LiteralPath $OutputDirectory) { throw 'Choose a NEW output directory; existing files are never overwritten.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
Start-Transcript -Path (Join-Path $OutputDirectory 'board_acceptance.log') | Out-Null
try {
    Write-Host 'This test REPLACES the volatile key on the FPGA. Existing .slkh handles stop working.'
    $pk=Join-Path $OutputDirectory 'fpga.slpk'; $handle=Join-Path $OutputDirectory 'fpga.slkh'
    $msg=Join-Path $OutputDirectory 'message.txt'; $sig=Join-Path $OutputDirectory 'fpga.slsig'
    [IO.File]::WriteAllBytes($msg,[Text.Encoding]::UTF8.GetBytes('FPGA board acceptance: SLH-DSA-SHAKE-256f message.'))
    & $hostScript -Port $Port -Action keygen -Mode $Mode -PublicPath $pk -HandlePath $handle
    & $hostScript -Port $Port -Action sign -Mode $Mode -PublicPath $pk -HandlePath $handle -MessagePath $msg -SignaturePath $sig
    & $signer verify $pk $msg $sig; if($LASTEXITCODE -ne 0) { throw 'FPGA->Windows verification failed' }
    & $hostScript -Port $Port -Action verify -Mode $Mode -PublicPath $pk -MessagePath $msg -SignaturePath $sig
    $bad=Join-Path $OutputDirectory 'modified.txt'; $data=[IO.File]::ReadAllBytes($msg); $data[0]=$data[0] -bxor 1; [IO.File]::WriteAllBytes($bad,$data)
    $rejected=$false
    try { & $hostScript -Port $Port -Action verify -Mode $Mode -PublicPath $pk -MessagePath $bad -SignaturePath $sig }
    catch { if($_.Exception.Message -match 'INVALID SIGNATURE') { $rejected=$true } else { throw } }
    if(-not $rejected) { throw 'Modified message accepted' }
    foreach($kind in @('signature','context')) {
        $badSig=Join-Path $OutputDirectory ("modified-$kind.slsig")
        $data=[IO.File]::ReadAllBytes($sig)
        $index=if($kind -eq 'signature'){$data.Length-1}else{64}
        $data[$index]=$data[$index] -bxor 1; [IO.File]::WriteAllBytes($badSig,$data)
        $rejected=$false
        try { & $hostScript -Port $Port -Action verify -Mode $Mode -PublicPath $pk -MessagePath $msg -SignaturePath $badSig }
        catch { if($_.Exception.Message -match 'INVALID SIGNATURE') { $rejected=$true } else { throw } }
        if(-not $rejected) { throw "Modified $kind accepted" }
    }
    $pcPk=Join-Path $OutputDirectory 'windows.slpk'; $pcSk=Join-Path $OutputDirectory 'windows.slsk'; $pcSig=Join-Path $OutputDirectory 'windows.slsig'
    & $signer keygen $pcPk $pcSk; if($LASTEXITCODE -ne 0) { throw 'Windows keygen failed' }
    & $signer sign $pcSk $msg $pcSig --context DO-AN-VC707; if($LASTEXITCODE -ne 0) { throw 'Windows sign failed' }
    & $hostScript -Port $Port -Action verify -Mode $Mode -PublicPath $pcPk -MessagePath $msg -SignaturePath $pcSig
    # Change the container fingerprint to the other key, so rejection exercises
    # FPGA cryptographic verification rather than just the host metadata check.
    $wrongKeySig=Join-Path $OutputDirectory 'wrong-key.slsig'; $data=[IO.File]::ReadAllBytes($sig)
    $fingerprint=(& $signer public-fingerprint $pcPk | Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $fingerprint.Length -ne 64) { throw 'Fingerprint helper failed' }
    for($i=0;$i -lt 32;$i++) { $data[26+$i]=[Convert]::ToByte($fingerprint.Substring(2*$i,2),16) }
    [IO.File]::WriteAllBytes($wrongKeySig,$data); $rejected=$false
    try { & $hostScript -Port $Port -Action verify -Mode $Mode -PublicPath $pcPk -MessagePath $msg -SignaturePath $wrongKeySig }
    catch { if($_.Exception.Message -match 'INVALID SIGNATURE') { $rejected=$true } else { throw } }
    if(-not $rejected) { throw 'Wrong public key accepted' }
    if($Benchmark) { & $hostScript -Port $Port -Action benchmark -HandlePath $handle -PublicPath $pk -MessagePath $msg -CsvPath (Join-Path $OutputDirectory 'benchmark.csv') }
    & $hostScript -Port $Port -Action zeroize
    & $hostScript -Port $Port -Action info
    Write-Host 'BOARD KEYGEN/SIGN/VERIFY + WINDOWS INTEROP + MESSAGE/SIGNATURE/CONTEXT/WRONG-KEY TESTS PASSED'
    Write-Host "Evidence: $OutputDirectory"
} finally { Stop-Transcript | Out-Null }
