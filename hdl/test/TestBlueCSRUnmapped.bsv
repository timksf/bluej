package TestBlueCSRUnmapped;

import GetPut :: *;
import StmtFSM :: *;

import TestHelper :: *;

import BlueCSRCore :: *;

module [BlueCSRCtx_t#(8, 32)] unmapped_test_map(Empty);

    csr_regmap_def("unmappedTest", "BlueCSR unmapped response test");

    csr_reg_def('h04, "STATUS", "Read-only mapped register");
    csr_reg_rc('h04, Bit#(32)'('h12345678), 0, "VALUE", "Value", "Test value.");

endmodule

interface HUTestState_ifc;
    method Bit#(32) value;
    method Action update(Bit#(32) value);
endinterface

module [BlueCSRCtx_t#(8, 32)] hu_test_map(HUTestState_ifc);

    Wire#(Maybe#(Bit#(32))) w_update <- mkDWire(tagged Invalid);
    ReadOnly#(Bit#(32)) rg_value <- csr_reg_hu('h04, 0, 0, w_update, "VALUE", "Value", "Hardware-updatable test value.");

    csr_regmap_def("huTest", "BlueCSR hardware-updatable field test");
    csr_reg_def('h04, "VALUE", "Hardware-updatable test value");

    method value = rg_value;
    method Action update(Bit#(32) update_value);
        action
            w_update <= tagged Valid update_value;
        endaction
    endmethod

endmodule

module [Module] mkTestBlueCSRUnmapped(TestHandler);

    BlueCSRAccess_ifc#(8, 32, 0, Empty) i_default <-
        create_blue_csr(unmapped_test_map, False);
    BlueCSRAccess_ifc#(8, 32, 0, Empty) i_okay <-
        create_blue_csr_with_default_response(unmapped_test_map, False, CSR_OKAY);
    BlueCSRAccess_ifc#(8, 32, 0, HUTestState_ifc) i_hu <-
        create_blue_csr(hu_test_map, False);

    Reg#(Bool) rg_started <- mkReg(False);

    function Action issue_request(
        BlueCSR_ifc#(8, 32, 0) csr,
        Bool write,
        Bit#(8) address
    );
        action
            csr.request.put(BlueCSR_Req_t {
                wr:    write,
                addr:  address,
                wdata: 32'hdeadbeef,
                wstrb: 4'hf,
                prot:  CSR_SECURE
            });
        endaction
    endfunction

    function Action expect_response(
        BlueCSR_ifc#(8, 32, 0) csr,
        Bit#(32) expected_data,
        BlueCSRResponse_t expected_response,
        String label
    );
        action
            let response <- csr.response.get;
            if(response.rdata != expected_data || response.resp != expected_response) begin
                $display("%s: expected %08x/", label, expected_data,
                         fshow(expected_response), ", got %08x/", response.rdata,
                         fshow(response.resp));
                $finish(1);
            end
        endaction
    endfunction

    function Action issue_hu_write(Bit#(32) value, Bit#(4) strobe);
        action
            i_hu.external.request.put(BlueCSR_Req_t {
                wr:    True,
                addr:  'h04,
                wdata: value,
                wstrb: strobe,
                prot:  CSR_SECURE
            });
        endaction
    endfunction

    Stmt test = seq
        issue_request(i_default.external, False, 'h20);
        expect_response(i_default.external, 0, CSR_DECERR, "default unmapped read");
        issue_request(i_default.external, True, 'h20);
        expect_response(i_default.external, 0, CSR_DECERR, "default unmapped write");
        issue_request(i_default.external, True, 'h04);
        expect_response(i_default.external, 0, CSR_DECERR, "default unsupported write");

        issue_request(i_okay.external, False, 'h20);
        expect_response(i_okay.external, 0, CSR_OKAY, "configured unmapped read");
        issue_request(i_okay.external, True, 'h20);
        expect_response(i_okay.external, 0, CSR_OKAY, "configured unmapped write");

        issue_request(i_okay.external, False, 'h04);
        expect_response(i_okay.external, 32'h12345678, CSR_OKAY, "mapped read");
        issue_request(i_okay.external, True, 'h04);
        expect_response(i_okay.external, 0, CSR_OKAY, "configured fallback write");

        issue_hu_write(32'h11223344, 4'hf);
        expect_response(i_hu.external, 0, CSR_OKAY, "hardware-updatable full write");
        issue_request(i_hu.external, False, 'h04);
        expect_response(i_hu.external, 32'h11223344, CSR_OKAY, "hardware-updatable full read");

        issue_hu_write(32'haabbccdd, 4'b0101);
        expect_response(i_hu.external, 0, CSR_OKAY, "hardware-updatable partial write");
        issue_request(i_hu.external, False, 'h04);
        expect_response(i_hu.external, 32'h11bb33dd, CSR_OKAY, "hardware-updatable partial read");

        action
            issue_hu_write(32'hdeadbeef, 4'hf);
            i_hu.internal.update(32'hfeedface);
        endaction
        expect_response(i_hu.external, 0, CSR_OKAY, "hardware update and write");
        issue_request(i_hu.external, False, 'h04);
        expect_response(i_hu.external, 32'hfeedface, CSR_OKAY, "hardware update wins");

        $display("BlueCSR unmapped response test passed");
    endseq;

    FSM f_test <- mkFSM(test);

    method Action go if(!rg_started);
        rg_started <= True;
        f_test.start;
    endmethod

    method done = rg_started && f_test.done;

endmodule

endpackage
