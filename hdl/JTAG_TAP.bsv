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

    method Bit#(1) int_tdi();
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
    Bool reset_idcode_not_bypass,
    Vector#(n, ReadOnly#(Bit#(1))) vTDO_up,
    Clock tdo_clk,
    Reset tdo_rst
    )(JTAG_TAP_Controller_ifc#(n)) provisos(Add#(1, a__, w));

    let tck <- exposeCurrentClock;
    let tck_inv = tdo_clk;
    let trst_inv = tdo_rst;

    //IR has to be reset to IDCODE/BYPASS
    //BYPASS has to be identified at least with all 1's
    JTAGInstruction_t#(w) instr_bypass = unpack(-1);
    JTAGInstruction_t#(w) ir_rst = reset_idcode_not_bypass ? instr_idcode : instr_bypass;

    let tap_fsm <- mkJTAG_TAP_FSM();

    //IR register is required to hold 0b01 at [1:0] after capture
    JTAG_Reg_ifc#(Bit#(w)) jtagIR <- mkJTAGRegR('h01, tagged WithReset ir_rst);
    JTAG_Reg_ifc#(Bit#(1)) jtagBypass <- mkJTAGBypass();
    JTAG_Reg_ifc#(Bit#(32)) jtagIDCode <- mkJTAGReg({tap_cfg.idcode_man, tap_cfg.idcode_part, tap_cfg.idcode_ver, 1'b1}); //idcode is required to have a 1 as LSB

    Wire#(Bit#(1)) bwTDI <- mkBypassWire;

    //instruction decoder based on IR hold register
    Vector#(n, Bool) vSelect = newVector;
    for(Integer i = 0; i < valueof(n); i = i + 1) begin
        vSelect[i] = jtagIR.reg_o() == tap_cfg.instrs[i];
    end

    ReadOnly#(Vector#(n, Bool)) sel_crossed <- mkNullCrossingWire(tck_inv, vSelect);
    ReadOnly#(Bool) shift_ir_crossed <- mkNullCrossingWire(tck_inv, tap_fsm.ctrl.shift_ir);
    ReadOnly#(Bit#(w)) ir_crossed <- mkNullCrossingWire(tck_inv, jtagIR.reg_o());
    ReadOnly#(Bit#(1)) ir_tdo_crossed <- mkNullCrossingWire(tck_inv, jtagIR.tdo());
    ReadOnly#(Bit#(1)) idc_tdo_crossed <- mkNullCrossingWire(tck_inv, jtagIDCode.tdo());
    ReadOnly#(Bit#(1)) byp_tdo_crossed <- mkNullCrossingWire(tck_inv, jtagBypass.tdo());
    ReadOnly#(Vector#(n, Bit#(1))) tdos_crossed <- mkNullCrossingWire(tck_inv, read_v_ro(vTDO_up));
    
    /* TDO MUX
    */
    Reg#(Bit#(1)) rg_ext_tdo <- mkRegU(clocked_by tck_inv, reset_by trst_inv);

    Bit#(1) int_tdo = 0;
    //could make vSelect take prio with && pack(sel_crossed) == 0
    if(shift_ir_crossed)
        int_tdo = ir_tdo_crossed;
    else if(ir_crossed == 0)
        int_tdo = idc_tdo_crossed;
    else if(pack(sel_crossed) == 0 && ir_crossed == pack(instr_bypass))
        int_tdo = byp_tdo_crossed;
    else
        for(Integer i = 0; i < valueof(n); i = i + 1)
            if(sel_crossed[i])
                int_tdo = tdos_crossed[i];
    
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

    rule rout;
        rg_ext_tdo <= int_tdo;
    endrule

    rule rir;
        jtagIR.ctrl.sel(True);
    endrule

    method tdo = tap_cfg.reg_tdo ? rg_ext_tdo : int_tdo;
    method tdi = bwTDI._write;
    method tms = tap_fsm.tms;

    method int_tdi = bwTDI;

    interface JTAG_Ctrl_Up_ifc tap_ctrl;
        method update = tap_fsm.ctrl.update_dr;
        method capture = tap_fsm.ctrl.capture_dr;
        method shift = tap_fsm.ctrl.shift_dr;

        interface select = vSelect;
    endinterface

endmodule

endpackage