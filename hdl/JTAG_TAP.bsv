package JTAG_TAP;

import Vector :: *;

typedef Bit#(w) JTAGInstruction_t#(numeric type w);

typedef Vector#(n, JTAGInstruction#(w)) JTAG_TAP_Config_t#(numeric type n, numeric type w);

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
    )(JTAG_TAP_Controller_ifc#(n));
    
    //IR has to be reset to IDCODE/BYPASS
    //BYPASS has to be identified at least with all 1's
    JTAGInstruction_t instr_bypass = unpack(-1);
    JTAGInstruction_t ir_rst = reset_idcode_not_bypass ? instr_idcode : instr_bypass;

    let tap_fsm <- mkJTAG_TAP_FSM();

    Reg#(JTAGInstruction#(w)) rIR <- mkReg(ir_rst);
    Vector#(n, Wire#(Bool)) vSelect <- replicateM(mkDWire(False));

    // rule rir;
    //     if(tap_fsm.jtag_ctrl.capture_ir)
    //         rIR <= extend('b01); //load with predefined value
    //     else if(tap_fsm.jtag_ctrl.shift_ir)
    //     else if(tap_fsm.jtag_ctrl.update_ir)
    // endrule

    rule rsel;
        for(Integer i = 0; i < valueof(n); i = i + 1) begin
            vSelect[i] <= rIR == tap_cfg[i];
        end
    endrule

    interface select = readVReg(vSelect);
    interface jtag_ctrl = tap_fsm.jtag_ctrl;

endmodule

endpackage