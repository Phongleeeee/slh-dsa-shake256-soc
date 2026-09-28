# Kiểm chứng SoC portable SLH-DSA-SHAKE-256f

Ngày: **28/09/2026**. Công cụ: Vivado/XSim 2025.1.
Thiết bị triển khai: **xc7vx485tffg1761-2 (VC707)**.

**Cập nhật bố cục:** source đã di chuyển theo [bản đồ thư mục](../../docs/CAU_TRUC_THU_MUC.md).
Đợt 28/09 đã sửa hai lỗi DMA và thực hiện một lần synthesis/route mới.
Đường dẫn project chính và bitstream không đổi; bản cũ được giữ tại
`output_portable/releases/pre_dma_fix_20260928`. Firmware binary không đổi.
Chi tiết lỗi và ma trận kiểm tra: [báo cáo DMA](../../docs/RA_SOAT_DMA_2026-09-28.md).

## Kết quả timing của toàn hệ thống

| Chỉ tiêu post-route | Kết quả |
|---|---:|
| Clock SoC | **296,296296 MHz** |
| Chu kỳ clock | 3,375 ns |
| Setup WNS | **+0,001 ns (rất sát biên)** |
| Setup TNS / endpoint vi phạm | 0 ns / 0 |
| Hold WHS | **+0,055 ns** |
| Hold THS / endpoint vi phạm | 0 ns / 0 |
| Pulse-width slack / vi phạm | +0,919 ns / 0 |
| Register không có clock | 0 |
| Endpoint nội bộ thiếu ràng buộc | 0 |
| DRC ruledeck mặc định | **0 vi phạm** |
| DRC bitstream_checks (đọc lại checkpoint phát hành) | **0 vi phạm** |
| LUT / flip-flop | 16.731 / 17.682 |
| RAMB36 / DSP | 48 / 0 |

CPU, AXI, RAM0/1/2, DMA/IOMMU, SHAKE256, UART và timer/GPIO **đều dùng
clock 296,296 MHz**, không có khối xử lý nội bộ chạy clock chậm riêng.
Clock đầu vào kit vẫn là 200 MHz; MMCM tạo VCO 1 GHz, chia 3,375 cho SoC.
UART vẫn truyền 115200 baud, 8N1 — baud không phải tần số clock xử lý UART.

Đây là **mức cao nhất đã build đạt trong các lần thử của phiên chỉnh sửa
này**, không phải khẳng định giới hạn vật lý tuyệt đối hay bảo đảm mọi kit
đều đạt cùng tốc độ. Các bản 250 và 266,667 MHz trước đó được giữ trong
`output_portable/releases` để đối chiếu; source/bitstream chính là bản hiện tại.

Giữ nguyên clock của bản 27/09, cao hơn **7,407%** so với baseline
275,862069 MHz. Setup margin theo độ phân giải báo cáo chỉ **1 ps**,
không có dự phòng đáng kể. Đây là cấu hình
hiệu năng sát biên cho đồ án, chưa phải xác nhận ổn định trên board thật.
Không tự tăng clock; nếu cần margin lớn hơn phải build/kiểm tra lại ở clock
thấp hơn. Đường tới hạn hiện tại nằm trong CDMA:
`write_addr_reg_reg[1]` → `write_addr_reg_reg[31]`.
Fmax không đồng nghĩa với tốc độ ký: chưa đo chữ ký/giây trên board.

### Timing từng khối trong SoC

| Khối | Clock đã đạt (MHz) | Setup slack (ns) |
|---|---:|---:|
| PicoRV32 | 296,296 | +0,062 |
| AXI fabric | 296,296 | +0,022 |
| RAM0 / RAM1 / RAM2 | 296,296 | +0,002 / +0,145 / +0,169 |
| SHAKE AXI F/H | 296,296 | +0,078 |
| SHAKE core / Keccak | 296,296 | +0,078 / +0,078 |
| DMA/IOMMU | 296,296 | +0,001 |
| IOMMU riêng | 296,296 | +0,177 |
| UART | 296,296 | +0,044 |
| Timer/GPIO | 296,296 | +0,321 |

Các scope bao gồm đường vào từ khối khác. Cột `estimated_limit_mhz` trong
CSV chỉ là ngoại suy từ slack của placement hiện tại, **không phải Fmax OOC
đã build đạt**. Không dùng các số ngoại suy đó làm tần số nạp board.

## Kiến trúc đã hoàn thành

Bản nâng cấp dịch vụ UART/DMA/vault và hướng dẫn sử dụng đầy đủ:
[SERVICE_GUIDE.md](SERVICE_GUIDE.md). Bản sửa DMA giữ **296,296 MHz**,
thêm 16 LUT và 3 FF so với bản 27/09;
không thêm BRAM hoặc DSP. Firmware: text **24.240 byte**, data **4 byte**,
BSS **69.048 byte** (không cộng nhầm BSS vào kích thước ảnh boot).

1. `../rtl/soc/portable_slh_soc_core.v`: CPU PicoRV32, AXI, SHAKE F/H, DMA/IOMMU,
   ba RAM 64 KiB, UART và timer/GPIO; không chứa MIG, MMCM hoặc chân VC707.
2. `../boards/vc707/rtl/vc707_portable_wrapper.v`: IBUFDS/MMCM/BUFG, reset đồng bộ, UART,
   LED; không chứa logic DDR3.
3. `../boards/vc707/constraints/vc707_portable.xdc`: chân, clock và timing của VC707.
4. Firmware portable khởi động từ RAM0; bài DMA là
   **RAM1 → RAM2 → RAM1**, có so sánh và xóa bản gốc trước lượt truyền về.
5. DDR3 được giữ qua giao diện AXI tùy chọn (`ENABLE_EXT_MEMORY=1`). Mặc
   định tắt; không chờ MIG calibration và không cần DDR3 để khởi động.

Kit AMD/Xilinx khác giữ lõi và firmware, thay wrapper, XDC và part/top trong
build. Kit phải đủ tài nguyên. Đổi sang FPGA hãng khác còn cần thay backend
RAM XPM và công cụ build; không chỉ đổi chân.

## Tối ưu thực hiện và kiểm tra hồi quy

- CPU tách ALU/compare thành hai chu kỳ, có barrel shifter.
- DMA pipeline snapshot thống kê: đóng băng bộ đếm rồi chốt kết quả ở chu kỳ
  sau. Phần mềm chờ `perf_seq`; không thêm chu kỳ cho dữ liệu hay IRQ DMA.
- DMA đếm byte còn lại bão hòa để bỏ phép cộng rồi so sánh 32 bit liên tiếp
  trên đường nhận biết beat cuối; kiểm tra bất biến bằng assertion.
- Scheduler tách bước tính biên trang sau khi chốt descriptor; thêm một nhịp
  chuẩn bị mỗi lệnh DMA, không thêm nhịp từng beat. IOMMU kiểm tra length
  bằng offset trang và kiểm tra bit cao thay cho phép tính địa chỉ rộng.
- Sửa race thu hồi quyền/TLB fill, tràn range ở cấu hình địa chỉ hẹp, cờ
  DONE/ERROR khi abort muộn, STATS mode, parser container và cleanup file lỗi.
  Chi tiết và log tái hiện: [báo cáo rà soát](../../docs/RA_SOAT_KIEM_CHUNG_2026-09-27.md).
- Reset đồng bộ được phân phối qua bốn nhóm thanh ghi cùng cạnh clock,
  giảm fanout và bỏ reset bất đồng bộ trực tiếp tới điều khiển BRAM.
- Sửa reset vector firmware: tắt GNU build-id, loại `.note*`, linker kiểm tra
  `_start == 0` và giới hạn vùng nhớ.
- Dùng tối ưu placement/physical/routing; bitstream bị chặn nếu setup/hold âm.

| Bộ kiểm tra XSim | Kết quả hiện tại |
|---|---|
| Router AXI bộ nhớ mở rộng cũ | PASS |
| AXI, SHAKE F/H, UART, GPIO, bridge DMA | PASS |
| CPU boot, DMA nội bộ và SHAKE known-answer | PASS |
| Reset giữa DMA ghi, sau đó hai lần boot/DMA/SHAKE | PASS |
| Ảnh firmware C thật: startup và DMA RAM roundtrip | PASS |
| DMA/IOMMU: M2M/S2M/M2S, backpressure, quyền, lỗi AXI, descriptor, reset | PASS |
| Kiểm tra snapshot DMA đầy đủ | 39 lần PASS |
| Ma trận DMA 9 tổ hợp, gồm phục hồi | 456 lệnh hợp lệ PASS, 129.738 word đối chiếu |
| Cấu hình/quyền sai và lỗi AXI | 51 ca từ chối + 48 ca lỗi bus/phục hồi PASS |
| FIFO descriptor/completion depth 4 và 8 | 80.000 lượt mô hình độc lập PASS |
| Adapter DMA → SHAKE F/H, backpressure, framing lỗi, abort, reset và scrub | PASS |
| IOMMU secure-local: chặn vault/stack/boot/MMIO và alias vật lý | PASS |
| Firmware RV32 thật gọi DMA F known-answer | PASS |
| RV32 UART SLH3: bounds/state/context 255 byte/chunk/retry/CRC/phục hồi | PASS, 23 response đã kiểm tra |
| F/H RTL đối chiếu `hashlib.shake_256` độc lập | 256 vector + 20 ca lỗi PASS |
| Scheduler đối chiếu mô hình độc lập | 512 lệnh / 56.482 descriptor + 6 lệnh lỗi PASS |
| IOMMU range / maintenance race | 51.202 yêu cầu / 30 response PASS |
| Khởi tạo GUI Windows/FPGA và kiểm tra bounds, không mở COM/window | PASS |
| Engine dịch vụ native + Windows containers + UTF-8 context + benchmark 3 mode | PASS, không phải FPGA |
| NIST ACVP SLH-DSA-SHAKE-256f | 104/104 PASS, phần mềm Windows |
| Native service boundary/state/fault injection | 69.522 assertion PASS; không phải RTL/FPGA |
| ACVP qua hook F/H/PRF giả lập C | 104 vector × 3 mode PASS; không phải 312 vector khác nhau |
| Windows container và lỗi ghi file | 151 ca PASS + mock commit-failure cleanup PASS |

Log nằm trong `output_portable/sim_regression` và
`output_portable/dma_regression`. Mô phỏng là kiểm tra chức năng RTL, không
phải đo Fmax: tốc độ được xác nhận riêng bằng timing post-route bên trên.
Hồi quy SoC hiện có **9 testbench đều PASS** trong
`dma_audit_20260928_soc_final.log`; tổng hợp phần mềm/RTL trong
`dma_audit_20260928_review_final.log`.
Firmware đã sửa linker `.sdata/.sbss` và dọn payload trước cached reply:
không trả response rồi tiếp tục scrub khiến request tiếp theo tràn UART.

DRC mặc định không có vi phạm. Báo cáo methodology của implementation vẫn
có cảnh báo LUTAR-1 cho OR reset nút nhấn/MMCM trước chuỗi đồng bộ reset
wrapper và XDCB-5 về hiệu quả truy vấn pin XDC. Không tuyên bố mọi loại
cảnh báo của Vivado đã bằng 0. UART RX và nút reset là đầu vào bất đồng bộ;
chỉ đường vào bộ đồng bộ được loại khỏi setup. UART TX/LED được giới hạn
propagation 8 ns. Không che đường dữ liệu nội bộ bằng false/multicycle path.

## Mở, mô phỏng, build và nạp

Từ PowerShell tại `C:\SHAKE256`:

```powershell
.\open_vivado.ps1
.\hardware\soc\scripts\test_soc.ps1
.\hardware\soc\scripts\test_portable_dma.ps1
.\hardware\soc\scripts\test_dma_matrix.ps1
# Chỉ cần lệnh dưới nếu muốn build lại toàn bộ:
.\hardware\soc\scripts\build_portable_soc.ps1
# Rà soát mở rộng (native/RTL; không giả lập kết quả board):
.\hardware\soc\scripts\test_review.ps1 -VerifyNistProvenance
```

- Project duy nhất đang dùng: `build_portable/portable_slh_soc.xpr`.
- Top: `vc707_portable_wrapper`.
- File nạp: `output_portable/portable_slh_soc_vc707.bit`.
- Checkpoint đã nghiệm thu: `output_portable/portable_soc_routed.dcp`.
- Bằng chứng: `output_portable/timing_summary.rpt`, `drc.rpt`,
  `bitstream_drc.rpt`, `methodology.rpt`, `artifact_recheck.log`,
  `utilization.rpt`, `ip_timing/summary.csv`.
- Vivado **Run Behavioral Simulation** chạy `tb_portable_service_boot`
  đến UART `DMA F/H STREAM KAT PASS` rồi dừng. Boot KAT kiểm tra F;
  testbench adapter độc lập kiểm tra cả F và H.
- Build script dừng run project ở routing rồi finalize checkpoint và xuất
  bitstream riêng; nếu GUI báo Out-of-date hoặc bước post-route chưa chạy, mở checkpoint
  nghiệm thu bằng **File → Checkpoint → Open** để xem implementation cuối.
- Nạp bitstream bằng Hardware Manager; mở COM 115200, 8N1, reset board.
  LED0 = firmware PASS, LED1 = FAIL, LED4 = CPU trap, LED5 = AXI error.

## Giới hạn phải nói rõ khi báo cáo đồ án

Đây là SoC đồng thiết kế phần cứng/phần mềm: FORS, WOTS+, XMSS và hypertree
chạy bằng firmware PicoRV32; F/H dùng accelerator RTL. Không gọi đây là
toàn bộ SLH-DSA được thực hiện bằng mạch RTL chuyên dụng.

Firmware RV32 keygen/sign/verify đã biên dịch; bài startup/DMA dừng trước
keygen/sign/verify. **Chưa nạp board và chưa xác nhận bài SLH-DSA đầy đủ
end-to-end trên VC707 trong phiên này.** Test phần mềm Windows không thay
thế kiểm thử firmware trên CPU FPGA.

Firmware chính nay là dịch vụ SLH3, dùng seed/addrnd Windows CSPRNG qua
UART tin cậy, không dùng seed cố định của selftest. Chưa có TRNG trên kit
được đánh giá; host thấy seed và UART chưa mã hóa/xác thực. Vault ngăn DMA,
không ngăn CPU/JTAG, không thay thế chống side-channel/fault injection.
Bản này là prototype đồ án, chưa phải HSM
hoặc sản phẩm chữ ký số thương mại đã chứng nhận.

## Nhận diện đúng ảnh build

SHA-256 bitstream:
`B4169BE8EB061DD4EE81DC47413F861CD57D80D4F4838280EA8129F97027F4F0`.

SHA-256 firmware binary:
`0829A5F52211569E1B21972C3437082CBDB01935CEA8904A653749C2C0E7C2AD`.

Hash dùng để nhận diện file đã kiểm chứng, không thay thế chữ ký phát hành
hay chứng nhận bảo mật. Các lần build sau lưu console Vivado vào
`output_portable/portable_build.log`.

`output_portable/release_manifest.json` lưu hash source, firmware, phần mềm
Windows, checkpoint, bitstream và các bằng chứng đã rà soát. Chạy
`scripts/verify_service_release.ps1` để phát hiện source hoặc artifact đổi
so với bộ đã kiểm chứng. Manifest không chứa khóa/tài liệu người dùng,
không có chữ ký mật mã và không tự cấp chứng nhận cho một build mới.
