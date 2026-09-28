# Trạng thái sản phẩm mẫu SLH-DSA-SHAKE-256f

## Cấu hình SoC chính hiện tại (28/09/2026)

`portable_slh_soc_core.v` chứa PicoRV32, AXI, DMA/IOMMU, SHAKE256 F/H,
UART, timer/GPIO và 192 KiB RAM nội bộ. `vc707_portable_wrapper.v` chỉ
chứa clock/reset và I/O kit. DDR3/MIG không còn là điều kiện khởi động;
bản mở rộng bộ nhớ ngoài vẫn được giữ riêng để tham khảo/tích hợp tùy chọn.

Project chính: `hardware/soc/build_portable/portable_slh_soc.xpr`.
Xem [trạng thái kiểm chứng và cách build](../hardware/soc/PORTABLE_SOC.md).
Toàn SoC portable sau sửa DMA đạt post-route **296,296 MHz**, WNS +0,001 ns
(rất sát biên), WHS +0,055 ns; [biên bản kiểm chứng](../hardware/soc/ACCEPTANCE.md).
Các số Fmax OOC bên dưới thuộc IP độc lập, không phải toàn SoC.

[Rà soát DMA 28/09/2026](RA_SOAT_DMA_2026-09-28.md): sửa DONE đến sớm
ở M2S và commit bảng trang sai khi WSTRB=0; 9/9 tổ hợp, 456 lệnh hợp lệ,
51 lệnh bị từ chối, 48 lỗi bus/phục hồi và 80.000 lượt mô hình FIFO PASS.

[Rà soát mở rộng 27/09/2026](RA_SOAT_KIEM_CHUNG_2026-09-27.md): sửa 6 lỗi,
đối chiếu NIST, thêm test biên/framing/abort/thu hồi quyền và parser file.
Clock tăng 7,407% so với baseline; chưa có benchmark/đo ổn định trên kit.

Nâng cấp 5 hướng: [hướng dẫn dịch vụ mới](../hardware/soc/SERVICE_GUIDE.md).
Đã có app FPGA UART, firmware keygen/sign/verify, benchmark CPU/AXI/DMA,
DMA stream dùng chung SHAKE, vault chặn DMA và zeroize. Engine/PC đối chiếu
đạt; chưa có nghiệm thu ký đủ và số đo benchmark trên kit thật.

## Đã hoàn thành trong phiên bản này

1. Chuyển phần mềm chính từ SPHINCS+ submission sang FIPS 205 SLH-DSA.
2. Chốt một cấu hình duy nhất: `SLH-DSA-SHAKE-256f`, security category 5.
3. Thêm pure signing, HashSLH pre-hash, context và deterministic/hedged.
4. Bảo vệ khóa bí mật bằng Windows DPAPI thay cho file 128 byte thô.
5. Thêm container có version và fingerprint để chống dùng nhầm khóa/mode.
6. Chạy đạt 104/104 vector NIST ACVP v1.1.0.40 cho cấu hình chính.
7. Đóng gói lõi FPGA thành IP AXI4-Lite v2 có register map và interrupt.
8. Cung cấp driver C để MicroBlaze/CPU gọi phép F/H.
9. XSim kiểm tra toàn bộ giao dịch AXI và hai vector F/H.
10. Implementation OOC IP ở 300 MHz đạt WNS +0,276 ns, WHS +0,042 ns và
    DRC 0 lỗi; 330 MHz đạt sát biên, 335 MHz không đạt, nên 300 MHz là mức
    phát hành có margin.
11. Bổ sung zeroize/abort, input write-only, kiểm tra đủ cấu hình, AXI
    `SLVERR`, ngắt mask/W1C, xử lý AW/W độc lập và tự scrub dữ liệu trung
    gian trước DONE.

## Mức sản phẩm hiện tại

Đây là một **product prototype học thuật**:

- Có bộ ký file FIPS 205 sử dụng được trên Windows.
- Có IP tăng tốc SHAKE256 F/H v2 300 MHz có thể kéo vào Vivado Block Design.
- Có firmware RV32 keygen/sign/verify; startup và DMA RAM nội bộ đã đạt XSim.
  Keygen/sign/verify end-to-end trên bản portable cần kiểm tra thêm qua UART.
- Bitstream SHAKE độc lập 250 MHz trước đây không phải bitstream SoC portable.
- Có test phần mềm, ACVP, RTL, AXI và timing.

Nó chưa phải sản phẩm chữ ký số thương mại hoặc đã chứng nhận vì chưa có
HSM, chứng thư X.509/CA, CMS/PAdES, timestamp, CRL/OCSP, xác thực PIN/OTP,
chống side-channel/fault và đánh giá FIPS 140-3.

## Công việc phần cứng tiếp theo

Thực hiện theo thứ tự sau để tránh mở rộng thiết kế thiếu kiểm soát:

1. `T_l` nhiều khối cho nén public key WOTS+.
2. PRF đã dùng chung F engine qua MMIO; bước tiếp theo là PRFmsg và Hmsg RTL.
3. Bộ sinh và cập nhật ADRS chuẩn FIPS 205.
4. WOTS+ chain/checksum/public-key generation.
5. XMSS treehash và authentication path.
6. FORS sign/public-key reconstruction.
7. Hypertree controller.
8. Keygen/sign/verify controller.
9. DMA → accelerator F/H đã tích hợp và kiểm tra RTL; bước tiếp theo là batch
   descriptor và T_l streaming. Signature/message lưu trong RAM và truyền UART;
   không nhầm với phép băm F/H đang dùng DMA.
10. Timeout phía host, redundant verification và fault detection/side-channel
    masking. Zeroization cơ bản đã có trong IP v2.

## Công việc tích hợp sản phẩm tiếp theo

1. Hoàn thành kiểm thử keygen/sign/verify end-to-end trên PicoRV32 SoC portable.
2. Giao thức host SLH3 qua UART đã có; nghiệm thu trên COM thật trước khi
   mở rộng Ethernet/PCIe và file lớn.
3. DER/PEM và OID `id-slh-dsa-shake-256f`.
4. CMS detached signature, sau đó mới đến PAdES/PDF.
5. Chứng thư X.509 thử nghiệm và chuỗi CA phòng lab.
6. Timestamp và trạng thái thu hồi.
7. PIN/OTP, audit log và chính sách sử dụng khóa.

Không tuyên bố đã nghiệm thu toàn bộ SLH-DSA trên FPGA khi chưa chạy
keygen/sign/verify end-to-end trên kit. Chạy thuật toán bằng firmware CPU
trong FPGA khác với viết toàn bộ thuật toán thành khối RTL chuyên dụng.
