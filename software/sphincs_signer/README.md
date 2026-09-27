# Bộ ký SLH-DSA-SHAKE-256f theo FIPS 205

Đây là phần mềm sản phẩm mẫu chính của đồ án. Nó đã thay thế bộ ký
SPHINCS+ submission cũ bằng `SLH-DSA-SHAKE-256f` theo FIPS 205.

App hiện có hai backend **Windows** và **FPGA UART**. Backend FPGA không tự
fallback sang Windows: cần bitstream SLH3 và COM thật, pure message ≤16 KiB.
FPGA tạo `.slpk` + `.slkh` (handle, không có SK), không tạo `.slsk` DPAPI.
Cách sử dụng và giới hạn: [SERVICE_GUIDE.md](../../hardware/soc/SERVICE_GUIDE.md).

## Chức năng đã có

- Tạo khóa FIPS 205.
- Ký và xác minh file ở chế độ pure.
- Ký hedged mặc định bằng CSPRNG của Windows.
- Ký deterministic khi cần tái lập kết quả thử nghiệm.
- HashSLH-DSA pre-hash với SHAKE-256 hoặc SHA2-256.
- Context string FIPS 205 tối đa 255 byte.
- Khóa bí mật được Windows DPAPI mã hóa và ràng buộc với tài khoản hiện tại.
- Container có version, thuật toán, mode, context và fingerprint khóa.
- Không ghi đè khóa hoặc chữ ký đã tồn tại.
- Xóa vùng nhớ khóa và chữ ký tạm trước khi giải phóng.
- Self-test, negative test, benchmark và đối chiếu RTL `thash`.
- 104/104 vector NIST ACVP v1.1.0.40 riêng cho
  `SLH-DSA-SHAKE-256f` đã PASS.

Thư viện thuật toán được ghim tại `../../third_party/slhdsa-c`, commit
`174c02e42257f95c210963272877c49dbb50070f`. Source upstream hiện vẫn tự
ghi rõ chưa khuyến nghị bảo vệ dữ liệu nhạy cảm trong production; đồ án này
vì vậy là **product prototype**, không phải sản phẩm đã chứng nhận.
Có patch hook tăng tốc F/H/PRF dưới `SLH_RV32_HW_ACCEL`; build Windows không
bật macro này. ACVP Windows không thay thế nghiệm thu đường tăng tốc trên kit.

## Build và chạy

```powershell
cd C:\SHAKE256\software\sphincs_signer
.\build.cmd fips205
.\build\slh_dsa_shake_256f.exe selftest
.\test_cli.ps1
.\test_acvp.ps1
```

Hoặc dùng entrypoint duy nhất từ thư mục gốc:

```powershell
cd C:\SHAKE256
.\slh_dsa.ps1 info
.\slh_dsa.ps1 keygen signer.slpk signer.slsk
.\slh_dsa.ps1 sign signer.slsk tai_lieu.pdf tai_lieu.slsig `
    --context DO-AN-SPHINCS-VC707
.\slh_dsa.ps1 verify signer.slpk tai_lieu.pdf tai_lieu.slsig
.\slh_dsa.ps1 inspect tai_lieu.slsig
```

Khóa `.slsk` chỉ giải mã được bởi cùng tài khoản Windows trên máy tạo khóa.
Không sao chép nó sang máy khác và mong đợi giải mã thành công.

## Các định dạng file

- `.slpk`: khóa công khai 64 byte trong container có version.
- `.slsk`: khóa bí mật 128 byte được DPAPI bảo vệ.
- `.slsig`: chữ ký detached 49.856 byte cùng metadata xác minh.

Ba container trên là định dạng riêng của đồ án, chưa phải DER/PEM, CMS,
X.509 hay PAdES. Chữ ký mật mã bên trong là chữ ký FIPS 205 chuẩn.

## Benchmark

```powershell
.\build\slh_dsa_shake_256f.exe benchmark
```

Kết quả tham khảo trên máy phát triển cho implementation C portable:

- keygen: khoảng 6,3 ms;
- sign: khoảng 128,9 ms;
- verify: khoảng 3,4 ms.

Đây là một lần đo trên máy hiện tại, không phải cam kết hiệu năng.

## Giới hạn an toàn

- DPAPI tốt hơn khóa thô nhưng không thay thế HSM/USB Token.
- Chưa có PIN/OTP, chứng thư X.509, CA, timestamp, CRL/OCSP hoặc audit log.
- Container chưa phải định dạng chữ ký tài liệu được phần mềm thương mại nhận.
- Chưa được đánh giá side-channel, fault injection hoặc FIPS 140-3.
