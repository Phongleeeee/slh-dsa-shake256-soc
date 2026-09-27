$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path (Split-Path -Parent $scriptDir) 'build_portable\portable_slh_soc.xpr'
$vivado = 'D:\2025.1\Vivado\bin\vivado.bat'
if (-not (Test-Path $project)) { throw 'Chua co project. Hay chay build_portable_soc.ps1 truoc.' }
Start-Process -FilePath $vivado -ArgumentList ('"' + $project + '"') -WindowStyle Hidden
