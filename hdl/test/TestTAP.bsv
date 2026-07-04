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
import JTAG_TB :: *;

`define IR_WIDTH 8

interface MyJTAGSystem_ifc;
    method ActionValue#(Bit#(32)) myreg_read();
endinterface

module [JTAGSystem#(1, `IR_WIDTH)] myJTAGSystem(MyJTAGSystem_ifc);

    jtag_meta_config(0, 'b00000010111, 'h04);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(0);
    jtag_rst_to_idcode();
    jtag_enable_debug();

    //we expect this module to be clocked/reset by tck and trst
    Reg#(Bit#(32))                my_reg_value <- mkReg('hDEADBEEF);
    JTAGRegAccess_ifc#(Bit#(32))  my_reg       <- jtag_reg_rw(my_reg_value, 'h02);

    //blocks if no value loaded into register
    method myreg_read = my_reg.updated;

endmodule

(* synthesize *)
module mkDUT#(Clock tdo_clk, Reset tdo_rst)(JTAGSystem_ifc#(MyJTAGSystem_ifc));
    let jtag_sys <- build_jtag_system(myJTAGSystem, tdo_clk, tdo_rst);
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
            jtag_reset(wtck, ext_tms, ext_tdi);
            jtag_idle(wtck, ext_tms, ext_tdi, 10);
            delay(10);
            jtag_ir(wtck, ext_tms, ext_tdi, 8'hFF);
            jtag_reset(wtck, ext_tms, ext_tdi);
            //read custom register
            jtag_ir(wtck, ext_tms, ext_tdi, 8'h02);
            jtag_idle(wtck, ext_tms, ext_tdi, 10);
            jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
            $display("[%0t] USER DR read: %0x", $time, rOut);
            jtag_idle(wtck, ext_tms, ext_tdi, 1);
            //read IDCODE
            jtag_ir(wtck, ext_tms, ext_tdi, 8'h00);
            jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
            $display("[%0t] IDCODE DR read: %0x", $time, rOut);
            delay(10); //not driving JTAG signals should not have any effect on JTAG hardware
            rOut <= 0;
            //BYPASS
            jtag_ir(wtck, ext_tms, ext_tdi, Bit#(`IR_WIDTH)'(unpack(-1)));
            jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, 'hCAFEAFFE, rOut, 1);
            action
                Bit#(33) bypass_expected = Bit#(33)'('hCAFEAFFE);
                Bit#(33) bypass_aligned = rOut >> 1; //bypass results arrive once cycle delayed in relation to TDI
                $display("[%0t] BYPASS raw read:     %0x", $time, rOut);
                $display("[%0t] BYPASS aligned read: %0x (expected %0x)", $time, bypass_aligned, bypass_expected);
                if(bypass_aligned != bypass_expected) begin
                    $display("ERROR: BYPASS shifted value does not match scan input");
                end
                rOut <= bypass_aligned;
            endaction
            delay(10);
        endseq
    };

    FSM f <- mkFSM(s);
    method go = f.start;
    method done = f.done;

endmodule

endpackage
