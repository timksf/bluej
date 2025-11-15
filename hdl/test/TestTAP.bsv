package TestTAP;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import StmtFSM :: *;
import BuildVector :: *;
import Connectable :: *;

import TestHelper :: *;

import BlueJ :: *;
import ClockUtil :: *;

`define IR_WIDTH 8

interface MyJTAGSystem_ifc;
    method ActionValue#(Bit#(32)) myreg_read();
endinterface

module [JTAGSystem#(1, `IR_WIDTH)] myJTAGSystem(MyJTAGSystem_ifc);

    JTAG_TAP_Config_t#(1, `IR_WIDTH) tap_config = JTAG_TAP_Config_t {
        idcode_man: 'b00000010111,
        idcode_part: 'h04,
        idcode_ver: 0,
        reg_tdo: True,
        instrs: vec('h02),
        debug: True,
        instr_idcode: 0, //IDCODE instruction
        reset_idcode_not_bypass: True //reset to idcode not bypass
    };

    //we expect this module to be clocked/reset by tck and trst
    JTAG_Reg_ifc#(Bit#(32)) my_reg <- mkJTAGReg('hDEADBEEF);

    setTAPConfig(tap_config);
    addJTAGReg(my_reg);

    //blocks if no value loaded into register
    method myreg_read if(my_reg.wr_o()) = actionvalue return my_reg.reg_o(); endactionvalue;

endmodule

(* synthesize *)
module mkDUT#(Clock tdo_clk, Reset tdo_rst)(JTAGSystem_ifc#(MyJTAGSystem_ifc));
    let jtag_sys <- buildJTAGSystem(myJTAGSystem, tdo_clk, tdo_rst);
    return jtag_sys;
endmodule

(* synthesize *)
module [Module] mkTestTAP(TestHandler);

    Wire#(Bit#(1)) wtck     <- mkWire;
    Wire#(Bit#(1)) wtrst    <- mkWire;
    Wire#(Bit#(1)) ext_tdi  <- mkWire;
    Wire#(Bit#(1)) ext_tms  <- mkWire;
    Wire#(Bit#(1)) ext_tdo  <- mkBypassWire;

    let jtag_stim <- mkJTAGShim();

    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;
    let tck_inv = jtag_stim.tdo_clk;
    let trst_inv = jtag_stim.tdo_rst;
    
    let dut <- mkDUT(tck_inv, trst_inv, clocked_by tck, reset_by trst);

    Reg#(Bit#(32)) rCount <- mkRegU;
    Reg#(Bit#(33)) rOut <- mkReg(0);

    //connect TAP controller to stimulus
    mkConnection(toGet(wtck),               toPut(jtag_stim.ext_tck));
    mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(ext_tdi),            toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(ext_tms),            toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(ext_tdo)));

    mkConnection(toGet(jtag_stim.int_tms),  toPut(dut.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(dut.tdi));

    mkConnection(toGet(dut.tdo),            toPut(jtag_stim.int_tdo));

    rule r;
        $display("Update user reg: %0x", dut.device_ifc.myreg_read());
    endrule

    Stmt s = {
        seq
            jtag_reset(rCount, wtck, ext_tms, ext_tdi);
            jtag_idle(rCount, wtck, ext_tms, ext_tdi, 10);
            delay(10);
            jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'hFF);
            jtag_reset(rCount, wtck, ext_tms, ext_tdi);
            //read custom register
            jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'h02);
            jtag_idle(rCount, wtck, ext_tms, ext_tdi, 10);
            jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
            jtag_idle(rCount, wtck, ext_tms, ext_tdi, 1);
            //read IDCODE
            jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'h00);
            jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
            delay(10); //not driving JTAG signals should not have any effect on JTAG hardware
            rOut <= 0;
            //BYPASS
            jtag_ir(rCount, wtck, ext_tms, ext_tdi, Bit#(`IR_WIDTH)'(unpack(-1)));
            jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'hCAFEAFFE, rOut, 1);
            rOut <= rOut >> 1; //bypass results arrive once cycle delayed in relation to TDI
            delay(10);
        endseq
    };

    FSM f <- mkFSM(s);
    method go = f.start;
    method done = f.done;

endmodule

endpackage