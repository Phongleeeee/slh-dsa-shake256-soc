# RTL theo chức năng

| Thư mục | Nội dung | Dùng trong SoC chính |
|---|---|---|
| `axi/` | Crossbar, interconnect, arbiter, pipeline, AXI RAM và router bộ nhớ | Có |
| `axi/test_models/` | Phiên bản AXI/RAM của bài test DMA nhập từ project cũ | Chỉ mô phỏng DMA riêng |
| `cpu/` | PicoRV32, giấy phép và công cụ tạo ảnh RAM | Có |
| `dma/` | CDMA, M2S/S2M, scheduler, FIFO, registers và top DMA/IOMMU | Có |
| `iommu/` | IOMMU phía DMA, TLB và pseudo-LRU | Có; không phải CPU MMU |
| `sphincs_shake256/` | Keccak, SHAKE256, F/H, giao tiếp AXI-Lite và adapter DMA | Có |
| `peripherals/` | UART, timer/GPIO | Có |
| `soc/` | Lõi SoC portable, ghép ngoại vi và facade tương thích | Có |

Clock/reset, chân kit và DDR3 tùy chọn nằm trong `../boards/vc707/`.
Firmware C/assembly nằm trong `../soc/firmware/`, không phải mã RTL của CPU.
FORS/WOTS+/XMSS/hypertree đang chạy bằng firmware; thư mục SHAKE không có
nghĩa toàn bộ thuật toán chữ ký đã được hiện thực bằng RTL chuyên dụng.

Danh sách source SoC chuẩn: `../manifests/soc_common.f`. Không thêm đệ quy
toàn bộ `rtl/` vào Vivado: các model test có module trùng tên với bản chính.

Source được chuyển nguyên byte từ các vị trí cũ. Bản đồ đường dẫn và hồ sơ
giấy phép/nguồn gốc được giữ trong `../../docs/path_migration_20260927.json`,
`cpu/COPYING`, header source và thư mục lưu trữ nhập liệu của đợt sắp xếp.
