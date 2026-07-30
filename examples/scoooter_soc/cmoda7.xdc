# 12 MHz board oscillator
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports { clk_12 }]
create_clock -add -name clk_12 -period 83.333 -waveform {0 41.666} [get_ports { clk_12 }]

create_generated_clock -name system_clk_50 \
    -source [get_pins {i_system_mmcm/CLKIN1}] \
    -multiply_by 50 -divide_by 12 \
    [get_pins {i_system_mmcm/CLKOUT0}]

# User buttons: button[0] resets the complete SoC; button[1] is GPIO 2.
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports { button[0] }]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports { button[1] }]

# Logical GPIO 0 and 1.
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]

# FT2232HQ USB UART.
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]

# External JTAG on contiguous Cmod DIP pins 18..21. DIP 18 / N3 is MRCC.
set_property -dict { PACKAGE_PIN N3 IOSTANDARD LVCMOS33 } [get_ports { jtag_tck }]
set_property -dict { PACKAGE_PIN P3 IOSTANDARD LVCMOS33 } [get_ports { jtag_tms }]
set_property -dict { PACKAGE_PIN M2 IOSTANDARD LVCMOS33 } [get_ports { jtag_tdi }]
set_property -dict { PACKAGE_PIN N1 IOSTANDARD LVCMOS33 } [get_ports { jtag_tdo }]
create_clock -add -name jtag_tck -period 100.000 -waveform {0 50.000} [get_ports { jtag_tck }]

set_clock_groups -asynchronous \
    -group [get_clocks system_clk_50] \
    -group [get_clocks jtag_tck]

# Logical GPIO 3..6 on the second Pmod row, JA7..JA10.
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { gpio_external[0] }]
set_property -dict { PACKAGE_PIN H19 IOSTANDARD LVCMOS33 } [get_ports { gpio_external[1] }]
set_property -dict { PACKAGE_PIN J19 IOSTANDARD LVCMOS33 } [get_ports { gpio_external[2] }]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports { gpio_external[3] }]

# Logical GPIO 7 on Cmod DIP pin 1.
set_property -dict { PACKAGE_PIN M3 IOSTANDARD LVCMOS33 } [get_ports { gpio_external[4] }]
