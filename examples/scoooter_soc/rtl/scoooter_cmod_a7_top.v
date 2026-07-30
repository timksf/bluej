`timescale 1ns / 1ps

module scoooter_cmod_a7_top (
    input  wire       clk_12,
    input  wire [1:0] button,
    output wire [1:0] led,

    input  wire       uart_rx,
    output wire       uart_tx,

    input  wire       jtag_tck,
    input  wire       jtag_tms,
    input  wire       jtag_tdi,
    output wire       jtag_tdo,

    inout  wire [4:0] gpio_external
);

    wire startup_done;
    wire mmcm_locked;
    wire mmcm_reset;

    wire system_clk_unbuffered;
    wire system_clk;
    wire mmcm_feedback;
    wire mmcm_feedback_buffered;

    wire reset_async_n;
    reg  [3:0] system_reset_sync;
    wire system_reset_n;

    wire jtag_tck_unbuffered;
    wire jtag_tck_global;
    reg  [1:0] jtag_reset_sync;
    reg  [1:0] jtag_tdo_reset_sync;
    wire jtag_reset_n;
    wire jtag_tdo_reset_n;

    wire [7:0] gpio_input;
    wire [7:0] gpio_output;
    wire [7:0] gpio_output_enable;
    wire [4:0] gpio_external_input;

    STARTUPE2 i_startup (
        .CFGCLK(),
        .CFGMCLK(),
        .EOS(startup_done),
        .PREQ(),
        .CLK(1'b0),
        .GSR(1'b0),
        .GTS(1'b0),
        .KEYCLEARB(1'b1),
        .PACK(1'b0),
        .USRCCLKO(1'b0),
        .USRCCLKTS(1'b1),
        .USRDONEO(1'b1),
        .USRDONETS(1'b1)
    );

    assign mmcm_reset = ~startup_done;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(50.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(83.333),
        .CLKOUT0_DIVIDE_F(12.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.01),
        .STARTUP_WAIT("FALSE")
    ) i_system_mmcm (
        .CLKFBOUT(mmcm_feedback),
        .CLKFBOUTB(),
        .CLKOUT0(system_clk_unbuffered),
        .CLKOUT0B(),
        .CLKOUT1(),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(mmcm_locked),
        .CLKFBIN(mmcm_feedback_buffered),
        .CLKIN1(clk_12),
        .PWRDWN(1'b0),
        .RST(mmcm_reset)
    );

    BUFG i_mmcm_feedback_bufg (
        .I(mmcm_feedback),
        .O(mmcm_feedback_buffered)
    );

    BUFG i_system_clk_bufg (
        .I(system_clk_unbuffered),
        .O(system_clk)
    );

    assign reset_async_n = startup_done && mmcm_locked && !button[0];

    always @(posedge system_clk or negedge reset_async_n) begin
        if (!reset_async_n)
            system_reset_sync <= 4'b0000;
        else
            system_reset_sync <= {system_reset_sync[2:0], 1'b1};
    end

    assign system_reset_n = system_reset_sync[3];

    IBUF i_jtag_tck_ibuf (
        .I(jtag_tck),
        .O(jtag_tck_unbuffered)
    );

    BUFG i_jtag_tck_bufg (
        .I(jtag_tck_unbuffered),
        .O(jtag_tck_global)
    );

    always @(posedge jtag_tck_global or negedge system_reset_n) begin
        if (!system_reset_n)
            jtag_reset_sync <= 2'b00;
        else
            jtag_reset_sync <= {jtag_reset_sync[0], 1'b1};
    end

    always @(negedge jtag_tck_global or negedge system_reset_n) begin
        if (!system_reset_n)
            jtag_tdo_reset_sync <= 2'b00;
        else
            jtag_tdo_reset_sync <= {jtag_tdo_reset_sync[0], 1'b1};
    end

    assign jtag_reset_n = jtag_reset_sync[1];
    assign jtag_tdo_reset_n = jtag_tdo_reset_sync[1];

    genvar gpio_index;
    generate
        for (gpio_index = 0; gpio_index < 5; gpio_index = gpio_index + 1) begin : g_gpio_iobuf
            IOBUF i_gpio_iobuf (
                .I(gpio_output[gpio_index + 3]),
                .O(gpio_external_input[gpio_index]),
                .T(~gpio_output_enable[gpio_index + 3]),
                .IO(gpio_external[gpio_index])
            );
        end
    endgenerate

    assign led[0] = gpio_output_enable[0] && gpio_output[0];
    assign led[1] = gpio_output_enable[1] && gpio_output[1];

    assign gpio_input[0] = led[0];
    assign gpio_input[1] = led[1];
    assign gpio_input[2] = button[1];
    assign gpio_input[7:3] = gpio_external_input;

    mkScoooterSystem i_scoooter_soc (
        .jtag_tck(jtag_tck_global),
        .jtag_reset_n(jtag_reset_n),
        .tdo_clk(jtag_tck_global),
        .RST_N_tdo_rst_n(jtag_tdo_reset_n),
        .system_clk(system_clk),
        .RST_N_system_rst_n(system_reset_n),
        .gpio_input(gpio_input),
        .gpio_output(gpio_output),
        .gpio_output_enable(gpio_output_enable),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .jtag_tms(jtag_tms),
        .jtag_tdi(jtag_tdi),
        .jtag_tdo(jtag_tdo)
    );

endmodule
