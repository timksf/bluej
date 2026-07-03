package TestBSCANNested;

import StmtFSM :: *;
import Connectable :: *;
import GetPut :: *;
import BuildVector :: *;
import Clocks :: *;

import TestHelper :: *;

import BlueJ :: *;
import GLBL :: *;
import JTAG_SIME2 :: *;
import JTAG_TB :: *;

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
    Reg#(Bit#(32))           my_reg_value <- mkReg('hDEADBEEF);
    JTAGRegAccess_ifc#(Bit#(32)) my_reg       <- jtag_reg_rw(my_reg_value, 'h02);

    set_tap_config(tap_config);

    //blocks if no value loaded into register
    method myreg_read = my_reg.updated;

endmodule

(* synthesize *)
module mkNestedTAP#(Clock tdo_clk, Reset tdo_rst)(JTAGSystem_ifc#(MyJTAGSystem_ifc));
    let jtag_sys <- build_jtag_system(myJTAGSystem, tdo_clk, tdo_rst);
    return jtag_sys;
endmodule

(* synthesize *)
module [Module] mkTestBSCANNested(TestHandler);

    //required for simulation of Xilinx IP (this handles driving BSCANE2)
    let glbl <- vMkGLBL;

    Wire#(Bit#(1)) wtck     <- mkWire;
    Wire#(Bit#(1)) wtrst    <- mkWire;
    Wire#(Bit#(1)) ext_tdi  <- mkWire;
    Wire#(Bit#(1)) ext_tms  <- mkWire;
    Wire#(Bit#(1)) ext_tdo  <- mkBypassWire;

    Reg#(Bit#(32)) rOut     <- mkRegU;

    //handles clocking
    let jtag_stim <- mkJTAGShim();

    let tck         = jtag_stim.tck_out;
    let trst        = jtag_stim.trst_out;
    let tck_inv     = jtag_stim.tdo_clk;
    let trst_inv    = jtag_stim.tdo_rst;

    //xilinx JTAG simulation primitives
    let jtag_sime2 <- mkJTAG_SIME2("xcku3p", clocked_by tck);
    
    let bscan_cfg = BSCANE2_Config { p_DISABLE_JTAG: False, p_JTAG_CHAIN: 3 };
    let bscane2 <- mkBSCANE2(bscan_cfg, tck_inv, clocked_by tck);

    //only activate TCK to the nested TAP, when the user data register is selected
    let bufgce <- mkBUFGCE(defaultValue, bscane2.sel, clocked_by bscane2.bscan_tck);
    let tap_rst <- mkAsyncResetFromCR(1, bufgce.clk_out);

    let nested_tap <- mkNestedTAP(tck_inv, trst_inv, clocked_by bufgce.clk_out, reset_by tap_rst);
    let tdo_bscane2 <- mkNullCrossingWire(bufgce.clk_out, nested_tap.tdo);

    //testbench jtag wires to jtag stimulator
    mkConnection(toGet(wtck),               toPut(jtag_stim.ext_tck));
    mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(ext_tdi),            toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(ext_tms),            toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(ext_tdo)));

    //correctly clocked signals to hard jtag tap
    mkConnection(toGet(jtag_stim.int_tms),  toPut(jtag_sime2.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(jtag_sime2.tdi));
    mkConnection(toGet(jtag_sime2.tdo),     toPut(jtag_stim.int_tdo));

    //connect nested tap to BSCANE2
    mkConnection(toGet(bscane2.tms), toPut(nested_tap.tms));
    mkConnection(toGet(bscane2.tdi), toPut(nested_tap.tdi));
    mkConnection(toGet(tdo_bscane2), toPut(bscane2.tdo));

    //this only fires when the user register behind the nested tap is updated
    rule r;
        $display("Update user reg: %0x", nested_tap.device_ifc.myreg_read());
    endrule

    Stmt s = seq
        $display("Hello");

        jtag_reset(wtck, ext_tms, ext_tdi);
        jtag_ir(wtck, ext_tms, ext_tdi, c_INSTR_BYPASS);
        jtag_idle(wtck, ext_tms, ext_tdi, 10);

        jtag_ir(wtck, ext_tms, ext_tdi, c_INSTR_IDCODE);
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
        $display("IDCODE: %0x", rOut);

        jtag_ir(wtck, ext_tms, ext_tdi, c_INSTR_USER3);
        jtag_dr(wtck, ext_tms, ext_tdi, 14'b11111111000000);
        // $display("USER: %0x", rOut);

    endseq;

    FSM f <- mkFSM(s);
    method go = f.start;
    method done = f.done;

endmodule

endpackage
