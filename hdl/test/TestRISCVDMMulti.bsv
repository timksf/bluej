package TestRISCVDMMulti;

import ClientServer :: *;
import GetPut :: *;
import StmtFSM :: *;
import Vector :: *;

import RISCV_DMI :: *;
import RISCV_DM :: *;

import TestHelper :: *;

typedef 3 HartCount;

module [Module] mkTestRISCVDMMulti(TestHandler);

    RISCVDM_ifc#(HartCount) dut <- mkRISCVDM;

    Vector#(HartCount, Reg#(Bool)) rg_halted <- replicateM(mkReg(False));
    Vector#(HartCount, Reg#(Bool)) rg_running <- replicateM(mkReg(True));
    Reg#(Bool) rg_started <- mkReg(False);
    Reg#(Bool) rg_failed <- mkReg(False);

    for(Integer i = 0; i < valueOf(HartCount); i = i + 1) begin
        rule r_drive_hart_status;
            dut.harts[i].status(DMHartStatus_t {
                halted: rg_halted[i],
                running: rg_running[i],
                unavailable: False
            });
        endrule
    end

    function Stmt dmi_write(Bit#(32) address, Bit#(32) data);
        return seq
            dut.dmi.request.put(DMI_Request_t {
                address: truncate(address >> 2),
                data:    data,
                op:      DMI_WRITE,
                epoch:   0
            });
            action
                let response <- dut.dmi.response.get;
                if(response.error) begin
                    $display("DMI write at %08x failed", address);
                    rg_failed <= True;
                end
            endaction
        endseq;
    endfunction

    function Stmt expect_dmi_read(Bit#(32) address, Bit#(32) expected, Bit#(32) mask);
        return seq
            dut.dmi.request.put(DMI_Request_t {
                address: truncate(address >> 2),
                data:    0,
                op:      DMI_READ,
                epoch:   0
            });
            action
                let response <- dut.dmi.response.get;
                if(response.error || (response.data & mask) != (expected & mask)) begin
                    $display("DMI read mismatch at %08x: expected %08x mask %08x, got %08x",
                             address, expected, mask, response.data);
                    rg_failed <= True;
                end
            endaction
        endseq;
    endfunction

    Stmt test = seq
        dmi_write(32'h040, 32'h00000001);
        delay(2);

        action
            rg_halted[1] <= True;
            rg_running[1] <= False;
            rg_halted[2] <= True;
            rg_running[2] <= False;
        endaction
        delay(2);

        // Each implemented hart is independently selectable.
        dmi_write(32'h040, 32'h00010001);
        delay(2);
        expect_dmi_read(32'h044, 32'h00000382, 32'h0000ffff);
        expect_dmi_read(32'h100, 32'h00000006, 32'hffffffff);

        dmi_write(32'h040, 32'h80020001);
        delay(2);
        action
            if(dut.harts[0].halt_request || dut.harts[1].halt_request || !dut.harts[2].halt_request) begin
                $display("halt request was not routed exclusively to hart 2");
                rg_failed <= True;
            end
        endaction

        // Abstract commands are routed to the selected hart.
        dmi_write(32'h040, 32'h00010001);
        dmi_write(32'h05c, 32'h00221005);
        action
            let request <- dut.harts[1].registers.request.get;
            if(request.regno != 16'h1005 || request.write) begin
                $display("hart 1 abstract request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            dut.harts[1].registers.response.put(DMHartRegResponse_t {
                data: 32'h13579bdf,
                error: 0,
                epoch: request.epoch
            });
        endaction
        expect_dmi_read(32'h010, 32'h13579bdf, 32'hffffffff);

        // A selector encoding outside the configured vector reports nonexistent.
        dmi_write(32'h040, 32'h00030001);
        delay(2);
        expect_dmi_read(32'h040, 32'h00030001, 32'h00030001);
        expect_dmi_read(32'h044, 32'h0000c082, 32'h0000ffff);
        dmi_write(32'h05c, 32'h00221005);
        delay(2);
        expect_dmi_read(32'h058, 32'h00000401, 32'h00001f0f);

        action
            if(rg_failed) begin
                $display("RISC-V multi-hart DM test failed");
                $finish(1);
            end
            else begin
                $display("RISC-V multi-hart DM test passed");
            end
        endaction
    endseq;

    FSM f_test <- mkFSM(test);

    method Action go if(!rg_started);
        rg_started <= True;
        f_test.start;
    endmethod

    method done = rg_started && f_test.done;

endmodule

endpackage
