@echo off
setlocal
set "GUI=%~dp0software\sphincs_signer\slh_dsa_gui.ps1"

if not exist "%GUI%" (
  echo Khong tim thay giao dien: %GUI%
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File "%GUI%"
if errorlevel 1 (
  echo.
  echo Giao dien dung do co loi. Hay chup man hinh dong loi nay.
  pause
)

