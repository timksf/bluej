package JTAG_SIME2;

//https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/JTAG-Simulation

(* always_enabled *)
interface JTAG_SIME2_ifc;
    (* prefix="" *) 
    method Action tck((*port="TCK"*) Bit#(1) t);
    (* prefix="" *) 
    method Action tms((*port="TMS"*) Bit#(1) t);
    (* prefix="" *) 
    method Action tdi((*port="TDI"*) Bit#(1) t);
    (* prefix="", result="TDO" *)
    method Bit#(1) tdo();
endinterface

typedef struct {
    String p_PART_NAME; 
} JTAG_SIME2_Config;

import "BVI" JTAG_SIME2 = 
module vMkJTAG_SIME2#(JTAG_SIME2_Config cfg)(JTAG_SIME2_ifc);

    parameter PART_NAME = cfg.p_PART_NAME;

    

endpackage

endpackage