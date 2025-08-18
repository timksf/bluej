package JTAG_TAP;

import Vector :: *;
import GetPut :: *;
import Clocks :: *;
import Connectable :: *;

import JTAG_Types :: *;
import JTAG_Reg :: *;

typedef enum {
    TestLogicReset = 0,
    RunTestIdle = 1,
    SelectDRScan = 2,
    CaptureDR = 3,
    ShiftDR = 4,
    Exit1DR = 5,
    PauseDR = 6,
    Exit2DR = 7,
    UpdateDR = 8,
    SelectIRScan = 9,
    CaptureIR = 10,
    ShiftIR = 11,
    Exit1IR = 12,
    PauseIR = 13,
    Exit2IR = 14,
    UpdateIR = 15
} JTAG_TAP_State_t deriving(Eq, Bits, FShow);

(* always_ready *)
interface JTAG_FSM_Ctrl_ifc;
    method Bool update_dr();
    method Bool shift_dr();
    method Bool capture_dr();
    method Bool update_ir();
    method Bool shift_ir();
    method Bool capture_ir();
endinterface

(* always_enabled *)
interface JTAP_TAP_FSM_ifc;

    (* prefix="" *) 
    method Action tms((*port="TMS"*) Bit#(1) t);

    (* prefix="" *)
    interface JTAG_FSM_Ctrl_ifc ctrl;

endinterface

interface JTAG_TAP_Controller_ifc#(numeric type n);

    (* prefix="" *) 
    method Action tms((*port="TMS"*) Bit#(1) t);
    (* prefix="" *) 
    method Action tdi((*port="TDI"*) Bit#(1) t);
    (* prefix="", result="TDO" *)
    method Bit#(1) tdo();

    interface JTAG_Ctrl_Up_ifc#(n) tap_ctrl;

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
    Wire#(JTAG_TAP_State_t) next <- mkWire;
    Reg#(JTAG_TAP_State_t)  rState <- mkReg(TestLogicReset);


    rule rfsm;
        let next_state = tap_next_state(rState, bwTMS);
        next <= next_state;
        // $write("[%0t] state ", $time, fshow(rState)); $display(" next state ", fshow(next_state));
        rState <= next_state;
    endrule

    method tms = bwTMS._write;

    interface JTAG_FSM_Ctrl_ifc ctrl;
        method update_dr    = rState == UpdateDR;
        method shift_dr     = rState == ShiftDR;
        method capture_dr   = rState == CaptureDR;
        method update_ir    = rState == UpdateIR;
        method shift_ir     = rState == ShiftIR;
        method capture_ir   = rState == CaptureIR;
    endinterface

endmodule

// (*
//     default_clock_osc="TCK",
//     default_reset="TRST"
// *)
module mkJTAG_TAP_Controller#(
    JTAG_TAP_Config_t#(n, w) tap_cfg,
    JTAGInstruction_t#(w) instr_idcode,
    Bool reset_idcode_not_bypass
    )(JTAG_TAP_Controller_ifc#(n)) provisos(Add#(1, a__, w));

    let tck <- exposeCurrentClock;
    let tck_inv <- invertCurrentClock;

    //IR has to be reset to IDCODE/BYPASS
    //BYPASS has to be identified at least with all 1's
    JTAGInstruction_t#(w) instr_bypass = unpack(-1);
    JTAGInstruction_t#(w) ir_rst = reset_idcode_not_bypass ? instr_idcode : instr_bypass;

    let tap_fsm <- mkJTAG_TAP_FSM();
    JTAG_Reg_ifc#(Bit#(w)) jtagIR <- mkJTAGReg(ir_rst);
    JTAG_Reg_ifc#(Bit#(1)) jtagBypass <- mkJTAGBypass();
    JTAG_Reg_ifc#(Bit#(32)) jtagIDCode <- mkJTAGReg({tap_cfg.idcode_man, tap_cfg.idcode_part, tap_cfg.idcode_ver, 1'b1}); //idcode is required to have a 1 as LSB
    Vector#(n, Wire#(Bool)) vSelect <- replicateM(mkDWire(False));
    Vector#(n, Wire#(Bit#(1))) vTDO_up <- replicateM(mkBypassWire); //upstream TDO

    //crossed signals for TDO update on falling edge of tck
    // Vector#(n, Wire#(Bit#(1))) vTDO_up <- replicateM(mkBypassWire(clocked_by inver));

    Wire#(Bit#(1)) bwTDI <- mkBypassWire;
    
    //only activate bypass/idcode when no matching instruction was found in the config
    Bool id_sel = pack(readVReg(vSelect)) == 0 && jtagIR.reg_o() == 0;
    Bool byp_sel = pack(readVReg(vSelect)) == 0 && jtagIR.reg_o() == pack(instr_bypass);

    Bool scan_ir = tap_fsm.ctrl.capture_ir || tap_fsm.ctrl.shift_ir || tap_fsm.ctrl.update_ir;
    Bool scan_dr = tap_fsm.ctrl.capture_dr || tap_fsm.ctrl.shift_dr || tap_fsm.ctrl.update_dr;
    
    //the IR is the only JTAGReg connected to the IR control lines of the TAP FSM
    mkConnection(jtagIR.ctrl.capture, tap_fsm.ctrl.capture_ir);
    mkConnection(jtagIR.ctrl.shift, tap_fsm.ctrl.shift_ir);
    mkConnection(jtagIR.ctrl.update, tap_fsm.ctrl.update_ir);
    mkConnection(jtagIR.tdi, bwTDI);

    mkConnection(jtagBypass.ctrl.capture, tap_fsm.ctrl.capture_dr);
    mkConnection(jtagBypass.ctrl.shift, tap_fsm.ctrl.shift_dr);
    mkConnection(jtagBypass.ctrl.update, tap_fsm.ctrl.update_dr);
    mkConnection(jtagBypass.ctrl.sel, byp_sel);
    mkConnection(jtagBypass.tdi, bwTDI);

    mkConnection(jtagIDCode.ctrl.capture, tap_fsm.ctrl.capture_dr);
    mkConnection(jtagIDCode.ctrl.shift, tap_fsm.ctrl.shift_dr);
    mkConnection(jtagIDCode.ctrl.update, tap_fsm.ctrl.update_dr);
    mkConnection(jtagIDCode.ctrl.sel, id_sel);
    mkConnection(jtagIDCode.tdi, bwTDI);

    rule rir;
        jtagIR.ctrl.sel(True);
    endrule

    //instruction decoder based on IR hold register
    rule rdecode;
        for(Integer i = 0; i < valueof(n); i = i + 1) begin
            vSelect[i] <= jtagIR.reg_o() == tap_cfg.instrs[i];
        end
    endrule

    //tdo mux, clocked by inverted TCK
    method Bit#(1) tdo();
        Bit#(1) tdo_ = 0;
        if(id_sel) 
            tdo_ = jtagIDCode.ctrl.tdo();
        else if(byp_sel)
            tdo_ = jtagBypass.ctrl.tdo();
        else
            for(Integer i = 0; i < valueof(n); i = i + 1)
                if(vSelect[i])
                    tdo_ = vTDO_up[i];
        return tdo_;
    endmethod

    method tdi = bwTDI._write;
    method tms = tap_fsm.tms;

    interface JTAG_Ctrl_Up_ifc tap_ctrl;
        method update = tap_fsm.ctrl.update_dr;
        method capture = tap_fsm.ctrl.capture_dr;
        method shift = tap_fsm.ctrl.shift_dr;

        interface tdo_up = map(reg_to_write_only, map(asReg, vTDO_up));
        interface select = readVReg(vSelect);
    endinterface

endmodule

endpackage