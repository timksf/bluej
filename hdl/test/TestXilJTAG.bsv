package TestXilJTAG;

import StmtFSM :: *;
import Connectable :: *;
import GetPut :: *;
import BuildVector :: *;
import Clocks :: *;

import TestHelper :: *;

import BlueJ :: *;
import ClockUtil :: *;
import GLBL :: *;
import BSCANE2 :: *;
import JTAG_SIME2 :: *;
import JTAG_Xilinx :: *;

(* synthesize *)
module [Module] mkTestXilJTAG(TestHandler);

    //required for simulation of Xilinx IP (this handles driving BSCANE2)
    let glbl <- vMkGLBL;

    Wire#(Bit#(1)) wtck     <- mkWire;
    Wire#(Bit#(1)) wtrst    <- mkWire;
    Wire#(Bit#(1)) ext_tdi  <- mkWire;
    Wire#(Bit#(1)) ext_tms  <- mkWire;
    Wire#(Bit#(1)) ext_tdo  <- mkBypassWire;

    Reg#(Bit#(32)) rOut     <- mkRegU;
    Reg#(Bit#(32)) rCount   <- mkRegU;

    //handles clocking
    let jtag_stim <- mkJTAGShim();

    let tck         = jtag_stim.tck_out;
    let trst        = jtag_stim.trst_out;
    let tck_inv     = jtag_stim.tdo_clk;
    let trst_inv    = jtag_stim.tdo_rst;

    //user register
    JTAG_Reg_ifc#(Bit#(32)) user_reg <- mkJTAGReg('hC0DEAFFE, clocked_by tck, reset_by trst);

    //xilinx JTAG simulation primitives
    let jtag_sime2 <- mkJTAG_SIME2("xcku3p", clocked_by tck);
    
    let bscan_cfg = BSCANE2_Config { p_DISABLE_JTAG: False, p_JTAG_CHAIN: 3 };
    let bscane2 <- mkBSCANE2_BlueJ_(bscan_cfg, tck_inv, vec(as_read_only(user_reg.tdo)), clocked_by tck);

    mkConnection(toGet(wtck),               toPut(jtag_stim.ext_tck));
    mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(ext_tdi),            toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(ext_tms),            toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(ext_tdo)));

    //correctly clocked signals to DUT
    mkConnection(toGet(jtag_stim.int_tms),  toPut(jtag_sime2.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(jtag_sime2.tdi));
    mkConnection(toGet(jtag_sime2.tdo),     toPut(jtag_stim.int_tdo));

    //connect user register to BSCANE2
    jtagConnect(bscane2.tap_ctrl, user_reg.ctrl, 0);
    mkConnection(toGet(bscane2.int_tdi), toPut(user_reg.tdi));

    Stmt s = seq
        $display("Hello");

        jtag_reset(rCount, wtck, ext_tms, ext_tdi);
        jtag_ir(rCount, wtck, ext_tms, ext_tdi, c_INSTR_BYPASS);
        jtag_idle(rCount, wtck, ext_tms, ext_tdi, 10);

        jtag_ir(rCount, wtck, ext_tms, ext_tdi, c_INSTR_IDCODE);
        jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
        $display("IDCODE: %0x", rOut);

        jtag_ir(rCount, wtck, ext_tms, ext_tdi, c_INSTR_USER3);
        jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
        $display("USER: %0x", rOut);

        delay(20);
    endseq;

    FSM f <- mkFSM(s);
    method go = f.start;
    method done = f.done;

endmodule

endpackage