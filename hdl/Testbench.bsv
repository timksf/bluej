package Testbench;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import StmtFSM :: *;
import BuildVector :: *;
import Connectable :: *;

import BlueJ :: *;
import ClockUtil :: *;

`define IR_WIDTH 8

// (* synthesize *)
module mkDUT#(Clock tdo_clk, Reset tdo_rst)(JTAG_TAP_Controller_ifc#(1));

    let tck <- exposeCurrentClock;
    let trst <- exposeCurrentReset;

    JTAG_TAP_Config_t#(1, `IR_WIDTH) jtag_config = JTAG_TAP_Config_t {
        idcode_man: 'b00000010111,
        idcode_part: 'h04,
        idcode_ver: 0,
        instrs: vec('h02)
    };
    
    JTAG_Reg_ifc#(Bit#(32)) reg0 <- mkJTAGReg('hDEADBEEF, clocked_by tck, reset_by trst);
    JTAG_TAP_Controller_ifc#(1) ifc <- mkJTAG_TAP_Controller(
        jtag_config,    //tap config
        0,              //IDCODE instruction
        True,           //reset to idcode not bypass
        vec(as_read_only(reg0.tdo)),  //upstream TDOs
        tdo_clk, tdo_rst,
        clocked_by tck, reset_by trst
    );

    //connect custom data register
    mkConnection(reg0.tdi, ifc.int_tdi);
    jtagConnect(ifc.tap_ctrl, reg0.ctrl, 0);

    return ifc;
endmodule

module mkTestbench();

    let jtag_stim <- mkJTAGShim();

    Wire#(Bit#(1)) wtck <- mkWire;
    Wire#(Bit#(1)) wtrst <- mkWire;
    Wire#(Bit#(1)) ext_tdi <- mkWire;
    Wire#(Bit#(1)) ext_tms <- mkWire;
    Wire#(Bit#(1)) ext_tdo <- mkBypassWire;

    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;

    let dut <- mkDUT(jtag_stim.tdo_clk, jtag_stim. tdo_rst, clocked_by tck, reset_by trst);

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

    Stmt s = {
        seq
            jtag_reset(rCount, wtck, ext_tms, ext_tdi);
            jtag_idle(rCount, wtck, ext_tms, ext_tdi, 10);
            delay(10);
            //read custom register
            jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'h02);
            jtag_idle(rCount, wtck, ext_tms, ext_tdi, 10);
            jtag_dr_ret(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut);
            jtag_idle(rCount, wtck, ext_tms, ext_tdi, 1);
            //read IDCODE
            jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'h00);
            jtag_dr_ret(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut);
            delay(10); //not driving JTAG signals should not have any effect on JTAG hardware
            rOut <= 0;
            //BYPASS
            jtag_ir(rCount, wtck, ext_tms, ext_tdi, Bit#(`IR_WIDTH)'(unpack(-1)));
            jtag_dr_ret(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'hCAFEAFFE, rOut);
            rOut <= rOut >> 1; //bypass results arrive once cycle delayed in relation to TDI
            delay(10);
        endseq
    };

    mkAutoFSM(s);


endmodule

endpackage