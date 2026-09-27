# SoC SLH-DSA portable

Bản chính dùng CPU PicoRV32, AXI, SHAKE256 F/H, DMA/IOMMU, UART,
timer/GPIO và ba RAM nội bộ 64 KiB. Hệ thống khởi động không cần DDR3.

**Bản nâng cấp mới:** [dịch vụ UART, DMA stream, benchmark và vault](SERVICE_GUIDE.md).
Firmware mặc định không tự ký seed mẫu nữa; nó chờ yêu cầu từ app Windows.

## Các file chính

| File | Trách nhiệm |
|---|---|
| `../rtl/soc/portable_slh_soc_core.v` | Toàn bộ SoC, nhận `clk/resetn`, không chứa MIG, MMCM, IBUFDS hoặc chân kit |
| `../boards/vc707/rtl/vc707_portable_wrapper.v` | Clock/reset của VC707, UART và 8 LED |
| `../boards/vc707/constraints/vc707_portable.xdc` | Chân VC707 và ràng buộc timing |
| `firmware/main_slh_service.c` / `slh_service.c` | Boot/DMA KAT, giao thức UART SLH3, keygen/sign/verify/zeroize |
| `firmware/main_slh_dsa.c` | Selftest cũ, chỉ chọn khi build `-Selftest`; không phải bản nạp chính |
| `../rtl/sphincs_shake256/slh_dma_stream_adapter.v` | DMA AXIS ↔ accelerator F/H dùng chung, watchdog và cleanup |
| `scripts/build_portable_soc.ps1` | Biên dịch firmware RV32 và build Vivado bản portable |
| `scripts/test_soc.ps1` | Mô phỏng hồi quy RTL và khởi động firmware C |
| `scripts/test_portable_dma.ps1` | Hồi quy DMA/IOMMU: backpressure, phân quyền, lỗi AXI, descriptor và reset |

```text
Kit FPGA
  clock/reset, UART, LED
          |
  wrapper riêng của kit
          |
  portable_slh_soc_core
     PicoRV32 ------ AXI fabric ------ RAM0 / RAM1 / RAM2
                        |------------ SHAKE256 F/H
                        |------------ UART, timer/GPIO
     DMA/IOMMU ---------+------------ DMA control
          |
     AXI memory extension (tùy chọn, tắt mặc định)
```

## Bộ nhớ và firmware

| Vùng | Địa chỉ | Kích thước / công dụng |
|---|---|---|
| RAM0 | `0x00000000` | 64 KiB, firmware và hằng số |
| RAM1 | `0x00010000` | 64 KiB, chữ ký, public key và dữ liệu |
| RAM2 | `0x00020000` | Workspace đến `0x2AFFF`, service stack, vault 4 KiB, crypto stack 8 KiB |
| SHAKE F/H | `0x00030000` | Register map của accelerator |
| UART | `0x00031000` | Truyền nhận UART |
| Timer/GPIO | `0x00032000` | Timer 64 bit và trạng thái firmware |
| DMA/IOMMU | `0x00033000` | Descriptor, ánh xạ và quyền truy cập |
| DMA hash stream | `0x00034000` | ARM/ABORT, busy/done/error, ID |

Kích thước text/data/BSS của firmware dịch vụ được ghi trong
[biên bản kiểm chứng](ACCEPTANCE.md) của bản phát hành hiện tại.
Service stack ở `0x2B000..0x2CFFF`, vault `0x2D000..0x2DFFF`, crypto stack
`0x2E000..0x2FFFF`; cả ba cấm DMA. Linker kiểm tra `_start == 0` và giới
hạn code/BSS/vault. DMA mẫu chỉ dùng lúc boot trước khi nhận yêu cầu.

Bài DMA portable thực hiện RAM1 → RAM2, so sánh dữ liệu, xóa bản gốc RAM1,
DMA RAM2 → RAM1 và so sánh lại. IOMMU chỉ ánh xạ hai trang RAM cần cho bài thử.
`build_slh_firmware.ps1 -Selftest` xuất `slh_dsa_portable_selftest.mem/bin/elf`
riêng, không ghi đè ảnh dịch vụ `slh_dsa_portable.*`.

## Build, mở và nạp

```powershell
cd C:\SHAKE256
.\hardware\soc\scripts\build_portable_soc.ps1
.\hardware\soc\scripts\test_soc.ps1
.\hardware\soc\scripts\test_portable_dma.ps1
.\open_vivado.ps1
```

Project chính: `build_portable/portable_slh_soc.xpr`.
Top chính: `vc707_portable_wrapper`.
Bitstream chỉ được xuất khi setup và hold đạt:
`output_portable/portable_slh_soc_vc707.bit`.
Báo cáo timing và tài nguyên nằm cùng thư mục `output_portable`.
Kết quả bản hiện tại và phạm vi kiểm chứng: [ACCEPTANCE.md](ACCEPTANCE.md).

Trong Vivado, chọn **Run Simulation → Run Behavioral Simulation** để chạy
`tb_portable_service_boot`. Test này chạy ảnh firmware C thật đến dòng UART
`DMA F/H STREAM KAT PASS` rồi dừng, không phải bài ký đầy đủ. Muốn chạy
cả bộ hồi quy, dùng hai script `test_soc.ps1` và `test_portable_dma.ps1` ở trên.

Đối số `ClockMHz` phải tương ứng bộ chia MMCM hợp lệ ở bước 0,125.
200 MHz dùng bộ chia 5; 250 MHz dùng bộ chia 4; 296,296296 MHz dùng bộ
chia 3,375 với VCO 1 GHz. Script build và wrapper mặc định cùng mức 296,296296 MHz.
Tần số yêu cầu không tự động có nghĩa là đã đạt: xem báo cáo post-route.

Để thử lại placement/routing khi chỉ đổi XDC hoặc chiến lược timing, có thể
thêm `-ReuseSynthesis`. Chế độ này bắt buộc cùng clock/generic, có checkpoint
synthesis và không có file RTL/ảnh RAM mới hơn checkpoint. Khi đổi RTL hoặc
firmware, dùng build đầy đủ (không thêm cờ này).

Thử nghiệm clock tách riêng bằng `-ClockMHz <MHz> -ExperimentName <ten>`.
Project/report thử nằm trong `output_portable/experiments/<ten>`, không phải
bản nạp chính. Không tự thay bitstream chính bằng một ảnh thử chưa nghiệm thu.

UART của bản nạp board dùng 115200 baud, 8N1. LED0 = boot/KAT PASS, service READY,
LED1 = FAIL firmware, LED2/3 = trạng thái tiến trình; LED4 = CPU trap,
LED5 = AXI error, LED6 = SHAKE IRQ, LED7 = DMA IRQ.
LED0 không thay thế kết quả xác minh chữ ký trong app.

## Đổi kit

Giữ nguyên RTL lõi, register map và thuật toán firmware. Tạo wrapper mới để
chuyển clock nguồn của kit thành clock SoC, đồng bộ reset và nối UART/LED;
tạo XDC mới với part/pin/clock đúng. Thay part và top trong cấu hình build.
`CLOCK_HZ` phải khớp clock thật để UART và phép đo thời gian đúng.
Kit cần đủ tài nguyên cho thiết kế, đặc biệt 192 KiB block RAM; không phải
mọi kit nhỏ đều chứa được bản này. RAM được suy luận qua XPM trong source
AXI RAM hiện dùng, nên hỗ trợ nhiều kit AMD/Xilinx; để chuyển sang FPGA
hãng khác cần thay backend RAM và công cụ build phù hợp.

## DDR3 tùy chọn

`ENABLE_EXT_MEMORY=0` là mặc định. DMA nối thẳng vào AXI nội bộ, toàn bộ
logic bộ định tuyến và cổng mở rộng không dùng được loại bỏ khi tổng hợp.
Địa chỉ ngoài bản đồ nội bộ nhận lỗi AXI, không chờ DDR calibration.

Để dùng bộ nhớ ngoài, đặt `ENABLE_EXT_MEMORY=1`, nối `ext_m_axi_*` tới một
AXI slave bộ nhớ của nền tảng. Cửa sổ mở rộng là `0x80000000..0xBFFFFFFF`.
Nó hiện phục vụ DMA; CPU chưa truy cập trực tiếp cửa sổ này. MIG, bộ chuyển
clock/data-width và chân DDR thuộc wrapper mở rộng của kit.

`picorv32_slh_soc.v` là facade tương thích cho wrapper DDR cũ và dùng chung
lõi mới. `build_full_slh_soc_ddr.ps1` biên dịch firmware với
`SLH_USE_EXT_MEMORY` để giữ bài DDR riêng; nó không phải cấu hình chính.
**Firewall vault secure-local chỉ bật ở cấu hình portable mặc định.** Nhánh
`ENABLE_EXT_MEMORY=1` giữ policy cũ để tương thích DDR; chưa được nghiệm thu
với bảo vệ khóa của dịch vụ mới.

## Phạm vi kiểm chứng

RTL SHAKE và F/H có bài known-answer; AXI, ngoại vi, DMA roundtrip và
firmware C startup/DMA có hồi quy XSim. Firmware keygen/sign/verify được
biên dịch cho RV32I. Bài mô phỏng startup/DMA dừng sau DMA PASS, vì vậy không
được dùng kết quả đó để khẳng định keygen/sign/verify end-to-end đã chạy đạt.
Các phép FORS, WOTS+, XMSS và hypertree hiện được CPU thực hiện bằng firmware;
SHAKE F/H và PRF được tăng tốc RTL ở mode AXI/DMA. PRFmsg/Hmsg/T_l nhiều
khối vẫn là SHAKE256 firmware. Đây là đồng thiết kế phần cứng/phần mềm.

Seed/addrnd selftest cũ chỉ để kiểm tra. Dịch vụ chính nhận entropy từ
Windows CSPRNG qua UART tin cậy; chưa có TRNG kit được đánh giá, mã hóa UART,
secure boot hay chống side-channel.

## Thay đổi phục vụ timing và khởi động

PicoRV32 bật `TWO_CYCLE_ALU` và `TWO_CYCLE_COMPARE` để tách đường tổ hợp
ALU/so sánh; `BARREL_SHIFTER` giúp dịch bit nhanh hơn cho firmware SHAKE.
Đây là đánh đổi số chu kỳ mỗi lệnh lấy clock cao hơn. Fmax không đồng nghĩa
với số chữ ký/giây: vẫn cần đo thời gian keygen/sign/verify trên board.
AXI giữ các thanh ghi pipeline của fabric; CPU và DMA là hai master cùng
truy cập ba RAM qua crossbar, không thay bằng bus nối tiếp đơn giản hơn.

DMA chốt các thanh ghi thống kê qua một tầng pipeline: khi hoàn thành truyền,
các bộ đếm làm việc được đóng băng; chu kỳ kế tiếp mới xuất snapshot và tăng
`perf_seq`. Cách này bỏ đường tổ hợp dài từ AXI ready qua phép cộng/so sánh
32 bit tới enable của hàng trăm flip-flop thống kê. Dữ liệu DMA, IRQ hoàn thành
và giao thức AXI không bị thêm độ trễ; chỉ thời điểm công bố thống kê trễ một
chu kỳ. Phần mềm muốn đọc snapshot mới phải chờ `perf_seq` thay đổi.

Linker đã tắt GNU build-id và loại bỏ `.note*`. `_start` bắt buộc ở địa chỉ
`0x00000000`, trùng reset vector của CPU; nếu không, metadata ELF có thể đứng
trước lệnh khởi động và CPU trap ngay sau reset. Bài mô phỏng C startup/DMA
kiểm tra chính ảnh firmware được dùng cho build portable.

UART TX và LED không có thiết bị nhận đồng bộ theo clock SoC bên ngoài FPGA.
XDC giới hạn propagation của riêng 9 chân này ở 8 ns bằng `set_max_delay
-datapath_only`, không áp `set_output_delay` giả định receiver 250 MHz.
UART thật là 115200 baud (~8.680 ns/bit). Toàn bộ đường register-to-register
của CPU, AXI, RAM, DMA/IOMMU và SHAKE vẫn kiểm tra theo chu kỳ clock SoC, kể
cả setup/hold và recovery/removal reset. Không có ngoại lệ multicycle hay
false path để che đường dữ liệu nội bộ.

Cách ràng buộc tín hiệu bất đồng bộ tham khảo
[AMD UG903](https://docs.amd.com/r/2021.2-English/ug903-vivado-using-constraints/Constraining-Asynchronous-Signals).

Reset ngoài được wrapper đồng bộ trước khi vào core. Core phân phối reset
qua các thanh ghi đồng bộ riêng cho CPU, DMA, AXI/RAM và ngoại vi. Các bản
reset đổi trạng thái cùng một cạnh clock, thêm một chu kỳ khởi động, giảm
fanout toàn chip và tránh tín hiệu reset bất đồng bộ trực tiếp điều khiển
BRAM. Wrapper của kit khác phải giữ reset ít nhất vài chu kỳ clock hợp lệ.
Bài hồi quy SoC ngắt reset giữa giao dịch ghi DMA rồi khởi động lại hai lần,
kiểm tra DMA, SHAKE KAT, không CPU trap và giữ nguyên ảnh boot trong RAM0.

Bộ thống kê DMA dùng thêm bộ đếm byte còn lại bão hòa ở 0 để nhận biết beat
cuối của M2S. Nhờ vậy tín hiệu AXI ready không còn phải đi qua phép cộng
32 bit rồi phép so sánh 32 bit liên tiếp mới cập nhật trạng thái hoàn thành.
Byte tổng và thời gian đo vẫn tính từ handshake thực; bài hồi quy kiểm tra
bất biến `remaining = max(length - accepted_bytes, 0)` và snapshot sau freeze.
