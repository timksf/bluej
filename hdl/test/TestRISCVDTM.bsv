package TestRISCVDTM;

import StmtFSM :: *;
import GetPut :: *;
import ClientServer :: *;

import TestHelper :: *;

import RISCV_DMI :: *;
import RISCV_DTM :: *;

typedef 7 TestABits;

module [Module] mkTestRISCVDTM(TestHandler);

    RISCVDTM_ifc#(TestABits) dut <- mkRISCVDTM;

    Reg#(Bool) rg_started <- mkReg(False);
    Reg#(Bool) rg_hard_reset_seen <- mkReg(False);
    Reg#(DMI_Request_t#(TestABits)) rg_request <- mkRegU;

    rule r_latch_hard_reset if(dut.hard_reset);
        rg_hard_reset_seen <= True;
    endrule

    function Action expect_status(Bit#(2) expected, String label);
        action
            if(dut.dtmcs[11:10] != expected) begin
                $display("%s: expected dmistat %0d, got %0d", label, expected, dut.dtmcs[11:10]);
                $finish(1);
            end
        endaction
    endfunction

    function Action expect_scan(DMI_Scan_t#(TestABits) expected, String label);
        action
            if(dut.dmi != expected) begin
                $display("%s: expected ", label, fshow(expected), " got ", fshow(dut.dmi));
                $finish(1);
            end
        endaction
    endfunction

    Stmt test = seq
        action
            if(dut.dtmcs != 32'h00000071) begin
                $display("DTMCS reset value mismatch: %08x", dut.dtmcs);
                $finish(1);
            end
        endaction

        dut.update_dmi(DMI_Scan_t { address: 7'h12, data: 32'h11223344, op: DMI_READ });
        delay(1);
        action
            let request <- dut.dmi_bus.request.get;
            rg_request <= request;
            if(request.address != 7'h12 || request.op != DMI_READ || request.epoch != 0) begin
                $display("Read request mismatch: ", fshow(request));
                $finish(1);
            end
        endaction
        dut.dmi_bus.response.put(DMI_Response_t {
            address: 7'h12,
            data:    32'hcafef00d,
            error:   False,
            epoch:   0
        });
        delay(2);
        expect_scan(DMI_Scan_t { address: 7'h12, data: 32'hcafef00d, op: DMI_NOP }, "successful read");

        dut.update_dmi(DMI_Scan_t { address: 7'h20, data: 0, op: DMI_READ });
        delay(1);
        action
            let request <- dut.dmi_bus.request.get;
            rg_request <= request;
        endaction
        dut.capture_dmi;
        delay(1);
        expect_status(3, "capture while pending");

        dut.update_dtmcs(32'h00010000);
        delay(1);
        expect_status(0, "dmireset");
        dut.dmi_bus.response.put(DMI_Response_t {
            address: 7'h20,
            data:    32'h55667788,
            error:   False,
            epoch:   0
        });
        delay(2);
        expect_scan(DMI_Scan_t { address: 7'h20, data: 32'h55667788, op: DMI_NOP }, "completion after dmireset");

        dut.update_dmi(DMI_Scan_t { address: 7'h21, data: 32'hdeadbeef, op: DMI_WRITE });
        delay(1);
        action
            let request <- dut.dmi_bus.request.get;
            rg_request <= request;
        endaction
        dut.dmi_bus.response.put(DMI_Response_t {
            address: 7'h21,
            data:    0,
            error:   True,
            epoch:   0
        });
        delay(2);
        expect_status(2, "failed write");

        dut.update_dtmcs(32'h00010000);
        delay(1);
        dut.update_dmi(DMI_Scan_t { address: 7'h30, data: 0, op: DMI_READ });
        delay(1);
        action
            let request <- dut.dmi_bus.request.get;
            rg_request <= request;
            if(request.epoch != 0) begin
                $display("Unexpected epoch before hard reset");
                $finish(1);
            end
        endaction

        dut.update_dtmcs(32'h00020000);
        delay(1);
        action
            if(!rg_hard_reset_seen) begin
                $display("Hard-reset pulse was not asserted");
                $finish(1);
            end
        endaction
        dut.dmi_bus.response.put(DMI_Response_t {
            address: 7'h30,
            data:    32'hbad0bad0,
            error:   False,
            epoch:   0
        });
        delay(2);
        dut.update_dmi(DMI_Scan_t { address: 7'h31, data: 0, op: DMI_READ });
        delay(1);
        action
            let request <- dut.dmi_bus.request.get;
            rg_request <= request;
            if(request.epoch != 1) begin
                $display("Hard reset did not advance request epoch");
                $finish(1);
            end
        endaction
        dut.dmi_bus.response.put(DMI_Response_t {
            address: 7'h31,
            data:    32'h0ddba11,
            error:   False,
            epoch:   1
        });
        delay(2);
        expect_scan(DMI_Scan_t { address: 7'h31, data: 32'h00ddba11, op: DMI_NOP }, "post-hard-reset read");

        $display("RISC-V DTM core test passed");
    endseq;

    FSM f_test <- mkFSM(test);

    method Action go if(!rg_started);
        rg_started <= True;
        f_test.start;
    endmethod

    method done = rg_started && f_test.done;

endmodule

endpackage
