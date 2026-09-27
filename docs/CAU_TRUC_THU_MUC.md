# Bản đồ hệ thống sau sắp xếp — 27/09/2026

## 1. Tìm mã ở đâu?

```text
C:\SHAKE256
├── hardware
│   ├── rtl
│   │   ├── axi                 AXI chính, AXI RAM, router
│   │   │   └── test_models     AXI behavioral cho test DMA riêng
│   │   ├── cpu                 PicoRV32 + COPYING + tools/makehex.py
│   │   ├── dma                 DMA, scheduler, FIFO, registers
│   │   ├── iommu               Dịch địa chỉ/quyền DMA, TLB
│   │   ├── sphincs_shake256    Keccak, SHAKE, F/H, AXI-Lite, adapter DMA
│   │   ├── peripherals        UART, timer/GPIO
│   │   └── soc                Ghép CPU/AXI/RAM/DMA/SHAKE
│   ├── boards/vc707
│   │   ├── rtl                Wrapper/clock/reset kit
│   │   ├── constraints        XDC chân/clock
│   │   └── optional_ddr3      MIG và converter, không dùng bản chính
│   ├── manifests              Danh sách source chuẩn
│   ├── scripts                Build/test/package IP SHAKE độc lập
│   ├── sim                    Test SHAKE/IP độc lập
│   └── soc
│       ├── firmware           Firmware C/assembly cho PicoRV32
│       ├── scripts            Build/test/check SoC
│       ├── sim                Test hệ thống và DMA/IOMMU
│       ├── build_portable     PROJECT VIVADO CHÍNH
│       └── output_portable    BITSTREAM, timing, báo cáo, log
├── software/sphincs_signer    App Windows, CLI, giao tiếp FPGA
├── third_party               Thuật toán/thư viện C dùng chung, nguồn tham chiếu
├── docs                      Báo cáo Word/slide/PDF và hướng dẫn
├── demo_chay_thu              Dữ liệu dùng thử của người dùng; giữ nguyên
├── tools                     Công cụ quản lý/kiểm tra bố cục
└── archive                   Nguồn cũ, lịch sử, cấu hình không dùng
```

Tên module không đổi; việc gom thư mục không thay giao thức hoặc chức năng.
Không gộp firmware C với RTL Verilog chỉ vì cùng liên quan SLH-DSA.

## 2. Bản chính không đổi chỗ

- Project: `hardware/soc/build_portable/portable_slh_soc.xpr`.
- Bitstream: `hardware/soc/output_portable/portable_slh_soc_vc707.bit`.
- Mở Vivado: `open_vivado.ps1` ở thư mục gốc.
- Mở phần mềm: `MO_PHAN_MEM_SLH_DSA.cmd` ở thư mục gốc.

Đợt này giữ nguyên bitstream đã đạt timing 296,296296 MHz; không tạo một
bitstream khác chỉ để đổi đường dẫn. Hash code sản xuất, firmware và ảnh nạp
được đối chiếu với bản đã nghiệm thu trước sắp xếp. Khi chỉnh logic sau này,
phải build lại và kiểm tra timing, không suy ra Fmax từ tên thư mục.

## 3. Những thư mục cũ đã đi đâu?

57 file cần thiết được **di chuyển**, không tạo thêm một bản code chính song
song. Phần còn lại của `Project_Vivado`, `RTL-20260907T024349Z-1-001`,
`picorv32-main` và project `vivado_vc707` cũ được giữ tại:

`archive/reorganization_20260927/imports_remaining/`

Trong đó có CPU MMU chưa dùng, Systolic, các CPU/UART/top cũ, source thử,
firmware cũ và Git history của project nhập vào. Chúng không còn là nguồn
phụ thuộc của project portable. Do đã lấy các file cần thiết ra ngoài, đây
là phần lưu trữ tham khảo, không phải một project cũ độc lập đã được sửa để
build ngay. `path_migration_20260927.json` cho biết từng file đã chuyển đi đâu.

`archive/reorganization_20260927/before/` giữ project, script, manifest,
checkpoint và bitstream trước sắp xếp. `moved_files_sha256.json` ghi hash của
57 file tại thời điểm di chuyển. Không xóa khóa, chữ ký, tài liệu demo hoặc
báo cáo của người dùng. Header bản quyền và giấy phép PicoRV32 được giữ lại.

Các build/output SoC DDR cũ và build SHAKE cũ được đưa vào
`archive/reorganization_20260927/generated_legacy/`. Project SHAKE độc lập
và gói IP được tạo lại với đường dẫn mới; project portable chính vẫn giữ
nguyên vị trí. Hai script di chuyển một lần nằm trong `operations/` để tra
cứu, không phải lệnh cần chạy lại. Build và ký file không cần source trong
archive; riêng công cụ đối chiếu trước/sau dùng bản sao baseline tại đó.

Hai bộ AXI không đồng nhất: bản chính nằm trực tiếp trong `hardware/rtl/axi`,
bản phục vụ test DMA cũ nằm trong `axi/test_models`. Không thêm cả hai vào
cùng một lần compile. CPU MMU không dùng khác với IOMMU DMA đang dùng.

## 4. Build và kiểm tra

```powershell
cd C:\SHAKE256
.\tools\check_layout_integrity.ps1
.\hardware\soc\scripts\test_soc.ps1
.\hardware\soc\scripts\test_portable_dma.ps1
.\hardware\soc\scripts\test_scheduler_review.ps1
.\hardware\scripts\run_tests.ps1
# Chỉ khi cần tạo lại bitstream:
.\hardware\soc\scripts\build_portable_soc.ps1
```

`hardware/manifests/soc_common.f` là danh sách RTL chung cho build và test
SoC; `shake_core.f` cho SHAKE/IP độc lập. Cấu hình board thêm wrapper riêng.
Không dùng cách quét đệ quy mọi file `.v/.sv` của toàn workspace.

Các log kiểm tra bố cục mang tiền tố `reorganization_` trong
`hardware/soc/output_portable`. Kiểm thử vật lý trên COM/kit vẫn là bước
nghiệm thu riêng; việc sắp xếp thư mục không tạo ra bằng chứng board mới.

## 5. Kết quả nghiệm thu bố cục

- 57 file đã di chuyển khớp SHA-256 với trước khi di chuyển.
- 90 file code/artifact của bản đã nghiệm thu vẫn nguyên byte, gồm RTL/XDC,
  firmware binary, checkpoint và bitstream. 52 đường dẫn file trong project tồn tại.
- Vivado mở project, đối chiếu manifest và RTL elaboration: PASS.
- Hồi quy SoC: 9 testbench PASS, gồm UART RV32 đủ 23 response.
- DMA tích hợp: PASS, 39 snapshot; scheduler: 512 lệnh/56.482 descriptor PASS.
- IOMMU: 51.202 yêu cầu range và 30 response maintenance PASS.
- SHAKE/THASH/AXI IP/board selftest mô phỏng: cả 4 nhóm PASS.
- Project SHAKE độc lập được tạo lại; IP v2 được đóng gói lại và 11 tham
  chiếu file trong component.xml tồn tại.
- Manifest phát hành cập nhật thành 180 file; `verify_service_release.ps1` PASS.

Đã chuyển 44 file/thư mục cache, log, waveform tạo tự động và bản `.mem`
trùng ở thư mục gốc vào `archive/reorganization_20260927/generated_scratch/`.
Không xóa vĩnh viễn các dữ liệu này; có thể lấy lại từ archive. Chỉ các thư
mục source cũ đã rỗng được loại bỏ. Báo cáo Word/slide giai đoạn trước giữ
nguyên; tra tài liệu này để lấy đường dẫn hiện hành.
