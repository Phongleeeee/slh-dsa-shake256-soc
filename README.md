# SoC portable SLH-DSA-SHAKE-256f, triển khai trên VC707

Đây là thư mục gốc duy nhất của đồ án. Cấu hình chính được chốt là
**FIPS 205 SLH-DSA-SHAKE-256f**. Lõi SoC dùng RAM nội bộ và độc lập chân kit;
VC707 là nền tảng triển khai hiện tại. DDR3 là phần mở rộng tùy chọn.

## Bản mã nguồn trên GitHub

Repository này chứa **mã nguồn**, không chứa khóa thật, tài liệu cá nhân,
project Vivado đã sinh, executable, bitstream hoặc checkpoint. Sau khi clone,
làm theo [hướng dẫn build từ mã nguồn](docs/GITHUB_BUILD.md) trước khi mở app
hay project Vivado. Các đường dẫn build/output bên dưới được tạo trên máy bạn;
`archive/` và `demo_chay_thu/` chỉ tồn tại trong workspace gốc.

Đây là **đồng thiết kế phần cứng/phần mềm**, không phải toàn bộ SLH-DSA bằng RTL:
PicoRV32 chạy firmware chữ ký và gọi bộ tăng tốc SHAKE256. Các kết quả test
được ghi trong tài liệu là kết quả của workspace đã kiểm chứng; không phải
chứng nhận FIPS, đo trên kit thật hay bảo đảm timing cho mọi lần build.
Xem [nguồn gốc và giấy phép thành phần](THIRD_PARTY_NOTICES.md).

## Bắt đầu nhanh

Bản mới có backend **FPGA UART**, firmware dịch vụ SLH3, DMA → SHAKE,
benchmark ba mode và vault chặn DMA. Bản rà soát đạt **296,296 MHz**
post-route, WNS +0,001 ns và WHS +0,055 ns sau sửa DMA ngày 28/09;
setup vẫn rất sát biên, chưa đo ổn định trên kit thật.
Xem [hướng dẫn sử dụng mới](hardware/soc/SERVICE_GUIDE.md) và
[báo cáo rà soát/test/đối chiếu NIST](docs/RA_SOAT_KIEM_CHUNG_2026-09-27.md).
Đợt mới nhất: [ma trận 9 tổ hợp DMA và hai lỗi đã sửa](docs/RA_SOAT_DMA_2026-09-28.md).
Mở app bằng `MO_PHAN_MEM_SLH_DSA.cmd`; backend Windows và FPGA tách rõ.

Build và kiểm tra SoC portable:

```powershell
cd C:\SHAKE256
./hardware/soc/scripts/build_portable_soc.ps1
./hardware/soc/scripts/test_soc.ps1
./hardware/soc/scripts/test_portable_dma.ps1
./hardware/soc/scripts/test_dma_matrix.ps1
```

Mở đúng project Vivado chính:

```powershell
./open_vivado.ps1
```

Hoặc mở trực tiếp:

`hardware/soc/build_portable/portable_slh_soc.xpr`

Bitstream SoC portable để nạp VC707 sau khi build đạt timing:

`hardware/soc/output_portable/portable_slh_soc_vc707.bit`

Top: `vc707_portable_wrapper`. Xem [kiến trúc và cách đổi kit](hardware/soc/PORTABLE_SOC.md).
Mức clock yêu cầu trong lệnh build phải được xác nhận bằng báo cáo post-route.
Kết quả bản phát hành portable: xem [biên bản kiểm chứng](hardware/soc/ACCEPTANCE.md).

IP AXI4-Lite chính để thêm vào Vivado Block Design:

`hardware/output/ip_repo/slh_dsa_shake_accel_2.0/component.xml`

Chạy sản phẩm ký số mẫu:

```powershell
./slh_dsa.ps1 info
./slh_dsa.ps1 keygen signer.slpk signer.slsk
./slh_dsa.ps1 sign signer.slsk document.pdf document.slsig --context DO-AN-VC707
./slh_dsa.ps1 verify signer.slpk document.pdf document.slsig
```

## Cấu trúc chuẩn

**Mã nguồn đã gom theo chức năng:** [bản đồ thư mục](docs/CAU_TRUC_THU_MUC.md).
AXI ở `hardware/rtl/axi`, CPU ở `hardware/rtl/cpu`, DMA ở `hardware/rtl/dma`,
IOMMU ở `hardware/rtl/iommu`, SHAKE/F/H ở `hardware/rtl/sphincs_shake256`.
Wrapper và XDC riêng của kit ở `hardware/boards/vc707`.
Source cũ không dùng nằm trong `archive/reorganization_20260927`, không còn
phụ thuộc trực tiếp vào các thư mục nhập liệu ở gốc.

```text
C:\SHAKE256\
├── hardware/       RTL, mô phỏng, project Vivado và firmware VC707
├── software/       Chương trình tạo khóa, ký và xác minh
├── third_party/    Source tham chiếu ghim phiên bản; có hook tăng tốc RV32
├── docs/           Báo cáo, slide và đặc tả
├── tools/          Kiểm tra tính toàn vẹn/bố cục source
├── demo_chay_thu/  Dữ liệu demo người dùng, không bị dọn xóa
├── archive/        Đồ án 1 và các lần thử Fmax cũ, chỉ để tra cứu
├── build_all.ps1   Một lệnh build/test toàn bộ đồ án
└── open_vivado.ps1 Mở đúng project Vivado chính
```

## Trạng thái sản phẩm

- Phần mềm: tạo khóa, ký và xác minh FIPS 205 SLH-DSA-SHAKE-256f; hỗ trợ
  pure, pre-hash, context, deterministic/hedged và khóa bí mật DPAPI.
- NIST ACVP: 104/104 vector dành cho SLH-DSA-SHAKE-256f đã PASS.
- SoC: CPU PicoRV32, AXI, DMA/IOMMU, UART, timer và 192 KiB RAM nội bộ.
  RTL SHAKE F/H và DMA RAM1→RAM2→RAM1 đã chạy XSim; firmware C khởi động
  và DMA roundtrip cũng đã được mô phỏng.
- IP: AXI4-Lite v2.0 đã đóng gói, XSim PASS và implementation OOC 300 MHz
  PASS với WNS +0,276 ns, WHS +0,042 ns. IP có kiểm tra cấu hình, phản hồi SLVERR,
  thanh ghi đầu vào write-only, ngắt W1C và lệnh zeroize/abort.
- FORS/WOTS+/XMSS/hypertree chạy bằng firmware RV32; F/H tăng tốc bằng RTL.
  Keygen/sign/verify end-to-end trên board portable cần kiểm tra qua UART.
- Bản LED SHAKE độc lập cũ dùng clock 250 MHz. IP AXI v2 trước đây build ở 300
  MHz; Fmax OOC đã kiểm chứng là 330 MHz (+0,029 ns), còn 335 MHz không đạt
  (-0,079 ns). Không dùng mức 330 MHz sát biên cho hệ thống hoàn chỉnh.

Các số OOC/LED độc lập ở trên không phải Fmax của toàn SoC hiện tại.
Xem [hướng dẫn SoC portable](hardware/soc/PORTABLE_SOC.md),
[hướng dẫn bộ ký phần mềm](software/sphincs_signer/README.md) và
[trạng thái sản phẩm](docs/PRODUCT_STATUS.md).

Các project cũ/DDR và build SHAKE trước sắp xếp đã được đưa vào `archive`.
Không mở project trong archive để chạy bản chính; dùng `open_vivado.ps1`.
