# Nguồn gốc và giấy phép thành phần

Không áp dụng một giấy phép mới cho toàn bộ repository trong lần công bố
này. Mỗi thành phần bên thứ ba giữ thông báo bản quyền và điều kiện sử dụng
của nguồn gốc. Việc repository công khai không tự thay đổi các điều kiện đó.

| Thành phần | Nguồn/giấy phép được giữ trong source |
|---|---|
| PicoRV32 | `hardware/rtl/cpu/COPYING`, ISC; header trong `picorv32.v` |
| AXI crossbar, các AXI test model, AXI DMA/CDMA của Alex Forencich | MIT trong header từng file thuộc `hardware/rtl/axi` và `hardware/rtl/dma` |
| pseudoLRU, Barcelona Supercomputing Center | Header `hardware/rtl/iommu/pseudoLRU.sv`: Solderpad 2.1 hoặc Apache 2.0; giữ nguyên thông báo |
| slhdsa-c | `third_party/slhdsa-c/LICENSE`; baseline `174c02e42257f95c210963272877c49dbb50070f`, có chỉnh sửa hook tăng tốc RV32 của đồ án |
| SPHINCS+ tham chiếu lịch sử | `third_party/sphincsplus/LICENSE` và `LICENSES/` |
| SPHINCS-SHAKE256 đời cũ | Phần License của `third_party/sphincs-shake256-legacy/README.md` |

Các header bản quyền đi kèm file được bảo toàn. Không coi phần AXI/DMA hay
PicoRV32 có nguồn gốc bên ngoài là thiết kế mới hoàn toàn của đồ án.
Văn bản Apache 2.0 cũng được giữ trong `third_party/slhdsa-c/LICENSE`;
header pseudoLRU dẫn tới https://solderpad.org/licenses/SHL-2.1/.

IP DDR3/MIG và AXI converter do công cụ của nhà cung cấp sinh, các thư viện
Vivado, bộ cài công cụ và tài liệu PDF bên ngoài không được đưa vào bản
source công khai này. Người dùng cần cài công cụ phù hợp để tạo lại sản phẩm
build. Không cấp lại giấy phép hoặc quyền phân phối các thành phần đó.
