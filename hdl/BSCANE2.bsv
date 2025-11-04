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
    
    method Action tdo(Bit#(1) b);
    
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
module vMkBSCANE2#(BSCANE2_Config cfg, Clock tck_inv)(BSCANE2_ifc);

    parameter DISABLE_JTAG    = cfg.p_DISABLE_JTAG;
    parameter JTAG_CHAIN      = cfg.p_JTAG_CHAIN;

    default_clock no_clock;
    default_reset no_reset;

    //this primitive takes TCK from the glbl module and outputs it via its interface
    output_clock tck (TCK);
    output_clock drck (DRCK);

    //input
    //the user TDO signals in JTAG_SIME2 are assigned to this input
    method tdo (TDO) enable((*inhigh*) EN0) clocked_by(tck);

    //output
    //these signals come from JTAG_SIME2 via glbl and are clocked by the inverted tck
    method (* reg *)   CAPTURE  capture()   clocked_by(tck_inv);
    method (* reg *)   RESET    reset()     clocked_by(tck_inv);
    method (* reg *)   RUNTEST  runtest()   clocked_by(tck_inv);
    method (* reg *)   SHIFT    shift()     clocked_by(tck_inv);
    method (* reg *)   UPDATE   update()    clocked_by(tck_inv);

    method (* reg *) SEL sel() clocked_by(tck);

    method TMS tms() clocked_by(tck);
    method TDI tdi() clocked_by(tdi);

    schedule(
        capture,
        reset,
        runtest,
        shift,
        update,
        sel,
        tdi,
        tms,
        tdo
    ) CF (
        capture,
        reset,
        runtest,
        shift,
        update,
        sel,
        tdi,
        tms,
        tdo
    );

endmodule
    
module mkBSCANE2#(BSCANE2_Config cfg, Clock tck_inv)(BSCANE2_ifc);
    (* hide *)
    let _int <- vMkBSCANE2(cfg, tck_inv);
    return _int;
endmodule
        
endpackage