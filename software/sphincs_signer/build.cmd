@echo off
setlocal
set "BASE=%~dp0"
set "SLH=%BASE%..\..\third_party\slhdsa-c"
set "OUT=%BASE%build\slh_dsa_shake_256f.exe"
set "OBJ=%BASE%build\fips205"
set "VSDEV=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"

if /I "%~1"=="256f" goto build
if /I "%~1"=="fips205" goto build
if "%~1"=="" goto build
echo Usage: build.cmd [256f^|fips205]
exit /b 2

:build
if not exist "%VSDEV%" (
  echo Visual Studio 2022 Community C/C++ tools not found.
  exit /b 1
)
if not exist "%SLH%\slh_dsa.c" (
  echo Missing dependency: third_party\slhdsa-c
  exit /b 1
)
call "%VSDEV%" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b 1
if not exist "%BASE%build" mkdir "%BASE%build"
if not exist "%OBJ%" mkdir "%OBJ%"
pushd "%OBJ%"
cl /nologo /O2 /W4 /TC /I"%SLH%" /D__x86_64__=1 ^
  /D__BYTE_ORDER__=1234 /D__ORDER_LITTLE_ENDIAN__=1234 ^
  /D__ORDER_BIG_ENDIAN__=4321 /Fe:"%OUT%" ^
  "%SLH%\sha2_256.c" "%SLH%\sha2_512.c" ^
  "%SLH%\sha3_api.c" "%SLH%\sha3_f1600.c" ^
  "%SLH%\slh_dsa.c" "%SLH%\slh_prehash.c" ^
  "%SLH%\slh_sha2.c" "%SLH%\slh_shake.c" ^
  "%BASE%slh_product_cli.c" /link bcrypt.lib crypt32.lib
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" exit /b %RC%
echo Built: %OUT%
exit /b 0
