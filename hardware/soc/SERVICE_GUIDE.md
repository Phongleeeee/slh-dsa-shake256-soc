# Bản nâng cấp 5 hướng: dịch vụ ký số portable SLH3

Ngày 28/09/2026. Cấu hình chính: **SLH-DSA-SHAKE-256f**, RAM nội bộ,
PicoRV32 + AXI + DMA/IOMMU + accelerator SHAKE. Không cần DDR3.
Đọc cùng [biên bản kiểm chứng](ACCEPTANCE.md).

## 1. Những gì đã bổ sung và những gì chưa được xác nhận

| Hướng | Đã triển khai | Phạm vi kiểm chứng |
|---|---|---|
| 1. Keygen/ký/xác minh và đối chiếu PC | Firmware dịch vụ, upload message/signature, PC kiểm tra độc lập, script nghiệm thu kit | Engine portable và Windows đối chiếu đạt trên native; RV32 boot/DMA/UART kiểm tra bằng XSim. Chưa chạy toàn bộ chữ ký trên kit thật |
| 2. Windows ↔ FPGA | Backend FPGA UART trong app, C# client, frame có CRC/sequence/timeout; không tự fallback sang Windows | RV32 XSim UART, gói lặp và CRC recovery PASS; native host workflow/GUI construction PASS; COM thật chờ kit |
| 3. Benchmark | CPU / AXI / DMA, cycles 64 bit, bộ đếm F/H/PRF/DMA/lỗi, xuất CSV | Đã kiểm tra định dạng và đồng nhất chữ ký bằng native. Chưa có số đo ký/giây của FPGA |
| 4. DMA → SHAKE | RAM → M2S → adapter → SHAKE F/H → S2M → RAM; dùng chung một accelerator | RTL F/H, backpressure, lỗi và zeroize; firmware RV32 chạy DMA F known-answer |
| 5. Bảo vệ khóa | Seed từ Windows CSPRNG, vault/private stack chặn DMA, không xuất SK, zeroize, lỗi framing làm mất hiệu lực khóa | Hồi quy IOMMU/engine; không phải chứng nhận entropy, chống side-channel hay HSM |

**Không gọi đây là toàn bộ thuật toán đã viết thành RTL.** FORS, WOTS+,
XMSS, hypertree và quản lý luồng SLH-DSA chạy trong firmware trên PicoRV32.
F/H và PRF dùng accelerator ở chế độ phần cứng; PRFmsg, Hmsg và T_l nhiều
khối vẫn dùng SHAKE256 phần mềm. Chế độ CPU dùng phần mềm cho toàn bộ phép băm.

## 2. File/project nào phải mở?

- Vivado: `C:\SHAKE256\hardware\soc\build_portable\portable_slh_soc.xpr`.
- Top: `vc707_portable_wrapper`.
- Nạp: `C:\SHAKE256\hardware\soc\output_portable\portable_slh_soc_vc707.bit`.
- Phần mềm: chạy `C:\SHAKE256\MO_PHAN_MEM_SLH_DSA.cmd`.
- Đừng nạp bitstream SHAKE LED hoặc DDR cũ để thử giao thức SLH3.

Trong Vivado, Run Behavioral Simulation mặc định chạy `tb_portable_service_boot`
đến DMA F KAT PASS rồi dừng. Muốn thử giao thức, đặt
`tb_portable_service_uart` làm Simulation Top, chạy Run All (hoặc 600 ms);
test chạy firmware RV32 thật, kiểm tra 23 response và kết thúc khoảng 391 ms
thời gian mô phỏng. Đây vẫn chưa phải bài tạo khóa/ký đầy đủ.
Dùng `scripts/test_soc.ps1` để chạy đủ 9 testbench.

Clock toàn hệ thống sau sửa DMA **296,296296 MHz**, WNS +0,001 ns,
WHS +0,055 ns, timing đạt, DRC mặc định/bitstream 0 vi phạm.
Clock tăng 7,407% so với 275,862069 MHz; setup đang sát biên, chưa có xác
nhận ổn định trên board thật. Timing này chỉ áp dụng part VC707 hiện tại.
Kiểm tra đúng cặp bitstream/firmware đã nghiệm thu bằng
`scripts/verify_service_release.ps1`; đây chỉ là kiểm tra hash/timing, không
thay bài ký/xác minh trên kit thật. Build mới phải nghiệm thu và cập nhật hash.

## 3. Kiến trúc và luồng dữ liệu

```text
Windows app -- COM 115200 8N1 -- UART -- firmware dịch vụ trên PicoRV32
                                             |
                                         AXI fabric
                       +---------------------+-------------------+
                       |                     |                   |
                 RAM0: firmware      RAM1/RAM2: workspace    MMIO SHAKE
                                             |                   |
                                      DMA + IOMMU           F/H/PRF engine
                                             |                   ^
                                          AXIS M2S                |
                                             +--> stream adapter-+
                                                  |
                                           digest AXIS S2M
                                                  |
                                                 RAM

RAM2: service stack | private vault | crypto stack
                          ^
                   chỉ CPU truy cập;
                 DMA bị chặn theo địa chỉ vật lý
```

CPU chọn ba cách tính cùng thuật toán, không đổi dạng chữ ký:
Mode CPU dưới backend FPGA là **PicoRV32 trong FPGA**, không phải CPU máy
tính Windows. Backend Windows software là đường chạy riêng.

| Mode | F/H | PRF | PRFmsg/Hmsg/T_l |
|---|---|---|---|
| 0 CPU | SHAKE256 phần mềm | Phần mềm | Phần mềm |
| 1 AXI | Ghi/đọc register accelerator | AXI MMIO | Phần mềm |
| 2 DMA | DMA packet → accelerator → DMA digest | AXI MMIO, không đưa SK.seed vào DMA packet | Phần mềm |

DMA không mặc nhiên nhanh hơn AXI: F/H chỉ có 96/128 byte input, thêm setup,
dịch địa chỉ và handshake có thể làm tổng thời gian dài hơn. Benchmark phải
đo trên kit; không suy luận tốc độ ký chỉ từ MHz.

### Vùng nhớ của bản portable bảo vệ DMA

| Vùng | Địa chỉ | DMA |
|---|---|---|
| Boot RAM0, mã và hằng số | `0x00000..0x0FFFF` | Cấm |
| Workspace, message, signature, public key, DMA buffers | `0x10000..0x2AFFF` | Chỉ khi ánh xạ và quyền IOMMU hợp lệ |
| Service stack, 8 KiB | `0x2B000..0x2CFFF` | Cấm |
| Vault, 4 KiB: SK và gói nhận chứa seed | `0x2D000..0x2DFFF` | Cấm |
| Crypto stack, 8 KiB | `0x2E000..0x2FFFF` | Cấm |
| SHAKE / UART / timer / DMA MMIO | `0x30000` / `0x31000` / `0x32000` / `0x33000` | Cấm DMA memory access |
| Stream control | `0x34000` | CPU MMIO |

IOMMU kiểm tra **PPN vật lý sau dịch**, nên ánh xạ một địa chỉ ảo khác tới
vault vẫn bị từ chối. Thêm một chu kỳ kiểm tra quyền để tránh kéo dài đường
tổ hợp ảnh hưởng Fmax. CPU vẫn có quyền truy cập: đây không phải enclave,
không chống firmware độc hại hoặc đọc khóa qua JTAG.

## 4. Các file xuất hiện từ đâu?

| File | Backend Windows | Backend FPGA UART |
|---|---|---|
| Tài liệu cần ký | File người dùng tạo | File người dùng tạo, tối đa 16 KiB trong bản này |
| `.slpk` | Khóa công khai tạo bằng keygen Windows | PK 64 byte do firmware FPGA tính, host đóng container 96 byte |
| `.slsk` | SK 128 byte được bảo vệ Windows DPAPI trong container | **Không tạo, không xuất SK** |
| `.slkh` | Không dùng | Handle JSON chứa PK/backend/đường dẫn; không chứa SK và không khôi phục khóa |
| `.slsig` | Chữ ký detached từ Windows | Signature 49.856 byte do firmware FPGA tính, host xác minh PC rồi đóng container |
| `.csv` | Không cần cho ký thường | Bảng benchmark; chỉ số thực khi Backend=FPGA |

Khóa FPGA chỉ tồn tại trong RAM trong phiên hiện tại. Reset, mất nguồn,
zeroize, thay khóa, hoặc lỗi frame UART nhận dở/sai CRC làm khóa mất hiệu lực.
Idle bình thường không tự xóa khóa. Nếu handle không khớp PK hiện tại, app
báo lỗi và yêu cầu tạo cặp khóa mới; nó không âm thầm dùng khóa Windows.

### Tạo khóa

1. Windows dùng CSPRNG tạo 96 byte: SK.seed 32, SK.prf 32, PK.seed 32.
2. Truyền frame KEYGEN; FPGA nhận thẳng vào vault, kiểm tra length và CRC.
3. Firmware dùng seed để tính WOTS+/XMSS root của tầng cao nhất. SHAKE F/H
   và PRF được tăng tốc tùy mode; các phần còn lại do CPU điều phối.
4. SK = SK.seed || SK.prf || PK.seed || PK.root, tổng 128 byte, giữ trong vault.
5. PK = PK.seed || PK.root, tổng 64 byte, trả về Windows.
6. Host tạo `.slpk` và `.slkh` ở **hai tên file mới**, không ghi đè.

Seed đã đi qua Windows và UART: không thể tuyên bố khóa sinh hoàn toàn trong
FPGA hay bí mật chưa từng tồn tại trên host. Windows và dây UART phải tin cậy.
Reject zero/reuse seed là kiểm tra lỗi cơ bản, **không đo entropy**.
Lịch sử seed chỉ giữ đến khi reset/zeroize/lỗi frame xóa trạng thái; không
phải cơ chế phát hiện trùng khóa xuyên reboot hoặc nhiều thiết bị.

### Ký

1. Chọn tài liệu, `.slpk`, `.slkh`, tên `.slsig` mới và context.
2. Host kiểm tra handle/PK khớp khóa đang giữ; gửi message và context từng chunk.
3. Windows CSPRNG sinh addrnd 32 byte cho hedged signing; gửi lệnh SIGN.
4. PRFmsg/SHAKE256 tính R; Hmsg/SHAKE256 tính digest và chỉ số cây.
5. FORS ký digest; WOTS+/XMSS/hypertree ký tiếp FORS root, nối các phần chữ ký.
   Các vòng PRF/F/H/T_l dùng SHAKE256 theo chức năng; không phải chỉ băm file một lần.
6. FPGA giữ signature 49.856 byte trong workspace, host tải về từng chunk.
7. CLI Windows **xác minh độc lập** bằng `.slpk` trước khi xuất `.slsig`.
   Message gốc không bị sửa, không bị mã hóa, không bị thay bằng chữ ký.

### Xác minh

1. Chỉ cần tài liệu, `.slpk`, `.slsig`; không cần `.slsk` hay `.slkh`.
2. Host kiểm tra container, fingerprint, kích thước; lấy context từ chữ ký.
3. Gửi message/context, signature và PK tới FPGA.
4. Hmsg tính lại digest; FORS khôi phục root; WOTS+/XMSS/hypertree khôi phục
   root tầng cao nhất. So sánh với PK.root → VALID hoặc INVALID.
5. Sửa một byte message/signature/context hoặc dùng nhầm PK phải bị từ chối.

## 5. Cách thử trên kit thật

1. Nối JTAG và USB-UART, cấp nguồn VC707.
2. Nạp đúng bitstream mới bằng Hardware Manager, reset board.
3. Mở app; chọn **FPGA UART**, điền COM đúng, mode AXI trước hoặc DMA để thử luồng mới.
4. Bấm Thông tin. Nếu không trả SLH3, kiểm tra COM, bitstream và reset.
   Đóng terminal serial khác; mỗi lúc chỉ một chương trình giữ COM.
5. Chọn một file nhỏ, bấm Tạo cặp khóa, lưu `nguoi_ky.slpk` và `nguoi_ky.slkh`.
6. Ký file, chọn `tai_lieu.slsig` mới. Xác minh; sửa bản sao tài liệu để thử INVALID.
7. Bấm Benchmark để lưu CSV; bấm Xóa khóa khi kết thúc.

Tự nghiệm thu toàn bộ (thay COM7 bằng cổng thực):

```powershell
cd C:\SHAKE256
.\hardware\soc\scripts\test_fpga_board.ps1 -Port COM7 -Mode 2 -Benchmark
```

**Script thay khóa đang có trên FPGA**, làm handle cũ không còn dùng được.
Nó tạo thư mục kết quả mới, ký FPGA → xác minh PC, ký PC → xác minh FPGA,
thử sai message/signature/context/PK, benchmark và zeroize; chỉ in BOARD PASS
khi mọi bước thực sự đạt. Không có board thì không chạy và không nhận PASS giả.

Lệnh riêng (khóa/mất nguồn/reset cần keygen lại):

```powershell
.\software\sphincs_signer\fpga_host.ps1 -Port COM7 -Action info
.\software\sphincs_signer\fpga_host.ps1 -Port COM7 -Action keygen -PublicPath signer.slpk -HandlePath signer.slkh -Mode 1
.\software\sphincs_signer\fpga_host.ps1 -Port COM7 -Action sign -HandlePath signer.slkh -PublicPath signer.slpk -MessagePath cast.txt -SignaturePath cast.slsig -Mode 1
.\software\sphincs_signer\fpga_host.ps1 -Port COM7 -Action verify -PublicPath signer.slpk -MessagePath cast.txt -SignaturePath cast.slsig -Mode 1
.\software\sphincs_signer\fpga_host.ps1 -Port COM7 -Action zeroize
```

## 6. Benchmark đọc thế nào?

CSV có Backend, Operation, Mode, ClockHz, Cycles, CryptoMs, HostRoundtripMs,
F, H, PRF, DMAHashes, Failures, SoftwareCalls.
Lệnh benchmark hiện xuất **6 dòng: ký và xác minh cho 3 mode**. Keygen trả
thống kê ngay khi tạo khóa và được lưu trong transcript nghiệm thu; benchmark
không tự tạo lại khóa để tránh làm mất hiệu lực handle người dùng đang giữ.

- **Cycles / ClockHz**: thời gian firmware job, có cleanup; không gồm upload.
- **HostRoundtripMs**: ký gồm command + tải signature, verify gồm upload
  signature + command; không gồm upload message trước đó. Không phải thời gian
  toàn workflow và không được so trực tiếp với CryptoMs.
- Cùng key/message/context/addrnd cho ba mode → phải cho cùng signature.
- Failures phải bằng 0; nếu accelerator lỗi, dịch vụ không công bố SIGN PASS
  nhờ fallback phần mềm.
- STATS giữ mode của job đã chạy, không đổi nhãn khi chỉ dùng lệnh MODE để
  chọn cách tính cho job tiếp theo. INFO trả mode đang được chọn.
- SoftwareCalls chỉ đếm hook F/H/PRF chạy phần mềm/fallback; không đếm
  PRFmsg/Hmsg/T_l. SoftwareCalls=0 không có nghĩa mọi phép SHAKE chạy RTL.
- UART 115200 8N1 truyền riêng 49.856 byte đã cần ít nhất khoảng 4,33 giây,
  chưa tính framing, handshake và tính chữ ký. Clock cao không làm UART nhanh lên.
- CSV ghi `NATIVE_TEST_NOT_FPGA` chỉ kiểm tra phần mềm/giao thức. Không dùng
  số thời gian emulated đó trong báo cáo hiệu năng FPGA.

## 7. Giao thức, DMA và lỗi

Frame 20 byte + payload ≤1.024 byte, little-endian:
`SLH3 | version:u8 | op:u8 | flags/status:u16 | seq:u32 | len:u32 | crc32:u32`.
CRC32 IEEE tính trên 16 byte đầu và payload, bỏ trường CRC. Request flags=0,
response op=request|0x80. Sequence ghép response với request. Một request
lặp ngay trước đó có cùng seq/op/CRC được trả cached response.
**CRC/sequence không phải MAC, mã hóa hay chống replay mật mã.**

Ops: 1 INFO, 2 KEYGEN, 3 MSG_BEGIN, 4 MSG_CHUNK, 5 SIGN, 6 SIG_READ,
7 VERIFY, 8 SIG_BEGIN, 9 SIG_CHUNK, 10 PK, 11 ZEROIZE, 12 MODE,
13 STATS, 14 PING. Chunk upload đúng thứ tự/offset; host hiện gửi tối đa 512
byte data/chunk. Unknown op/length/bounds/state không hợp lệ trả lỗi.

Stream control CPU: `0x34000+0` ARM bit0/ABORT bit1,
`+4` busy/done/error bits0/1/2, `+8` ID `0x53445301`.
Packet 32-bit word: mode 0(F)/1(H), PK.seed 8 word, ADRS 8 word,
input 8/16 word → 100/132 byte; TKEEP=1111, TLAST chính xác.
Digest 8 word → 32 byte. Adapter độc quyền accelerator lúc busy; CPU MMIO
đồng thời bị SLVERR. Kết thúc tự zeroize register bank; abort/watchdog vào cleanup.
Lỗi nghiêm trọng cần CPU dừng/reset DMA endpoint trước giao dịch tiếp theo.

## 8. Giới hạn bảo mật và bước sau

- Không có TRNG FPGA đã qualification, UART chưa mã hóa/xác thực, không PIN/OTP.
- Người có quyền truy cập UART có thể yêu cầu ký bằng khóa đang giữ; handle
  chỉ chống dùng nhầm khóa, không phải thông tin xác thực hay quyền sở hữu.
- Host cung cấp entropy nên host tin cậy; không phải HSM độc lập.
- SK không xuất qua lệnh dịch vụ, nhưng CPU/JTAG không bị khóa bởi vault DMA.
- DMA F/H packet có thể chứa dữ liệu trung gian nhạy cảm. Nó chỉ tồn tại
  trong workspace tạm và được xóa sau phép băm; vault không biến toàn bộ
  workspace thành vùng chống đọc trộm. Firmware và DMA master phải tin cậy.
- Private crypto stack được xóa sau job; chưa chứng minh chống stack overflow
  của mọi đường thuật toán bằng đo high-water trên board.
- Message tối đa 16 KiB, pure mode; HashSLH streaming và file lớn là bước sau.
- LED0 chỉ báo boot/DMA/SHAKE KAT và dịch vụ sẵn sàng, không báo chữ ký
  vừa ký đã hợp lệ. Kết quả từng lệnh phải xem trong app/transcript.
- Chưa có key persistence/sealing, secure boot, side-channel/fault protection,
  CMS/PAdES/X.509, timestamp/thu hồi hoặc chứng nhận FIPS 140-3.
- `ENABLE_EXT_MEMORY=1` là nhánh DDR cũ; firewall secure-local hiện chỉ bật
  ở bản portable mặc định. Muốn DDR + vault cần thiết kế lại policy và test,
  không coi nhánh DDR đã có cùng bảo vệ.

Đừng sử dụng seed mẫu hoặc test key vào hệ thống thật. Bản này phục vụ đồ án.
Việc cần làm ngay sau khi kết nối kit: nghiệm thu ký đủ trên RV32, đo high-water
stack, thời gian từng mode và nhiệt/timing ổn định; sau đó mới chọn hướng TRNG
được đánh giá, giao thức xác thực, secure boot và hardening sâu hơn.
