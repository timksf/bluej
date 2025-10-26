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
module mkTAP#(Clock tdo_clk, Reset tdo_rst)(JTAG_TAP_Controller_ifc#(1));

    let tck <- exposeCurrentClock;
    let trst <- exposeCurrentReset;

    JTAG_TAP_Config_t#(1, `IR_WIDTH) jtag_config = JTAG_TAP_Config_t {
        idcode_man: 'h3A7,
        idcode_part: 'h04,
        idcode_ver: 0,
        reg_tdo: True,
        instrs: vec(
            'h02 //dummy register
        )
    };
    
    JTAG_Reg_ifc#(Bit#(32)) reg0 <- mkJTAGReg('hC0DEAFFE, clocked_by tck, reset_by trst);
    JTAG_TAP_Controller_ifc#(1) ifc <- mkJTAG_TAP_Controller(
        jtag_config,
        0,
        True,
        vec(as_read_only(reg0.tdo)),
        tdo_clk, tdo_rst,
        clocked_by tck, reset_by trst
    );

    mkConnection(reg0.tdi, ifc.int_tdi);
    jtagConnect(ifc.tap_ctrl, reg0.ctrl, 0);

    return ifc;
endmodule

module mkTestOOCD();

    let bus_clk <- mkAbsoluteClock(0, 2);
    let bus_rst <- mkAsyncResetFromCR(2, bus_clk);

    JTAG_TDO_Delay#(1) tdo_delay = ?;

    let oocd_driver <- mkJTAG_Driver_OOCD(tdo_delay, clocked_by bus_clk, reset_by bus_rst);
    JTAG_Stim_ifc jtag_stim <- mkJTAGShim(clocked_by bus_clk, reset_by bus_rst);
    
    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;
    let tck_inv = jtag_stim.tdo_clk;
    let trst_inv = jtag_stim.tdo_rst;

    let tap <- mkTAP(tck_inv, trst_inv, clocked_by tck, reset_by trst);

    //connect TAP to driver
    mkConnection(toGet(oocd_driver.ext_tck),    toPut(jtag_stim.ext_tck));
    // mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(oocd_driver.ext_tdi),    toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(oocd_driver.ext_tms),    toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),      toPut(oocd_driver.ext_tdo));
    
    mkConnection(toGet(jtag_stim.int_tms),  toPut(tap.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(tap.tdi));
    

    Stmt s = seq
        $display("Hello");
        // delay(500000);
        await(False);
    endseq;

    mkAutoFSM(s, clocked_by bus_clk, reset_by bus_rst);

endmodule

endpackage