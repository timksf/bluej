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

(* always_ready *)
interface IJTAG_ifc;
    method Bit#(1) tdo();
    method Action tdi(Bit#(1) t);
    interface JTAG_Ctrl_Dn_ifc ctrl;
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

function Vector#(sz, t) read_v_ro(Vector#(sz, ReadOnly#(t)) v) provisos(Bits#(t, s));
    return map(begin function t f(ReadOnly#(t) e); return e; endfunction f; end, v);
endfunction

function ReadOnly#(t) as_read_only(t v) provisos(Bits#(t, s));
    return 
        interface ReadOnly;
            method _read = v;
        endinterface;
endfunction

function WriteOnly#(t) as_write_only(function Action f(t v)) provisos(Bits#(t, s));
    return 
        interface WriteOnly;
            method _write = f;
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
    Bit#(4)  idcode_ver;
    Bit#(11) idcode_man;
    Bit#(16) idcode_part;
} JTAG_TAP_Meta_Config_t deriving(FShow, Eq, Bits);

typedef struct {
    Bit#(11) idcode_man;
    Bit#(16) idcode_part;
    Bit#(4) idcode_ver;
    /* When reg_tdo is enabled, a register is inserted after the TDO mux. This register is clocked by an
    externally supplied clock signal, which ideally should be the inverse of TCK, to adhere to the JTAG spec.
    However, because the TDO output has to be crossed into the testbench clock domain in a bluesim test setup, 
    an additional register stage, inserting unwanted delay into the TDO line would be necessary.
    Thus, the TDO output register can be left out, leaving the output combinational (but still in the TDO clock domain
    for bluesim). The null crossing of the TDO signal into the testbench clock domain can then simply be handled by a NullCrossingReg
    inside the JTAG stimulator module.
    Another workaround that can be applied to get the correct results in the bluesim testbench is adding another shift-out
    cycle at the end of a JTAG register read.
    */
    Bool reg_tdo;
    // Primitive TAP configuration includes the fully derived instruction map.
    // Higher-level JTAGSystem code should collect endpoint instructions and
    // build this vector rather than asking users to specify it separately.
    Vector#(n, JTAGInstruction_t#(w)) instrs;
    JTAGInstruction_t#(w) instr_idcode;
    Bool reset_idcode_not_bypass;
    Bool debug;
} JTAG_TAP_Config_t#(numeric type n, numeric type w) deriving(FShow, Eq, Bits);

typedef struct {} JTAG_TDO_Delay#(numeric type n);

endpackage
