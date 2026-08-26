package TestRISCVDM;

import GetPut :: *;
import ClientServer :: *;
import Memory :: *;
import StmtFSM :: *;

import TestHelper :: *;

import BlueCSRCore :: *;
import BlueCSRExport :: *;

import RISCV_DMI :: *;
import RISCV_DM :: *;

module [Module] mkTestRISCVDM(TestHandler);

    RegMapDoc_t#(32) doc <- doc_blue_csr_markdown(riscv_dm_register_map);
    messageM(doc.reg_defs);

    RISCVDM_ifc#(1) dut <- mkRISCVDM;

    Reg#(Bool) rg_started          <- mkReg(False);
    Reg#(Bool) rg_failed           <- mkReg(False);
    Reg#(Bool) rg_hart_halted      <- mkReg(True);
    Reg#(Bool) rg_hart_running     <- mkReg(False);
    Reg#(Bool) rg_hart_unavailable <- mkReg(False);
    Reg#(Bit#(8)) rg_request_epoch <- mkReg(0);

    rule r_drive_hart_status;
        dut.harts[0].status(DMHartStatus_t {
            halted:      rg_hart_halted,
            running:     rg_hart_running,
            unavailable: rg_hart_unavailable
        });
    endrule

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
        // DM register behavior and hart halt request.
        expect_dmi_read(32'h044, 32'h00000382, 32'h000fffff);
        dmi_write(32'h040, 32'h00000001);
        dmi_write(32'h040, 32'h80000001);
        delay(2);
        action
            if(!dut.dmactive) begin
                $display("dmactive did not assert");
            end
            if(!dut.harts[0].halt_request) begin
                $display("halt request did not assert");
            end
            if(!dut.dmactive || !dut.harts[0].halt_request) begin
                rg_failed <= True;
            end
        endaction
        expect_dmi_read(32'h044, 32'h00000382, 32'h000fffff);
        expect_dmi_read(32'h054, 32'h00000000, 32'hffffffff);
        dmi_write(32'h054, 32'hffffffff);
        expect_dmi_read(32'h054, 32'h00000000, 32'hffffffff);

        // The BlueCSR action queue accepts successive mapped writes.
        action
            dut.dmi.request.put(DMI_Request_t {
                address: 7'h04,
                data:    32'h11111111,
                op:      DMI_WRITE,
                epoch:   0
            });
        endaction
        action
            dut.dmi.request.put(DMI_Request_t {
                address: 7'h04,
                data:    32'h22222222,
                op:      DMI_WRITE,
                epoch:   0
            });
        endaction
        action
            let response <- dut.dmi.response.get;
            if(response.error) begin
                $display("First queued DATA0 write failed");
                rg_failed <= True;
            end
        endaction
        action
            let response <- dut.dmi.response.get;
            if(response.error) begin
                $display("Second queued DATA0 write failed");
                rg_failed <= True;
            end
        endaction
        expect_dmi_read(32'h010, 32'h22222222, 32'hffffffff);

        // Write one GPR through the mandatory Access Register command.
        dmi_write(32'h010, 32'hdeadbeef);
        dmi_write(32'h05c, 32'h00231005);
        action
            let request <- dut.harts[0].registers.request.get;
            if(request.regno != 16'h1005 || !request.write || request.data != 32'hdeadbeef) begin
                $display("abstract GPR write request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            rg_request_epoch <= request.epoch;
        endaction
        expect_dmi_read(32'h058, 32'h00001001, 32'h00001f0f);
        dut.harts[0].registers.response.put(DMHartRegResponse_t {
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
            let request <- dut.harts[0].registers.request.get;
            if(request.regno != 16'h1006 || request.write) begin
                $display("abstract GPR read request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            dut.harts[0].registers.response.put(DMHartRegResponse_t {
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
            let request <- dut.harts[0].registers.request.get;
            dut.harts[0].registers.response.put(DMHartRegResponse_t {
                data:  32'h123456ab,
                error: 0,
                epoch: request.epoch
            });
        endaction
        expect_dmi_read(32'h010, 32'h000000ab, 32'hffffffff);

        // Resume a halted hart and observe resume acknowledgement.
        dmi_write(32'h040, 32'h40000001);
        action
            if(!dut.harts[0].resume_request) begin
                $display("resume request did not assert");
                rg_failed <= True;
            end
            rg_hart_halted <= False;
            rg_hart_running <= True;
        endaction
        delay(2);
        action
            if(dut.harts[0].resume_request) begin
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
            let request <- dut.m_system.request.get;
            if(!request.write || request.address != 32'h00002000 || request.data != 32'h11223344 || request.byteen != 4'hf) begin
                $display("SBA write request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            dut.m_system.response.put(MemoryResponse { data: 0 });
        endaction
        expect_dmi_read(32'h0e4, 32'h00002004, 32'hffffffff);

        // SBA read-on-address and read data.
        dmi_write(32'h0e0, 32'h00150000);
        dmi_write(32'h0e4, 32'h00003000);
        action
            let request <- dut.m_system.request.get;
            if(request.write || request.address != 32'h00003000) begin
                $display("SBA read request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            dut.m_system.response.put(MemoryResponse { data: 32'h55667788 });
        endaction
        expect_dmi_read(32'h0f0, 32'h55667788, 32'hffffffff);
        expect_dmi_read(32'h0e4, 32'h00003004, 32'hffffffff);

        // Byte writes are aligned onto the 32-bit AXI bus with byte strobes.
        dmi_write(32'h0e0, 32'h00010000);
        dmi_write(32'h0e4, 32'h00003103);
        dmi_write(32'h0f0, 32'h000000a5);
        action
            let request <- dut.m_system.request.get;
            if(!request.write || request.address != 32'h00003100 || request.data != 32'ha5000000 || request.byteen != 4'h8) begin
                $display("SBA byte write request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            dut.m_system.response.put(MemoryResponse { data: 0 });
        endaction
        expect_dmi_read(32'h0e4, 32'h00003104, 32'hffffffff);

        // Halfword reads select the requested lane and return it in SBDATA0[15:0].
        dmi_write(32'h0e0, 32'h00120000);
        dmi_write(32'h0e4, 32'h00003202);
        action
            let request <- dut.m_system.request.get;
            if(request.write || request.address != 32'h00003200) begin
                $display("SBA halfword read request mismatch: ", fshow(request));
                rg_failed <= True;
            end
            dut.m_system.response.put(MemoryResponse { data: 32'ha1b2c3d4 });
        endaction
        expect_dmi_read(32'h0f0, 32'h0000a1b2, 32'hffffffff);

        // Alignment errors are sticky and can be cleared through SBCS.
        dmi_write(32'h0e0, 32'h00150000);
        dmi_write(32'h0e4, 32'h00003002);
        expect_dmi_read(32'h0e0, 32'h00003000, 32'h00007000);
        dmi_write(32'h0e0, 32'h00057000);
        expect_dmi_read(32'h0e0, 32'h00000000, 32'h00007000);

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
