package JTAG_TAP;

import Vector :: *;
import GetPut :: *;
import Connectable :: *;

import JTAG_Types :: *;
import JTAG_Reg :: *;

typedef enum {
    TestLogicReset,
    RunTestIdle,
    SelectDRScan,
    CaptureDR,
    ShiftDR,
    Exit1DR,
    PauseDR,
    Exit2DR,
    UpdateDR,
    SelectIRScan,
    CaptureIR,
    ShiftIR,
    Exit1IR,
    PauseIR,
    Exit2IR,
    UpdateIR
} JTAG_TAP_State_t deriving(Eq, Bits, FShow);

(* always_ready *)
interface JTAG_Ctrl_ifc;
    method Bool update_dr;
    method Bool capture_dr;
    method Bool shift_dr;
    method Bool update_ir;
    method Bool capture_ir;
    method Bool shift_ir;
endinterface

(* always_enabled *)
interface JTAP_TAP_FSM_ifc;

    (* prefix="" *) 
    method Action tms((*port="TMS"*) Bit#(1) t);

    (* prefix="" *)
    interface JTAG_Ctrl_ifc jtag_ctrl;

endinterface

interface JTAG_TAP_Controller_ifc#(numeric type n);

    (* prefix="" *) 
    method Action tms((*port="TMS"*) Bit#(1) t);
    (* prefix="" *) 
    method Action tdi((*port="TDI"*) Bit#(1) t);
    (* prefix="", result="TDO" *)
    method Bit#(1) tdo();


    interface Vector#(n, Put#(Bit#(1))) tdo_up;
    interface Vector#(n, Bool) select;
    interface JTAG_Ctrl_ifc jtag_ctrl;

endinterface

function JTAG_TAP_State_t tap_next_state(JTAG_TAP_State_t state, Bit#(1) tms);
    JTAG_TAP_State_t next_state = state;
    case(state)
    TestLogicReset: if(tms == 0) next_state = RunTestIdle;
    RunTestIdle:    if(tms == 1) next_state = SelectDRScan;
    SelectDRScan:   if(tms == 1) next_state = SelectIRScan;     else next_state = CaptureDR;
    CaptureDR:      if(tms == 1) next_state = Exit1DR;          else next_state = ShiftDR;
    ShiftDR:        if(tms == 1) next_state = Exit1DR;
    Exit1DR:        if(tms == 1) next_state = UpdateDR;         else next_state = PauseDR;
    PauseDR:        if(tms == 1) next_state = Exit2DR;
    Exit2DR:        if(tms == 1) next_state = UpdateDR;         else next_state = ShiftDR;
    UpdateDR:       if(tms == 1) next_state = SelectDRScan;     else next_state = RunTestIdle;
    SelectIRScan:   if(tms == 1) next_state = TestLogicReset;   else next_state = CaptureIR;
    CaptureIR:      if(tms == 1) next_state = Exit1IR;          else next_state = ShiftIR;
    ShiftIR:        if(tms == 1) next_state = Exit1IR;
    Exit1IR:        if(tms == 1) next_state = UpdateIR;         else next_state = PauseIR;
    PauseIR:        if(tms == 1) next_state = Exit2IR;
    Exit2IR:        if(tms == 1) next_state = UpdateIR;         else next_state = ShiftIR;
    UpdateIR:       if(tms == 1) next_state = SelectIRScan;     else next_state = RunTestIdle;
    endcase
    return next_state;
endfunction

(*
    default_clock_osc="TCK",
    default_reset="TRST"
*)
module mkJTAG_TAP_FSM(JTAP_TAP_FSM_ifc);

    //ToDo reset synchronization should be at leafs, including the TAP
    // let tck     <- exposeCurrentClock();
    // let trst    <- exposeCurrentReset();

    Wire#(Bit#(1))          bwTMS <- mkBypassWire;
    Reg#(JTAG_TAP_State_t)  rState <- mkReg(TestLogicReset);

    rule rfsm;
        rState <= tap_next_state(rState, bwTMS);
    endrule

    method tms = bwTMS._write;

    interface JTAG_Ctrl_ifc jtag_ctrl;
        method update_dr    = rState == UpdateDR;
        method shift_dr     = rState == ShiftDR;
        method capture_dr   = rState == CaptureDR;
        method update_ir    = rState == UpdateIR;
        method shift_ir     = rState == ShiftIR;
        method capture_ir   = rState == CaptureIR;
    endinterface

endmodule

(*
    default_clock_osc="TCK",
    default_reset="TRST"
*)
module mkJTAG_TAP_Controller#(
    JTAG_TAP_Config_t#(n, w) tap_cfg,
    JTAGInstruction_t#(w) instr_idcode,
    Bool reset_idcode_not_bypass
    )(JTAG_TAP_Controller_ifc#(n)) provisos(Add#(1, a__, w));
    
    //IR has to be reset to IDCODE/BYPASS
    //BYPASS has to be identified at least with all 1's
    JTAGInstruction_t#(w) instr_bypass = unpack(-1);
    JTAGInstruction_t#(w) ir_rst = reset_idcode_not_bypass ? instr_idcode : instr_bypass;

    let tap_fsm <- mkJTAG_TAP_FSM();
    
    JTAG_Reg_ifc#(w) jtagIR <- mkJTAGReg(ir_rst);
    JTAG_Reg_ifc#(1) jtagBypass <- mkJTAGBypass();
    JTAG_Reg_ifc#(10) jtagIDCode <- mkJTAGReg({'b010010011, 1'b1}); //idcode is required to have a 1 as LSB
    Vector#(n, Wire#(Bool)) vSelect <- replicateM(mkDWire(False));
    Vector#(n, Wire#(Bit#(1))) vTDO_up <- replicateM(mkBypassWire); //upstream TDO

    Wire#(Bit#(1)) bwTDI <- mkBypassWire;
    
    //only activate bypass/idcode when no matching instruction was found in the config
    Bool id_sel = pack(readVReg(vSelect)) == 0 && jtagIR.reg_o() == 0;
    Bool byp_sel = pack(readVReg(vSelect)) == 0 && jtagIR.reg_o() == pack(instr_bypass);

    Bool scan_ir = tap_fsm.jtag_ctrl.capture_ir || tap_fsm.jtag_ctrl.shift_ir || tap_fsm.jtag_ctrl.update_ir;
    Bool scan_dr = tap_fsm.jtag_ctrl.capture_dr || tap_fsm.jtag_ctrl.shift_dr || tap_fsm.jtag_ctrl.update_dr;
    
    mkConnection(jtagIR.capture, tap_fsm.jtag_ctrl.capture_ir);
    mkConnection(jtagIR.shift, tap_fsm.jtag_ctrl.shift_ir);
    mkConnection(jtagIR.update, tap_fsm.jtag_ctrl.update_ir);
    mkConnection(jtagIR.tdi, bwTDI);

    mkConnection(jtagBypass.capture, tap_fsm.jtag_ctrl.capture_dr);
    mkConnection(jtagBypass.shift, tap_fsm.jtag_ctrl.shift_dr);
    mkConnection(jtagBypass.update, tap_fsm.jtag_ctrl.update_dr);
    mkConnection(jtagBypass.tdi, bwTDI);
    mkConnection(jtagBypass.sel, byp_sel);

    mkConnection(jtagIDCode.capture, tap_fsm.jtag_ctrl.capture_dr);
    mkConnection(jtagIDCode.shift, tap_fsm.jtag_ctrl.shift_dr);
    mkConnection(jtagIDCode.update, tap_fsm.jtag_ctrl.update_dr);
    mkConnection(jtagIDCode.tdi, bwTDI);
    mkConnection(jtagIDCode.sel, id_sel);

    //instruction decoder based on IR hold register
    rule rdecode;
        for(Integer i = 0; i < valueof(n); i = i + 1) begin
            vSelect[i] <= jtagIR.reg_o() == tap_cfg[i];
        end
    endrule

    //tdo mux
    method Bit#(1) tdo();
        Bit#(1) tdo_ = 0;
        if(id_sel) 
            tdo_ = jtagIDCode.tdo();
        else if(byp_sel)
            tdo_ = jtagBypass.tdo();
        else
            for(Integer i = 0; i < valueof(n); i = i + 1)
                if(vSelect[i])
                    tdo_ = vTDO_up[i];
        return tdo_;
    endmethod

    method tdi = bwTDI._write;
    method tms = tap_fsm.tms;
    interface tdo_up = map(toPut, map(asReg, vTDO_up));
    interface select = readVReg(vSelect);
    interface jtag_ctrl = tap_fsm.jtag_ctrl;

endmodule

endpackage