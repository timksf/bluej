package TestRISCVDM;

import Connectable :: *;
import GetPut :: *;
import ClientServer :: *;
import StmtFSM :: *;

import TestHelper :: *;

import AXI4_Lite_Types :: *;
import AXI4_Lite_Master :: *;
import AXI4_Lite_Slave :: *;
import RISCV_DM :: *;

module [Module] mkTestRISCVDM(TestHandler);

    RISCVDM_ifc dut <- mkRISCVDM;

    AXI4_Lite_Master_Rd#(32, 32) i_dmi_rd <- mkAXI4_Lite_Master_Rd(2);
    AXI4_Lite_Master_Wr#(32, 32) i_dmi_wr <- mkAXI4_Lite_Master_Wr(2);
    AXI4_Lite_Slave_Rd#(32, 32) i_system_rd <- mkAXI4_Lite_Slave_Rd(2);
    AXI4_Lite_Slave_Wr#(32, 32) i_system_wr <- mkAXI4_Lite_Slave_Wr(2);

    mkConnection(i_dmi_rd.fab, dut.s_dmi_rd);
    mkConnection(i_dmi_wr.fab, dut.s_dmi_wr);
    mkConnection(dut.m_system_rd, i_system_rd.fab);
    mkConnection(dut.m_system_wr, i_system_wr.fab);

    Reg#(Bool) rg_started          <- mkReg(False);
    Reg#(Bool) rg_failed           <- mkReg(False);
    Reg#(Bool) rg_hart_halted      <- mkReg(True);
    Reg#(Bool) rg_hart_running     <- mkReg(False);
    Reg#(Bool) rg_hart_unavailable <- mkReg(False);
    Reg#(Bit#(8)) rg_request_epoch <- mkReg(0);

    rule r_drive_hart_status;
        dut.hart.status(DMHartStatus_t {
            halted:      rg_hart_halted,
            running:     rg_hart_running,
            unavailable: rg_hart_unavailable
        });
    endrule

    function Stmt dmi_write(Bit#(32) address, Bit#(32) data);
        return seq
            i_dmi_wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                addr: address,
                data: data,
                strb: 4'hf,
                prot: UNPRIV_SECURE_DATA
            });
            action
                let response <- i_dmi_wr.response.get;
                if(response.resp != OKAY) begin
                    $display("DMI write at %08x returned ", address, fshow(response.resp));
                    rg_failed <= True;
                end
            endaction
        endseq;
    endfunction

    function Stmt expect_dmi_read(Bit#(32) address, Bit#(32) expected, Bit#(32) mask);
        return seq
            i_dmi_rd.request.put(AXI4_Lite_Read_Rq_Pkg {
                addr: address,
                prot: UNPRIV_SECURE_DATA
            });
            action
                let response <- i_dmi_rd.response.get;
                if(response.resp != OKAY || (response.data & mask) != (expected & mask)) begin
                    $display("DMI read mismatch at %08x: expected %08x mask %08x, got %08x ",
                             address, expected, mask, response.data, fshow(response.resp));
                    rg_failed <= True;
                end
            endaction
        endseq;
    endfunction

    Stmt test = seq
        // DM register behavior and hart halt request.
        expect_dmi_read(32'h044, 32'h00000382, 32'h000fffff);
        dmi_write(32'h040, 32'h00000001);
        dmi_write(32'h040, 32'h80000001);
        delay(2);
        action
            if(!dut.dmactive) begin
                $display("dmactive did not assert");
            end
            if(!dut.hart.halt_request) begin
                $display("halt request did not assert");
            end
            if(!dut.dmactive || !dut.hart.halt_request) begin
                rg_failed <= True;
            end
        endaction
        expect_dmi_read(32'h044, 32'h00000382, 32'h000fffff);
        expect_dmi_read(32'h054, 32'h00000000, 32'hffffffff);
        dmi_write(32'h054, 32'hffffffff);
        expect_dmi_read(32'h054, 32'h00000000, 32'hffffffff);

        // The BlueCSR action queue accepts successive mapped writes.
        action
            i_dmi_wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                addr: 32'h010,
                data: 32'h11111111,
                strb: 4'hf,
                prot: UNPRIV_SECURE_DATA
            });
        endaction
        action
            i_dmi_wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                addr: 32'h010,
                data: 32'h22222222,
                strb: 4'hf,
                prot: UNPRIV_SECURE_DATA
            });
        endaction
        action
            let response <- i_dmi_wr.response.get;
            if(response.resp != OKAY) begin
                $display("First queued DATA0 write failed: ", fshow(response.resp));
                rg_failed <= True;
            end
        endaction
        action
            let response <- i_dmi_wr.response.get;
            if(response.resp != OKAY) begin
                $display("Second queued DATA0 write failed: ", fshow(response.resp));
                rg_failed <= True;
            end
        endaction
        expect_dmi_read(32'h010, 32'h22222222, 32'hffffffff);

        // Write one GPR through the mandatory Access Register command.
        dmi_write(32'h010, 32'hdeadbeef);
        dmi_write(32'h05c, 32'h00231005);
        action
            let request <- dut.hart.registers.request.get;
            if(request.regno != 16'h1005 || !request.write || request.data != 32'hdeadbeef) begin
                $display("abstract GPR write request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            rg_request_epoch <= request.epoch;
        endaction
        expect_dmi_read(32'h058, 32'h00001001, 32'h00001f0f);
        dut.hart.registers.response.put(DMHartRegResponse_t {
            data:  32'ha5a5a5a5,
            error: 0,
            epoch: rg_request_epoch
        });
        delay(2);
        expect_dmi_read(32'h058, 32'h00000001, 32'h00001f0f);
        expect_dmi_read(32'h010, 32'hdeadbeef, 32'hffffffff);

        // Read one GPR and return its value through DATA0.
        dmi_write(32'h05c, 32'h00221006);
        action
            let request <- dut.hart.registers.request.get;
            if(request.regno != 16'h1006 || request.write) begin
                $display("abstract GPR read request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            dut.hart.registers.response.put(DMHartRegResponse_t {
                data:  32'hcafebabe,
                error: 0,
                epoch: request.epoch
            });
        endaction
        expect_dmi_read(32'h058, 32'h00000001, 32'h00001f0f);
        expect_dmi_read(32'h010, 32'hcafebabe, 32'hffffffff);

        // Narrow register reads are legal and return the requested low bits.
        dmi_write(32'h05c, 32'h00021006);
        action
            let request <- dut.hart.registers.request.get;
            dut.hart.registers.response.put(DMHartRegResponse_t {
                data:  32'h123456ab,
                error: 0,
                epoch: request.epoch
            });
        endaction
        expect_dmi_read(32'h010, 32'h000000ab, 32'hffffffff);

        // Resume a halted hart and observe resume acknowledgement.
        dmi_write(32'h040, 32'h40000001);
        action
            if(!dut.hart.resume_request) begin
                $display("resume request did not assert");
                rg_failed <= True;
            end
            rg_hart_halted <= False;
            rg_hart_running <= True;
        endaction
        delay(2);
        action
            if(dut.hart.resume_request) begin
                $display("resume request did not clear after the hart ran");
                rg_failed <= True;
            end
        endaction
        expect_dmi_read(32'h044, 32'h00030c82, 32'h000fffff);

        // SBA write with auto-increment.
        dmi_write(32'h0e0, 32'h00050000);
        dmi_write(32'h0e4, 32'h00002000);
        dmi_write(32'h0f0, 32'h11223344);
        action
            let request <- i_system_wr.request.get;
            if(request.addr != 32'h00002000 || request.data != 32'h11223344 || request.strb != 4'hf) begin
                $display("SBA write request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            i_system_wr.response.put(AXI4_Lite_Write_Rs_Pkg { resp: OKAY });
        endaction
        expect_dmi_read(32'h0e4, 32'h00002004, 32'hffffffff);

        // SBA read-on-address and read data.
        dmi_write(32'h0e0, 32'h00150000);
        dmi_write(32'h0e4, 32'h00003000);
        action
            let request <- i_system_rd.request.get;
            if(request.addr != 32'h00003000) begin
                $display("SBA read request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            i_system_rd.response.put(AXI4_Lite_Read_Rs_Pkg {
                data: 32'h55667788,
                resp: OKAY
            });
        endaction
        expect_dmi_read(32'h0f0, 32'h55667788, 32'hffffffff);
        expect_dmi_read(32'h0e4, 32'h00003004, 32'hffffffff);

        // Alignment errors are sticky and can be cleared through SBCS.
        dmi_write(32'h0e4, 32'h00003002);
        expect_dmi_read(32'h0e0, 32'h00003000, 32'h00007000);
        dmi_write(32'h0e0, 32'h00057000);
        expect_dmi_read(32'h0e0, 32'h00000000, 32'h00007000);

        // AXI errors map to the SBA "other" error code.
        dmi_write(32'h0e4, 32'h00004000);
        dmi_write(32'h0f0, 32'h89abcdef);
        action
            let request <- i_system_wr.request.get;
            if(request.addr != 32'h00004000) begin
                $display("SBA error-path write address mismatch: ", fshow(request));
                rg_failed <= True;
            end
            i_system_wr.response.put(AXI4_Lite_Write_Rs_Pkg { resp: SLVERR });
        endaction
        expect_dmi_read(32'h0e0, 32'h00007000, 32'h00007000);

        action
            if(rg_failed) begin
                $display("RISC-V DM test failed");
                $finish(1);
            end
            else begin
                $display("RISC-V DM test passed");
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
