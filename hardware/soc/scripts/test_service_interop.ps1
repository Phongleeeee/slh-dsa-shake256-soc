$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$signer=Join-Path $root 'software\sphincs_signer\build\slh_dsa_shake_256f.exe'
$hostScript=Join-Path $root 'software\sphincs_signer\fpga_host.ps1'
$native=Join-Path $root 'hardware\soc\output_portable\service_native\service_native.exe'
& $hostScript -Action info -MockExecutable $native
$dir=Join-Path $root ('hardware\soc\output_portable\service_interop\'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir | Out-Null
function Save([string]$Name,[byte[]]$Data) { [IO.File]::WriteAllBytes((Join-Path $dir $Name),$Data) }
function Invoke-TestSigner([string[]]$Commands) { $lines=& $signer @Commands 2>&1; if($LASTEXITCODE -ne 0) { throw ($lines|Out-String) }; $lines|ForEach-Object { Write-Host $_ } }
$client=[SlhFpgaClient]::new($native)
try {
    $info=$client.Info(); if(-not $client.IsMock) { throw 'Expected native test' }
    $pk=$client.Keygen(); Save 'public.raw' $pk
    Invoke-TestSigner @('pack-public',(Join-Path $dir 'public.raw'),(Join-Path $dir 'native.slpk'))
    $message=[Text.Encoding]::UTF8.GetBytes('SLH service interoperability: message 0123456789')
    $ctx=[Text.Encoding]::UTF8.GetBytes('DO-AN-VC707')
    Save 'message.txt' $message
    foreach($mode in 0..2) {
        $client.SetMode([uint32]$mode); $client.UploadMessage($message,$ctx); $sig=$client.Sign()
        Save "signature-$mode.raw" $sig
        Invoke-TestSigner @('pack-signature',(Join-Path $dir "signature-$mode.raw"),(Join-Path $dir 'native.slpk'),
            (Join-Path $dir 'message.txt'),(Join-Path $dir "native-$mode.slsig"),'--context','DO-AN-VC707')
        Invoke-TestSigner @('verify',(Join-Path $dir 'native.slpk'),(Join-Path $dir 'message.txt'),(Join-Path $dir "native-$mode.slsig"))
        if(-not $client.Verify($pk,$sig)) { throw 'Native verify failed' }
        $badMsg=$message.Clone(); $badMsg[0]=$badMsg[0] -bxor 1
        $client.UploadMessage($badMsg,$ctx); if($client.Verify($pk,$sig)) { throw 'Modified message accepted' }
        $client.UploadMessage($message,[Text.Encoding]::UTF8.GetBytes('WRONG')); if($client.Verify($pk,$sig)) { throw 'Wrong context accepted' }
        $client.UploadMessage($message,$ctx); $sig[$sig.Length-1]=$sig[$sig.Length-1] -bxor 1
        if($client.Verify($pk,$sig)) { throw 'Modified signature accepted' }
    }
    Invoke-TestSigner @('keygen',(Join-Path $dir 'windows.slpk'),(Join-Path $dir 'windows.slsk'))
    Invoke-TestSigner @('sign',(Join-Path $dir 'windows.slsk'),(Join-Path $dir 'message.txt'),(Join-Path $dir 'windows.slsig'),'--context','DO-AN-VC707')
    $pcKey=[IO.File]::ReadAllBytes((Join-Path $dir 'windows.slpk'))
    $pcContainer=[IO.File]::ReadAllBytes((Join-Path $dir 'windows.slsig'))
    $pcSig=New-Object byte[] 49856; [Array]::Copy($pcContainer,64+$pcContainer[12],$pcSig,0,49856)
    $client.UploadMessage($message,$ctx)
    if(-not $client.Verify([byte[]]$pcKey[32..95],$pcSig)) { throw 'Windows->native service verify failed' }
    # Exercise the exact GUI host workflow, including containers, handles, UTF-8
    # context and CSV formatting, over a clearly marked persistent native client.
    $hostPk=Join-Path $dir 'host.slpk'; $hostHandle=Join-Path $dir 'host.slkh'; $hostSig=Join-Path $dir 'host.slsig'
    & $hostScript -NativeTestClient $client -Action keygen -PublicPath $hostPk -HandlePath $hostHandle -Mode 2
    & $hostScript -NativeTestClient $client -Action sign -PublicPath $hostPk -HandlePath $hostHandle -MessagePath (Join-Path $dir 'message.txt') -SignaturePath $hostSig -Context 'Đồ án VC707' -Mode 2
    Invoke-TestSigner @('verify',$hostPk,(Join-Path $dir 'message.txt'),$hostSig)
    & $hostScript -NativeTestClient $client -Action verify -PublicPath $hostPk -MessagePath (Join-Path $dir 'message.txt') -SignaturePath $hostSig -Mode 2
    foreach($kind in @('public-reserved','signature-reserved','signature-flags','oversized-signature')) {
        $badPk=$hostPk; $badSig=$hostSig
        if($kind -eq 'public-reserved') {
            $bytes=[IO.File]::ReadAllBytes($hostPk); $bytes[16]=1
            Save 'bad-public.slpk' $bytes; $badPk=Join-Path $dir 'bad-public.slpk'
        } else {
            $bytes=[IO.File]::ReadAllBytes($hostSig)
            if($kind -eq 'signature-reserved') { $bytes[58]=1 }
            elseif($kind -eq 'signature-flags') { $bytes[11]=128 }
            else { $bytes=New-Object byte[] 50176 }
            Save 'bad-signature.slsig' $bytes; $badSig=Join-Path $dir 'bad-signature.slsig'
        }
        $statsBefore=[Convert]::ToBase64String($client.Stats()); $rejected=$false
        try { & $hostScript -NativeTestClient $client -Action verify -PublicPath $badPk -MessagePath (Join-Path $dir 'message.txt') -SignaturePath $badSig -Mode 2 }
        catch { $rejected=$true }
        if(-not $rejected -or [Convert]::ToBase64String($client.Stats()) -ne $statsBefore) { throw "Host failed early rejection: $kind" }
    }
    $csv=Join-Path $dir 'native-only-benchmark.csv'
    & $hostScript -NativeTestClient $client -Action benchmark -PublicPath $hostPk -HandlePath $hostHandle -MessagePath (Join-Path $dir 'message.txt') -CsvPath $csv
    $rows=@(Import-Csv -LiteralPath $csv)
    if($rows.Count -ne 6 -or @($rows|Where-Object {$_.Backend -ne 'NATIVE_TEST_NOT_FPGA' -or [int]$_.Failures -ne 0}).Count) {
        throw 'Host benchmark CSV incorrectly labelled or failed'
    }
    $client.Zeroize(); $info=$client.Info(); if([SlhFpgaClient]::U32($info,20)) { throw 'Key retained after zeroize' }
    Write-Host 'NATIVE HOST/ENGINE/WINDOWS INTEROPERABILITY + NEGATIVE TESTS PASSED (NOT FPGA)'
    Write-Host "Artifacts: $dir"
} finally { $client.Dispose() }
