package TestRISCVJTAGDTM;

import Clocks :: *;
import ClientServer :: *;
import Connectable :: *;
import GetPut :: *;
import StmtFSM :: *;

import TestHelper :: *;
import JTAG_TB :: *;

import JTAG_System :: *;
import JTAG_Types :: *;
import ClockUtil :: *;
import RISCV_DMI :: *;
import RISCV_DTM :: *;

typedef 7 TestABits;
typedef 41 TestDMIWidth;

function Bit#(TestDMIWidth) dmi_scan_bits(Bit#(TestABits) address, Bit#(32) data, DMI_Op_t op);
    DMI_Scan_t#(TestABits) scan = DMI_Scan_t {
        address: address,
        data:    data,
        op:      op
    };
    return pack(scan);
endfunction

(* synthesize *)
module mkRISCVJTAGDUT#(
    Clock tdo_clk,
    Reset tdo_rst,
    Clock dmi_clk,
    Reset dmi_rst
)(JTAGSystem_ifc#(RISCVDTMDevice_ifc#(TestABits)));

    JTAG_TAP_Meta_Config_t tap_meta = JTAG_TAP_Meta_Config_t {
        idcode_ver:  4'h1,
        idcode_man:  11'h023,
        idcode_part: 16'h4567
    };

    let system <- mkRISCVDTM(tap_meta, tdo_clk, tdo_rst, dmi_clk, dmi_rst);
    return system;

endmodule

module [Module] mkTestRISCVJTAGDTM(TestHandler);

    Clock dmi_clk <- exposeCurrentClock;
    Reset dmi_rst <- exposeCurrentReset;

    let jtag_stim <- mkJTAGShim;

    Wire#(Bit#(1)) w_tck <- mkWire;
    Reg#(Bit#(1)) w_trst <- mkReg(0);
    Wire#(Bit#(1)) w_tdi <- mkWire;
    Wire#(Bit#(1)) w_tms <- mkWire;
    Wire#(Bit#(1)) w_tdo <- mkBypassWire;

    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;
    let tdo_clk = jtag_stim.tdo_clk;
    let tdo_rst = jtag_stim.tdo_rst;

    let dut <- mkRISCVJTAGDUT(tdo_clk, tdo_rst, dmi_clk, dmi_rst, clocked_by tck, reset_by trst);

    mkConnection(toGet(w_tck),              toPut(jtag_stim.ext_tck));
    mkConnection(toGet(w_trst),             toPut(jtag_stim.ext_trst));
    mkConnection(toGet(w_tdi),              toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(w_tms),              toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(w_tdo)));

    mkConnection(toGet(jtag_stim.int_tms),  toPut(dut.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(dut.tdi));
    mkConnection(toGet(dut.tdo),            toPut(jtag_stim.int_tdo));

    Reg#(Bit#(32)) rg_written_data <- mkReg(0);
    Reg#(Bit#(32)) rg_dtmcs_out <- mkReg(0);
    Reg#(Bit#(32)) rg_idcode_out <- mkReg(0);
    Reg#(Bit#(TestDMIWidth)) rg_dmi_out <- mkReg(0);
    Reg#(Bit#(2)) rg_bypass_out <- mkReg(0);
    Reg#(Bool) rg_hard_reset_seen <- mkReg(False);

    rule r_latch_hard_reset if(dut.device_ifc.hard_reset);
        rg_hard_reset_seen <= True;
    endrule

    rule r_dmi_request;
        let request <- dut.device_ifc.dmi.request.get;
        if(request.op == DMI_WRITE && request.address == 7'h10) begin
            rg_written_data <= request.data;
        end
        dut.device_ifc.dmi.response.put(DMI_Response_t {
            address: request.address,
            data:    request.op == DMI_READ && request.address == 7'h11 ? 32'h89abcdef : 0,
            error:   False,
            epoch:   request.epoch
        });
    endrule

    Stmt test = seq
        action
            w_tck <= 0;
            w_tms <= 1;
            w_tdi <= 0;
        endaction
        delay(2);
        w_tck <= 1;
        delay(2);
        w_tck <= 0;
        delay(2);
        w_trst <= 1;
        delay(2);
        jtag_reset(w_tck, w_tms, w_tdi);

        jtag_dr_ret_del(w_tck, w_tms, w_tdi, w_tdo, 32'h0, rg_idcode_out, 1);
        action
            if(rg_idcode_out != 32'h14567047) begin
                $display("IDCODE mismatch after TAP reset: %08x", rg_idcode_out);
                $finish(1);
            end
        endaction

        jtag_ir(w_tck, w_tms, w_tdi, 5'h10);
        jtag_idle(w_tck, w_tms, w_tdi, 2);
        jtag_dr_ret_del(w_tck, w_tms, w_tdi, w_tdo, 32'h0, rg_dtmcs_out, 1);
        action
            if(rg_dtmcs_out != 32'h00000071) begin
                $display("DTMCS scan mismatch: %08x", rg_dtmcs_out);
                $finish(1);
            end
        endaction

        jtag_ir(w_tck, w_tms, w_tdi, 5'h11);
        jtag_dr_ret_del(
            w_tck,
            w_tms,
            w_tdi,
            w_tdo,
            dmi_scan_bits(7'h11, 0, DMI_READ),
            rg_dmi_out,
            1
        );
        jtag_idle(w_tck, w_tms, w_tdi, 12);
        jtag_dr_ret_del(
            w_tck,
            w_tms,
            w_tdi,
            w_tdo,
            dmi_scan_bits(0, 0, DMI_NOP),
            rg_dmi_out,
            1
        );
        action
            DMI_Scan_t#(TestABits) response = unpack(rg_dmi_out);
            if(response.address != 7'h11 || response.data != 32'h89abcdef || response.op != DMI_NOP) begin
                $display("JTAG DMI read mismatch: ", fshow(response));
                $finish(1);
            end
        endaction

        jtag_dr_ret_del(
            w_tck,
            w_tms,
            w_tdi,
            w_tdo,
            dmi_scan_bits(7'h10, 32'hdecafbad, DMI_WRITE),
            rg_dmi_out,
            1
        );
        jtag_idle(w_tck, w_tms, w_tdi, 12);
        jtag_dr_ret_del(
            w_tck,
            w_tms,
            w_tdi,
            w_tdo,
            dmi_scan_bits(0, 0, DMI_NOP),
            rg_dmi_out,
            1
        );
        action
            if(rg_written_data != 32'hdecafbad) begin
                $display("JTAG DMI write did not reach AXI: %08x", rg_written_data);
                $finish(1);
            end
        endaction

        jtag_ir(w_tck, w_tms, w_tdi, 5'h12);
        jtag_dr_ret_del(w_tck, w_tms, w_tdi, w_tdo, 2'b01, rg_bypass_out, 1);
        action
            if(rg_bypass_out != 2'b10) begin
                $display("Reserved instruction did not select one-bit BYPASS: %02b", rg_bypass_out);
                $finish(1);
            end
        endaction

        jtag_ir(w_tck, w_tms, w_tdi, 5'h10);
        jtag_dr_ret_del(w_tck, w_tms, w_tdi, w_tdo, 32'h00020000, rg_dtmcs_out, 1);
        jtag_idle(w_tck, w_tms, w_tdi, 12);
        action
            if(!rg_hard_reset_seen) begin
                $display("DTMHARDRESET did not cross to the DMI clock domain");
                $finish(1);
            end
        endaction

        jtag_ir(w_tck, w_tms, w_tdi, 5'h11);
        jtag_reset(w_tck, w_tms, w_tdi);
        jtag_dr_ret_del(w_tck, w_tms, w_tdi, w_tdo, 32'h0, rg_idcode_out, 1);
        action
            if(rg_idcode_out != 32'h14567047) begin
                $display("Test-Logic-Reset did not restore IDCODE: %08x", rg_idcode_out);
                $finish(1);
            end
        endaction

        $display("RISC-V JTAG DTM integration test passed");
    endseq;

    FSM f_test <- mkFSM(test);
    Reg#(Bool) rg_started <- mkReg(False);

    method Action go if(!rg_started);
        rg_started <= True;
        f_test.start;
    endmethod

    method done = rg_started && f_test.done;

endmodule

endpackage
