# Sử dụng bản mã nguồn GitHub

## Phạm vi bản công khai

- Có RTL phân nhóm AXI/CPU/DMA/IOMMU/SHAKE, wrapper VC707, XDC, firmware C,
  ứng dụng Windows, testbench, script build/test và nguồn C tham chiếu.
- Không có khóa `.slsk`, `.slpk`, chữ ký `.slsig`, handle `.slkh`, dữ liệu ký
  của người dùng, báo cáo Word/PowerPoint/PDF cá nhân hoặc thư mục `archive`.
- Không có executable, firmware đã biên dịch, bitstream, checkpoint, XPR,
  log/waveform/cache và IP DDR3 do Vivado sinh ra. Các file này vẫn được giữ
  nguyên trong workspace gốc; việc không đưa lên Git không xóa chúng.
- `third_party/slhdsa-c` được đưa vào như **source vendored**, không phải
  submodule. Thay đổi hook RV32 được giữ; không cần `git submodule update`.

## Công cụ cần có

Môi trường đang dùng là Windows, PowerShell, Python 3, Vivado 2025.1 có hỗ
trợ Virtex-7 và Visual Studio 2022 Community với công cụ C/C++.
Firmware cần RISC-V GCC hỗ trợ `rv32i_zicsr`, ABI `ilp32`.

**Đặt checkout trong đường dẫn ASCII không có dấu cách**, ví dụ
`C:\slh-dsa-shake256-soc`. Khi kiểm tra bản xuất sạch, GCC đi kèm Xilinx bị
lỗi tách đường dẫn ở thư mục người dùng có dấu cách/ký tự tiếng Việt.
Script hiện tại chưa xử lý tương thích trường hợp đó.

Các script hiện còn đường dẫn cài đặt riêng của máy phát triển:

- Vivado: `D:\2025.1\Vivado\bin`.
- RISC-V GCC: tìm trong PATH trước; fallback
  `D:\2025.1\gnu\riscv\nt\riscv64-unknown-elf\bin`.
- MSVC: `C:\Program Files\Microsoft Visual Studio\2022\Community`.

Nếu máy bạn cài khác, sửa đường dẫn trong các script liên quan hoặc dùng tham
số `-VivadoBin` ở script có hỗ trợ. Tham số của `build_all.ps1` chưa được
truyền tới mọi script con; không coi đó là tùy chọn cấu hình toàn hệ thống.
Không cần DDR3 để build cấu hình portable.

## 1. Tải source và thử phần mềm Windows

```powershell
git clone https://github.com/Phongleeeee/slh-dsa-shake256-soc.git
cd slh-dsa-shake256-soc
.\software\sphincs_signer\build.cmd fips205
.\software\sphincs_signer\build\slh_dsa_shake_256f.exe selftest
.\MO_PHAN_MEM_SLH_DSA.cmd
```

App Windows chạy bằng CPU máy tính khi chọn backend Windows. Để dùng FPGA,
cần build/nạp bitstream và chọn backend FPGA UART với cổng COM thực tế.
Tự tạo cặp khóa mới bằng app; không tải khóa thật lên GitHub.

## 2. Tạo firmware và chạy test RTL

Chạy tại thư mục gốc repository:

```powershell
python .\hardware\soc\firmware\gen_soc_boot.py
.\hardware\soc\scripts\build_slh_firmware.ps1 -Selftest
.\hardware\soc\scripts\build_slh_firmware.ps1
.\hardware\scripts\run_tests.ps1
.\hardware\soc\scripts\test_soc.ps1
.\hardware\soc\scripts\test_portable_dma.ps1
.\hardware\soc\scripts\test_scheduler_review.ps1
```

Các ảnh bộ nhớ `.mem` được tạo ở `hardware/soc/firmware/`. Không bỏ qua bước
này trong checkout mới. AXI chính và `axi/test_models` chứa tên module trùng
nhau: dùng script/manifests đúng, không biên dịch tất cả RTL bằng wildcard.

Kiểm thử ACVP phần mềm:

```powershell
.\software\sphincs_signer\test_acvp.ps1
```

Lần đầu cần mạng để tải bộ vector NIST theo tag ghim `v1.1.0.40`; cache không
được đưa lên Git. PASS ACVP ở đây là kiểm thử phần mềm, không phải chứng nhận
FIPS hoặc kết quả keygen/sign/verify trên FPGA.

## 3. Build SoC portable cho VC707

```powershell
.\hardware\soc\scripts\build_portable_soc.ps1
.\open_vivado.ps1
```

- Top: `vc707_portable_wrapper`.
- Project được sinh: `hardware/soc/build_portable/portable_slh_soc.xpr`.
- Bitstream sau build thành công:
  `hardware/soc/output_portable/portable_slh_soc_vc707.bit`.
- Build mặc định yêu cầu 296,296296 MHz. Phải đọc báo cáo timing mới của lần
  build; bản sửa DMA 28/09 có WNS +0,001 ns rất sát biên và không bảo đảm mọi lần
  build đều đạt. Chưa có xác nhận ổn định thực tế trên kit.

IP SHAKE đóng gói riêng có thể tạo lại bằng
`hardware/scripts/package_ip.ps1`. Không nhầm clock OOC của IP riêng với
clock toàn SoC.

## Các giới hạn cần biết

- Script `verify_service_release.ps1` nhận diện **bản build gốc** bằng hash,
  cần bitstream, báo cáo và `release_manifest.json` cục bộ. Đây không phải
  lệnh kiểm tra checkout sạch; build lại có thể tạo artifact khác hash.
- `tools/check_layout_integrity.ps1` kiểm tra lịch sử di chuyển source, cần
  baseline trong `archive`; không chạy được chỉ với repository công khai.
- Tài liệu cũ có thể nhắc tới báo cáo, log và file local không được công bố.
- DDR3 là nhánh tùy chọn cũ. Các script/wrapper còn đó để tham khảo, nhưng
  IP MIG/AXI converter không được phát hành; cần tạo lại IP và kiểm chứng
  riêng trước khi dùng nhánh DDR.
- Chưa có TRNG được chứng nhận, secure boot, UART được xác thực/mã hóa hay
  kiểm chứng chống side-channel/fault. Không dùng bản đồ án để giữ khóa có
  giá trị thật trong môi trường sản xuất.
