package Testbench;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import StmtFSM :: *;
import BuildVector :: *;
import Connectable :: *;

import BlueJ :: *;
import ClockUtil :: *;

typedef 8 IR_WIDTH;

(* synthesize *)
module mkDUT(JTAG_TAP_Controller_ifc#(1));

    let tck <- exposeCurrentClock;
    let trst <- exposeCurrentReset;

    JTAG_TAP_Config_t#(1, IR_WIDTH) jtag_config = JTAG_TAP_Config_t {
        idcode_man: 'b00000010111,
        idcode_part: 'h04,
        idcode_ver: 0,
        instrs: vec('h02)
    };
    
    JTAG_TAP_Controller_ifc#(1) ifc <- mkJTAG_TAP_Controller(jtag_config, 0, True, clocked_by tck, reset_by trst);

    return ifc;
endmodule

module mkTestbench();

    let jtag_stim <- mkJTAGShim;

    Wire#(Bit#(1)) wtck <- mkWire;
    Wire#(Bit#(1)) wtrst <- mkWire;
    Wire#(Bit#(1)) ext_tdi <- mkWire;
    Wire#(Bit#(1)) ext_tms <- mkWire;
    Wire#(Bit#(1)) ext_tdo <- mkBypassWire;

    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;

    let dut <- mkDUT(clocked_by tck, reset_by trst);

    JTAG_Reg_ifc#(32) reg0 <- mkJTAGReg('hDEADBEEF, clocked_by tck, reset_by trst);

    //connect custom data register
    mkConnection(reg0.tdi, jtag_stim.int_tdi);
    jtagConnect(dut.tap_ctrl, reg0.ctrl, 0);

    Reg#(Bit#(32)) rCount <- mkRegU;
    Reg#(Bit#(32)) rOut <- mkReg(0);

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
            jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'h02);
            jtag_idle(rCount, wtck, ext_tms, ext_tdi, 10);
            jtag_dr_ret(rCount, wtck, ext_tms, ext_tdi, ext_tdo, rOut);
            jtag_idle(rCount, wtck, ext_tms, ext_tdi, 1);
            //read IDCODE
            jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'h00);
            jtag_dr_ret(rCount, wtck, ext_tms, ext_tdi, ext_tdo, rOut);
            delay(10);
        endseq
    };

    mkAutoFSM(s);


endmodule

endpackage