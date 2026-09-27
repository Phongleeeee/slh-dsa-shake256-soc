@echo off
setlocal
set "GUI=%~dp0software\sphincs_signer\slh_dsa_gui.ps1"
set "DEMO=%~dp0demo_chay_thu"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File "%GUI%" -DemoFolder "%DEMO%"
if errorlevel 1 (
  echo.
  echo Khong mo duoc bo demo. Hay chup man hinh dong loi nay.
  pause
)

