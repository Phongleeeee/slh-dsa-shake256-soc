param(
    [ValidateSet('info','keygen','sign','verify','zeroize','benchmark')][string]$Action='info',
    [string]$Port='', [int]$Baud=115200, [string]$PublicPath='',
    [string]$HandlePath='', [string]$MessagePath='', [string]$SignaturePath='',
    [string]$Context='DO-AN-VC707', [ValidateRange(0,2)][int]$Mode=1,
    [string]$CsvPath='', [string]$MockExecutable='',
    # Regression-only borrowed native transport. Never accepts a real COM client.
    [object]$NativeTestClient=$null
)
$ErrorActionPreference='Stop'
if (-not ('SlhFpgaClient' -as [type])) {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $fpgaReferences=@(Get-ChildItem -LiteralPath (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
        $fpgaReferences += [System.IO.Ports.SerialPort].Assembly.Location
        Add-Type -Path (Join-Path $PSScriptRoot 'SlhFpgaClient.cs') -ReferencedAssemblies $fpgaReferences
    } else { Add-Type -Path (Join-Path $PSScriptRoot 'SlhFpgaClient.cs') }
}
$signer=Join-Path $PSScriptRoot 'build\slh_dsa_shake_256f.exe'
function Write-Exclusive([string]$Path,[byte[]]$Bytes) {
    $f=[IO.File]::Open([IO.Path]::GetFullPath($Path),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $f.Write($Bytes,0,$Bytes.Length) } finally { $f.Dispose() }
}
function Invoke-Pack([string[]]$Command) {
    $result=& $signer @Command 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($result | Out-String) }
    $result | ForEach-Object { Write-Host $_ }
}
function Read-LimitedFile([string]$Path,[int]$Limit) {
    $f=[IO.File]::OpenRead($Path)
    try {
        if($f.Length -gt $Limit) { throw "File vuot gioi han $Limit byte." }
        $b=New-Object byte[] ([int]$f.Length); $offset=0
        while($offset -lt $b.Length) {
            $n=$f.Read($b,$offset,$b.Length-$offset)
            if($n -le 0) { throw 'File bi cat ngan trong khi doc.' }
            $offset+=$n
        }
        return ,$b
    } finally { $f.Dispose() }
}
function Read-Public([string]$Path) {
    $b=Read-LimitedFile $Path 96
    if ($b.Length -ne 96 -or [Text.Encoding]::ASCII.GetString($b,0,8) -ne 'SLHKEY01' -or
        $b[8] -ne 1 -or $b[9] -ne 1 -or $b[10] -ne 1 -or $b[11] -ne 0 -or [SlhFpgaClient]::U32($b,12) -ne 64) { throw 'Khong phai public key .slpk hop le.' }
    foreach($i in 16..31) { if($b[$i] -ne 0) { throw 'Public key v1: reserved bytes phai bang 0.' } }
    return ,([byte[]]$b[32..95])
}
function Stats-Object([string]$Operation,[double]$HostMs) {
    $s=$client.Stats()
    [pscustomobject]@{Backend=$(if($client.IsMock){'NATIVE_TEST_NOT_FPGA'}else{'FPGA'});
        Operation=$Operation;Mode=[SlhFpgaClient]::U32($s,4);ClockHz=$clockHz;
        Cycles=[SlhFpgaClient]::U64($s,8);CryptoMs=1000.0*[SlhFpgaClient]::U64($s,8)/$clockHz;
        HostRoundtripMs=$HostMs;F=[SlhFpgaClient]::U32($s,16);H=[SlhFpgaClient]::U32($s,20);
        PRF=[SlhFpgaClient]::U32($s,24);DMAHashes=[SlhFpgaClient]::U32($s,28);
        Failures=[SlhFpgaClient]::U32($s,32);SoftwareCalls=[SlhFpgaClient]::U32($s,36)}
}
$client=$null
$fpgaTemp=Join-Path ([IO.Path]::GetTempPath()) ('slh-public-' + [Guid]::NewGuid().ToString('N'))
try {
    if($NativeTestClient) {
        if($NativeTestClient -isnot [SlhFpgaClient] -or -not $NativeTestClient.IsMock -or $Port -or $MockExecutable) {
            throw 'NativeTestClient accepts only an explicit native-test transport, without Port/MockExecutable.'
        }
        $client=$NativeTestClient
    }
    elseif($MockExecutable) { $client=[SlhFpgaClient]::new([IO.Path]::GetFullPath($MockExecutable)) }
    else {
        if(-not $Port) { throw 'Can chon cong COM cua FPGA. Khong tu chuyen sang ky bang CPU Windows.' }
        $client=[SlhFpgaClient]::new($Port,$Baud)
    }
    $info=$client.Info(); $clockHz=[SlhFpgaClient]::U32($info,4)
    $backendLabel=if($client.IsMock){'NATIVE TEST, NOT FPGA'}else{'FPGA'}
    if($client.IsMock) { Write-Host 'CANH BAO: native test backend, KHONG PHAI FPGA.' }
    else { Write-Host ('FPGA clock: {0:N3} MHz' -f ($clockHz/1e6)) }
    if($Action -eq 'info') {
        Write-Host 'SLH3 service | pure mode | message <=16 KiB | key volatile | trusted UART | no board TRNG'
        Write-Host ('Key state: '+$(if([SlhFpgaClient]::U32($info,20)){'LOADED (RAM only)'}else{'EMPTY - keygen required for signing'}))
        return
    }
    if($Action -eq 'zeroize') { $client.Zeroize(); Write-Host 'KEY/DATA ZEROIZE PASS'; return }
    $client.SetMode([uint32]$Mode)
    if($Action -eq 'keygen') {
        if(-not $PublicPath -or -not $HandlePath) { throw 'Can PublicPath (.slpk) va HandlePath (.slkh).' }
        if([IO.Path]::GetFullPath($PublicPath) -eq [IO.Path]::GetFullPath($HandlePath) -or
           (Test-Path -LiteralPath $PublicPath) -or (Test-Path -LiteralPath $HandlePath)) { throw 'Khong ghi de file cu. Hay chon hai ten file moi khac nhau.' }
        $watch=[Diagnostics.Stopwatch]::StartNew(); $pk=$client.Keygen(); $watch.Stop()
        New-Item -ItemType Directory -Path $fpgaTemp | Out-Null
        $raw=Join-Path $fpgaTemp 'public.raw'; Write-Exclusive $raw $pk
        Invoke-Pack @('pack-public',$raw,$PublicPath)
        $handle=[ordered]@{Format='SLH-FPGA-HANDLE-1';Algorithm='SLH-DSA-SHAKE-256f';
            Volatile=$true;PublicKeyBase64=[Convert]::ToBase64String($pk);PublicPath=[IO.Path]::GetFullPath($PublicPath);
            Backend=$(if($client.IsMock){'NATIVE_TEST_NOT_FPGA'}else{'FPGA'});
            Note='No private key in this file. Key lost on reset, malformed/incomplete UART frame, key replacement or zeroize; not on ordinary idle.'}
        Write-Exclusive $HandlePath ([Text.Encoding]::UTF8.GetBytes(($handle | ConvertTo-Json)))
        Stats-Object 'keygen' $watch.Elapsed.TotalMilliseconds; Write-Host 'KEYGEN PASS: .slpk + .slkh; khong tao .slsk.'; return
    }
    if(-not $MessagePath) { throw 'Can MessagePath.' }
    $messageInfo=Get-Item -LiteralPath $MessagePath
    if($messageInfo.PSIsContainer -or $messageInfo.Length -gt 16384) { throw 'FPGA pure mode: file can ky toi da 16 KiB. File lon can HashSLH streaming, chua ho tro tren firmware nay.' }
    $message=Read-LimitedFile $MessagePath 16384
    $contextBytes=[Text.Encoding]::UTF8.GetBytes($Context)
    if($Action -ne 'verify' -and $contextBytes.Length -gt 255) { throw 'Context UTF-8 toi da 255 byte.' }
    if($Action -eq 'verify') {
        $pk=Read-Public $PublicPath; $container=Read-LimitedFile $SignaturePath (64+255+49856)
        if($container.Length -lt 64 -or [Text.Encoding]::ASCII.GetString($container,0,8) -ne 'SLHSIG01' -or
            $container[8] -ne 1 -or $container[9] -ne 1 -or $container[10] -ne 0 -or $container[11] -gt 1 -or $container[13] -ne 0 -or
            [SlhFpgaClient]::U32($container,14) -ne 49856 -or $container.Length -ne 64+$container[12]+49856 -or
            [SlhFpgaClient]::U64($container,18) -ne $message.Length) { throw 'Container khong hop le/khong ho tro: FPGA hien chi pure SLH-DSA.' }
        foreach($i in 58..63) { if($container[$i] -ne 0) { throw 'Signature v1: reserved bytes phai bang 0.' } }
        $contextBytes=New-Object byte[] $container[12]
        $expectedFingerprint=(& $signer public-fingerprint $PublicPath | Out-String).Trim()
        if($LASTEXITCODE -ne 0 -or $expectedFingerprint -ne ([BitConverter]::ToString($container,26,32) -replace '-','').ToLowerInvariant()) {
            throw 'INVALID SIGNATURE (container/public-key fingerprint mismatch)'
        }
        [Array]::Copy($container,64,$contextBytes,0,$contextBytes.Length)
        $signature=New-Object byte[] 49856; [Array]::Copy($container,64+$contextBytes.Length,$signature,0,49856)
        $client.UploadMessage($message,$contextBytes); $watch=[Diagnostics.Stopwatch]::StartNew()
        $valid=$client.Verify($pk,$signature); $watch.Stop(); Stats-Object 'verify' $watch.Elapsed.TotalMilliseconds
        if(-not $valid) { throw "INVALID SIGNATURE ($backendLabel)" }; Write-Host "VALID SIGNATURE ($backendLabel)"; return
    }
    if(-not $HandlePath) { throw 'Can HandlePath (.slkh).' }
    $handle=Get-Content -LiteralPath $HandlePath -Raw | ConvertFrom-Json
    if($handle.Format -ne 'SLH-FPGA-HANDLE-1' -or $handle.Backend -ne $(if($client.IsMock){'NATIVE_TEST_NOT_FPGA'}else{'FPGA'})) { throw 'Sai hardware handle/backend.' }
    $expected=[Convert]::FromBase64String($handle.PublicKeyBase64)
    try { $pk=$client.PublicKey() } catch { throw "FPGA khong con khoa hop le. Board da reset/zeroize: hay tao cap khoa moi. $($_.Exception.Message)" }
    if([Convert]::ToBase64String($pk) -ne [Convert]::ToBase64String($expected)) { throw 'Khoa tren FPGA khong khop handle. Board da reset/tao khoa moi; can tao cap khoa moi.' }
    if(-not $PublicPath) { $PublicPath=$handle.PublicPath }
    $selected=Read-Public $PublicPath
    if([Convert]::ToBase64String($selected) -ne [Convert]::ToBase64String($pk)) { throw 'Sai file khoa cong khai.' }
    if($Action -eq 'benchmark') {
        if(-not $CsvPath -or (Test-Path -LiteralPath $CsvPath)) { throw 'Can CsvPath moi, khong ghi de.' }
        $rows=@()
        $benchmarkRandomness=[SlhFpgaClient]::Random(32); $firstSignature=$null
        try {
        foreach($benchMode in 0..2) {
            $client.SetMode([uint32]$benchMode); $client.UploadMessage($message,$contextBytes)
            $watch=[Diagnostics.Stopwatch]::StartNew(); $sig=$client.SignWithRandomness($benchmarkRandomness); $watch.Stop()
            if($null -eq $firstSignature) { $firstSignature=[Convert]::ToBase64String($sig) }
            elseif([Convert]::ToBase64String($sig) -ne $firstSignature) { throw 'CPU/AXI/DMA signatures differ with identical inputs; benchmark rejected.' }
            $rows+=Stats-Object 'sign' $watch.Elapsed.TotalMilliseconds
            $watch.Restart(); $ok=$client.Verify($pk,$sig); $watch.Stop()
            if(-not $ok) { throw 'Benchmark verify failed' }; $rows+=Stats-Object 'verify' $watch.Elapsed.TotalMilliseconds
        }
        } finally { [Array]::Clear($benchmarkRandomness,0,$benchmarkRandomness.Length) }
        Write-Exclusive $CsvPath ([Text.Encoding]::UTF8.GetBytes((($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n")))
        $rows; return
    }
    if(-not $SignaturePath -or (Test-Path -LiteralPath $SignaturePath)) { throw 'Can ten SignaturePath moi; khong ghi de chu ky cu.' }
    $client.UploadMessage($message,$contextBytes); $watch=[Diagnostics.Stopwatch]::StartNew()
    $signature=$client.Sign(); $watch.Stop(); Stats-Object 'sign' $watch.Elapsed.TotalMilliseconds
    New-Item -ItemType Directory -Path $fpgaTemp | Out-Null
    $raw=Join-Path $fpgaTemp 'signature.raw'; Write-Exclusive $raw $signature
    $contextHex=([BitConverter]::ToString($contextBytes) -replace '-','').ToLowerInvariant()
    Invoke-Pack @('pack-signature',$raw,$PublicPath,$MessagePath,$SignaturePath,'--context-hex',$contextHex)
    Write-Host "SIGN PASS: $backendLabel result independently verified on Windows."
} finally {
    if($client -and -not $NativeTestClient) { $client.Dispose() }
    # This exact GUID directory contains only public key/signature temporary files.
    if(Test-Path -LiteralPath $fpgaTemp) {
        $resolvedFpgaTemp=[IO.Path]::GetFullPath($fpgaTemp)
        $resolvedFpgaTempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if(-not $resolvedFpgaTemp.StartsWith($resolvedFpgaTempBase,[StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolvedFpgaTemp) -notmatch '^slh-public-[0-9a-f]{32}$') { throw 'Unsafe temporary cleanup path' }
        Remove-Item -LiteralPath $resolvedFpgaTemp -Recurse -Force
    }
}
