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
import JTAG_Reg_Sync :: *;
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

interface JTAGRegAccess_ifc#(type t);
    method ActionValue#(t) updated();
endinterface

interface JTAGPulseAccess_ifc;
    method Action pulse();
endinterface

//TODO: instead of this struct, introduce new "IJTAG" interface for internal jtag components
typedef struct {
    Maybe#(JTAGInstruction_t#(w)) instr;
    ReadOnly#(Bit#(1))           tdo;
    WriteOnly#(Bit#(1))          tdi;
    JTAG_Ctrl_Dn_ifc             ctrl;
} IJTAG_#(numeric type w);

typedef union tagged {
    IJTAG_#(w) IJTAG;
    JTAG_TAP_Config_t#(n, w) TAPConfig;
} JTAGSystem_item#(numeric type n, numeric type w);

//n: number of (custom) instructions, w: instruction width
typedef ModuleCollect#(JTAGSystem_item#(n, w), ifc) JTAGSystem#(numeric type n, numeric type w, type ifc);

function List#(IJTAG_#(w)) get_ijtag(JTAGSystem_item#(n, w) item);
    return item matches tagged IJTAG .ijtag ? List::cons(ijtag, Nil) : Nil;
endfunction

function List#(JTAG_TAP_Config_t#(n, w)) get_tap_cfg(JTAGSystem_item#(n, w) item);
    return item matches tagged TAPConfig .cfg ? List::cons(cfg, Nil) : Nil;
endfunction

module [JTAGSystem#(n, w)] set_tap_config#(JTAG_TAP_Config_t#(n, w) cfg)();
    //check if a config has already been specified
    let ctx <- getContext;
    let items = flatten(ctx);
    function Bool f_match_cfg(JTAGSystem_item#(n, w) it) = it matches tagged TAPConfig ._c ? True : False;
    let e = List::find(f_match_cfg, items);
    Bool exists = e matches tagged Invalid ? False : True;
    staticAssert(!exists, "TAP config already specified!");
    addToCollection(tagged TAPConfig cfg);
endmodule

module [JTAGSystem#(n, w)] add_jtag_reg#(JTAG_Reg_ifc#(t) jtag_reg)();

    JTAGSystem_item#(n, w) new_item =
        tagged IJTAG IJTAG_ {
            instr: tagged Invalid,
            ctrl:  jtag_reg.ctrl,
            tdo:   as_read_only(jtag_reg.tdo),
            tdi:   as_write_only(jtag_reg.tdi)
        };

    addToCollection(new_item);

endmodule

module [JTAGSystem#(n, w)] jtag_endpoint#(JTAG_Reg_ifc#(t) jtag_reg, JTAGInstruction_t#(w) instr)(JTAGRegAccess_ifc#(t));

    JTAGSystem_item#(n, w) new_item =
        tagged IJTAG IJTAG_ {
            instr: tagged Valid instr,
            ctrl:  jtag_reg.ctrl,
            tdo:   as_read_only(jtag_reg.tdo),
            tdi:   as_write_only(jtag_reg.tdi)
        };

    addToCollection(new_item);

    method updated if(jtag_reg.wr_o()) = actionvalue
        return jtag_reg.reg_o();
    endactionvalue;

endmodule

module [JTAGSystem#(n, w)] jtag_reg_ro#(t reg_i, JTAGInstruction_t#(w) instr)()
    provisos(Bits#(t, tw));

    JTAG_Reg_ifc#(t)  jreg    <- mkJTAGReg(reg_i);
    JTAGRegAccess_ifc#(t) _access <- jtag_endpoint(jreg, instr);

endmodule

module [JTAGSystem#(n, w)] jtag_reg_wo#(JTAGInstruction_t#(w) instr)(JTAGRegAccess_ifc#(t))
    provisos(Bits#(t, tw));

    JTAG_Reg_ifc#(t)  jreg   <- mkJTAGReg(unpack(0));
    JTAGRegAccess_ifc#(t) access <- jtag_endpoint(jreg, instr);

    return access;

endmodule

module [JTAGSystem#(n, w)] jtag_reg_rw#(Reg#(t) device_reg, JTAGInstruction_t#(w) instr)(JTAGRegAccess_ifc#(t))
    provisos(Bits#(t, tw));

    JTAG_Reg_ifc#(t)  jreg    <- mkJTAGReg(device_reg);
    JTAGRegAccess_ifc#(t) _access <- jtag_endpoint(jreg, instr);

    rule update_device_reg if(jreg.wr_o());
        device_reg <= jreg.reg_o();
    endrule

    method updated if(jreg.wr_o()) = actionvalue
        return jreg.reg_o();
    endactionvalue;

endmodule

module [JTAGSystem#(n, w)] jtag_reg_pulse#(JTAGInstruction_t#(w) instr)(JTAGPulseAccess_ifc);

    JTAG_Reg_ifc#(Bit#(1))  jreg    <- mkJTAGReg(0);
    JTAGRegAccess_ifc#(Bit#(1)) _access <- jtag_endpoint(jreg, instr);

    method Action pulse() if(jreg.wr_o() && jreg.reg_o() == 1'b1);
        noAction;
    endmethod

endmodule

module [JTAGSystem#(n, w)] jtag_sync_reg_ro#(t reg_i, JTAGInstruction_t#(w) instr, Clock sysclk, Reset sysrst)()
    provisos(Bits#(t, tw));

    JTAG_Reg_ifc#(t)  jreg    <- mkJTAG_Reg_Sync(reg_i, sysclk, sysrst);
    JTAGRegAccess_ifc#(t) _access <- jtag_endpoint(jreg, instr);

endmodule

module [JTAGSystem#(n, w)] jtag_sync_reg_wo#(JTAGInstruction_t#(w) instr, Clock sysclk, Reset sysrst)(JTAGRegAccess_ifc#(t))
    provisos(Bits#(t, tw));

    JTAG_Reg_ifc#(t)  jreg   <- mkJTAG_Reg_Sync(unpack(0), sysclk, sysrst);
    JTAGRegAccess_ifc#(t) access <- jtag_endpoint(jreg, instr);

    return access;

endmodule

module [JTAGSystem#(n, w)] jtag_sync_reg_rw#(Reg#(t) device_reg, JTAGInstruction_t#(w) instr, Clock sysclk, Reset sysrst)(JTAGRegAccess_ifc#(t))
    provisos(Bits#(t, tw));

    JTAG_Reg_ifc#(t)  jreg    <- mkJTAG_Reg_Sync(device_reg, sysclk, sysrst);
    JTAGRegAccess_ifc#(t) _access <- jtag_endpoint(jreg, instr);

    rule update_device_reg if(jreg.wr_o());
        device_reg <= jreg.reg_o();
    endrule

    method updated if(jreg.wr_o()) = actionvalue
        return jreg.reg_o();
    endactionvalue;

endmodule

module [JTAGSystem#(n, w)] jtag_sync_reg_pulse#(JTAGInstruction_t#(w) instr, Clock sysclk, Reset sysrst)(JTAGPulseAccess_ifc);

    JTAG_Reg_ifc#(Bit#(1))  jreg    <- mkJTAG_Reg_Sync(0, sysclk, sysrst);
    JTAGRegAccess_ifc#(Bit#(1)) _access <- jtag_endpoint(jreg, instr);

    method Action pulse() if(jreg.wr_o() && jreg.reg_o() == 1'b1);
        noAction;
    endmethod

endmodule

function Put#(t) write_only_to_put(WriteOnly#(t) wo);
    return
    interface Put;
        method put = wo._write;
    endinterface;
endfunction

module [Module] build_jtag_system#(JTAGSystem#(n, w, ifc) jtag_sys, Clock tdo_clk, Reset tdo_rst)(JTAGSystem_ifc#(ifc))
    provisos(Add#(1, a__, w));

    let {coll_device_ifc, items} <- getCollection(jtag_sys);
    let jtag_regs                 = List::concat(List::map(get_ijtag, items));
    let tap_cfgs                  = List::concat(List::map(get_tap_cfg, items)); //should only be a single one

    staticAssert(List::length(tap_cfgs) == 1, "No TAP configuration provided");
    staticAssert(List::length(jtag_regs) == valueof(n), "Instruction count and JTAG reg mismatch");

    let tap_cfg_base = tap_cfgs[0];

    //collect TDOs from jtag registers
    Vector#(n, ReadOnly#(Bit#(1)))    tdos   = newVector;
    Vector#(n, JTAGInstruction_t#(w)) instrs = newVector;
    for(Integer i = 0; i < valueof(n); i = i + 1) begin
        tdos[i] = jtag_regs[i].tdo;
        instrs[i] = jtag_regs[i].instr matches tagged Valid .instr ? instr : tap_cfg_base.instrs[i];
    end
    //the i-th added jtag register is mapped to the i-th derived instruction

    JTAG_TAP_Config_t#(n, w) tap_cfg = JTAG_TAP_Config_t {
        idcode_man: tap_cfg_base.idcode_man,
        idcode_part: tap_cfg_base.idcode_part,
        idcode_ver: tap_cfg_base.idcode_ver,
        reg_tdo: tap_cfg_base.reg_tdo,
        instrs: instrs,
        instr_idcode: tap_cfg_base.instr_idcode,
        reset_idcode_not_bypass: tap_cfg_base.reset_idcode_not_bypass,
        debug: tap_cfg_base.debug
    };

    JTAG_TAP_Controller_ifc#(n) tap <- mkJTAG_TAP_Controller(
        tap_cfg,
        tdos,
        tdo_clk,
        tdo_rst
    );

    for(Integer i = 0; i < valueof(n); i = i + 1) begin
        jtagConnect(tap.tap_ctrl, jtag_regs[i].ctrl, i);
        mkConnection(toGet(tap.int_tdi), write_only_to_put(jtag_regs[i].tdi));
    end

    method tms = tap.tms;
    method tdi = tap.tdi;
    method tdo = tap.tdo;

    interface device_ifc = coll_device_ifc;

endmodule

endpackage
