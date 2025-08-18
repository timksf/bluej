package JTAG_Reg;

import BUtils :: *;

import JTAG_Types :: *;

interface JTAG_Reg_ifc#(type t);

    method t reg_o();
    method Bool wr_o();
    method Action tdi(Bit#(1) t);

    interface JTAG_Ctrl_Dn_ifc ctrl;

endinterface

module mkJTAGReg#(t reg_i)(JTAG_Reg_ifc#(t)) provisos(Bits#(t, w), Add#(1, a__, w));

    Reg#(Bit#(w)) rSR   <- mkRegU;
    Reg#(Bit#(w)) rHR   <- mkRegU;

    Wire#(Bit#(1))  dwTDO       <- mkDWire(0);
    Wire#(Bit#(1))  bwTDI       <- mkBypassWire;
    Wire#(Bool)     bwCapture   <- mkBypassWire;
    Wire#(Bool)     bwShift     <- mkBypassWire;
    Wire#(Bool)     bwUpdate    <- mkBypassWire;
    Wire#(Bool)     bwSelect    <- mkBypassWire;

    rule rshift if(bwShift && bwSelect);
        rSR <= {bwTDI, rSR[valueof(w)-1:1]}; //requires proviso
        dwTDO <= rSR[0];
    endrule

    rule rcapture if(bwCapture && bwSelect);
        rSR <= pack(reg_i);
    endrule

    rule rupdate if(bwUpdate && bwSelect);
        rHR <= rSR;
    endrule

    method reg_o    = unpack(rHR);
    method wr_o     = bwSelect && bwUpdate; //indicate update after shift
    method tdi      = bwTDI._write;
    
    interface JTAG_Ctrl_Dn_ifc ctrl;
        method tdo      = dwTDO;
        method capture  = bwCapture._write;
        method shift    = bwShift._write;
        method update   = bwUpdate._write;
        method sel      = bwSelect._write;
    endinterface
endmodule

module mkJTAGBypass(JTAG_Reg_ifc#(Bit#(1)));

    Reg#(Bit#(1)) rSR   <- mkRegU;
    Reg#(Bit#(1)) rHR   <- mkRegU;

    Wire#(Bit#(1))  dwTDO       <- mkDWire(0);
    Wire#(Bit#(1))  bwTDI       <- mkBypassWire;
    Wire#(Bool)     bwCapture   <- mkBypassWire;
    Wire#(Bool)     bwShift     <- mkBypassWire;
    Wire#(Bool)     bwUpdate    <- mkBypassWire;
    Wire#(Bool)     bwSelect    <- mkBypassWire;

    rule rshift if(bwShift && bwSelect);
        rSR <= bwTDI;
        dwTDO <= rSR;
    endrule

    rule rcapture if(bwCapture && bwSelect);
        rSR <= 0;
    endrule

    rule rupdate if(bwUpdate && bwSelect);
        rHR <= rSR;
    endrule

    method reg_o    = rHR;
    method wr_o     = bwSelect && bwUpdate; //indicate update after shift
    method tdi      = bwTDI._write;
    
    interface JTAG_Ctrl_Dn_ifc ctrl;
        method tdo      = dwTDO;
        method capture  = bwCapture._write;
        method shift    = bwShift._write;
        method update   = bwUpdate._write;
        method sel      = bwSelect._write;
    endinterface
endmodule

endpackage