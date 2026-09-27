# Đề tài: SLH-DSA-SHAKE-256f theo FIPS 205 trên FPGA VC707

Tên “SPHINCS+-SHAKE256” phù hợp để trình bày nguồn gốc của đề tài, nhưng
tên kỹ thuật chính xác của cấu hình sản phẩm hiện tại là
**SLH-DSA-SHAKE-256f theo FIPS 205**. SHAKE256 là XOF nền tảng; chữ `256f`
là tập tham số mức an toàn category 5 ưu tiên tốc độ.

## Mô tả ngắn theo form báo cáo

Đồ án xây dựng một sản phẩm mẫu chữ ký số hậu lượng tử không trạng thái dựa
trên SLH-DSA, chuẩn hóa từ SPHINCS+, và dùng SHAKE256 cho các phép băm mật
mã. Hệ thống hiện có phần mềm tạo khóa, ký và xác minh file tương thích cấu
hình FIPS 205 SLH-DSA-SHAKE-256f; đồng thời có IP AXI4-Lite trên Virtex-7
VC707 để tăng tốc các phép băm có địa chỉ F/H của thuật toán.

## Đặc điểm chính

- **Hậu lượng tử:** an toàn dựa trên các giả định của hàm băm mật mã, thay
  vì phân tích số hoặc logarit rời rạc. Không tuyên bố “an toàn tuyệt đối”.
- **Không trạng thái:** người ký không cần duy trì bộ đếm chữ ký bền vững,
  nhưng vẫn phải bảo vệ khóa bí mật, nguồn ngẫu nhiên và lỗi phần cứng.
- **SHAKE256:** XOF dựa trên Keccak thuộc họ SHA-3, có đầu ra dài tùy ý và
  khác SHA3-256 có đầu ra cố định.
- **Một cấu hình phát hành:** chỉ dùng `SLH-DSA-SHAKE-256f`, tránh nhầm lẫn
  giữa các bản 128f, 256f hoặc submission cũ.
- **Tăng tốc FPGA:** lõi hiện tăng tốc F/H; toàn bộ WOTS+, FORS, XMSS và
  hypertree vẫn do phần mềm chuẩn thực hiện.

## Đầu vào và đầu ra

| Chức năng | Đầu vào | Đầu ra |
| --- | --- | --- |
| Tạo khóa | CSPRNG của hệ điều hành | khóa công khai `.slpk`, khóa bí mật DPAPI `.slsk` |
| Ký | `.slsk`, file thông điệp, context tùy chọn | container `.slsig` chứa chữ ký 49.856 byte cùng metadata |
| Xác minh | `.slpk`, file gốc, `.slsig` | hợp lệ hoặc không hợp lệ |
| IP F/H | `PK.seed`, `ADRS`, một hoặc hai khối 32 byte | digest 32 byte và interrupt hoàn tất |

Kích thước khóa mật mã nguyên bản là 64 byte cho khóa công khai và 128 byte
cho khóa bí mật. Container của đồ án lớn hơn vì chứa version, mode,
fingerprint và lớp bảo vệ DPAPI.

## Trạng thái đã kiểm chứng

| Thành phần | Kết quả hiện tại |
| --- | --- |
| Phần mềm FIPS 205 | keygen/sign/verify pure, context, hedged/deterministic và HashSLH pre-hash |
| Kiểm thử chuẩn | NIST ACVP v1.1.0.40 cho SHAKE-256f: **104/104 PASS** |
| RTL SHAKE256 | XSim PASS các độ dài 0, 3, 135, 136, 137, 272 và 2.208 byte |
| F/H và AXI4-Lite | XSim PASS hai vector và kiểm thử giao thức/bảo mật AXI v2 |
| Firmware VC707 | bitstream 250 MHz; WNS +0,461 ns, WHS +0,085 ns, 5.290 LUT, 6.824 FF; DRC 0 lỗi |
| IP OOC VC707 | phát hành 300 MHz: WNS +0,276 ns, WHS +0,042 ns, 6.737 LUT, 9.229 FF; Fmax đo được 330 MHz |
| Kit vật lý | chưa nạp và đo trực tiếp trong môi trường phát triển này |

Firmware LED hiện tại chỉ là self-test F/H. IP AXI đã đóng gói để ghép với
MicroBlaze hoặc CPU, nhưng chưa được nối thành một block design host–FPGA
hoàn chỉnh. Vì vậy không được mô tả rằng toàn bộ phép ký đang chạy trong
FPGA.

## Phần còn thiếu để thành sản phẩm hoàn chỉnh hơn

1. Ghép IP AXI với MicroBlaze, bộ nhớ và UART để demo dữ liệu thật.
2. Mở rộng RTL với T_l nhiều khối, PRF, PRFmsg và Hmsg.
3. Hiện thực WOTS+, FORS, XMSS treehash và hypertree trên FPGA.
4. Thêm AXI DMA/Stream cho chữ ký 49.856 byte và thông điệp lớn.
5. Bổ sung timeout hệ thống, kiểm tra lỗi dư thừa và chống side-channel/fault;
   zeroization cơ bản đã được thực hiện trong AXI IP v2.
6. Chuẩn hóa DER/PEM, OID, CMS/PAdES, X.509, timestamp và CRL/OCSP nếu mục
   tiêu là tương tác với phần mềm chữ ký tài liệu thương mại.
7. Đo keygen/sign/verify end-to-end trên kit VC707 thật.

## Phạm vi tuyên bố

Phiên bản hiện tại là **product prototype học thuật**, không phải sản phẩm
đã chứng nhận FIPS 140-3 hay thiết bị ký số thương mại. Phần mềm thực hiện
đúng thuật toán FIPS 205 và đã qua vector ACVP mục tiêu; container `.slpk`,
`.slsk`, `.slsig` là định dạng riêng của đồ án.

## Nguồn chính

- [FIPS 202: SHA-3 và SHAKE256](https://csrc.nist.gov/pubs/fips/202/final)
- [FIPS 205: SLH-DSA](https://csrc.nist.gov/pubs/fips/205/final)
- [Trang SPHINCS+](https://sphincs.org/)
- [slhdsa-c](https://github.com/pq-code-package/slhdsa-c)
