package TestSystemAPI;

import Vector :: *;
import Clocks :: *;
import DReg :: *;

import TestHelper :: *;

import BlueJ :: *;

`define IR_WIDTH 8

interface APITest_ifc;
    method Bit#(8) dummy();
endinterface

module [JTAGSystem#(9, `IR_WIDTH)] apiJTAGSystem#(Clock sys_clk, Reset sys_rst)(APITest_ifc);

    jtag_meta_config(0, 'b00000010111, 'h04);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(0);
    jtag_rst_to_idcode();

    Reg#(Bit#(8)) rw_value        <- mkReg('h12);
    Reg#(Bit#(8)) wo_seen         <- mkReg(0);
    Reg#(Bit#(8)) rw_seen         <- mkReg(0);
    Reg#(Bit#(8)) raw_seen        <- mkReg(0);
    Reg#(Bool)    pulse_seen      <- mkDReg(False);

    Reg#(Bit#(8)) sync_rw_value   <- mkReg('h34, clocked_by sys_clk, reset_by sys_rst);
    Reg#(Bit#(8)) sync_wo_seen    <- mkReg(0, clocked_by sys_clk, reset_by sys_rst);
    Reg#(Bit#(8)) sync_rw_seen    <- mkReg(0, clocked_by sys_clk, reset_by sys_rst);
    Reg#(Bool)    sync_pulse_seen <- mkDReg(False, clocked_by sys_clk, reset_by sys_rst);

    JTAGInstruction_t#(`IR_WIDTH) instr_ro         = 'h10;
    JTAGInstruction_t#(`IR_WIDTH) instr_wo         = 'h11;
    JTAGInstruction_t#(`IR_WIDTH) instr_rw         = 'h12;
    JTAGInstruction_t#(`IR_WIDTH) instr_pulse      = 'h13;
    JTAGInstruction_t#(`IR_WIDTH) instr_raw        = 'h14;
    JTAGInstruction_t#(`IR_WIDTH) instr_sync_ro    = 'h20;
    JTAGInstruction_t#(`IR_WIDTH) instr_sync_wo    = 'h21;
    JTAGInstruction_t#(`IR_WIDTH) instr_sync_rw    = 'h22;
    JTAGInstruction_t#(`IR_WIDTH) instr_sync_pulse = 'h23;
    Bit#(8)                         ro_value         = 8'h01;
    Bit#(8)                         sync_ro_value    = 8'h21;

    jtag_reg_ro(ro_value, instr_ro);
    JTAGRegAccess_ifc#(Bit#(8)) wo    <- jtag_reg_wo(instr_wo);
    JTAGRegAccess_ifc#(Bit#(8)) rw    <- jtag_reg_rw(rw_value, instr_rw);
    JTAGPulseAccess_ifc          pulse <- jtag_reg_pulse(instr_pulse);

    JTAG_Reg_ifc#(Bit#(8))  raw        <- mkJTAGReg(8'h55);
    JTAGRegAccess_ifc#(Bit#(8)) raw_access <- jtag_endpoint(raw, instr_raw);

    jtag_sync_reg_ro(sync_ro_value, instr_sync_ro, sys_clk, sys_rst);
    JTAGRegAccess_ifc#(Bit#(8)) sync_wo    <- jtag_sync_reg_wo(instr_sync_wo, sys_clk, sys_rst);
    JTAGRegAccess_ifc#(Bit#(8)) sync_rw    <- jtag_sync_reg_rw(sync_rw_value, instr_sync_rw, sys_clk, sys_rst);
    JTAGPulseAccess_ifc          sync_pulse <- jtag_sync_reg_pulse(instr_sync_pulse, sys_clk, sys_rst);

    rule consume_wo;
        let value <- wo.updated();
        wo_seen <= value;
    endrule

    rule consume_rw;
        let value <- rw.updated();
        rw_seen <= value;
    endrule

    rule consume_raw;
        let value <- raw_access.updated();
        raw_seen <= value;
    endrule

    rule consume_pulse;
        pulse.pulse();
        pulse_seen <= True;
    endrule

    rule consume_sync_wo;
        let value <- sync_wo.updated();
        sync_wo_seen <= value;
    endrule

    rule consume_sync_rw;
        let value <- sync_rw.updated();
        sync_rw_seen <= value;
    endrule

    rule consume_sync_pulse;
        sync_pulse.pulse();
        sync_pulse_seen <= True;
    endrule

    method dummy = rw_value ^ wo_seen ^ rw_seen ^ raw_seen;

endmodule

(* synthesize *)
module mkAPIDUT#(Clock tdo_clk, Reset tdo_rst, Clock sys_clk, Reset sys_rst)(JTAGSystem_ifc#(APITest_ifc));
    let jtag_sys <- build_jtag_system(apiJTAGSystem(sys_clk, sys_rst), tdo_clk, tdo_rst);
    return jtag_sys;
endmodule

(* synthesize *)
module [Module] mkTestSystemAPI(TestHandler);

    Clock sys_clk <- exposeCurrentClock;
    Reset sys_rst <- exposeCurrentReset;

    let dut <- mkAPIDUT(sys_clk, sys_rst, sys_clk, sys_rst);

    Reg#(Bool) started  <- mkReg(False);
    Reg#(Bool) finished <- mkReg(False);

    rule finish(started && !finished);
        let _dummy = dut.device_ifc.dummy();
        finished <= True;
    endrule

    method Action go() if(!started);
        started <= True;
    endmethod

    method done = finished;

endmodule

endpackage
