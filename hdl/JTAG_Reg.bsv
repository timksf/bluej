package JTAG_Reg;

interface JTAG_Reg_ifc#(numeric type w);

    method Bit#(1) tdo();
    method Bit#(w) reg_o();

    method Action tdi(Bit#(1) t);
    method Action capture(Bool v);
    method Action shift(Bool v);
    method Action update(Bool v);
    method Action sel(Bool v);

endinterface

module mkJTAGReg#(Bit#(w) reg_i)(JTAG_Reg_ifc#(w));

    Reg#(Bit#(w)) rSR   <- mkRegU;
    Reg#(Bit#(w)) rHR   <- mkRegU;

    Wire#(Bit#(1))  dwTDO       <- mkDWire(0);
    Wire#(Bit#(1))  bwTDI       <- mkBypassWire;
    Wire#(Bool)     bwCapture   <- mkBypassWire;
    Wire#(Bool)     bwShift     <- mkBypassWire;
    Wire#(Bool)     bwUpdate    <- mkBypassWire;
    Wire#(Bool)     bwSelect    <- mkBypassWire;

    rule rshift if(bwShift && bwSelect);
        rSR <= {bwTDI, rSR[valueof(w)-1:1]};
        dwTDO <= rSR[0];
    endrule

    rule rcapture if(bwCapture && bwSelect);
        rSR <= reg_i;
    endrule

    rule rupdate if(bwUpdate && bwSelect);
        rHR <= rSR;
    endrule

    method tdo      = dwTDO;
    method reg_o    = rHR;

    method tdi      = bwTDI._write;
    method capture  = bwCapture._write;
    method shift    = bwShift._write;
    method update   = bwUpdate._write;
    method sel      = bwSelect._write;

endpackage