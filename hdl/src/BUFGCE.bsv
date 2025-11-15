package BUFGCE;

import Clocks :: *;
import DefaultValue :: *;
// interface BUFGCE_ifc;
//     Clock clk_out;
//     method Action set_gate(Bool g);
// endinterface

(* always_enabled *)
interface BUFGCE_ifc;
    interface Clock clk_out;
    // method Action set_gate(Bool g);
endinterface

typedef struct {
    String  p_CE_TYPE;
    Bool    p_IS_CE_INVERTED;
    Bool    p_IS_I_INVERTED;
    String  p_SIM_DEVICE;
} BUFGCE_Config;

import "BVI" BUFGCE = 
module vMkBUFGCE#(BUFGCE_Config cfg, Bool gate)(BUFGCE_ifc);

    parameter CE_TYPE           = cfg.p_CE_TYPE;
    parameter IS_CE_INVERTED    = cfg.p_IS_CE_INVERTED;
    parameter IS_I_INVERTED     = cfg.p_IS_I_INVERTED;
    parameter SIM_DEVICE        = cfg.p_SIM_DEVICE;

    default_clock clk_in(I);
    default_reset no_reset;

    output_clock clk_out (O);

    port CE clocked_by(clk_in) reset_by(no_reset) = gate;

    path(I, O);
    path(CE, O);

    ancestor(clk_out, clk_in);
endmodule

module mkBUFGCE#(BUFGCE_Config cfg, Bool gate)(BUFGCE_ifc);
    // Wire#(Bool) dwCE <- mkDWire(True);
    (* hide *)
    let _int <- vMkBUFGCE(cfg, gate);
    return _int;
endmodule

instance DefaultValue#(BUFGCE_Config);
    defaultValue = BUFGCE_Config {
        p_CE_TYPE:          "SYNC",
        p_IS_CE_INVERTED:   False,
        p_IS_I_INVERTED:    False,
        p_SIM_DEVICE:       "ULTRASCALE"
    };
endinstance


endpackage