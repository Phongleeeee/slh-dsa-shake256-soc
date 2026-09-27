# Phần phụ thuộc kit VC707

- `rtl/vc707_portable_wrapper.v`: wrapper chính, clock/reset/UART/LED.
- `constraints/vc707_portable.xdc`: ràng buộc chính.
- Những wrapper/XDC còn lại: cấu hình SHAKE selftest hoặc SoC cũ/DDR tùy chọn.
- `optional_ddr3/`: ba IP MIG/clock converter/data-width converter và XML cấu
  hình được di chuyển nguyên trạng; **không tham gia build portable**.

Project nạp chính vẫn ở `../../soc/build_portable/portable_slh_soc.xpr`.
Không chọn wrapper DDR hoặc LED selftest khi muốn thử dịch vụ SLH3.
DDR3 chỉ được bảo toàn đường dẫn trong đợt sắp xếp này, chưa build/nạp lại.
