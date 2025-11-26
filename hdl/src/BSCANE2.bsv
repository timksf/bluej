package BSCANE2;

import DefaultValue :: *;

(* always_enabled *)
interface BSCANE2_ifc;
    method Bool capture;
    method Bool reset;      //Test-Logic-Reset state
    method Bool runtest;    //Run-Test/Idle state
    method Bool sel;
    method Bool shift;      //Shift-DR state

    method Bit#(1) tms;
    method Bit#(1) tdi;
    method Bool update;
    
    method Action tdo(Bit#(1) b);
    
    interface Clock bscan_tck;
    interface Clock bscan_drck; //TODO clock correct? ~ gated TCK
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

    parameter DISABLE_JTAG    = cfg.p_DISABLE_JTAG ? "True" : "False";
    parameter JTAG_CHAIN      = cfg.p_JTAG_CHAIN;

    default_clock no_clock;
    default_reset no_reset;

    //this primitive takes TCK from the glbl module and outputs it via its interface
    output_clock bscan_tck (TCK);
    output_clock bscan_drck (DRCK);

    //input
    //the user TDO signals in JTAG_SIME2 are assigned to this input
    method tdo (TDO) enable((*inhigh*) EN0) clocked_by(bscan_tck);

    //output
    //these signals come from JTAG_SIME2 via glbl and are clocked by the inverted tck
    method (* reg *)   CAPTURE  capture()   clocked_by(no_clock);
    method (* reg *)   RESET    reset()     clocked_by(no_clock);
    method (* reg *)   RUNTEST  runtest()   clocked_by(no_clock);
    method (* reg *)   SHIFT    shift()     clocked_by(no_clock);
    method (* reg *)   UPDATE   update()    clocked_by(no_clock);

    method (* reg *) SEL sel() clocked_by(no_clock);

    method TMS tms() clocked_by(no_clock);
    method TDI tdi() clocked_by(no_clock);

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
    
module mkBSCANE2#(BSCANE2_Config cfg)(BSCANE2_ifc);
    (* hide *)
    let _int <- vMkBSCANE2(cfg);
    return _int;
endmodule
        
endpackage