@echo off
setlocal
set "BASE=%~dp0"
set "SLH=%BASE%..\..\third_party\slhdsa-c"
set "OUT=%BASE%..\..\hardware\soc\output_portable\review_file_io"
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b 1
if not exist "%OUT%" mkdir "%OUT%"
pushd "%OUT%"
cl /nologo /O2 /TC /I"%SLH%" /D__x86_64__=1 /D__BYTE_ORDER__=1234 /D__ORDER_LITTLE_ENDIAN__=1234 /D__ORDER_BIG_ENDIAN__=4321 /Fe:test_write_failure.exe ^
 "%SLH%\sha2_256.c" "%SLH%\sha2_512.c" "%SLH%\sha3_api.c" "%SLH%\sha3_f1600.c" ^
 "%SLH%\slh_dsa.c" "%SLH%\slh_prehash.c" "%SLH%\slh_sha2.c" "%SLH%\slh_shake.c" "%BASE%test_write_failure.c" /link bcrypt.lib crypt32.lib
if errorlevel 1 (popd & exit /b 1)
test_write_failure.exe
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
