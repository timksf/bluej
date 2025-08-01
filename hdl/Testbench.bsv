package Testbench;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import StmtFSM :: *;
import BuildVector :: *;
import Connectable :: *;

import BlueJ :: *;

typedef 8 IR_WIDTH;

function Stmt jtag_sequence(Reg#(Bit#(32)) i, Wire#(Bool) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, Bit#(w) tms_vec, Bit#(w) tdi_vec);
    return seq
        i <= 0;
        while(i < fromInteger(valueof(w))) action
            tck <= True;
            tms <= tms_vec[fromInteger(valueof(w))-1-i];
            tdi <= tdi_vec[fromInteger(valueof(w))-1-i];
            i <= i + 1;
        endaction
    endseq;
endfunction

function Stmt jtag_idle(Reg#(Bit#(32)) i, Wire#(Bool) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, Integer cycles);
    return seq
        i <= 0;
        while(i < fromInteger(cycles)) action
            tck <= True;
            tms <= 0;
            tdi <= 0;
            i <= i + 1;
        endaction
    endseq;
endfunction

function Stmt jtag_reset(Reg#(Bit#(32)) i, Wire#(Bool) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi);
    // JTAG FSM reset: Hold TMS high for 5 TCK cycles, then go to Run-Test/Idle with TMS=0
    return jtag_sequence(i, tck, tms, tdi, 6'b111110, 6'b0);
endfunction

function Stmt jtag_ir(Reg#(Bit#(32)) i, Wire#(Bool) tck, Wire#(Bit#(1)) tms, Wire#(Bit#(1)) tdi, JTAGInstruction_t#(w) instr);
    //go to Shift-IR state with 1100
    //then repeat shift w times
    //then go to Run-Test/Idle with 110
    Bit#(w) z = 0;
    Bit#(TAdd#(w, 7)) tms_v = {4'b1100, z, 3'b110};
    Bit#(TAdd#(w, 7)) tdi_v = {4'b1111, instr, 3'b111};
    return jtag_sequence(i, tck, tms, tdi, tms_v, tdi_v);
endfunction

module mkTestbench();

    // let tck <- exposeCurrentClock();
    // let trst <- exposeCurrentReset();

    JTAG_TAP_Config_t#(1, IR_WIDTH) jtag_config = vec(
        'h0002
    );

    Wire#(Bool) dwGateTCK <- mkDWire(False);
    let tck_gated <- mkGatedClockFromCC(True);
    let tck = tck_gated.new_clk;

    JTAG_Reg_ifc#(32) reg0 <- mkJTAGReg('hDEADBEEF, clocked_by tck);
    JTAG_TAP_Controller_ifc#(1) dut <- mkJTAG_TAP_Controller(jtag_config, 0, True, clocked_by tck);

    Wire#(Bit#(1)) dwTMS <- mkDWire(1, clocked_by tck);
    Wire#(Bit#(1)) dwTDI <- mkDWire(0, clocked_by tck);
    Wire#(Bit#(1)) bwTDO <- mkBypassWire(clocked_by tck);

    Reg#(Bit#(32)) rCount <- mkRegU(clocked_by tck);

    //connect custom data register
    mkConnection(reg0.tdi, dwTDI, clocked_by tck);
    mkConnection(reg0.capture, dut.jtag_ctrl.capture_dr, clocked_by tck);
    mkConnection(reg0.shift, dut.jtag_ctrl.shift_dr, clocked_by tck);
    mkConnection(reg0.update, dut.jtag_ctrl.update_dr, clocked_by tck);
    mkConnection(reg0.sel, dut.select[0], clocked_by tck);
    mkConnection(toGet(reg0.tdo), dut.tdo_up[0], clocked_by tck); //todo connectable instance

    //connect TAP controller to stimulus
    mkConnection(dut.tms, dwTMS, clocked_by tck);
    mkConnection(dut.tdi, dwTDI, clocked_by tck);
    mkConnection(toGet(dut.tdo), toPut(asReg(bwTDO)), clocked_by tck);

    rule rtck;
        tck_gated.setGateCond(dwGateTCK);
    endrule

    Stmt s = {
        seq
            jtag_reset(rCount, dwGateTCK, dwTMS, dwTDI);
            jtag_idle(rCount, dwGateTCK, dwTMS, dwTDI, 10);
        endseq
    };

    mkAutoFSM(s);

endmodule

endpackage