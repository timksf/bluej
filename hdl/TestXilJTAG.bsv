package TestXilJTAG;

import StmtFSM :: *;
import Connectable :: *;
import GetPut :: *;

import BlueJ :: *;
import ClockUtil :: *;
import GLBL :: *;
import JTAG_SIME2 :: *;

module mkTestXilJTAG();

    //required for simulation of Xilinx IP (this handles driving BSCANE2)
    let glbl <- vMkGLBL;

    Wire#(Bit#(1)) wtck     <- mkWire;
    Wire#(Bit#(1)) wtrst    <- mkWire;
    Wire#(Bit#(1)) ext_tdi  <- mkWire;
    Wire#(Bit#(1)) ext_tms  <- mkWire;
    Wire#(Bit#(1)) ext_tdo  <- mkBypassWire;

    Reg#(Bit#(32)) rOut <- mkRegU;
    Reg#(Bit#(32)) rCount <- mkRegU;

    //handles clocking
    let jtag_stim <- mkJTAGShim();

    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;
    let tck_inv = jtag_stim.tdo_clk;
    let trst_inv = jtag_stim.tdo_rst;

    //xilinx JTAG simulation primitive
    let dut <- mkJTAG_SIME2("xcku3p", clocked_by tck);

    mkConnection(toGet(wtck),               toPut(jtag_stim.ext_tck));
    mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(ext_tdi),            toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(ext_tms),            toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(ext_tdo)));

    //correctly clocked signals to DUT
    mkConnection(toGet(jtag_stim.int_tms),  toPut(dut.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(dut.tdi));
    mkConnection(toGet(dut.tdo),            toPut(jtag_stim.int_tdo));

    Stmt s = seq
        $display("Hello");
        jtag_reset(rCount, wtck, ext_tms, ext_tdi);
        jtag_ir(rCount, wtck, ext_tms, ext_tdi, 6'b111111);
        jtag_idle(rCount, wtck, ext_tms, ext_tdi, 10);
        jtag_ir(rCount, wtck, ext_tms, ext_tdi, 6'b001001);
        jtag_idle(rCount, wtck, ext_tms, ext_tdi, 1);
        jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
        delay(20);
    endseq;

    mkAutoFSM(s);

endmodule

endpackage