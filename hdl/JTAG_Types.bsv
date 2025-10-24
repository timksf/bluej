package JTAG_Types;

import Vector :: *;
import Connectable :: *;

(* always_ready *)
interface JTAG_Ctrl_Up_ifc#(numeric type n);
    method Bool update;
    method Bool capture;
    method Bool shift;

    interface Vector#(n, Bool) select;
endinterface

(* always_ready *)
interface JTAG_Ctrl_Dn_ifc;
    method Action update(Bool b);
    method Action capture(Bool b);
    method Action shift(Bool b);
    method Action sel(Bool b);
endinterface

module jtagConnect#(JTAG_Ctrl_Up_ifc#(n) tap, JTAG_Ctrl_Dn_ifc jtag_target, Integer i)(Empty);

    rule rconn_ctrl;
        jtag_target.update(tap.update);
        jtag_target.capture(tap.capture);
        jtag_target.shift(tap.shift);
    endrule

    rule rconn_sel;
        jtag_target.sel(tap.select[i]);
    endrule

endmodule

// module jtagBuild#(
//      //TODO: either use this or context based code
//     JTAG_TAP_Config_t#(n, w) tap_cfg,
//     Vector#(n, JTAG_Ctrl_Dn_ifc) jtag_endpoints
//     )(JTAG_TAP_Controller_ifc#(n));

//     for(Integer i = 0; i < n; i = i + 1) begin
//         mkConnection(reg0.tdi, tdi);
//         jtagConnect(ifc.tap_ctrl, jtag_endpoints[i], i);
//     end
// endmodule

function Vector#(sz, t) read_v_ro(Vector#(sz, ReadOnly#(t)) v) provisos(Bits#(t, s));
    return map(begin function t f(ReadOnly#(t) e); return e; endfunction f; end, v);
endfunction

function ReadOnly#(t) as_read_only(t v) provisos(Bits#(t, s));
    return 
        interface ReadOnly;
            method _read = v;
        endinterface;
endfunction

function WriteOnly#(t) reg_to_write_only(Reg#(t) r) provisos(Bits#(t, s));
    return 
        interface WriteOnly;
            method _write = r._write;
        endinterface;
endfunction

function function Action _f(t b) reg_write_f(Reg#(t) r) provisos(Bits#(t, s));
    return r._write;
endfunction

typedef Bit#(w) JTAGInstruction_t#(numeric type w);

typedef struct {
    Bit#(11) idcode_man;
    Bit#(16) idcode_part;
    Bit#(4) idcode_ver;
    Vector#(n, JTAGInstruction_t#(w)) instrs;
} JTAG_TAP_Config_t#(numeric type n, numeric type w) deriving(FShow, Eq, Bits);

endpackage