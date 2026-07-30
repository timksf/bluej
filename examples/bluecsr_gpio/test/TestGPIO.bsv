// SPDX-License-Identifier: MIT

package TestGPIO;

import StmtFSM :: *;
import GetPut :: *;

import BlueCSRCore :: *;
import BlueCSRGPIO :: *;

module mkTestGPIO(Empty);

    BlueCSRGPIO_ifc#(8, 8) i_gpio <- mkBlueCSRGPIO;

    Reg#(Bit#(8)) rg_input <- mkReg(0);

    rule r_drive_pins;
        i_gpio.input_value(rg_input);
    endrule

    function Action issue_read(Bit#(8) address);
        action
            i_gpio.csr.request.put(BlueCSR_Req_t {
                wr:    False,
                addr:  address,
                wdata: 0,
                wstrb: 0,
                prot:  CSR_INSECURE
            });
        endaction
    endfunction

    function Action issue_write(Bit#(8) address, Bit#(32) data);
        action
            i_gpio.csr.request.put(BlueCSR_Req_t {
                wr:    True,
                addr:  address,
                wdata: data,
                wstrb: 4'hF,
                prot:  CSR_INSECURE
            });
        endaction
    endfunction

    function Action expect_read(Bit#(32) expected, String label);
        action
            let response <- i_gpio.csr.response.get;
            if(response.resp != CSR_OKAY || response.rdata != expected) begin
                $display(
                    "%s: expected %08x/OKAY, got %08x/%0d",
                    label, expected, response.rdata, response.resp
                );
                $finish(1);
            end
        endaction
    endfunction

    function Action expect_write(String label);
        action
            let response <- i_gpio.csr.response.get;
            if(response.resp != CSR_OKAY) begin
                $display("%s: expected OKAY, got %0d", label, response.resp);
                $finish(1);
            end
        endaction
    endfunction

    function Action expect_unmapped(String label);
        action
            let response <- i_gpio.csr.response.get;
            if(response.resp != CSR_DECERR) begin
                $display("%s: expected DECERR, got %0d", label, response.resp);
                $finish(1);
            end
        endaction
    endfunction

    function Action check(Bool condition, String label);
        action
            if(!condition) begin
                $display("%s", label);
                $finish(1);
            end
        endaction
    endfunction

    Stmt test = seq
        issue_read('h00);
        expect_read(0, "INPUT_VAL reset");

        issue_write('h04, 32'h0F);
        expect_write("INPUT_EN write");
        rg_input <= 8'h05;
        repeat(5) noAction;
        issue_read('h00);
        expect_read(32'h05, "synchronized INPUT_VAL");

        issue_write('h08, 32'h0F);
        expect_write("OUTPUT_EN write");
        issue_write('h0C, 32'h0A);
        expect_write("OUTPUT_VAL write");
        check(i_gpio.output_enable == 8'h0F, "OUTPUT_EN pin value mismatch");
        check(i_gpio.output_value == 8'h0A, "OUTPUT_VAL pin value mismatch");

        issue_write('h40, 32'h03);
        expect_write("OUT_XOR write");
        check(i_gpio.output_value == 8'h09, "OUT_XOR pin value mismatch");

        issue_read('h38);
        expect_unmapped("reserved offset 0x38");
        issue_read('h3C);
        expect_unmapped("reserved offset 0x3c");

        rg_input <= 0;
        repeat(5) noAction;
        issue_write('h1C, 32'hFF);
        expect_write("RISE_IP stale clear");
        issue_write('h18, 1);
        expect_write("RISE_IE write");
        rg_input <= 1;
        repeat(5) noAction;
        check(i_gpio.interrupt, "rising-edge interrupt did not assert");
        issue_read('h1C);
        expect_read(1, "RISE_IP");
        issue_write('h1C, 1);
        expect_write("RISE_IP clear");
        noAction;
        check(!i_gpio.interrupt, "rising-edge interrupt did not clear");

        $display("BlueCSR GPIO test passed");
    endseq;

    mkAutoFSM(test);

endmodule

endpackage
