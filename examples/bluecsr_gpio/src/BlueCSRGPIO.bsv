// SPDX-License-Identifier: MIT

package BlueCSRGPIO;

import Vector :: *;

import BlueCSRCore :: *;

interface GPIOPins_ifc#(numeric type n);
    (* always_enabled *) method Action input_value(Bit#(n) value);

    (* always_ready *) method Bit#(n) output_value;
    (* always_ready *) method Bit#(n) output_enable;
endinterface

interface BlueCSRGPIO_ifc#(numeric type n, numeric type aw);
    (* always_enabled *) method Action input_value(Bit#(n) value);

    (* always_ready *) method Bit#(n) output_value;
    (* always_ready *) method Bit#(n) output_enable;
    (* always_ready *) method Bool interrupt;

    interface BlueCSR_ifc#(aw, 32, 1) csr;
endinterface

module [BlueCSRCtx_t#(aw, 32)] gpio_csrs(GPIOPins_ifc#(n))
    provisos(Add#(n, unused, 32));

    Reg#(Bit#(n)) rg_input_0 <- mkReg(0);
    Reg#(Bit#(n)) rg_input_1 <- mkReg(0);
    Reg#(Bit#(n)) rg_input_2 <- mkReg(0);
    Reg#(Bit#(n)) rg_input_3 <- mkReg(0);

    csr_regmap_def("BlueCSRGPIO", "BlueCSR GPIO register map");

    csr_reg_def('h00, "INPUT_VAL", "GPIO input value register");
    Reg#(Bit#(n)) rg_input_val <- csr_reg_ro('h00, 0, 0, "VALUE", "Input Value", "Synchronized values of enabled GPIO inputs.");

    csr_reg_def('h04, "INPUT_EN", "GPIO input enable register");
    Reg#(Bit#(n)) rg_input_en <- csr_reg_rw('h04, 0, 0, "ENABLE", "Input Enable", "Enables sampling of each GPIO input.");

    csr_reg_def('h08, "OUTPUT_EN", "GPIO output enable register");
    Reg#(Bit#(n)) rg_output_en <- csr_reg_rw('h08, 0, 0, "ENABLE", "Output Enable", "Enables the output driver for each GPIO.");

    csr_reg_def('h0C, "OUTPUT_VAL", "GPIO output value register");
    Reg#(Bit#(n)) rg_output_val <- csr_reg_rw('h0C, 0, 0, "VALUE", "Output Value", "Software-controlled GPIO output values.");

    csr_reg_def('h18, "RISE_IE", "Rising-edge interrupt enable register");
    csr_reg_def('h1C, "RISE_IP", "Rising-edge interrupt pending register");
    csr_reg_def('h20, "FALL_IE", "Falling-edge interrupt enable register");
    csr_reg_def('h24, "FALL_IP", "Falling-edge interrupt pending register");
    csr_reg_def('h28, "HIGH_IE", "High-level interrupt enable register");
    csr_reg_def('h2C, "HIGH_IP", "High-level interrupt pending register");
    csr_reg_def('h30, "LOW_IE", "Low-level interrupt enable register");
    csr_reg_def('h34, "LOW_IP", "Low-level interrupt pending register");

    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        String suffix = integerToString(i);
        csr_irq(
            'h1C, 'h18, i, 0, unpack(rg_input_2[i]) && !unpack(rg_input_3[i]),
            "RISE" + suffix, "GPIO " + suffix + " Rising Edge",
            "A rising edge was detected on this GPIO input."
        );
        csr_irq(
            'h24, 'h20, i, 0, !unpack(rg_input_2[i]) && unpack(rg_input_3[i]),
            "FALL" + suffix, "GPIO " + suffix + " Falling Edge",
            "A falling edge was detected on this GPIO input."
        );
        csr_irq(
            'h2C, 'h28, i, 0, rg_input_3[i] == 1'b1,
            "HIGH" + suffix, "GPIO " + suffix + " High Level",
            "A high level was detected on this GPIO input."
        );
        csr_irq(
            'h34, 'h30, i, 0, rg_input_3[i] == 1'b0,
            "LOW" + suffix, "GPIO " + suffix + " Low Level",
            "A low level was detected on this GPIO input."
        );
    end

    csr_reg_def('h40, "OUT_XOR", "GPIO output inversion register");
    Reg#(Bit#(n)) rg_out_xor <- csr_reg_rw('h40, 0, 0, "INVERT", "Output Invert", "Inverts the final value of each GPIO output.");

    rule r_sync_inputs;
        rg_input_1   <= rg_input_0;
        rg_input_2   <= rg_input_1;
        rg_input_3   <= rg_input_2;
        rg_input_val <= rg_input_2;
    endrule

    method Action input_value(Bit#(n) value);
        rg_input_0 <= value & rg_input_en;
    endmethod

    method output_value = rg_output_val ^ rg_out_xor;

    method output_enable = rg_output_en;

endmodule

module [Module] mkBlueCSRGPIO(BlueCSRGPIO_ifc#(n, aw))
    provisos(Add#(n, unused, 32));

    BlueCSRAccess_ifc#(aw, 32, 1, GPIOPins_ifc#(n)) i_csrs <- create_blue_csr(gpio_csrs, False);

    method input_value = i_csrs.internal.input_value;

    method output_value  = i_csrs.internal.output_value;
    method output_enable = i_csrs.internal.output_enable;
    method interrupt     = i_csrs.external.irqs[0];

    interface csr = i_csrs.external;

endmodule

endpackage
