create_clock -name jtag_tck -period 100.000 [get_ports CLK]
create_clock -name axi_aclk -period 4.000  [get_ports CLK_bus_clk]