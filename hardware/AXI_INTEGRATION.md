# Tích hợp IP SLH-DSA SHAKE AXI v2

## Artefact phát hành

- IP catalog: `output/ip_repo/slh_dsa_shake_accel_2.0/component.xml`
- VLNV: `student.local:security:slh_dsa_shake_accel:2.0`
- Driver C tham chiếu: `drivers/slh_dsa_shake_accel.h`
- FPGA đã kiểm chứng: Virtex-7 `xc7vx485tffg1761-2` trên VC707
- Clock IP đã kiểm chứng OOC: 300 MHz

## Ghép trong Vivado Block Design

1. Vào **Settings > IP > Repository**, thêm thư mục
   `hardware/output/ip_repo` rồi chọn **Rescan**.
2. Thêm `SLH-DSA SHAKE256 F/H Accelerator v2` vào Block Design.
3. Nối `s_axi` tới AXI Interconnect/SmartConnect của MicroBlaze hoặc CPU.
4. Nối `s_axi_aclk` và toàn bộ master/interconnect cùng một clock không quá
   300 MHz. Nếu CPU chạy khác clock, đặt AXI Clock Converter trước IP.
5. Nối reset active-low đã đồng bộ theo `s_axi_aclk` tới `s_axi_aresetn`.
6. Nối `irq` qua AXI Interrupt Controller hoặc trực tiếp tới ngõ ngắt CPU.
7. Gán một vùng địa chỉ tối thiểu 4 KiB trong Address Editor.
8. Sau khi ghép hệ thống phải chạy lại synthesis, implementation, DRC và
   kiểm tra WNS/WHS; kết quả OOC 300 MHz không thay thế timing cấp hệ thống.

## Trình tự gọi một phép F hoặc H

1. Đọc `ID` tại `0xA8`, phải bằng `0x534C4802`; đọc `CAPABILITIES` tại
   `0xB4`, phải bằng `0x0001003F`.
2. Ghi đủ 32 byte `PK.seed` và 32 byte `ADRS`.
3. Ghi 32 byte input cho F hoặc 64 byte input cho H. Byte 0 nằm ở bit
   `[7:0]` của word đầu tiên.
4. Kiểm tra `STATUS.CONFIG_F_VALID` hoặc `STATUS.CONFIG_H_VALID`.
5. Ghi `IRQ_ENABLE=3`, sau đó ghi `CONTROL.START=1`; đặt thêm
   `CONTROL.TWO_BLOCKS=1` cho H.
6. Chờ `irq` hoặc poll `STATUS.DONE`. Nếu `STATUS.ERROR=1`, không dùng
   digest và xử lý lỗi.
7. Đọc 8 word digest tại `0x88..0xA4`, rồi ghi 1 vào bit DONE của
   `IRQ_STATUS` để xóa ngắt.
8. Khi kết thúc phiên hoặc khi timeout, ghi `CONTROL.ZEROIZE=1`. Lệnh này
   hủy tác vụ đang chạy, xóa seed/ADRS/input/digest và trạng thái Keccak.

Input AXI được tự xóa và mất cờ hợp lệ ngay sau khi lõi nhận yêu cầu; mỗi
phép F/H mới phải ghi lại input. Sponge, padded block và pipeline Keccak
được tự scrub trước khi DONE được phát. ZEROIZE vẫn cần dùng để xóa digest,
seed/ADRS, trạng thái điều khiển hoặc để hủy một phép đang chạy.

Hàm `slh_accel_start`, `slh_accel_finish` và `slh_accel_zeroize` trong
driver đã thực hiện trình tự trên. Phần mềm host vẫn phải dùng timeout hữu
hạn và gọi zeroize nếu timeout.

## Phản hồi lỗi được thiết kế sẵn

IP trả `SLVERR` và đặt cờ ERROR khi địa chỉ không căn 32 bit, địa chỉ không
tồn tại, ghi thanh ghi chỉ đọc, START lúc BUSY hoặc START khi dữ liệu chưa
đủ. Hai kênh AW và W được tiếp nhận độc lập theo AXI4-Lite. Vùng input chỉ
ghi và luôn đọc về zero để giảm khả năng phần mềm ngoài ý muốn đọc lại dữ
liệu trung gian.

## Giới hạn bảo mật cần giữ đúng khi tích hợp

- IP hiện chỉ tăng tốc F/H, không chứa khóa bí mật SLH-DSA đầy đủ và chưa
  thực hiện WOTS+, FORS, XMSS hay hypertree.
- Zeroize chống lưu dữ liệu vô tình, nhưng không thay thế biện pháp chống
  side-channel, glitch hoặc fault injection.
- AXI interconnect phải giới hạn master được phép truy cập IP; bản thân IP
  không xác thực quyền của AXI master.
- 300 MHz là mức phát hành trên VC707 speed grade -2 với WNS +0,276 ns.
  Fmax OOC đo được là 330 MHz với WNS chỉ +0,029 ns; 335 MHz thất bại với
  WNS -0,079 ns. Không dùng kết quả sát biên 330 MHz làm cam kết timing cho
  Block Design hoàn chỉnh.
