package BSCANE2;

import DefaultValue :: *;

(* always_enabled *)
interface BSCANE2_ifc;
    method Bit#(1) capture;
    method Bool reset;      //Test-Logic-Reset state
    method Bool runtest;    //Run-Test/Idle state
    method Bool sel;
    method Bool shift;      //Shift-DR state

    method Bit#(1) tms;
    method Bit#(1) tdi;
    method Bool update;
    
    method Action tdo(Bit#(1));
    
    interface Clock tck;
    interface Clock drck; //TODO clock correct? ~ gated TCK
endinterface

typedef struct {
    Bool    p_DISABLE_JTAG;
    Integer p_JTAG_CHAIN; 
} BSCANE2_Config;

instance DefaultValue#(BSCANE2_Config);
    function defaultValue = BSCANE2_Config { p_DISABLE_JTAG: False, p_JTAG_CHAIN: 1 };
endinstance

import "BVI" BSCANE2 = 
module vMkBSCANE2#(BSCANE2_Config cfg)(BSCANE2_ifc);

    parameter DISABLE_JTAG    = cfg.p_DISABLE_JTAG;
    parameter JTAG_CHAIN      = cfg.p_JTAG_CHAIN;

endpackage