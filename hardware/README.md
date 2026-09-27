# Hardware SLH-DSA-SHAKE-256f trên VC707

Đây là thư mục phần cứng **chính thức** của đồ án. Không mở các project
trong `archive/` để tiếp tục phát triển.

## Project Vivado chính

Sau khi build, chỉ mở file:

`build/vivado/sphincs_shake256_vc707.xpr`

Firmware chính:

`output/sphincs_shake256_vc707_250mhz.bit`

IP AXI4-Lite đóng gói để dùng trong Vivado Block Design:

`output/ip_repo/slh_dsa_shake_accel_2.0/component.xml`

Firmware LED độc lập dùng clock 250 MHz. IP AXI4-Lite v2 được tối ưu riêng
và phát hành ở 300 MHz. Fmax OOC đã kiểm chứng là 330 MHz với WNS chỉ
+0,029 ns; 335 MHz trượt setup 0,079 ns. Vì vậy không dùng 330 MHz sát biên
làm cấu hình tích hợp mặc định.

Kết quả sau route của firmware chính: WNS +0,461 ns, WHS +0,085 ns, DRC 0
lỗi, 5.290 LUT và 6.824 thanh ghi. Xem `output/BUILD_STATUS.md`.

## Cấu trúc

```text
hardware/
├── rtl/
│   ├── core/        Keccak-f[1600] và SHAKE256 dùng chung
│   ├── sphincs/     Các khối SLH-DSA (hiện có F/H cho SHAKE-256f)
│   ├── ip/          AXI4-Lite IP có thanh ghi, status và interrupt
│   └── board/       Top-level firmware VC707
├── drivers/         Header C điều khiển IP từ MicroBlaze/CPU
├── constraints/     Chân và clock VC707
├── sim/             Testbench và vector độc lập
├── scripts/         Tạo project, kiểm thử và build
├── build/           Project/tệp trung gian do Vivado tạo
└── output/          Bitstream và báo cáo chính thức
```

## Các lệnh duy nhất cần dùng

Kiểm thử toàn bộ RTL:

```powershell
./scripts/run_tests.ps1
```

Tạo lại project, chạy test và build firmware:

```powershell
./scripts/build_all.ps1
```

Chỉ đóng gói và implement IP AXI4-Lite:

```powershell
./scripts/build_ip.ps1
```

Mở project Vivado:

```powershell
./scripts/open_project.ps1
```

Có thể mở trực tiếp `build/vivado/sphincs_shake256_vc707.xpr` bằng Vivado.

## Chức năng firmware

Firmware tự kiểm tra hai phép F/H của SLH-DSA-SHAKE-256f:

`SHAKE256(PK.seed || ADRS || input, 32 byte)`

- LED0: cả hai vector đúng (PASS).
- LED1: ít nhất một vector sai (FAIL).
- LED2: đang chạy kiểm tra.
- LED7: heartbeat.

XSim còn kiểm tra lõi SHAKE256 với đầu vào 0, 3, 135, 136, 137, 272 và
2.208 byte. Test AXI thực hiện ghi thanh ghi, phát lệnh, poll status, nhận
interrupt và đọc digest cho cả F lẫn H.

IP AXI v2 đạt implementation OOC 300 MHz với WNS +0,276 ns, WHS +0,042 ns,
6.737 LUT, 9.229 FF và DRC 0 lỗi. Xem `output/IP_BUILD_STATUS.md` và
`output/ip_reports/`.

Keccak dùng hai stage đăng ký cho mỗi round: F/H có cùng một permutation
48 round-cycle; từ `start` của khối F/H đến `done` là 55 chu kỳ, tương đương
khoảng 183,3 ns ở 300 MHz. Đổi lại đường tổ hợp ngắn và Fmax cao. Đây là
tối ưu Fmax và khả năng ghép AXI, không phải kiến trúc nhiều context xử lý
song song.

## Register map IP AXI4-Lite

| Offset | Thanh ghi | Nội dung |
| --- | --- | --- |
| `0x00` | CONTROL | bit 0 START, bit 1 TWO_BLOCKS, bit 2 CLEAR_STATUS, bit 3 ZEROIZE/ABORT |
| `0x04` | STATUS | READY, DONE, BUSY, ERROR, CONFIG_F/H_VALID, ZEROIZING |
| `0x08..0x24` | PK.seed | 8 word, 32 byte |
| `0x28..0x44` | ADRS | 8 word, 32 byte |
| `0x48..0x84` | INPUT | tối đa 16 word, 64 byte; chỉ ghi |
| `0x88..0xA4` | DIGEST | 8 word, 32 byte |
| `0xA8` | ID | `0x534C4802` |
| `0xAC` | IRQ_ENABLE | bit 0 DONE, bit 1 ERROR |
| `0xB0` | IRQ_STATUS | trạng thái ngắt, ghi 1 để xóa (W1C) |
| `0xB4` | CAPABILITIES | `0x0001003F` |

Driver tham chiếu cho MicroBlaze/CPU nằm tại
`drivers/slh_dsa_shake_accel.h`.
Quy trình ghép Block Design và trình tự điều khiển nằm tại
`AXI_INTEGRATION.md`.

AXI v2 nhận kênh AW và W độc lập đúng giao thức, trả `SLVERR` cho địa chỉ
sai/không căn word, ghi thanh ghi chỉ đọc, START khi BUSY hoặc khi dữ liệu
chưa đủ. Lệnh ZEROIZE xóa các thanh ghi chứa seed, ADRS, input, digest và
trạng thái Keccak, đồng thời hủy tác vụ đang chạy.
Ngoài ra input được tự xóa sau khi lõi nhận lệnh, và sponge/pipeline Keccak
được scrub trước khi báo DONE để tránh lưu dữ liệu trung gian lâu hơn cần
thiết.

Firmware và IP này chưa phải bộ tạo khóa/ký/xác minh đầy đủ trên FPGA;
bộ ký FIPS 205 hoàn chỉnh hiện nằm trong `../software/`. Bước tiếp theo là
thêm T_l nhiều khối, PRF/PRFmsg/Hmsg, WOTS+, FORS, XMSS và hypertree.
