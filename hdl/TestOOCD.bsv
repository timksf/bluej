package TestOOCD;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import BRAM :: *;
import StmtFSM :: *;
import ClientServer :: *;
import BuildVector :: *;
import Connectable :: *;

import BlueJ :: *;
import ClockUtil :: *;

`define IR_WIDTH 8

(* synthesize *)
module mkTAP(JTAG_TAP_Controller_ifc#(1));

    let tck <- exposeCurrentClock;
    let trst <- exposeCurrentReset;

    JTAG_TAP_Config_t#(1, `IR_WIDTH) jtag_config = JTAG_TAP_Config_t {
        idcode_man: 'h3A7,
        idcode_part: 'h04,
        idcode_ver: 0,
        instrs: vec(
            'h02 //dummy register
        )
    };
    
    JTAG_TAP_Controller_ifc#(1) ifc <- mkJTAG_TAP_Controller(jtag_config, 0, True, clocked_by tck, reset_by trst);

    return ifc;
endmodule

module mkTestOOCD();

    let bus_clk <- mkAbsoluteClock(0, 2);
    let bus_rst <- mkAsyncResetFromCR(2, bus_clk);

    let oocd_driver <- mkJTAG_Driver_OOCD(clocked_by bus_clk, reset_by bus_rst);
    let jtag_stim <- mkJTAGShim(clocked_by bus_clk, reset_by bus_rst);
    
    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;

    let tap <- mkTAP(clocked_by tck, reset_by trst);
    JTAG_Reg_ifc#(Bit#(32)) reg0 <- mkJTAGReg('hC0DEAFFE, clocked_by tck, reset_by trst);

    mkConnection(reg0.tdi, jtag_stim.int_tdi);
    jtagConnect(tap.tap_ctrl, reg0.ctrl, 0);

    //connect TAP to driver
    mkConnection(toGet(oocd_driver.ext_tck),    toPut(jtag_stim.ext_tck));
    // mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(oocd_driver.ext_tdi),    toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(oocd_driver.ext_tms),    toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),      toPut(oocd_driver.ext_tdo));
    
    mkConnection(toGet(jtag_stim.int_tms),  toPut(tap.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(tap.tdi));
    mkConnection(toGet(tap.tdo),            toPut(jtag_stim.int_tdo));

    Stmt s = seq
        $display("Hello");
        await(False);
    endseq;

    mkAutoFSM(s, clocked_by bus_clk, reset_by bus_rst);

endmodule

endpackage