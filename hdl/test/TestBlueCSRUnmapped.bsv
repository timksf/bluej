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

module [Module] mkTestBlueCSRUnmapped(TestHandler);

    BlueCSRAccess_ifc#(8, 32, 0, Empty) i_default <-
        create_blue_csr(unmapped_test_map, False);
    BlueCSRAccess_ifc#(8, 32, 0, Empty) i_okay <-
        create_blue_csr_with_default_response(unmapped_test_map, False, CSR_OKAY);

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
