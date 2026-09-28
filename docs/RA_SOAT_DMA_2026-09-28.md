# Rà soát DMA và hồi quy SoC — 28/09/2026

## Kết luận chức năng

Đã tái hiện và sửa **hai lỗi RTL** trong DMA/control plane. Bộ kiểm tra mở
rộng PASS đủ **9/9 tổ hợp**, không chỉ chạy lại 9 bài truyền ngắn trước đây.
Kết quả này không có nghĩa mọi lỗi có thể xảy ra đã được loại bỏ.

## 1. Chín tổ hợp là gì?

Ba hướng truyền nhân với ba chế độ phục vụ. Đây **không phải** ma trận
RAM0/RAM1/RAM2 × RAM0/RAM1/RAM2.

| Hướng truyền | Burst | Cycle-stealing | Transparent |
|---|---:|---:|---:|
| Memory → Memory (M2M) | 53 PASS | 53 PASS | 53 PASS |
| Stream → Memory (S2M) | 49 PASS | 49 PASS | 49 PASS |
| Memory → Stream (M2S) | 50 PASS | 50 PASS | 50 PASS |

Các số trên là **456 lệnh truyền hợp lệ** ghi vào `matrix_cases.csv`, bao gồm
các lượt phục hồi sau lỗi. Mỗi ô có 20 ca biên chỉ định + 24 ca giả ngẫu
nhiên tái lập được; số còn lại kiểm tra phục hồi. Các ca lỗi không được
cộng vào số PASS truyền hợp lệ.

- Burst: truyền nhiều beat trong một giao dịch AXI, giới hạn tối đa 16 beat.
- Cycle-stealing: chia nhỏ việc truyền, các giao dịch trong test là một beat.
- Transparent: nhường khi tín hiệu CPU-busy được bật; test thay đổi tín hiệu
  này trong khi DMA đang chạy, đồng thời kiểm tra dữ liệu và kết thúc.
- Stream là giao diện AXI-Stream giữa DMA và ngoại vi/accelerator, không phải
  một vùng RAM khác. Trong SoC, nó nối bộ chuyển đổi dữ liệu vào/ra SHAKE.

## 2. Hai lỗi đã sửa

### DMA-01: M2S báo DONE trước khi ngoại vi nhận hết dữ liệu

Engine đọc báo descriptor complete khi dữ liệu đọc đã đi vào FIFO nội bộ.
Điều này chưa đồng nghĩa ngoại vi đã nhận dữ liệu qua `TVALID && TREADY`.
Trước sửa, với `TREADY=0`, tái hiện được DONE khi ngoại vi nhận **0/8 word**.
Nếu có descriptor kế tiếp, lệnh tiếp theo có thể khởi động và thay bộ đếm
TLAST khi gói trước chưa thoát hết FIFO.

Sửa tại `hardware/rtl/dma/dma_mmu_axi_top.sv`: giữ status/error bằng thanh
ghi và chỉ chuyển status cho scheduler khi **cả status engine và handshake
TLAST của descriptor nội bộ** đã xảy ra. Áp dụng cho từng chunk. Không nối
TREADY trực tiếp vào đường tổ hợp DONE. M2S có thể tốn thêm chu kỳ điều khiển;
không đánh đổi tính đúng lấy latency thấp.

Kiểm tra sau sửa: chặn đầu ra 150 chu kỳ ở cả ba mode; chuỗi 9 gói/hàng đợi
completion đầy; lỗi đọc AXI trong khi đầu ra bị chặn; reset khi đang chặn.
Đều PASS. Nếu bên nhận giữ TREADY thấp mãi, DMA vẫn chờ: đây là backpressure,
không phải một cơ chế timeout ngoại vi tự động.

### DMA-02: ghi AXI-Lite không chọn byte vẫn commit bảng trang

Trước sửa, ghi `PT_FLAGS` với `WSTRB=0` vẫn phát xung `pt_write`: VPN/PPN
đã chuẩn bị có thể bị ghi vào bảng trang và TLB bị vô hiệu hóa dù giao dịch
không yêu cầu ghi byte nào.

Sửa tại `hardware/rtl/dma/dma_axil_regs.sv`: chỉ commit khi `WSTRB[0]=1`,
vì VALID/R/W nằm trong byte thấp. Các byte khác vẫn theo quy tắc merge strobe,
nhưng không tạo tác dụng phụ commit. Test WSTRB=0 và WSTRB=14 đều PASS;
64 tổ hợp ghi/đọc kiểm tra thêm mặt nạ byte, AW/W đến lệch nhau và BREADY bị chặn.

Log tái hiện trước sửa được giữ trong
`hardware/soc/output_portable/dma_audit_20260928/`:

- `m2s_early_done_before_fix.log`;
- `axil_zero_strobe_before_fix.log`;
- hai bản chụp RTL trước sửa để đối chiếu, không nằm trong manifest build.

## 3. Phạm vi test bổ sung

| Nhóm | Kết quả |
|---|---|
| Truyền hợp lệ 9 tổ hợp | 456 lệnh PASS |
| Cấu hình/địa chỉ/quyền không hợp lệ | 51 lệnh bị từ chối đúng; không phát AXI memory ngoài ý muốn |
| AXI SLVERR/DECERR đọc/ghi, lệnh 4 và 64 byte | 48 ca PASS, truyền tốt lại ngay không reset |
| Reset M2S khi đầu ra đang bị chặn | 3 mode PASS, không sót dữ liệu/status/queue |
| Kiểm tra AXI-Lite | 66 kiểm tra PASS |
| Chặn hoàn tất M2S | 3 mode PASS |
| Descriptor đầy / completion đầy / thứ tự completion | 9 gói, 9 completion đúng thứ tự; descriptor tràn bị từ chối |
| Dữ liệu được đối chiếu | 129.738 word 32 bit |
| FIFO descriptor và completion, depth 4 và 8 | 80.000 lượt so sánh với mô hình độc lập PASS |
| Hồi quy DMA cũ | PASS, 39 snapshot thống kê |

Chi tiết dữ liệu/biên đã thử:

- Độ dài chỉ định: 4, 8, 12, 28, 32, 60, 64, 68, 124, 128, 132, 252,
  256, 260, 1.024, 4.092, 4.096, 4.100, 8.188, 8.192 byte.
- Burst request: 0, 1, 2, 3, 15, 16, 255 và các giá trị giả ngẫu nhiên.
  Kiểm tra cách RTL chuẩn hóa/giới hạn chúng, không giả định 255 beat được hỗ trợ.
- Nguồn/đích lệch biên trang 4 KiB; ánh xạ trang vật lý không liên tiếp.
- Không có burst vượt biên 4 KiB hoặc quá 16 beat; mode không burst chỉ một beat.
- Guard word trước/sau đích, TKEEP/TLAST, dữ liệu giữ ổn định khi bị backpressure,
  số byte thống kê, mode/type, gói thiếu/trùng và DONE đến sớm.
- Length 0, length không chia hết cho 4, địa chỉ memory không căn 4 byte,
  mode không hợp lệ, quyền đọc/ghi bị cấm; sau đó kiểm tra phục hồi.
- FIFO: push/pop đồng thời, đầy/rỗng, từ chối overflow, wrap-around và flush.

Testbench DMA mở rộng dùng **DMA/IOMMU RTL thật nhưng AXI fabric/RAM mô phỏng**
trong `hardware/rtl/axi/test_models`. Không nhầm chúng với fabric/RAM dùng để
tổng hợp. Tích hợp fabric sản xuất và firmware RV32 được kiểm tra riêng qua
`test_soc.ps1`. RAM simulation và timing implementation là hai loại bằng chứng khác nhau.

## 4. Hồi quy ngoài DMA

- SHAKE256, THASH, AXI SHAKE security/protocol và wrapper self-test: PASS XSim.
  Chữ “BOARD” trong tên runner này chỉ là testbench wrapper, **không phải kit thật**.
- Scheduler: 512 lệnh / 56.482 descriptor, 6 lệnh sai — PASS mô hình độc lập.
- IOMMU range: 51.202 request — PASS; thu hồi quyền/TLB maintenance: 30 response PASS.
- Dịch vụ SLH-DSA native: 69.522 assertion PASS; 104 vector ACVP cho mỗi trong
  ba chế độ hook — PASS; 151 kiểm tra container và bài lỗi exclusive write PASS.
  Các hook native không phải phép đo thuật toán end-to-end trên FPGA.

**Toàn bộ 9 testbench tích hợp SoC trên source cuối cùng PASS**, gồm
256 vector SHAKE độc lập + 20 ca lỗi, firewall vùng nhớ, reset/reboot,
firmware DMA roundtrip, DMA F known-answer và UART RV32 23 response.
Log: `output_portable/dma_audit_20260928_soc_final.log`.

### Build vật lý và bản nạp mới

Vivado đã synthesis/place/route lại RTL đã sửa và tạo bitstream mới. Đọc lại
checkpoint cuối để kiểm tra độc lập cũng PASS; không dùng timing bản cũ.

| Chỉ tiêu | Kết quả |
|---|---:|
| Clock toàn SoC | 296,296296 MHz — giữ nguyên |
| Setup WNS / Hold WHS | +0,001 ns / +0,055 ns |
| Setup/hold endpoint vi phạm | 0 / 0 |
| DRC mặc định / bitstream_checks | 0 / 0 vi phạm |
| LUT / FF / RAMB36 / DSP | 16.731 / 17.682 / 48 / 0 |

Setup margin chỉ 1 ps theo báo cáo, vẫn sát biên; không tuyên bố tăng Fmax
hoặc tăng tốc độ ký. Methodology còn ba cảnh báo đã ghi nhận: một LUTAR-1
ở reset wrapper và hai XDCB-5 về hiệu quả truy vấn pin. Không gọi là sạch
mọi cảnh báo, và timing PASS không thay thế nghiệm thu board.

Đã đưa bản mới về **đường dẫn chính**, không cần chọn một project thử nghiệm:

- Project: `hardware/soc/build_portable/portable_slh_soc.xpr`.
- Bitstream: `hardware/soc/output_portable/portable_slh_soc_vc707.bit`.
- Checkpoint sau tối ưu: `hardware/soc/output_portable/portable_soc_routed.dcp`.
- SHA-256 bitstream:
  `B4169BE8EB061DD4EE81DC47413F861CD57D80D4F4838280EA8129F97027F4F0`.
- Bản cũ giữ tại `hardware/soc/output_portable/releases/pre_dma_fix_20260928/`.
  Project cũ trong backup chỉ để khôi phục về vị trí gốc, không mở để chạy bản mới.

Project mới vẫn tham chiếu source chung trong `hardware/rtl`; 52 đường dẫn
file trong project được kiểm tra tồn tại. Inventory **185 file source/artifact**
đã khớp hash qua `verify_service_release.ps1`. Vivado Save Project As giữ các kết
quả run; sign-off cuối là checkpoint/bitstream bên trên, vì finalize tối ưu
sau route ngoài run thông thường. Nếu GUI báo Out-of-date, không lấy checkpoint
trước finalize trong thư mục `.runs` làm bằng chứng timing cuối.

## 5. Tự chạy lại

Từ thư mục gốc `C:\SHAKE256`, dùng PowerShell:

```powershell
# Ma trận 9 tổ hợp, lỗi/phục hồi, hàng đợi và mô hình FIFO
.\hardware\soc\scripts\test_dma_matrix.ps1

# Toàn bộ tích hợp CPU/AXI/RAM/DMA/SHAKE/firmware/UART
.\hardware\soc\scripts\test_soc.ps1
.\hardware\soc\scripts\test_portable_dma.ps1

# Tổng hợp review phần mềm + RTL, đã tích hợp bộ ma trận mới
.\hardware\soc\scripts\test_review.ps1

# Các test SHAKE/THASH/AXI riêng
.\hardware\scripts\run_tests.ps1
```

Log ma trận và từng lệnh ở
`hardware/soc/output_portable/dma_matrix_review/`.
Log các lượt rà soát ở `hardware/soc/output_portable/dma_audit_20260928*.log`.
Test source/script được giữ trong repository; output có thể sinh lại và không đưa lên Git.

Đường dẫn log mặc định của fixture DMA cũng đã đổi từ đường dẫn máy cũ
`C:/rtl/rtl/Project_Vivado/reports/` sang file tương đối trong thư mục chạy.
Vì vậy chạy testbench gốc trực tiếp không còn cần tạo thư mục máy cũ.
Fixture gốc đã được elaborate/chạy trực tiếp và in `ALL DMA/MMU AXI TESTS PASSED`.
Giới hạn thu stream và số lượt polling được tham số hóa để thử gói dài;
đây là thay đổi testbench, không phải mở rộng giới hạn phần cứng.

## 6. Điều chưa được khẳng định

Chưa nghiệm thu trên kit thật; chưa chạy đầy đủ keygen/sign/verify qua UART
trên FPGA; chưa đo hiệu năng ký thực tế, nguồn entropy, side-channel hoặc
fault injection vật lý. Đây là mô phỏng hữu hạn, không phải formal proof.
Các giá trị độ dài, seed, FIFO depth ngoài tập đã thử không tự được coi là
đã kiểm chứng. Fmax cao cũng không thay thế kiểm tra tính đúng và an toàn.
