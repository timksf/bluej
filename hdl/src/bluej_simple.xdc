create_clock -period 10 -name clk_100mhz [get_ports CLK_clk_p]
create_clock -name jtag_tck -period 100 -waveform {0 25} [get_nets {*bscane2$TCK}]

set_clock_groups -group clk_100mhz -group jtag_tck -asynchronous

set_property LOC E18 [get_ports CLK_clk_p]
set_property LOC D18 [get_ports CLK_clk_n]
set_property IOSTANDARD LVDS [get_ports CLK_clk_p]
set_property IOSTANDARD LVDS [get_ports CLK_clk_n]

set_property PACKAGE_PIN B11 [get_ports {LED[3]}]
set_property PACKAGE_PIN C11 [get_ports {LED[2]}]
set_property PACKAGE_PIN A10 [get_ports {LED[1]}]
set_property PACKAGE_PIN B10 [get_ports {LED[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {LED[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {LED[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {LED[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {LED[0]}]

set_property PACKAGE_PIN F18 [get_ports {RST_N}]
set_property IOSTANDARD LVCMOS18 [get_ports {RST_N}]