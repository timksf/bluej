package JTAG_System;

import Vector :: *;
import Connectable :: *;
import UnitAppendList :: *;
import ModuleContext :: *;
import ModuleCollect :: *;
import List :: *;
import Assert :: *;
import GetPut :: *;

import JTAG_Types :: *;
import JTAG_Reg :: *;
import JTAG_TAP :: *;

/* JTAG system builder
*/

interface JTAGSystem_ifc#(type internal_ifc);
    //external
    (* prefix="" *) 
    method Action tms((*port="TMS"*) Bit#(1) t);
    (* prefix="" *) 
    method Action tdi((*port="TDI"*) Bit#(1) t);
    (* prefix="", result="TDO" *)
    method Bit#(1) tdo();
    //internal
    interface internal_ifc device_ifc;
endinterface

//TODO: instead of this struct, introduce new "IJTAG" interface for internal jtag components
typedef struct {
    ReadOnly#(Bit#(1)) tdo;
    WriteOnly#(Bit#(1)) tdi;
    JTAG_Ctrl_Dn_ifc ctrl;
} IJTAG_;

typedef union tagged {
    IJTAG_ IJTAG;
    JTAG_TAP_Config_t#(n, w) TAPConfig;
} JTAGSystem_item#(numeric type n, numeric type w);

//n: number of (custom) instructions, w: instruction width
typedef ModuleCollect#(JTAGSystem_item#(n, w), ifc) JTAGSystem#(numeric type n, numeric type w, type ifc);

function List#(IJTAG_) getIJTAG(JTAGSystem_item#(n, w) item);
    return item matches tagged IJTAG .ijtag ? List::cons(ijtag, Nil) : Nil;
endfunction

function List#(JTAG_TAP_Config_t#(n, w)) getTAPCfg(JTAGSystem_item#(n, w) item);
    return item matches tagged TAPConfig .cfg ? List::cons(cfg, Nil) : Nil;
endfunction

module [JTAGSystem#(n, w)] setTAPConfig#(JTAG_TAP_Config_t#(n, w) cfg)();
    //check if a config has already been specified
    let ctx <- getContext;
    let items = flatten(ctx);
    function Bool f_match_cfg(JTAGSystem_item#(n, w) it) = it matches tagged TAPConfig ._c ? True : False;
    let e = List::find(f_match_cfg, items);
    Bool exists = e matches tagged Invalid ? False : True;
    staticAssert(!exists, "TAP config already specified!");
    addToCollection(tagged TAPConfig cfg);
endmodule

module [JTAGSystem#(n, w)] addJTAGReg#(JTAG_Reg_ifc#(t) jtag_reg)();

    JTAGSystem_item#(n, w) new_item = 
        tagged IJTAG IJTAG_ { ctrl: jtag_reg.ctrl, tdo: as_read_only(jtag_reg.tdo), tdi: as_write_only(jtag_reg.tdi) };

    addToCollection(new_item);

endmodule

function Put#(t) writeOnlytoPut(WriteOnly#(t) wo);
    return
    interface Put;
        method put = wo._write;
    endinterface;
endfunction

module [Module] buildJTAGSystem#(JTAGSystem#(n, w, ifc) jtag_sys, Clock tdo_clk, Reset tdo_rst)(JTAGSystem_ifc#(ifc)) 
    provisos(Add#(1, a__, w));

    let {coll_device_ifc, items} <- getCollection(jtag_sys);
    let jtag_regs = List::concat(List::map(getIJTAG, items));
    let tap_cfgs = List::concat(List::map(getTAPCfg, items)); //should only be a single one

    staticAssert(List::length(tap_cfgs) == 1, "No TAP configuration provided");
    staticAssert(List::length(jtag_regs) == valueof(n), "Instruction count and JTAG reg mismatch");

    let tap_cfg = tap_cfgs[0];

    //collect TDOs from jtag registers
    Vector#(n, ReadOnly#(Bit#(1))) tdos = newVector;
    for(Integer i = 0; i < valueof(n); i = i + 1)
        tdos[i] = jtag_regs[i].tdo;
    //the i-th added jtag register is mapped to the i-th instruction occurring in the TAP config

    JTAG_TAP_Controller_ifc#(n) tap <- mkJTAG_TAP_Controller(
        tap_cfg,
        tdos,
        tdo_clk,
        tdo_rst
    );

    for(Integer i = 0; i < valueof(n); i = i + 1) begin
        jtagConnect(tap.tap_ctrl, jtag_regs[i].ctrl, i);
        mkConnection(toGet(tap.int_tdi), writeOnlytoPut(jtag_regs[i].tdi));
    end

    method tms = tap.tms;
    method tdi = tap.tdi;
    method tdo = tap.tdo;

    interface device_ifc = coll_device_ifc;

endmodule

endpackage