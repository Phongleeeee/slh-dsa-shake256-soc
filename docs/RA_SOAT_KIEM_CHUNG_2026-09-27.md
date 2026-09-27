# Rà soát mở rộng SoC SLH-DSA-SHAKE-256f — 27/09/2026

Phạm vi: source RTL/firmware/Windows hiện tại, kiểm thử chức năng bằng XSim
2025.1, engine C chạy native, đối chiếu NIST và timing Vivado trên
`xc7vx485tffg1761-2`. Chưa có COM của kit trong phiên kiểm tra này; không
ghi nhận phép ký đầy đủ hoặc số đo hiệu năng trên board thật.

## 1. Các lỗi đã tái hiện và sửa

| Phát hiện | Điều kiện tái hiện và ảnh hưởng | Sửa và kiểm tra hồi quy |
|---|---|---|
| DMA có thể bật DONE và ERROR cùng lúc | ABORT đến đúng cạnh nhận write-response của bước cleanup cuối. Hai cờ mâu thuẫn; driver đang kiểm tra cả hai vẫn từ chối, nhưng bộ điều khiển chỉ nhìn DONE có thể hiểu sai | DONE kiểm tra cả lỗi đang đến, không chỉ thanh ghi lỗi của chu kỳ trước. Test RTL tái hiện `done=1 error=1` trước sửa, đạt sau sửa |
| STATS gắn sai mode | Chạy một job bằng DMA rồi đổi sang CPU trước khi đọc STATS. Counters của job DMA bị ghi nhãn CPU | Chốt `last_mode` khi bắt đầu job; INFO vẫn trả mode hiện tại. Kiểm tra STATS giữ nguyên sau MODE và xóa đúng khi ZEROIZE |
| IOMMU tràn phép tính range ở cấu hình hẹp | `ADDR_WIDTH=16`, `LEN_WIDTH=20`, địa chỉ 0, độ dài `0x20004` bị rút gọn thành một range có vẻ hợp lệ | So sánh độ dài với phần còn lại của trang, kiểm tra toàn bộ bit cao; 51.202 yêu cầu ở cấu hình 16/20 và 32/32. Lỗi này không phải lỗi tràn của cấu hình SoC chính 32/32 |
| IOMMU giữ quyền cũ khi thu hồi | Page-table write trùng thời điểm nạp TLB từ một miss. Lệnh invalidation bị phép fill ghi đè; yêu cầu sau vẫn có thể được phép ghi | Maintenance ưu tiên hơn fill và khởi động lại lookup đang chờ. Kiểm tra MATCH/RESP/CHECK, TLB cold/warm, cả cập nhật bảng trang và flush. Descriptor AXI đã phát trước khi thu hồi không bị hủy ngược |
| Parser file chấp nhận bit không định nghĩa | Sửa flag chưa hỗ trợ hoặc byte reserved của container v1 vẫn được chấp nhận | Windows CLI và host FPGA cùng yêu cầu flag hợp lệ, reserved bằng 0. Host đọc file với giới hạn kích thước. Đây là siết định dạng, không phải bằng chứng giả mạo chữ ký hoặc phá DPAPI |
| Rò handle khi flush file thất bại | `_commit(fd)` trả lỗi khiến toán tử `||` bỏ qua `_close(fd)`; file tạo dở vẫn bị khóa và không xóa được | Luôn đóng handle trước khi xử lý lỗi. Test chèn lỗi CRT tái hiện `close_calls=0, file_remained=1` trước sửa và đạt sau sửa |

Log tái hiện được giữ ở `hardware/soc/output_portable/`:
`review_stream_before_fix.log`, `review_native_before_fix.log`,
`review_range_before_fix.log`, `review_maintenance_before_fix.log`,
`review_containers_before_fix.log`, `review_file_io_before_fix.log`. Không sửa tài liệu/khóa/chữ ký của người dùng.
Các file tạo khi kiểm thử đều là khóa và tài liệu mẫu mới trong thư mục review.

## 2. Kiểm thử mở rộng và phạm vi bằng chứng

| Bộ kiểm tra | Kết quả đã ghi nhận | Giới hạn |
|---|---|---|
| Nguồn vector NIST | 7/7 file cache khớp Git blob ID ở tag `v1.1.0.40` của `usnistgov/ACVP-Server`; ghi thêm SHA-256 từng file | Xác định đúng nguồn fixture, không phải chứng nhận CAVP |
| ACVP Windows | 104/104 PASS: keygen, sigGen, sigVer của SHAKE-256f | Chạy trên CPU Windows |
| ACVP đường hook accelerator | 104/104 PASS cho mỗi mode 0, 1, 2; tổng 312 lượt | Hook F/H/PRF giả lập bằng C, không phải RTL hoặc PicoRV32 thật |
| Service engine | 5.000 lệnh malformed/state theo seed cố định; 19 cặp kích thước message/context × 3 mode; so sánh toàn bộ byte chữ ký với bản C không tăng tốc; mutation, upload dở, UINT32_MAX offset, inject lỗi accelerator; 69.522 assertion PASS | Native, không dùng số chu kỳ giả lập làm số đo FPGA |
| SHAKE F/H RTL | 256 vector độc lập từ `hashlib.shake_256`: zero, FF, one-hot, random; stall đầu vào/đầu ra; 20 ca lỗi framing/abort và phục hồi | Kiểm tra cả mạch F/H thật qua adapter DMA. Không phải 256 lần chạy toàn SLH-DSA bằng RTL |
| Scheduler DMA | 512 lệnh hợp lệ, 56.482 descriptor đối chiếu mô hình riêng; 6 lệnh không hợp lệ; burst, 3 loại chuyển, 3 mode, biên trang và config đổi sau START | Mô hình phản hồi IOMMU/engine dùng trong test đơn vị; hồi quy tích hợp DMA kiểm tra riêng |
| Range IOMMU | 51.202 yêu cầu; quét đủ 4.096 offset trong trang, độ dài 0/1/đúng biên/vượt biên, địa chỉ cuối không gian và random length | Cả cấu hình 16-bit cũ lẫn 32-bit chính |
| Maintenance IOMMU | 30 response kiểm tra thu hồi quyền/flush giữa lookup, cache cold/warm | Không hủy descriptor đã được AXI nhận trước đó |
| DMA tích hợp | Hồi quy M2M/M2S/S2M, quyền, lỗi AXI, reset và 39 snapshot PASS | XSim |
| UART RV32 | Tăng từ 8 lên 23 response: context 255 byte, upload thiếu, sai offset, retry, sai mode/length/state, CRC recovery; firmware C thật | Không chạy full keygen/sign/verify trên RV32 ở bài này |
| File Windows | 151 ca PASS: pure/hedged/deterministic/prehash, header, truncation, dữ liệu thừa, bitflip, DPAPI và chống ghi đè | Chứng minh các ca đã thử, không chứng minh hết mọi đầu vào |
| File I/O lỗi | Chèn lỗi flush, kiểm tra trả lỗi/đóng handle/xóa file tạo dở PASS | Dùng mock CRT, không cố làm đầy hoặc gây lỗi ổ đĩa thật |
| Windows–service | Tương thích hai chiều và host workflow/UTF-8/benchmark đạt trên PowerShell 7 và 5; file hỏng bị từ chối trước khi gọi crypto | Backend native được đánh dấu rõ, không có COM thật |
| GUI | Khởi tạo, lựa chọn backend và bounds smoke test đạt | Không điều khiển GUI trên COM thật |

Chạy lại bộ mở rộng:

```powershell
cd C:\SHAKE256
.\hardware\soc\scripts\test_review.ps1 -VerifyNistProvenance
```

Các log sau sửa có tên `review_native.log`, `review_stream.log`,
`review_scheduler.log`, `review_dma.log`, `review_soc_final.log`,
`review_acvp_windows.log`, `review_acvp_mode0/1/2.log`,
`review_containers.log`, `review_interop.log`, `review_interop_ps5.log`,
`review_cli_tests.log`, `review_gui.log`, `review_acvp_provenance.log`.
Lần chạy lại bộ mở rộng tổng hợp được lưu ở `review_aggregate_final.log`.
Script mô phỏng dừng bằng exception khi compile/elaboration lỗi, tránh
script cha tiếp tục báo thành công sau khi một script con thoát thất bại.

## 3. Đối chiếu tiêu chuẩn

[FIPS 205, bảng 2 và các thuật toán 21–25](https://nvlpubs.nist.gov/nistpubs/fips/nist.fips.205.pdf)
cho cấu hình SHAKE-256f: `n=32, h=68, d=17, h'=4, a=9, k=35, lg(w)=4`.
Khóa công khai 64 byte, khóa bí mật thô 128 byte, chữ ký 49.856 byte và
context tối đa 255 byte phù hợp với đồ án. Có thể kiểm tra kích thước chữ ký:

```text
R                         = 32
FORS = 35 × (9+1) × 32    = 11.200
Hypertree = 17 × (67+4)×32 = 38.624
Tổng                      = 49.856 byte
```

F/H trong bản SHAKE băm `PK.seed || ADRS || input`. Với n=32, độ dài input
cho SHAKE lần lượt 96 và 128 byte; output 32 byte. Fixture RTL dùng Python
SHAKE256 độc lập để phát hiện nhầm thứ tự byte, padding, mode hoặc dữ liệu cũ.
Pure signing bao gồm domain separator và context; thử message rỗng vẫn phải
dùng đúng giao diện pure. `.slsig` có header riêng của đồ án nên lớn hơn chữ ký
thô, còn `.slsk` DPAPI lớn hơn 128 byte là bình thường.

Nguồn vector: [NIST ACVP-Server, tag v1.1.0.40](https://github.com/usnistgov/ACVP-Server/tree/v1.1.0.40/gen-val/json-files).
Cách phân biệt internal/external, pure/prehash và additional randomness:
[đặc tả ACVP SLH-DSA](https://pages.nist.gov/ACVP/draft-livelsberger-acvp-slh-dsa.html).
Manifest nguồn được lưu tại `hardware/soc/output_portable/review_acvp_provenance.json`.

## 4. So sánh với công bố, không chỉ nhìn MHz

| Công bố | Số liệu/phạm vi công bố | Ý nghĩa khi đối chiếu đồ án |
|---|---|---|
| Amiet và cộng sự, DSD 2020, *FPGA-based SPHINCS+ Implementations: Mind the Glitch* | SPHINCS+-256f-simple trên Artix-7: 51.009 LUT, 74.539 FF, clock hệ thống/Keccak 250/500 MHz, ký 2,52 ms, xác minh 0,21 ms | Kiến trúc pipeline lớn, hai clock, phiên bản SPHINCS+ trước FIPS 205; không lấy MHz của một khối hoặc kích thước chữ ký cũ để kết luận đồ án đúng/sai hay nhanh/chậm |
| Saarinen, NIST PQC 2024, *SLotH* | RISC-V và một hash unit; bảng SHAKE-256f: keygen 815.609, ký 23.660.226, xác minh 857.059 chu kỳ | Gần hướng đồng thiết kế của đồ án hơn. Cần đo cycles thật của đồ án để so sánh; đẩy chuỗi WOTS+ vào accelerator giảm số lần CPU truy cập thanh ghi |

Nguồn gốc bảng và kiến trúc:
[bài báo DSD 2020, trang 5–6](https://www.ost.ch/fileadmin/dateiliste/3_forschung_dienstleistung/institute/imes/publikationen/2020_fpga-based_sphincsplus_implementations_-_mind_the_glitch.pdf),
[slide SLotH, trang 7–10 và 16](https://csrc.nist.gov/csrc/media/Presentations/2024/accelerating-slh-dsa/images-media/saarinen-accelerating-slh-dsa-pqc2024.pdf).

Đồ án có CPU, AXI, DMA/IOMMU, UART và 192 KiB RAM; không phải cùng phạm vi
tài nguyên với riêng hash core. Chưa có latency ký trên board nên chưa thể
tuyên bố vượt các công bố. Các nghiên cứu cũng chỉ ra bảo vệ chống lỗi vật lý
cần đánh giá riêng; ký xong xác minh lại không tự chứng minh khả năng chống
fault injection.

## 5. Fmax và bản phát hành

Baseline trước rà soát: 275,862069 MHz, WNS +0,059 ns, WHS +0,048 ns.
Đã sao lưu bitstream/checkpoint/firmware/report tại
`hardware/soc/output_portable/releases/275MHz_before_review`.

Tối ưu RTL:

1. Scheduler chốt descriptor rồi tính số byte còn lại trong trang ở chu kỳ
   riêng. Thêm một nhịp mỗi lệnh DMA, không thêm nhịp vào từng beat dữ liệu.
2. IOMMU kiểm tra range bằng offset và độ dài trong trang; bỏ đường cộng/trừ
   địa chỉ rộng. Bit cao của length vẫn được kiểm tra để không đánh đổi tính đúng.

Thử nghiệm 285,714286 MHz đã đạt +0,024 ns setup và +0,064 ns hold. Đây là
ảnh thử giữa quá trình rà soát, trước khi tích hợp đủ sửa lỗi; không dùng ảnh
thử này thay bản phát hành chính.

**Build cuối từ toàn bộ source đã sửa đạt 296,296296 MHz**: period 3,375 ns,
setup WNS **0,000 ns**, hold WHS **+0,067 ns**, TNS/THS và endpoint vi phạm
bằng 0, pulse-width slack +0,919 ns. Tăng **7,407%** so với baseline.
Tài nguyên: 16.715 LUT, 17.679 FF, 48 RAMB36, 0 DSP; thêm 27 LUT và 2 FF.
Critical path nay là IOMMU `req_vaddr_q_reg[17]` → `match_pt_index_q_reg[3]`.
Đây là mức cao nhất đã build đạt trong phiên, không phải giới hạn vật lý
tuyệt đối. Setup đã sát biên; không coi đây là xác nhận độ ổn định trên kit.

Project chính: `hardware/soc/build_portable/portable_slh_soc.xpr`.
Bitstream: `hardware/soc/output_portable/portable_slh_soc_vc707.bit`.
Chi tiết từng IP, hash và giới hạn: [ACCEPTANCE.md](../hardware/soc/ACCEPTANCE.md).
Đọc lại checkpoint phát hành lúc 14:54 ngày 27/09/2026 đạt timing gate;
DRC mặc định và `bitstream_checks` đều 0 vi phạm. Methodology còn 3 cảnh báo
(1 LUTAR-1 ở reset wrapper, 2 XDCB-5 truy vấn pin), không tuyên bố sạch mọi
cảnh báo. Manifest nhận diện **148 file** source/artifact đã khớp khi chạy
`hardware/soc/scripts/verify_service_release.ps1`.

Retime cùng placement thử 296 MHz ở mức 307,692308 MHz cho setup -0,124 ns.
Đây chỉ là chẩn đoán timing trên checkpoint, không phải build 307 MHz hoặc
bitstream có thể nạp (UART/timer chưa đổi theo). Kết quả không chứng minh
307 MHz là bất khả thi với kiến trúc/placement khác. Xem
`output_portable/review_frequency_headroom.csv`.

Clock tăng chỉ giảm phần thời gian phụ thuộc số chu kỳ. UART 115.200 baud
vẫn cần ít nhất khoảng 4,33 giây truyền 49.856 byte (8N1). Phải so thêm chu kỳ
mỗi phép ký, latency đầu-cuối và tài nguyên; không thêm pipeline tùy ý chỉ để
báo MHz cao hơn. Không nới ràng buộc bằng false path/multicycle nội bộ.

## 6. Giới hạn còn lại

- Full keygen/sign/verify trên PicoRV32 thật, COM thực tế và benchmark board
  vẫn cần nghiệm thu với kit. Hồi quy native và ACVP không thay bước này.
- File FPGA vẫn tối đa 16 KiB pure; prehash ở Windows không đồng nghĩa FPGA
  đã hỗ trợ HashSLH streaming.
- Chưa có TRNG FPGA qualification, UART xác thực/mã hóa, secure boot,
  bảo vệ CPU/JTAG, chống side-channel/fault hoặc chứng nhận sản phẩm.
- GCC RV32 `-fstack-usage` ghi frame lớn nhất `xmss_node=2528 byte`,
  `wots_pk_from_sig=2464 byte`, `slh_sign=656 byte`, `slh_verify=672 byte`.
  Đây là từng frame, không phải tổng stack; callback và chuỗi gọi phải cộng
  dồn. Chưa có đo high-water/canary trên board, nên không tuyên bố đã chứng
  minh mọi đường đều nằm trong private stack 8 KiB.
- Các bộ test là tập kiểm tra có thể tái lập, không phải chứng minh hình thức
  hoặc bằng chứng rằng mọi lỗi đã được loại bỏ.
