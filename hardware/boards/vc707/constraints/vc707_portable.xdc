## VC707 200 MHz differential clock, reset pushbutton, USB-UART and LEDs.
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]

set_property PACKAGE_PIN E19 [get_ports sysclk_p]
set_property PACKAGE_PIN E18 [get_ports sysclk_n]
set_property IOSTANDARD LVDS [get_ports {sysclk_p sysclk_n}]
create_clock -name sysclk200 -period 5.000 [get_ports sysclk_p]

set_property PACKAGE_PIN AV40 [get_ports reset_btn]
set_property IOSTANDARD LVCMOS18 [get_ports reset_btn]

## USB-UART bridge, signal names from the FPGA perspective.
set_property PACKAGE_PIN AU36 [get_ports uart_rx]
set_property PACKAGE_PIN AU33 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS18 [get_ports {uart_rx uart_tx}]

set_property PACKAGE_PIN AM39 [get_ports {led[0]}]
set_property PACKAGE_PIN AN39 [get_ports {led[1]}]
set_property PACKAGE_PIN AR37 [get_ports {led[2]}]
set_property PACKAGE_PIN AT37 [get_ports {led[3]}]
set_property PACKAGE_PIN AR35 [get_ports {led[4]}]
set_property PACKAGE_PIN AP41 [get_ports {led[5]}]
set_property PACKAGE_PIN AP42 [get_ports {led[6]}]
set_property PACKAGE_PIN AU39 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]

set_false_path -from [get_ports reset_btn]


# UART is asynchronous; only the first receive synchronizer stage is exempt.
set_false_path -from [get_ports uart_rx] -to [get_pins -hier -filter {NAME =~ */uart/rx_sync_q_reg[0]/D}]
# MMCM lock/button asynchronously assert only the wrapper reset synchronizer.
set_false_path -to [get_pins -hier -filter {NAME =~ *reset_pipe_reg*/PRE}]
# No false paths or multicycle exceptions on CPU, AXI, RAM, DMA or SHAKE.
# UART TX and LEDs have no off-chip SoC-clocked receiver. Bound their physical
# propagation to 8 ns rather than invent a synchronous 250 MHz receiver at
# the MMCM output. UART is 115200 baud (8680 ns/bit); LEDs are indicators.
# This exception applies ONLY to the nine asynchronous output ports.
set soc_output_clock [get_clocks -of_objects [get_pins clock_mmcm/CLKOUT0]]
set_max_delay -datapath_only 8.0 -from $soc_output_clock -to [get_ports {uart_tx led[*]}]
