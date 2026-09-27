@echo off
setlocal
set "BASE=%~dp0"
set "SLH=%BASE%..\..\third_party\slhdsa-c"
set "OBJ=%BASE%build\fips205"
set "OUT=%OBJ%\slh_acvp_bridge.dll"
set "VSDEV=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if not exist "%VSDEV%" exit /b 1
call "%VSDEV%" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b 1
if not exist "%OBJ%" mkdir "%OBJ%"
pushd "%OBJ%"
cl /nologo /O2 /LD /TC /I"%SLH%" /D__x86_64__=1 ^
  /D__BYTE_ORDER__=1234 /D__ORDER_LITTLE_ENDIAN__=1234 ^
  /D__ORDER_BIG_ENDIAN__=4321 /Fe:"%OUT%" ^
  "%SLH%\sha2_256.c" "%SLH%\sha2_512.c" ^
  "%SLH%\sha3_api.c" "%SLH%\sha3_f1600.c" ^
  "%SLH%\slh_dsa.c" "%SLH%\slh_prehash.c" ^
  "%SLH%\slh_sha2.c" "%SLH%\slh_shake.c" ^
  "%BASE%slh_acvp_bridge.c"
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" exit /b %RC%
echo Built: %OUT%
exit /b 0
