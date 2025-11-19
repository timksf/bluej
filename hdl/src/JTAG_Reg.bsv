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
    method t reg_o();
    method Bool wr_o();
    
    method Bit#(1) tdo();
    method Action tdi(Bit#(1) t);
    interface JTAG_Ctrl_Dn_ifc ctrl;

endinterface

module mkJTAGReg#(t reg_i)(JTAG_Reg_ifc#(t)) provisos(Bits#(t, w), Add#(1, a__, w));
    let i <- mkJTAGRegR(reg_i, tagged NoReset);
    return i;
endmodule

module mkJTAGRegR#(t reg_i, JTAG_Reg_Reset#(t) r)(JTAG_Reg_ifc#(t)) provisos(Bits#(t, w), Add#(1, a__, w));

    Reg#(Bit#(w)) rSR <- mkRegU;
    Reg#(Bit#(w)) rHR;
    if(r matches tagged WithReset .rst_v)
        rHR   <- mkReg(pack(rst_v));
    else
        rHR   <- mkRegU;

    Wire#(Bit#(1))  bwTDI       <- mkBypassWire;
    Wire#(Bool)     bwCapture   <- mkBypassWire;
    Wire#(Bool)     bwShift     <- mkBypassWire;
    Wire#(Bool)     bwUpdate    <- mkBypassWire;
    Wire#(Bool)     bwSelect    <- mkBypassWire;

    Reg#(Bool)      rWR         <- mkDReg(False);

    //the wires activating each rule are derived from different fsm states so cannot be active at the same time

    (* mutually_exclusive ="rshift, rcapture" *)
    rule rshift if(bwShift && bwSelect);
        rSR <= {bwTDI, rSR[valueof(w)-1:1]}; //requires proviso
    endrule

    (* mutually_exclusive ="rcapture, rupdate" *)
    rule rcapture if(bwCapture && bwSelect);
        rSR <= pack(reg_i);
    endrule

    (* mutually_exclusive ="rshift, rupdate" *)
    rule rupdate if(bwUpdate && bwSelect);
        rHR <= rSR;
        rWR <= True;
    endrule

    method reg_o    = unpack(rHR);
    method wr_o     = rWR; //indicate update after shift
    method tdi      = bwTDI._write;
    method tdo      = rSR[0];
    
    interface JTAG_Ctrl_Dn_ifc ctrl;
        method capture  = bwCapture._write;
        method shift    = bwShift._write;
        method update   = bwUpdate._write;
        method sel      = bwSelect._write;
    endinterface
endmodule

module mkJTAGBypass(JTAG_Reg_ifc#(Bit#(1)));

    Reg#(Bit#(1)) rSR   <- mkRegU;
    Reg#(Bit#(1)) rHR   <- mkRegU;

    Wire#(Bit#(1))  bwTDI       <- mkBypassWire;
    Wire#(Bool)     bwCapture   <- mkBypassWire;
    Wire#(Bool)     bwShift     <- mkBypassWire;
    Wire#(Bool)     bwUpdate    <- mkBypassWire;
    Wire#(Bool)     bwSelect    <- mkBypassWire;

    (* mutually_exclusive ="rshift, rcapture" *)
    rule rshift if(bwShift && bwSelect);
        rSR <= bwTDI;
    endrule

    (* mutually_exclusive ="rcapture, rupdate" *)
    rule rcapture if(bwCapture && bwSelect);
        rSR <= 0;
    endrule
    
    (* mutually_exclusive ="rshift, rupdate" *)
    rule rupdate if(bwUpdate && bwSelect);
        rHR <= rSR;
    endrule

    method reg_o    = rHR;
    method wr_o     = bwSelect && bwUpdate; //indicate update after shift
    method tdi      = bwTDI._write;
    method tdo      = rSR;

    interface JTAG_Ctrl_Dn_ifc ctrl;
        method capture  = bwCapture._write;
        method shift    = bwShift._write;
        method update   = bwUpdate._write;
        method sel      = bwSelect._write;
    endinterface
endmodule

function ReadOnly#(t) jreg_to_read_only(JTAG_Reg_ifc#(t) jreg);
    return interface ReadOnly;
        method _read if(jreg.wr_o()) = jreg.reg_o;
    endinterface;
endfunction

endpackage