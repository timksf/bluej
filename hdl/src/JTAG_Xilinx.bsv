package JTAG_Xilinx;

import Vector :: *;
import Clocks :: *;
import BuildVector :: *;

import BSCANE2 :: *;
import JTAG_Types :: *;
import JTAG_TAP :: *;

//these are the same for 7-series and ultrascale (though some devices have larger IRs)
Bit#(6) c_INSTR_USER1   = 6'b000010;
Bit#(6) c_INSTR_USER2   = 6'b000011;
Bit#(6) c_INSTR_USER3   = 6'b100010;
Bit#(6) c_INSTR_USER4   = 6'b100011;

Bit#(6) c_INSTR_IDCODE  = 6'b001001;
Bit#(6) c_INSTR_NOOP    = 6'b010100;
Bit#(6) c_INSTR_BYPASS  = 6'b111111;


module mkBSCANE2_BlueJ#(BSCANE2_Config cfg, Clock tck_inv, Vector#(n, ReadOnly#(Bit#(1))) tdo_up)(JTAG_TAP_Controller_ifc#(1));

    BSCANE2_ifc _int <- mkBSCANE2(cfg, tck_inv);
    //bscan.tck and tck are the same clocks, just not for the bsc
    let tdo_bscane2 <- mkNullCrossingWire(_int.bscan_tck, tdo_up[0]);

    rule fwd_tdo;
        _int.tdo(tdo_bscane2);
    endrule

    //tms and tdi are supplied via simulation model, so no external inputs to this IP
    method tms(t) = noAction;
    method tdi(t) = noAction;
    //similarly, this IP does not provide a TDO output
    method tdo = 0;

    method int_tdi = _int.tdi;

    interface JTAG_Ctrl_Up_ifc tap_ctrl;
        method update = _int.update;
        method capture = _int.capture;
        method shift = _int.shift;
        
        interface select = vec(_int.sel);
    endinterface

endmodule

endpackage