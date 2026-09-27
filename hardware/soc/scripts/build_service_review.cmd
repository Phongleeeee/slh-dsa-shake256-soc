@echo off
setlocal
set "SOC=%~dp0.."
set "ROOT=%SOC%\..\.."
set "SLH=%ROOT%\third_party\slhdsa-c"
set "OUT=%SOC%\output_portable\review_native"
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b 1
if not exist "%OUT%" mkdir "%OUT%"
pushd "%OUT%"
cl /nologo /O2 /W4 /LD /TC /DSLH_NATIVE_TEST /DSLH_RV32_HW_ACCEL /D__x86_64__=1 /D__BYTE_ORDER__=1234 /D__ORDER_LITTLE_ENDIAN__=1234 /D__ORDER_BIG_ENDIAN__=4321 /I"%SOC%\firmware" /I"%SLH%" /Fe:service_review.dll ^
 "%SOC%\sim\service_native_test.c" "%SOC%\firmware\slh_service.c" ^
 "%SLH%\slh_dsa.c" "%SLH%\slh_shake.c" "%SLH%\sha3_api.c" "%SLH%\sha3_f1600.c" ^
 "%SLH%\slh_prehash.c" "%SLH%\slh_sha2.c" "%SLH%\sha2_256.c" "%SLH%\sha2_512.c" ^
 "%ROOT%\software\sphincs_signer\slh_acvp_bridge.c" ^
 /link /EXPORT:slh_service_init /EXPORT:slh_service_command /EXPORT:slh_hw_set_mode /EXPORT:slh_test_fail_next
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
