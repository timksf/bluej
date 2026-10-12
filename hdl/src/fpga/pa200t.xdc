set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE Yes [current_design]

create_clock -period 5 -name clk_200 [get_ports CLK_clk_p]
create_clock -period 100 -name jtag_tck [get_nets {*bscane2$TCK}]

set_clock_groups -group clk_100mhz -group jtag_tck -asynchronous


set_property -dict {PACKAGE_PIN R4 IOSTANDARD DIFF_SSTL15} [get_ports CLK_clk_p]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD DIFF_SSTL15} [get_ports CLK_clk_n]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports RST_N]

set_property -dict {PACKAGE_PIN W22  IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN Y22  IOSTANDARD LVCMOS33} [get_ports {LED[1]}]