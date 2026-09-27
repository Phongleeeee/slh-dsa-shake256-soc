# AXI chính và model kiểm thử

Các file trực tiếp trong thư mục này là nguồn AXI của SoC chính. `axi_ram.v`
là backend RAM dùng trong hệ thống; `dma_axi_mem_router.v` định tuyến địa chỉ
nội bộ/cổng bộ nhớ mở rộng tùy chọn.

`test_models/` giữ nguyên 9 file AXI khác từ project DMA cũ. Chúng không
giống bản chính, kể cả khi bỏ khác biệt xuống dòng. Bài test DMA cũ quan sát
mảng RAM behavioral, nên không thay bằng XPM RAM một cách máy móc.
`test_portable_dma.ps1` chỉ biên dịch bộ model đó; `test_soc.ps1` dùng AXI chính.
Tuyệt đối không biên dịch hai bộ trong cùng library vì trùng tên module.
