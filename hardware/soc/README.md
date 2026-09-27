# SoC portable SLH-DSA-SHAKE-256f

Bản chính hiện tại dùng `portable_slh_soc_core.v` và
`vc707_portable_wrapper.v`, boot từ RAM nội bộ, không cần DDR3/MIG.
Xem [hướng dẫn portable](PORTABLE_SOC.md) để build, mở đúng project và đổi kit.
Xem [SERVICE_GUIDE.md](SERVICE_GUIDE.md) để dùng app FPGA UART, DMA hashing,
benchmark và hiểu cơ chế bảo vệ khóa của bản mới.

```powershell
.\hardware\soc\scripts\build_portable_soc.ps1
.\hardware\soc\scripts\test_soc.ps1
.\open_vivado.ps1
```

Project chính: `build_portable/portable_slh_soc.xpr`.
Kết quả hiện tại: [biên bản kiểm chứng portable](ACCEPTANCE.md).
Các phần bên dưới mô tả bản mở rộng DDR trước đây và kết quả timing của bản
đó; không dùng mức 106,67 MHz này làm Fmax của bản portable mới.

---

# Bản mở rộng DDR tùy chọn trên VC707

Project này là một FPGA SoC tự chứa cho kit Xilinx VC707 (`xc7vx485tffg1761-2`).
Nó ghép PicoRV32, AXI, DMA/IOMMU, BRAM, DDR3/MIG, UART và IP tăng tốc
SHAKE256 để chạy đầy đủ luồng keygen, ký và xác minh
SLH-DSA-SHAKE-256f theo FIPS 205.

Đây là kiến trúc **đồng thiết kế phần cứng/phần mềm**:

- PicoRV32 chạy firmware FIPS 205 và điều phối FORS, WOTS+, XMSS/hypertree.
- RTL SHAKE256 tăng tốc các phép F và H dùng nhiều nhất trong SLH-DSA.
- DMA di chuyển các khối dữ liệu độc lập với CPU; IOMMU giới hạn vùng DMA được phép truy cập.
- DDR3 của VC707 được nối qua MIG để có vùng nhớ ngoài cho thông điệp, chữ ký và vùng làm việc lớn.

Nó không có nghĩa toàn bộ FORS/WOTS+/XMSS đều đã được viết lại thành các khối RTL
riêng. Toàn bộ thuật toán chạy bên trong FPGA SoC, nhưng vẫn có phần firmware chạy
trên CPU mềm.

## Sơ đồ kiến trúc

```text
                         VC707 DDR3
                             ^
                             | AXI4 qua clock/data-width converter
                             | và Xilinx MIG
                             |
PicoRV32 ---- AXI master ----+---------------- AXI fabric
    |                        |                     |
    | IRQ                    |                     +-- RAM0: firmware 64 KiB
    |                        |                     +-- RAM1: data 64 KiB
    |                        |                     +-- RAM2: data 64 KiB
    |                        |                     +-- SHAKE256 F/H accelerator
    |                        |                     +-- UART
    |                        |                     +-- timer/GPIO
    |                        |                     +-- DMA/IOMMU control
    |                        |
    +-------------------- DMA/IOMMU master
                              |
                              +-- địa chỉ thấp: BRAM/ngoại vi cục bộ
                              +-- 0x8000_0000..0xBFFF_FFFF: DDR3
```

Bộ định tuyến DMA giữ kênh đọc và ghi độc lập. Vì vậy CDMA có thể phát địa chỉ
đọc và ghi đồng thời mà không khóa chéo AXI khi sao chép BRAM↔BRAM hoặc
BRAM↔DDR3.

## Bản đồ địa chỉ

| Địa chỉ | Khối | Công dụng |
|---|---|---|
| `0x0000_0000` | RAM0, 64 KiB | mã chương trình/boot firmware |
| `0x0001_0000` | RAM1, 64 KiB | dữ liệu cục bộ |
| `0x0002_0000` | RAM2, 64 KiB | dữ liệu cục bộ |
| `0x0003_0000` | SHAKE256 F/H | thanh ghi lệnh, đầu vào, đầu ra, IRQ và zeroize |
| `0x0003_1000` | UART | UART 115200, 8N1 |
| `0x0003_2000` | timer/GPIO | bộ đếm 64-bit và tín hiệu trạng thái |
| `0x0003_3000` | DMA/IOMMU | cấu hình CDMA, ánh xạ/quyền truy cập và trạng thái |
| `0x8000_0000`–`0xBFFF_FFFF` | cửa sổ DDR3 của DMA | vùng nhớ ngoài qua MIG |

IRQ 5 là SHAKE, IRQ 6 là UART, IRQ 7 là timer và IRQ 8 là DMA.
`bus_error` giữ lại mọi phản hồi AXI lỗi để hỗ trợ chẩn đoán.

## Firmware SLH-DSA đầy đủ

Firmware `main_slh_dsa.c` thực hiện bài tự kiểm tra sau:

1. Dùng DMA chép mẫu BRAM→DDR3→BRAM và so sánh dữ liệu nhận lại.
2. Kiểm tra ID/khả năng phản hồi của IP SHAKE256.
3. Tạo cặp khóa SLH-DSA-SHAKE-256f từ ba seed 32 byte.
4. Ký một thông điệp với context `DO-AN-VC707`.
5. Kiểm tra chữ ký hợp lệ.
6. Sửa một bit chữ ký và kiểm tra bắt buộc phải bị từ chối.
7. Zeroize các thanh ghi dữ liệu nhạy cảm trong IP SHAKE.

F/H có đường tăng tốc phần cứng và tự quay về SHAKE256 phần mềm nếu accelerator
không phản hồi. Những seed trong firmware hiện tại là mẫu xác định để kết quả
tự kiểm tra có thể lặp lại. Chúng **không phải số ngẫu nhiên an toàn** và không
được dùng để tạo khóa thật.

## Build và kiểm tra

Mở PowerShell tại `C:\SHAKE256`.

Chạy mô phỏng hồi quy AXI, DMA và SHAKE KAT:

```powershell
powershell -ExecutionPolicy Bypass -File .\hardware\soc\scripts\test_soc.ps1
```

Build bản BRAM cơ bản:

```powershell
powershell -ExecutionPolicy Bypass -File .\hardware\soc\scripts\build_soc.ps1
```

Build bản DMA + DDR3/MIG với firmware KAT ngắn:

```powershell
powershell -ExecutionPolicy Bypass -File .\hardware\soc\scripts\build_soc_ddr.ps1
```

Build bản đầy đủ được khuyến nghị, gồm firmware keygen/sign/verify:

```powershell
powershell -ExecutionPolicy Bypass -File .\hardware\soc\scripts\build_full_slh_soc_ddr.ps1
```

Bitstream đầy đủ được đặt tại:

```text
C:\SHAKE256\hardware\soc\output_ddr\picorv32_full_slh_dsa_dma_ddr_vc707.bit
```

Script firmware tự tìm RISC-V GCC đi kèm Vivado 2025.1. Firmware đã biên dịch có
18,308 byte mã và 50,048 byte BSS, phù hợp với RAM0 64 KiB và hai RAM dữ liệu.

## Trạng thái kiểm chứng

| Hạng mục | Trạng thái |
|---|---|
| AXI ngoại vi, UART, GPIO, SHAKE F/H | mô phỏng đạt |
| DMA BRAM1→BRAM2 và IOMMU | mô phỏng đạt |
| Firmware boot trên PicoRV32 + DMA + SHAKE KAT | mô phỏng đạt |
| Thư viện FIPS 205 trên máy tính | self-test keygen/sign/verify và negative test đạt |
| Firmware SLH-DSA-SHAKE-256f cho RV32I | biên dịch và nhúng BRAM đạt |
| MIG DDR3, clock converter, width converter | Vivado tổng hợp/đặt tuyến/tạo bitstream đạt |
| Keygen/sign/verify đầy đủ trên VC707 thật | cần nạp board và đo qua UART |
| Nguồn entropy an toàn dùng cho khóa thật | chưa hoàn thành |

Bản DDR hiện chạy SoC ở **106.666667 MHz** (MMCM 600 MHz chia 5.625), tăng
6.67% so với bản 100 MHz. Kết quả post-route của bitstream đầy đủ: WNS tổng thể
`+0.177 ns`, TNS `0`; riêng miền clock SoC có WNS `+0.233 ns`. Mọi timing
constraint đều đạt. Từ critical path của miền SoC có thể ước lượng giới hạn
khoảng `109.4 MHz`. Nấc MMCM tiếp theo là 109.09 MHz chỉ còn biên lý thuyết
khoảng 0.025 ns, nên bản chính giữ 106.67 MHz để có biên route hợp lý.

Đường khẳng định reset từ MIG/MMCM là bất đồng bộ theo chủ đích và đường nhả
reset đi qua ba tầng đồng bộ. Ba chân PRE của synchronizer được đánh dấu
false-path chính xác; không có đường dữ liệu CPU/AXI/SHAKE nào bị bỏ kiểm tra.

Tài nguyên toàn top: 32,408 LUT tổng, 29,849 logic LUT, 33,291 FF, 48 RAMB36
và 0 DSP. Bitstream đầy đủ có kích thước 5,796,147 byte và SHA-256:
`C9E44D4385BF05EEC617791AF859AB8C5843F20009901B1D0C67C27240E24D32`.

MIG có một số cảnh báo placement/clocking do thiết kế IP gốc dùng override
`CLOCK_DEDICATED_ROUTE`; báo cáo cuối có 0 DRC error và 24 warning (đa số là
RAMB36 async-control của fabric cùng cảnh báo clock/placement từ MIG). Vivado
vẫn tạo bitstream, nhưng cần kiểm chứng DDR calibration và độ ổn định trên
VC707 thật trước khi xem là sản phẩm hoàn thiện.

## Nạp VC707 và quan sát

1. Nối JTAG, USB-UART và DDR3 trên VC707 như cấu hình mặc định của board.
2. Program bitstream đầy đủ bằng Vivado Hardware Manager.
3. Mở cổng COM ở 115200 baud, 8 data bits, no parity, 1 stop bit.
4. LED0 phải sáng khi MIG hoàn tất calibration.
5. Chờ UART in lần lượt:

```text
SLH-DSA-256f FULL SELFTEST START
DMA DDR3 ROUNDTRIP PASS
KEYGEN PASS
SIGN PASS
VERIFY + NEGATIVE TEST PASS
FULL SLH-DSA SELFTEST PASS
```

SLH-DSA-SHAKE-256f là tham số ưu tiên tốc độ nhưng chữ ký vẫn rất lớn và số lần
băm nhiều, nên chạy đầy đủ trên PicoRV32 có thể lâu. Không ngắt nguồn chỉ vì UART
chưa in ngay kết quả tiếp theo.

Ý nghĩa LED của top DDR:

| LED | Ý nghĩa |
|---|---|
| 0 | MIG DDR3 calibration hoàn tất |
| 1 | CPU trap |
| 2 | AXI bus error |
| 3 | DMA IRQ |
| 4 | SHAKE IRQ |
| 5 | UART IRQ |
| 6 | timer IRQ |
| 7 | GPIO trạng thái firmware |

## Phần còn thiếu để dùng như sản phẩm bảo mật

Nguồn ngẫu nhiên an toàn là hạng mục bắt buộc còn thiếu. Bản tự kiểm tra dùng
seed cố định; nếu dùng seed này để tạo khóa thật thì các khóa sẽ lặp lại và mất
an toàn. Phiên bản sản phẩm cần một nguồn entropy đã được đánh giá (TRNG ngoài
hoặc mạch entropy phần cứng đã đặc tính hóa), kiểm tra sức khỏe theo SP 800-90B,
bộ điều hòa SHAKE256/DRBG, cơ chế fail-closed, zeroization và thử nghiệm theo
nhiệt độ/điện áp. Không nên gọi một mạch ring oscillator chưa được đánh giá là
“TRNG an toàn”.

Ngoài ra cần chạy keygen/sign/verify nhiều lần trên board thật, đo thời gian và
băng thông DMA/DDR, thử reset/lỗi AXI, đánh giá side-channel và fault injection
trước khi xem thiết kế là sản phẩm triển khai thực tế.
