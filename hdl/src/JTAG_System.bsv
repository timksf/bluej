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

typedef struct {
    JTAGInstruction_t#(w) instr;
    IJTAG_ifc scan;
} IJTAG_#(numeric type w);

typedef union tagged {
    IJTAG_#(w)             IJTAG;
    JTAG_TAP_Meta_Config_t TAPMetaConfig;
    Bool                   RegTDOConfig;
    JTAGInstruction_t#(w)  IDCodeInstruction;
    Bool                   ResetIDCodeConfig;
    Bool                   DebugConfig;
} JTAGSystem_item#(numeric type n, numeric type w);

//n: number of (custom) instructions, w: instruction width
typedef ModuleCollect#(JTAGSystem_item#(n, w), ifc) JTAGSystem#(numeric type n, numeric type w, type ifc);

function List#(IJTAG_#(w)) get_ijtag(JTAGSystem_item#(n, w) item);
    return item matches tagged IJTAG .ijtag ? List::cons(ijtag, Nil) : Nil;
endfunction

function List#(JTAG_TAP_Meta_Config_t) get_tap_meta_cfg(JTAGSystem_item#(n, w) item);
    return item matches tagged TAPMetaConfig .cfg ? List::cons(cfg, Nil) : Nil;
endfunction

function List#(Bool) get_reg_tdo_cfg(JTAGSystem_item#(n, w) item);
    return item matches tagged RegTDOConfig .cfg ? List::cons(cfg, Nil) : Nil;
endfunction

function List#(JTAGInstruction_t#(w)) get_idcode_instr_cfg(JTAGSystem_item#(n, w) item);
    return item matches tagged IDCodeInstruction .cfg ? List::cons(cfg, Nil) : Nil;
endfunction

function List#(Bool) get_reset_idcode_cfg(JTAGSystem_item#(n, w) item);
    return item matches tagged ResetIDCodeConfig .cfg ? List::cons(cfg, Nil) : Nil;
endfunction

function List#(Bool) get_debug_cfg(JTAGSystem_item#(n, w) item);
    return item matches tagged DebugConfig .cfg ? List::cons(cfg, Nil) : Nil;
endfunction

module [JTAGSystem#(n, w)] jtag_meta_config#(Bit#(4) version, Bit#(11) man, Bit#(16) part)();
    JTAG_TAP_Meta_Config_t cfg = JTAG_TAP_Meta_Config_t {
        idcode_ver:  version,
        idcode_man:  man,
        idcode_part: part
    };
    JTAGSystem_item#(n, w) new_item = tagged TAPMetaConfig cfg;

    addToCollection(new_item);
endmodule

module [JTAGSystem#(n, w)] jtag_set_reg_tdo#(Bool reg_tdo)();
    JTAGSystem_item#(n, w) new_item = tagged RegTDOConfig reg_tdo;
    addToCollection(new_item);
endmodule

module [JTAGSystem#(n, w)] jtag_set_idcode_instr#(JTAGInstruction_t#(w) instr)();
    JTAGSystem_item#(n, w) new_item = tagged IDCodeInstruction instr;
    addToCollection(new_item);
endmodule

module [JTAGSystem#(n, w)] jtag_rst_to_idcode();
    JTAGSystem_item#(n, w) new_item = tagged ResetIDCodeConfig True;
    addToCollection(new_item);
endmodule

module [JTAGSystem#(n, w)] jtag_rst_to_bypass();
    JTAGSystem_item#(n, w) new_item = tagged ResetIDCodeConfig False;
    addToCollection(new_item);
endmodule

module [JTAGSystem#(n, w)] jtag_enable_debug();
    JTAGSystem_item#(n, w) new_item = tagged DebugConfig True;
    addToCollection(new_item);
endmodule

module [JTAGSystem#(n, w)] jtag_scan_endpoint#(IJTAG_ifc scan, JTAGInstruction_t#(w) instr)(Empty);
    JTAGSystem_item#(n, w) new_item = tagged IJTAG IJTAG_ {
        instr: instr,
        scan: scan
    };
    addToCollection(new_item);
endmodule

module [JTAGSystem#(n, w)] jtag_endpoint#(JTAG_Reg_ifc#(t) jtag_reg, JTAGInstruction_t#(w) instr)(JTAGRegAccess_ifc#(t));

    jtag_scan_endpoint(jtag_reg.scan, instr);

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
    let jtag_regs        = List::concat(List::map(get_ijtag, items));
    let tap_meta_cfgs    = List::concat(List::map(get_tap_meta_cfg, items));
    let reg_tdo_cfgs     = List::concat(List::map(get_reg_tdo_cfg, items));
    let idcode_instr_cfg = List::concat(List::map(get_idcode_instr_cfg, items));
    let reset_cfgs       = List::concat(List::map(get_reset_idcode_cfg, items));
    let debug_cfgs       = List::concat(List::map(get_debug_cfg, items));

    staticAssert(List::length(tap_meta_cfgs) == 1, "No JTAG meta configuration provided");
    staticAssert(List::length(reg_tdo_cfgs) <= 1, "JTAG TDO register config specified more than once");
    staticAssert(List::length(idcode_instr_cfg) <= 1, "JTAG IDCODE instruction specified more than once");
    staticAssert(List::length(reset_cfgs) <= 1, "JTAG reset instruction specified more than once");
    staticAssert(List::length(debug_cfgs) <= 1, "JTAG debug config specified more than once");
    staticAssert(List::length(jtag_regs) == valueof(n), "Instruction count and JTAG reg mismatch");

    let tap_meta = tap_meta_cfgs[0];

    Bool reg_tdo = List::length(reg_tdo_cfgs) == 0 ? True : reg_tdo_cfgs[0];
    JTAGInstruction_t#(w) instr_idcode = List::length(idcode_instr_cfg) == 0 ? 0 : idcode_instr_cfg[0];
    Bool reset_idcode_not_bypass = List::length(reset_cfgs) == 0 ? True : reset_cfgs[0];
    Bool debug = List::length(debug_cfgs) == 0 ? False : debug_cfgs[0];

    //collect TDOs from jtag registers
    Vector#(n, ReadOnly#(Bit#(1)))    tdos   = newVector;
    Vector#(n, JTAGInstruction_t#(w)) instrs = newVector;
    for(Integer i = 0; i < valueof(n); i = i + 1) begin
        tdos[i] = as_read_only(jtag_regs[i].scan.tdo);
        instrs[i] = jtag_regs[i].instr;
    end

    JTAG_TAP_Config_t#(n, w) tap_cfg = JTAG_TAP_Config_t {
        idcode_man: tap_meta.idcode_man,
        idcode_part: tap_meta.idcode_part,
        idcode_ver: tap_meta.idcode_ver,
        reg_tdo: reg_tdo,
        instrs: instrs,
        instr_idcode: instr_idcode,
        reset_idcode_not_bypass: reset_idcode_not_bypass,
        debug: debug
    };

    JTAG_TAP_Controller_ifc#(n) tap <- mkJTAG_TAP_Controller(
        tap_cfg,
        tdos,
        tdo_clk,
        tdo_rst
    );

    for(Integer i = 0; i < valueof(n); i = i + 1) begin
        tapConnect(tap, jtag_regs[i].scan, i);
    end

    method tms = tap.tms;
    method tdi = tap.tdi;
    method tdo = tap.tdo;

    interface device_ifc = coll_device_ifc;

endmodule

endpackage
