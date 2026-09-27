# VC707 constraints for vc707_picorv32_slh_soc_ddr.
# DDR3 pins and the 200 MHz input clock are supplied by the imported MIG XDC.
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]

set_property PACKAGE_PIN E19 [get_ports sys_clk_p]
set_property PACKAGE_PIN E18 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL15 [get_ports {sys_clk_p sys_clk_n}]

set_property PACKAGE_PIN AV40 [get_ports cpu_reset]
set_property IOSTANDARD LVCMOS18 [get_ports cpu_reset]
set_property PACKAGE_PIN AU33 [get_ports uart_rx_i]
set_property PACKAGE_PIN AU36 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS18 [get_ports {uart_rx_i uart_tx_o}]

set_property PACKAGE_PIN AM39 [get_ports {led_o[0]}]
set_property PACKAGE_PIN AN39 [get_ports {led_o[1]}]
set_property PACKAGE_PIN AR37 [get_ports {led_o[2]}]
set_property PACKAGE_PIN AT37 [get_ports {led_o[3]}]
set_property PACKAGE_PIN AR35 [get_ports {led_o[4]}]
set_property PACKAGE_PIN AP41 [get_ports {led_o[5]}]
set_property PACKAGE_PIN AP42 [get_ports {led_o[6]}]
set_property PACKAGE_PIN AU39 [get_ports {led_o[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_o[*]}]

set_false_path -from [get_ports cpu_reset]
set_false_path -from [get_ports uart_rx_i]
set_false_path -to [get_ports uart_tx_o]
set_false_path -to [get_ports {led_o[*]}]

# reset_pipe implements the standard asynchronous-assert/synchronous-release
# reset synchronizer.  MIG calibration and MMCM lock are intentionally allowed
# to assert the PRE pins asynchronously; only the registered release is used by
# the SoC.  Cut exactly these asynchronous control arcs, not any data path.
set_false_path -to [get_pins -quiet {
    reset_pipe_reg[0]/PRE
    reset_pipe_reg[1]/PRE
    reset_pipe_reg[2]/PRE
}]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
