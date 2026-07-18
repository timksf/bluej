package JTAG_Reg;

import BUtils :: *;
import DReg :: *;

import JTAG_Types :: *;

typedef union tagged {
    void NoReset;
    t WithReset;
} JTAG_Reg_Reset#(type t) deriving(Eq, Bits);

interface JTAG_Reg_ifc#(type t);

    //device-facing, will be used by whoever instantiates a jtag register
    method t            reg_o();
    method Bool         wr_o();
    method Bool         cap_o();

    method Bit#(1)     tdo();
    method Action      tdi(Bit#(1) t);
    interface JTAG_Ctrl_Dn_ifc ctrl;

endinterface

interface JTAG_Instruction_Reg_ifc#(type t);

    method t            reg_o();
    method Bool         wr_o();

    method Action       test_logic_reset(Bool active);

    method Bit#(1)     tdo();
    method Action      tdi(Bit#(1) t);
    interface JTAG_Ctrl_Dn_ifc ctrl;

endinterface

module mkJTAGReg#(t reg_i)(JTAG_Reg_ifc#(t))
    provisos(Bits#(t, w));

    let i <- mkJTAGRegR(reg_i, tagged NoReset);
    return i;

endmodule

module mkJTAGRegR#(t reg_i, JTAG_Reg_Reset#(t) r)(JTAG_Reg_ifc#(t))
    provisos(Bits#(t, w));

    Reg#(Bit#(w))    rSR <- mkRegU;
    Reg#(Bit#(w))    rHR;
    if(r matches tagged WithReset .rst_v)
        rHR <- mkReg(pack(rst_v));
    else
        rHR <- mkRegU;

    Wire#(Bit#(1))   bwTDI     <- mkBypassWire;
    Wire#(Bool)      bwCapture <- mkBypassWire;
    Wire#(Bool)      bwShift   <- mkBypassWire;
    Wire#(Bool)      bwUpdate  <- mkBypassWire;
    Wire#(Bool)      bwSelect  <- mkBypassWire;

    Reg#(Bool)       rWR       <- mkDReg(False);
    Reg#(Bool)       rCAP      <- mkDReg(False);

    //the wires activating each rule are derived from different fsm states so cannot be active at the same time

    (* mutually_exclusive ="rshift, rcapture" *)
    rule rshift if(bwShift && bwSelect);
        Bit#(w) tdi_msb = bwTDI == 1'b1 ? (1 << (valueof(w) - 1)) : 0;
        rSR <= (rSR >> 1) | tdi_msb;
    endrule

    (* mutually_exclusive ="rcapture, rupdate" *)
    rule rcapture if(bwCapture && bwSelect);
        rSR <= pack(reg_i);
        rCAP <= True;
    endrule

    (* mutually_exclusive ="rshift, rupdate" *)
    rule rupdate if(bwUpdate && bwSelect);
        rHR <= rSR;
        rWR <= True;
    endrule

    method reg_o = unpack(rHR);
    method wr_o  = rWR; //indicate update after shift
    method cap_o = rCAP; //indicate capture before shift
    method tdi   = bwTDI._write;
    method tdo   = rSR[0];

    interface JTAG_Ctrl_Dn_ifc ctrl;
        method capture = bwCapture._write;
        method shift   = bwShift._write;
        method update  = bwUpdate._write;
        method sel     = bwSelect._write;
    endinterface
endmodule

module mkJTAGInstructionReg#(t capture_value, t reset_value)(JTAG_Instruction_Reg_ifc#(t))
    provisos(Bits#(t, w));

    Reg#(Bit#(w)) rSR <- mkRegU;
    Reg#(Bit#(w)) rHR <- mkReg(pack(reset_value));

    Wire#(Bit#(1)) bwTDI     <- mkBypassWire;
    Wire#(Bool)    bwCapture <- mkBypassWire;
    Wire#(Bool)    bwShift   <- mkBypassWire;
    Wire#(Bool)    bwUpdate  <- mkBypassWire;
    Wire#(Bool)    bwSelect  <- mkBypassWire;
    Wire#(Bool)    bwTLR     <- mkBypassWire;

    Reg#(Bool)     rWR       <- mkDReg(False);

    (* mutually_exclusive = "r_shift, r_capture" *)
    rule r_shift if(bwShift && bwSelect);
        Bit#(w) tdi_msb = bwTDI == 1'b1 ? (1 << (valueOf(w) - 1)) : 0;
        rSR <= (rSR >> 1) | tdi_msb;
    endrule

    (* mutually_exclusive = "r_capture, r_update" *)
    rule r_capture if(bwCapture && bwSelect);
        rSR <= pack(capture_value);
    endrule

    (* mutually_exclusive = "r_shift, r_update" *)
    rule r_update if(bwUpdate && bwSelect && !bwTLR);
        rHR <= rSR;
        rWR <= True;
    endrule

    rule r_test_logic_reset if(bwTLR);
        rHR <= pack(reset_value);
    endrule

    method reg_o = unpack(rHR);
    method wr_o  = rWR;

    method test_logic_reset = bwTLR._write;

    method tdi = bwTDI._write;
    method tdo = rSR[0];

    interface JTAG_Ctrl_Dn_ifc ctrl;
        method capture = bwCapture._write;
        method shift   = bwShift._write;
        method update  = bwUpdate._write;
        method sel     = bwSelect._write;
    endinterface

endmodule

module mkJTAGBypass(JTAG_Reg_ifc#(Bit#(1)));

    JTAG_Reg_ifc#(Bit#(1)) i <- mkJTAGRegR(0, tagged WithReset 0);
    return i;

endmodule

function ReadOnly#(t) jreg_to_read_only(JTAG_Reg_ifc#(t) jreg);
    return interface ReadOnly;
        method _read if(jreg.wr_o()) = jreg.reg_o;
    endinterface;
endfunction

endpackage
