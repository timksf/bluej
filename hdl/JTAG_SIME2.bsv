package JTAG_SIME2;

import Clocks :: *;
//https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/JTAG-Simulation

(* always_ready *)
interface JTAG_SIME2_ifc;
    // (* prefix="" *) 
    // method Action tck((*port="TCK"*) Bit#(1) t);
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

instance DefaultValue#(JTAG_SIME2_Config);
    function defaultValue = JTAG_SIME2_Config { p_PART_NAME: "xcku3p" };
endinstance

import "BVI" JTAG_SIME2 = 
module vMkJTAG_SIME2#(JTAG_SIME2_Config cfg)(JTAG_SIME2_ifc);

    parameter PART_NAME = cfg.p_PART_NAME;
    
    default_clock tck (TCK, (*unused*) _gate);
    default_reset no_reset;

    //everything unclocked to avoid issues...

    //input
    method tms (TMS) enable((*inhigh*) EN0) clocked_by(tck) reset_by(no_reset);
    method tdi (TDI) enable((*inhigh*) EN1) clocked_by(tck) reset_by(no_reset);

    //output
    method (* reg *) TDO tdo() clocked_by(no_clock) reset_by(no_reset);

    schedule (tms, tdi, tdo) CF (tms, tdi, tdo);

endmodule

module mkJTAG_SIME2#(String part_name)(JTAG_SIME2_ifc);
    (* hide *)
    let _int <- vMkJTAG_SIME2(JTAG_SIME2_Config { p_PART_NAME: part_name });
    return _int;
endmodule

endpackage