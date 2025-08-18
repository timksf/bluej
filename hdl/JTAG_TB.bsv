package JTAG_TB;

import StmtFSM :: *;

import JTAG_Types :: *;

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

function Stmt jtag_dr_ret(Reg#(Bit#(32)) i, Wire#(Bit#(1)) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, Wire#(Bit#(1)) tdo, Reg#(Bit#(w)) out)
    provisos(
        Add#(w1, 1, w)
    );
    Bit#(w1) z = 0;
    Bit#(TAdd#(w, 6)) tms_v = {4'b100, z, 3'b110};
    return par
        jtag_sequence(i, tck, tms, tdi, tms_v, 0);
        seq
            await(i == 5);
            while(i < fromInteger(valueof(w)) + 5) action
                out[i-5] <= tdo;
            endaction
        endseq
    endpar;
endfunction


endpackage