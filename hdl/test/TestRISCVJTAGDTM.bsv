package TestRISCVJTAGDTM;

import Clocks :: *;
import Connectable :: *;
import GetPut :: *;
import StmtFSM :: *;

import TestHelper :: *;
import JTAG_TB :: *;

import AXI4_Lite_Types :: *;
import AXI4_Lite_Slave :: *;
import JTAG_System :: *;
import JTAG_Types :: *;
import ClockUtil :: *;
import RISCV_DMI :: *;
import RISCV_JTAG_DTM :: *;

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
    Clock axi_clk,
    Reset axi_rst
)(JTAGSystem_ifc#(RISCVJTAGDTMDevice_ifc#(TestABits)));

    JTAG_TAP_Meta_Config_t tap_meta = JTAG_TAP_Meta_Config_t {
        idcode_ver:  4'h1,
        idcode_man:  11'h023,
        idcode_part: 16'h4567
    };

    let system <- mkRISCVJTAGDTMAXI4Lite(tap_meta, tdo_clk, tdo_rst, axi_clk, axi_rst);
    return system;

endmodule

module [Module] mkTestRISCVJTAGDTM(TestHandler);

    Clock axi_clk <- exposeCurrentClock;
    Reset axi_rst <- exposeCurrentReset;

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

    let dut <- mkRISCVJTAGDUT(tdo_clk, tdo_rst, axi_clk, axi_rst, clocked_by tck, reset_by trst);

    mkConnection(toGet(w_tck),              toPut(jtag_stim.ext_tck));
    mkConnection(toGet(w_trst),             toPut(jtag_stim.ext_trst));
    mkConnection(toGet(w_tdi),              toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(w_tms),              toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(w_tdo)));

    mkConnection(toGet(jtag_stim.int_tms),  toPut(dut.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(dut.tdi));
    mkConnection(toGet(dut.tdo),            toPut(jtag_stim.int_tdo));

    AXI4_Lite_Slave_Rd#(32, 32) i_axi_rd <- mkAXI4_Lite_Slave_Rd(2);
    AXI4_Lite_Slave_Wr#(32, 32) i_axi_wr <- mkAXI4_Lite_Slave_Wr(2);
    mkConnection(dut.device_ifc.m_axi_rd, i_axi_rd.fab);
    mkConnection(dut.device_ifc.m_axi_wr, i_axi_wr.fab);

    Reg#(Bit#(32)) rg_written_data <- mkReg(0);
    Reg#(Bit#(32)) rg_dtmcs_out <- mkReg(0);
    Reg#(Bit#(32)) rg_idcode_out <- mkReg(0);
    Reg#(Bit#(TestDMIWidth)) rg_dmi_out <- mkReg(0);
    Reg#(Bit#(2)) rg_bypass_out <- mkReg(0);

    rule r_axi_read;
        let request <- i_axi_rd.request.get;
        i_axi_rd.response.put(AXI4_Lite_Read_Rs_Pkg {
            data: request.addr == 32'h44 ? 32'h89abcdef : 0,
            resp: OKAY
        });
    endrule

    rule r_axi_write;
        let request <- i_axi_wr.request.get;
        if(request.addr == 32'h40) begin
            rg_written_data <= request.data;
        end
        i_axi_wr.response.put(AXI4_Lite_Write_Rs_Pkg { resp: OKAY });
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
        jtag_idle(w_tck, w_tms, w_tdi, 8);
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
        jtag_idle(w_tck, w_tms, w_tdi, 8);
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
