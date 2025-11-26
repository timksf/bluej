package TestFPGATop;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import BRAM :: *;
import StmtFSM :: *;
import ClientServer :: *;
import BuildVector :: *;
import Connectable :: *;

import TestHelper :: *;

import BlueJ :: *;
import GLBL :: *;
import FPGATop :: *;
import JTAG_SIME2 :: *;

(* synthesize *)
module [Module] mkTestFPGATop(TestHandler);

    Clock sys_clk <- mkAbsoluteClock(100, 50);
    Reset sys_rst <- mkAsyncResetFromCR(2, sys_clk);

    //required for simulation of Xilinx IP (JTAG magic)
    let glbl <- vMkGLBL;

    Wire#(Bit#(1)) wtck <- mkWire(clocked_by sys_clk, reset_by sys_rst);
    Wire#(Bit#(1)) wtrst <- mkWire(clocked_by sys_clk, reset_by sys_rst);
    Wire#(Bit#(1)) ext_tdi <- mkWire(clocked_by sys_clk, reset_by sys_rst);
    Wire#(Bit#(1)) ext_tms <- mkWire(clocked_by sys_clk, reset_by sys_rst);
    Wire#(Bit#(1)) ext_tdo <- mkBypassWire(clocked_by sys_clk, reset_by sys_rst);

    Reg#(Bit#(32)) rOut     <- mkRegU(clocked_by sys_clk);
    Reg#(Bit#(32)) rCount   <- mkRegU(clocked_by sys_clk);

    let jtag_stim <- mkJTAGShim(clocked_by sys_clk, reset_by sys_rst);

    let tck         = jtag_stim.tck_out;
    let trst        = jtag_stim.trst_out;
    let tck_inv     = jtag_stim.tdo_clk;
    let trst_inv    = jtag_stim.tdo_rst;

    //this will magically drive the BSCAN in the DUT
    let jtag_sime2 <- mkJTAG_SIME2("xcku3p", clocked_by tck);

    let dut <- mkFPGATestSimpleTop(clocked_by sys_clk, reset_by sys_rst);

    //synchronization of FSM start and stop
    SyncPulseIfc        pStart          <- mkSyncPulseFromCC(sys_clk);
    SyncPulseIfc        pStopped        <- mkSyncPulseToCC(sys_clk, sys_rst);
    SyncBitIfc#(Bool)   syncStarted     <- mkSyncBitToCC(sys_clk, sys_rst);

    //JTAG tesbench driver signals
    mkConnection(toGet(wtck),               toPut(jtag_stim.ext_tck));
    mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(ext_tdi),            toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(ext_tms),            toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(ext_tdo)));

    //correctly clocked signals to DUT
    mkConnection(toGet(jtag_stim.int_tms),  toPut(jtag_sime2.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(jtag_sime2.tdi));
    mkConnection(toGet(jtag_sime2.tdo),     toPut(jtag_stim.int_tdo));

    Stmt s = seq
        syncStarted.send(True);
        $display("Hello");
        jtag_reset(rCount, wtck, ext_tms, ext_tdi);

        //smoke-test: read IDCODE from BSCANE2
        jtag_ir(rCount, wtck, ext_tms, ext_tdi, c_INSTR_IDCODE);
        jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
        $display("IDCODE: %0x", rOut);

        //scan LED control into jtag register
        jtag_ir(rCount, wtck, ext_tms, ext_tdi, c_INSTR_USER3);
        jtag_dr(rCount, wtck, ext_tms, ext_tdi, ext_tdo, (Bit#(36)'('hF << 4 | 1)));

        //some idle cycles to let the jtag reg sync...
        jtag_idle(rCount, wtck, ext_tms, ext_tdi, 10);

        jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
        $display("USER3: %0x", rOut);

        delay(100);
    endseq;

    FSM f <- mkFSM(s, clocked_by sys_clk, reset_by sys_rst);

    rule start if(pStart.pulse());
        f.start();
    endrule

    rule stopped if(f.done());
        pStopped.send();
    endrule

    method go = pStart.send;
    method done = pStopped.pulse && syncStarted.read;

endmodule

endpackage