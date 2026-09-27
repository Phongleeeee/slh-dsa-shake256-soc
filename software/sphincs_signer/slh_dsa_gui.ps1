param(
    [string]$DemoFolder = '',
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Signer = Join-Path $PSScriptRoot 'build\slh_dsa_shake_256f.exe'
$script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Ensure-Signer {
    if (Test-Path -LiteralPath $script:Signer) { return $true }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Chua co file chuong trinh. Ban co muon build ngay khong?",
        'SLH-DSA-SHAKE-256f',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    $build = Join-Path $PSScriptRoot 'build.cmd'
    $output = & $build fips205 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $script:Signer)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Build that bai.`r`n`r`n$output",
            'Loi build',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }
    return $true
}

function Quote-ForLog([string]$Value) {
    if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
    return $Value
}

function Run-Signer([string[]]$Arguments) {
    if (-not (Ensure-Signer)) { return }

    $commandText = ($Arguments | ForEach-Object { Quote-ForLog $_ }) -join ' '
    $txtOutput.AppendText("`r`n> slh_dsa_shake_256f.exe $commandText`r`n")
    $form.UseWaitCursor = $true
    $statusLabel.Text = 'Dang xu ly...'
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $lines = & $script:Signer @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($null -ne $lines) {
            $txtOutput.AppendText(($lines | Out-String).TrimEnd() + "`r`n")
        }
        if ($exitCode -eq 0) {
            $statusLabel.Text = 'Hoan thanh thanh cong'
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        else {
            $statusLabel.Text = "That bai - ma loi $exitCode"
            $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        }
    }
    catch {
        $txtOutput.AppendText("LOI: $($_.Exception.Message)`r`n")
        $statusLabel.Text = 'Co loi khi chay chuong trinh'
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkRed
    }
    finally {
        $form.UseWaitCursor = $false
        $txtOutput.SelectionStart = $txtOutput.TextLength
        $txtOutput.ScrollToCaret()
    }
}

function Run-Fpga([hashtable]$Parameters) {
    if(-not $txtCom.Text.Trim()) { $txtOutput.AppendText("`r`nHay nhap cong COM cua FPGA.`r`n"); return }
    $Parameters['Port']=$txtCom.Text.Trim()
    $Parameters['Mode']=$cboHashMode.SelectedIndex
    $command=Join-Path $PSScriptRoot 'fpga_host.ps1'
    if($Parameters.Action -eq 'selftest') {
        $command=Join-Path $script:ProjectRoot 'hardware\soc\scripts\test_fpga_board.ps1'
        $Parameters.Remove('Action')
    }
    $worker=[PowerShell]::Create()
    [void]$worker.AddCommand($command)
    foreach($key in $Parameters.Keys) { [void]$worker.AddParameter($key,$Parameters[$key]) }
    $buttonPanel.Enabled=$false; $fpgaPanel.Enabled=$false; $cboBackend.Enabled=$false
    $form.UseWaitCursor=$true; $statusLabel.Text='FPGA dang xu ly...'
    $txtOutput.AppendText("`r`n> FPGA UART $($Parameters.Action) (khong fallback sang Windows)`r`n")
    try {
        $pending=$worker.BeginInvoke()
        while(-not $pending.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
        $lines=$worker.EndInvoke($pending)
        $worker.Streams.Information | ForEach-Object { $txtOutput.AppendText($_.MessageData.ToString()+"`r`n") }
        if($lines) { $txtOutput.AppendText(($lines|Out-String)) }
        if($worker.HadErrors) { throw ($worker.Streams.Error | Out-String) }
        $statusLabel.Text='FPGA hoan thanh'; $statusLabel.ForeColor=[Drawing.Color]::DarkGreen
    } catch {
        $txtOutput.AppendText("LOI FPGA: $($_.Exception.Message)`r`n")
        $statusLabel.Text='FPGA that bai'; $statusLabel.ForeColor=[Drawing.Color]::DarkRed
    } finally {
        $worker.Dispose(); $buttonPanel.Enabled=$true; $fpgaPanel.Enabled=$true; $cboBackend.Enabled=$true
        $form.UseWaitCursor=$false; $txtOutput.SelectionStart=$txtOutput.TextLength; $txtOutput.ScrollToCaret()
    }
}

function Pick-OpenFile([System.Windows.Forms.TextBox]$Target, [string]$Filter) {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = $Filter
    $dialog.CheckFileExists = $true
    if ($Target.Text -and (Test-Path -LiteralPath $Target.Text)) {
        $dialog.FileName = $Target.Text
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Target.Text = $dialog.FileName
    }
}

function Pick-SaveFile([System.Windows.Forms.TextBox]$Target, [string]$Filter, [string]$DefaultName) {
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = $Filter
    $dialog.FileName = $DefaultName
    $dialog.OverwritePrompt = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Target.Text = $dialog.FileName
        return $true
    }
    return $false
}

function Require-ExistingFile([System.Windows.Forms.TextBox]$Target, [string]$Description) {
    if (-not $Target.Text -or -not (Test-Path -LiteralPath $Target.Text -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Hay chon $Description hop le.",
            'Thieu du lieu',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }
    return $true
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'SLH-DSA-SHAKE-256f - Do an VC707'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(900, 680)
$form.MinimumSize = New-Object System.Drawing.Size(820, 620)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'BO KY SO HAU LUONG TU SLH-DSA-SHAKE-256f'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(22, 15)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'FIPS 205 | Public key 64 B | Private key 128 B | Signature 49,856 B'
$subtitle.AutoSize = $true
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.Location = New-Object System.Drawing.Point(25, 50)
$form.Controls.Add($subtitle)

function Add-FileRow([int]$Y, [string]$LabelText, [ref]$TextBoxRef, [scriptblock]$BrowseAction) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $LabelText
    $label.Location = New-Object System.Drawing.Point(25, $Y)
    $label.Size = New-Object System.Drawing.Size(130, 26)
    $form.Controls.Add($label)
    if($Y -eq 170) { $script:PrivateFileLabel=$label }

    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(155, ($Y - 3))
    $box.Size = New-Object System.Drawing.Size(625, 27)
    $box.Anchor = 'Top,Left,Right'
    $form.Controls.Add($box)
    $TextBoxRef.Value = $box

    $button = New-Object System.Windows.Forms.Button
    $button.Text = 'Chon...'
    $button.Location = New-Object System.Drawing.Point(790, ($Y - 5))
    $button.Size = New-Object System.Drawing.Size(85, 31)
    $button.Anchor = 'Top,Right'
    $button.Add_Click($BrowseAction)
    $form.Controls.Add($button)
}

$txtMessage = $null
$txtPublic = $null
$txtPrivate = $null
$txtSignature = $null

Add-FileRow 90 'File can ky:' ([ref]$txtMessage) {
    Pick-OpenFile $txtMessage 'Tat ca file (*.*)|*.*'
}
Add-FileRow 130 'Khoa cong khai:' ([ref]$txtPublic) {
    Pick-OpenFile $txtPublic 'SLH public key (*.slpk)|*.slpk|Tat ca file (*.*)|*.*'
}
Add-FileRow 170 'Khoa bi mat:' ([ref]$txtPrivate) {
    Pick-OpenFile $txtPrivate 'Khoa Windows / FPGA handle (*.slsk;*.slkh)|*.slsk;*.slkh|Tat ca file (*.*)|*.*'
}
Add-FileRow 210 'Chu ky:' ([ref]$txtSignature) {
    Pick-OpenFile $txtSignature 'SLH signature (*.slsig)|*.slsig|Tat ca file (*.*)|*.*'
}

$contextLabel = New-Object System.Windows.Forms.Label
$contextLabel.Text = 'Context:'
$contextLabel.Location = New-Object System.Drawing.Point(25, 250)
$contextLabel.Size = New-Object System.Drawing.Size(130, 26)
$form.Controls.Add($contextLabel)

$txtContext = New-Object System.Windows.Forms.TextBox
$txtContext.Text = 'DO-AN-VC707'
$txtContext.Location = New-Object System.Drawing.Point(155, 247)
$txtContext.Size = New-Object System.Drawing.Size(300, 27)
$form.Controls.Add($txtContext)

$cboBackend=New-Object Windows.Forms.ComboBox
$cboBackend.DropDownStyle='DropDownList'
$cboBackend.Items.AddRange(@('Windows software','FPGA qua UART'))
$cboBackend.SelectedIndex=0; $cboBackend.Location=New-Object Drawing.Point(465,247)
$cboBackend.Size=New-Object Drawing.Size(170,27); $form.Controls.Add($cboBackend)
$txtCom=New-Object Windows.Forms.ComboBox
$txtCom.DropDownStyle='DropDown'
$availablePorts=[IO.Ports.SerialPort]::GetPortNames()
if($availablePorts.Length) { $txtCom.Items.AddRange($availablePorts) }
$txtCom.Location=New-Object Drawing.Point(645,247); $txtCom.Size=New-Object Drawing.Size(80,27)
$txtCom.AccessibleName='Cong UART COM, vi du COM7'
$form.Controls.Add($txtCom)
$cboHashMode=New-Object Windows.Forms.ComboBox
$cboHashMode.DropDownStyle='DropDownList'; $cboHashMode.Items.AddRange(@('CPU SHAKE','AXI F/H','DMA F/H'))
$cboHashMode.SelectedIndex=1; $cboHashMode.Location=New-Object Drawing.Point(735,247)
$cboHashMode.Size=New-Object Drawing.Size(140,27); $form.Controls.Add($cboHashMode)
$backendTips=New-Object Windows.Forms.ToolTip
$backendTips.SetToolTip($txtCom,'Nhap cong USB-UART trong Device Manager, vi du COM7. Khong phai cong JTAG.')
$backendTips.SetToolTip($cboHashMode,'CPU SHAKE la PicoRV32 tren FPGA, khong phai CPU Windows. AXI/DMA dung accelerator. Do tren kit de so sanh.')
$cboBackend.Add_SelectedIndexChanged({
    $hardwareBackend=$cboBackend.SelectedIndex -eq 1
    $script:PrivateFileLabel.Text=if($hardwareBackend){'FPGA handle:'}else{'Khoa bi mat:'}
    $txtCom.Enabled=$hardwareBackend; $cboHashMode.Enabled=$hardwareBackend
    $fpgaPanel.Enabled=$hardwareBackend
})
$txtCom.Enabled=$false; $cboHashMode.Enabled=$false

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Location = New-Object System.Drawing.Point(25, 292)
$buttonPanel.Size = New-Object System.Drawing.Size(850, 44)
$buttonPanel.Anchor = 'Top,Left,Right'
$buttonPanel.WrapContents = $false
$form.Controls.Add($buttonPanel)

function New-ActionButton([string]$Text, [scriptblock]$Action) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size(128, 36)
    $button.Add_Click($Action)
    $buttonPanel.Controls.Add($button)
}

New-ActionButton 'Thong tin' {
    if($cboBackend.SelectedIndex -eq 1) { Run-Fpga @{Action='info'} } else { Run-Signer @('info') }
}
New-ActionButton 'Tu kiem tra' {
    if($cboBackend.SelectedIndex -eq 1) {
        if([Windows.Forms.MessageBox]::Show('Test FPGA day du se TAO KHOA MOI va thay khoa dang giu tren board. Handle cu se khong ky duoc nua. Tiep tuc?','FPGA selftest','YesNo','Warning') -eq 'Yes') {
            Run-Fpga @{Action='selftest'}
        }
    } else { Run-Signer @('selftest') }
}
New-ActionButton 'Tao cap khoa' {
    $publicDialog = New-Object System.Windows.Forms.SaveFileDialog
    $publicDialog.Filter = 'SLH public key (*.slpk)|*.slpk'
    $publicDialog.FileName = 'signer.slpk'
    if ($publicDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    if($cboBackend.SelectedIndex -eq 1) {
        $handleDialog=New-Object Windows.Forms.SaveFileDialog
        $handleDialog.Filter='FPGA volatile key handle (*.slkh)|*.slkh'; $handleDialog.FileName='signer.slkh'
        if($handleDialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
        $txtPublic.Text=$publicDialog.FileName; $txtPrivate.Text=$handleDialog.FileName
        $txtOutput.AppendText("FPGA: .slkh chi la handle, khong chua khoa bi mat. Reset/zeroize lam mat khoa. Windows va UART phai duoc tin cay.`r`n")
        Run-Fpga @{Action='keygen';PublicPath=$txtPublic.Text;HandlePath=$txtPrivate.Text}; return
    }

    $privateDialog = New-Object System.Windows.Forms.SaveFileDialog
    $privateDialog.Filter = 'SLH private key (*.slsk)|*.slsk'
    $privateDialog.FileName = 'signer.slsk'
    $privateDialog.InitialDirectory = Split-Path $publicDialog.FileName -Parent
    if ($privateDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $txtPublic.Text = $publicDialog.FileName
    $txtPrivate.Text = $privateDialog.FileName
    Run-Signer @('keygen', $txtPublic.Text, $txtPrivate.Text)
}
New-ActionButton 'Ky file' {
    $privatePurpose=if($cboBackend.SelectedIndex -eq 1){'FPGA handle .slkh'}else{'khoa bi mat .slsk'}
    if (-not (Require-ExistingFile $txtPrivate $privatePurpose)) { return }
    if (-not (Require-ExistingFile $txtMessage 'file can ky')) { return }
    if (-not $txtSignature.Text -or (Test-Path -LiteralPath $txtSignature.Text)) {
        $defaultName = [System.IO.Path]::GetFileName($txtMessage.Text) + '.slsig'
        if($txtSignature.Text -and (Test-Path -LiteralPath $txtSignature.Text)) {
            $defaultName=[IO.Path]::GetFileName($txtMessage.Text)+'-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss')+'.slsig'
            $txtOutput.AppendText("`r`nKhong ghi de chu ky cu. Hay chon file chu ky MOI.`r`n")
        }
        if (-not (Pick-SaveFile $txtSignature 'SLH signature (*.slsig)|*.slsig' $defaultName)) { return }
    }
    if(Test-Path -LiteralPath $txtSignature.Text) {
        [Windows.Forms.MessageBox]::Show('File chu ky da ton tai. Hay chon ten file moi; chuong trinh khong ghi de.','Chu ky moi','OK','Warning')|Out-Null
        return
    }
    if($cboBackend.SelectedIndex -eq 1) {
        Run-Fpga @{Action='sign';PublicPath=$txtPublic.Text;HandlePath=$txtPrivate.Text;
            MessagePath=$txtMessage.Text;SignaturePath=$txtSignature.Text;Context=$txtContext.Text}; return
    }
    $args = @('sign', $txtPrivate.Text, $txtMessage.Text, $txtSignature.Text)
    if ($txtContext.Text) { $args += @('--context', $txtContext.Text) }
    Run-Signer $args
}
New-ActionButton 'Xac minh' {
    if (-not (Require-ExistingFile $txtPublic 'khoa cong khai')) { return }
    if (-not (Require-ExistingFile $txtMessage 'file can kiem tra')) { return }
    if (-not (Require-ExistingFile $txtSignature 'chu ky')) { return }
    if($cboBackend.SelectedIndex -eq 1) {
        Run-Fpga @{Action='verify';PublicPath=$txtPublic.Text;MessagePath=$txtMessage.Text;SignaturePath=$txtSignature.Text}; return
    }
    Run-Signer @('verify', $txtPublic.Text, $txtMessage.Text, $txtSignature.Text)
}
New-ActionButton 'Xem chu ky' {
    if (-not (Require-ExistingFile $txtSignature 'chu ky')) { return }
    Run-Signer @('inspect', $txtSignature.Text)
}

$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = 'Ket qua:'
$fpgaPanel=New-Object Windows.Forms.FlowLayoutPanel
$fpgaPanel.Location=New-Object Drawing.Point(25,337); $fpgaPanel.Size=New-Object Drawing.Size(850,38)
$form.Controls.Add($fpgaPanel)
$fpgaPanel.Enabled=$false
$eraseButton=New-Object Windows.Forms.Button; $eraseButton.Text='Zeroize FPGA'; $eraseButton.Size=New-Object Drawing.Size(145,32)
$eraseButton.Add_Click({
    if([Windows.Forms.MessageBox]::Show('Xoa khoa dang giu tren FPGA? Handle cu se khong ky duoc nua.','Zeroize','YesNo','Warning') -eq 'Yes') { Run-Fpga @{Action='zeroize'} }
}); $fpgaPanel.Controls.Add($eraseButton)
$benchmarkButton=New-Object Windows.Forms.Button; $benchmarkButton.Text='Do hieu nang FPGA'; $benchmarkButton.Size=New-Object Drawing.Size(180,32)
$benchmarkButton.Add_Click({
    if(-not (Require-ExistingFile $txtMessage 'file can ky') -or -not (Require-ExistingFile $txtPrivate 'FPGA handle .slkh')) { return }
    $csvDialog=New-Object Windows.Forms.SaveFileDialog; $csvDialog.Filter='Benchmark CSV (*.csv)|*.csv'; $csvDialog.FileName='fpga_benchmark.csv'
    if($csvDialog.ShowDialog() -eq 'OK') {
        Run-Fpga @{Action='benchmark';PublicPath=$txtPublic.Text;HandlePath=$txtPrivate.Text;
            MessagePath=$txtMessage.Text;Context=$txtContext.Text;CsvPath=$csvDialog.FileName}
    }
}); $fpgaPanel.Controls.Add($benchmarkButton)
$scanComButton=New-Object Windows.Forms.Button; $scanComButton.Text='Quet COM'; $scanComButton.Size=New-Object Drawing.Size(100,32)
$scanComButton.Add_Click({
    $previousCom=$txtCom.Text; $txtCom.Items.Clear(); $ports=[IO.Ports.SerialPort]::GetPortNames()
    if($ports.Length){$txtCom.Items.AddRange($ports)}
    $txtCom.Text=$previousCom
    $txtOutput.AppendText("`r`nCong UART: $($ports -join ', '). Neu rong, hay cam USB-UART va kiem tra Device Manager.`r`n")
}); $fpgaPanel.Controls.Add($scanComButton)
$outputLabel.Location = New-Object System.Drawing.Point(25, 385)
$outputLabel.AutoSize = $true
$form.Controls.Add($outputLabel)

$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(25, 410)
$txtOutput.Size = New-Object System.Drawing.Size(850, 210)
$txtOutput.Anchor = 'Top,Bottom,Left,Right'
$txtOutput.Multiline = $true
$txtOutput.ScrollBars = 'Both'
$txtOutput.ReadOnly = $true
$txtOutput.WordWrap = $false
$txtOutput.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$txtOutput.Text = "Nhan 'Thong tin' de kiem tra chuong trinh.`r`n"
$form.Controls.Add($txtOutput)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'San sang'
$statusLabel.Location = New-Object System.Drawing.Point(25, 635)
$statusLabel.Size = New-Object System.Drawing.Size(600, 25)
$statusLabel.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($statusLabel)

$openFolder = New-Object System.Windows.Forms.Button
$openFolder.Text = 'Mo thu muc do an'
$openFolder.Location = New-Object System.Drawing.Point(715, 630)
$openFolder.Size = New-Object System.Drawing.Size(160, 32)
$openFolder.Anchor = 'Bottom,Right'
$openFolder.Add_Click({ Start-Process explorer.exe -ArgumentList $script:ProjectRoot })
$form.Controls.Add($openFolder)

if ($DemoFolder) {
    $resolvedDemo = [System.IO.Path]::GetFullPath($DemoFolder)
    $demoMessage = Join-Path $resolvedDemo 'tai_lieu_mau.txt'
    $demoPublic = Join-Path $resolvedDemo 'khoa_cong_khai.slpk'
    $demoPrivate = Join-Path $resolvedDemo 'khoa_bi_mat.slsk'
    $demoSignature = Join-Path $resolvedDemo 'chu_ky_tai_lieu.slsig'

    if (Test-Path -LiteralPath $demoMessage) { $txtMessage.Text = $demoMessage }
    if (Test-Path -LiteralPath $demoPublic) { $txtPublic.Text = $demoPublic }
    if (Test-Path -LiteralPath $demoPrivate) { $txtPrivate.Text = $demoPrivate }
    if (Test-Path -LiteralPath $demoSignature) { $txtSignature.Text = $demoSignature }
    $txtContext.Text = 'DO-AN-VC707-DEMO'
}

$form.Add_Shown({
    if (Ensure-Signer) { Run-Signer @('info') }
})

if($SmokeTest) {
    # Construct and validate our own controls without showing a window or
    # opening serial/JTAG. This is not an interactive or real-board test.
    $form.PerformLayout()
    $cboBackend.SelectedIndex=1
    if($script:PrivateFileLabel.Text -ne 'FPGA handle:' -or -not $txtCom.Enabled -or -not $fpgaPanel.Enabled) {
        throw 'FPGA GUI backend controls failed'
    }
    $cboBackend.SelectedIndex=0
    if($script:PrivateFileLabel.Text -ne 'Khoa bi mat:' -or $txtCom.Enabled -or $fpgaPanel.Enabled) {
        throw 'Windows GUI backend controls failed'
    }
    foreach($control in $form.Controls) {
        if($control.Right -gt $form.ClientSize.Width -or $control.Bottom -gt $form.ClientSize.Height) {
            throw "GUI control outside client area: $($control.Name) $($control.Text)"
        }
    }
    $form.Dispose()
    Write-Host 'GUI CONSTRUCTION/BACKEND/BOUNDS SMOKE TEST PASSED (NO WINDOW/COM OPENED)'
} else { [void]$form.ShowDialog() }
