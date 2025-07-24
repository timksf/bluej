package Testbench;

import GetPut :: *;
import Vector :: *;
import StmtFSM :: *;
import BuildVector :: *;
import Connectable :: *;

import BlueJ :: *;

typedef 8 IR_WIDTH;

function Stmt jtag_sequence(Reg#(Bit#(32)) i, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, Bit#(w) tms_vec, Bit#(w) tdi_vec);
    return seq
        i <= 0;
        while(i < fromInteger(valueof(w))) action
            tms <= tms_vec[fromInteger(valueof(w))-1-i];
            tdi <= tdi_vec[fromInteger(valueof(w))-1-i];
            i <= i + 1;
        endaction
    endseq;
endfunction

function Stmt jtag_reset(Reg#(Bit#(32)) i, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi);
    // JTAG FSM reset: Hold TMS high for 5 TCK cycles, then go to Run-Test/Idle with TMS=0
    return jtag_sequence(i, tms, tdi, 6'b111110, 6'b0);
endfunction

function Stmt jtag_ir(Reg#(Bit#(32)) i, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, JTAGInstruction_t#(w) instr);
    //go to Shift-IR state with 1100
    //then repeat shift w times
    //then go to Run-Test/Idle with 110
    Bit#(w) z = 0;
    Bit#(TAdd#(w, 7)) tms_v = {4'b1100, z, 3'b110};
    Bit#(TAdd#(w, 7)) tdi_v = {4'b1111, instr, 3'b111};
    return jtag_sequence(i, tms, tdi, tms_v, tdi_v);
endfunction

module mkTestbench();

    let tck <- exposeCurrentClock();
    let trst <- exposeCurrentReset();

    JTAG_TAP_Config_t#(1, IR_WIDTH) jtag_config = vec(
        'h0002
    );

    JTAG_Reg_ifc#(32) reg0 <- mkJTAGReg('hDEADBEEF);
    JTAG_TAP_Controller_ifc#(1) dut <- mkJTAG_TAP_Controller(jtag_config, 0, True);

    Wire#(Bit#(1)) dwTMS <- mkDWire(1);
    Wire#(Bit#(1)) dwTDI <- mkDWire(0);
    Wire#(Bit#(1)) bwTDO <- mkBypassWire;

    Reg#(Bit#(32)) rCount <- mkRegU;

    //connect custom data register
    mkConnection(reg0.tdi, dwTDI);
    mkConnection(reg0.capture, dut.jtag_ctrl.capture_dr);
    mkConnection(reg0.shift, dut.jtag_ctrl.shift_dr);
    mkConnection(reg0.update, dut.jtag_ctrl.update_dr);
    mkConnection(reg0.sel, dut.select[0]);
    mkConnection(reg0.tdo, dut.tdo_up[0]); //todo connectable instance

    //connect TAP controller to stimulus
    mkConnection(dut.tms, dwTMS);
    mkConnection(dut.tdi, dwTDI);
    mkConnection(bwTDO, dut.tdo);

    Stmt s = {
        seq
            jtag_reset(rCount, dwTMS, dwTDI);
        endseq
    };

    mkAutoFSM(s);

endmodule

endpackage