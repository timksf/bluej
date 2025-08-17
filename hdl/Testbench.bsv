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

function Stmt jtag_stim(Wire#(Bit#(1)) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, Bit#(1) tms_v, Bit#(1) tdi_v);
    return seq
        action
            tck <= 0;
            tms <= tms_v;
            tdi <= tdi_v;
        endaction
        action
            tck <= 1;
            tms <= tms_v;
            tdi <= tdi_v;
        endaction
    endseq;
endfunction

function Stmt jtag_sequence(Reg#(Bit#(32)) i, Wire#(Bit#(1)) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, Bit#(w) tms_vec, Bit#(w) tdi_vec);
    return seq
        i <= 0;
        while(i < fromInteger(valueof(w))) par
            jtag_stim(tck, tms, tdi, tms_vec[fromInteger(valueof(w))-1-i], tdi_vec[fromInteger(valueof(w))-1-i]);
            i <= i + 1;
        endpar
    endseq;
endfunction

function Stmt jtag_idle(Reg#(Bit#(32)) i, Wire#(Bit#(1)) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, Integer cycles);
    return seq
        i <= 0;
        while(i < fromInteger(cycles)) par
            jtag_stim(tck, tms, tdi, 0, 0);
            i <= i + 1;
        endpar
    endseq;
endfunction

function Stmt jtag_reset(Reg#(Bit#(32)) i, Wire#(Bit#(1)) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi);
    // JTAG FSM reset: Hold TMS high for 5 TCK cycles, then go to Run-Test/Idle with TMS=0
    return jtag_sequence(i, tck, tms, tdi, 6'b111110, 6'b0);
endfunction

function Stmt jtag_ir(Reg#(Bit#(32)) i, Wire#(Bit#(1)) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, JTAGInstruction_t#(w) instr)
    provisos(
        Add#(w1, 1, w)
    );
    //go to Shift-IR state with 1100
    //then repeat shift w times
    //then go to Run-Test/Idle with 110
    Bit#(w1) z = 0;
    Bit#(TAdd#(w, 6)) tms_v = {4'b1100, z, 3'b110};
    Bit#(TAdd#(w, 6)) tdi_v = {4'b1111, reverseBits(instr), 2'b11};
    return jtag_sequence(i, tck, tms, tdi, tms_v, tdi_v);
endfunction

module mkTestbench();

    JTAG_TAP_Config_t#(1, IR_WIDTH) jtag_config = vec(
        'h02
    );

    let jtag_stim <- mkJTAGShim;

    Wire#(Bit#(1)) wtck <- mkWire;
    Wire#(Bit#(1)) wtrst <- mkWire;
    Wire#(Bit#(1)) ext_tdi <- mkWire;
    Wire#(Bit#(1)) ext_tms <- mkWire;
    Wire#(Bit#(1)) ext_tdo <- mkBypassWire;

    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;

    JTAG_Reg_ifc#(32) reg0 <- mkJTAGReg('hDEADBEEF, clocked_by tck, reset_by trst);
    JTAG_TAP_Controller_ifc#(1) dut <- mkJTAG_TAP_Controller(jtag_config, 0, True, clocked_by tck, reset_by trst);

    Reg#(Bit#(32)) rCount <- mkRegU;

    //connect custom data register
    mkConnection(reg0.tdi, jtag_stim.int_tdi);
    jtagConnect(dut.tap_ctrl, reg0.ctrl, 0);

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
        endseq
    };

    mkAutoFSM(s);


endmodule

endpackage