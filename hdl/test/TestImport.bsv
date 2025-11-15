package TestImport;

import StmtFSM :: *;
import Clocks :: *;
import DefaultValue :: *;
import BuildVector :: *;

import TestHelper :: *;
import BlueJ :: *;
import GLBL :: *;
import JTAG_SIME2 :: *;
import JTAG_Xilinx :: *;
import BSCANE2 :: *;

(* synthesize *)
module [Module] mkTestImport(TestHandler);

    let clk <- exposeCurrentClock;

    let glbl <- vMkGLBL;
    let jtag_sime2 <- mkJTAG_SIME2("xcku3p");
    let b <- mkDWire(0);
    let bscan_cfg = BSCANE2_Config { p_DISABLE_JTAG: False, p_JTAG_CHAIN: 3 };
    let bscane2 <- mkBSCANE2_BlueJ(bscan_cfg, clk, vec(as_read_only(b)));

    rule dummy;
        jtag_sime2.tms(0);
        jtag_sime2.tdi(0);
    endrule

    Stmt s = seq
        $display("yo");
        delay(10);
    endseq;

    let fsm <- mkFSM(s);

    method go = fsm.start;
    method done = fsm.done;

endmodule

endpackage