package TestJTAGRegSync;

import Clocks :: *;
import TestHelper :: *;
import JTAG_Reg :: *;
import JTAG_Types :: *;
import JTAG_Reg_Sync :: *;

function Bit#(32) update_value(UInt#(5) index);
    case(pack(index)[1:0])
        0: return 'h00;
        1: return 'hFFFFFFFF;
        default: return 'hDEADBEEF;
    endcase
endfunction

module mkSyncRegScenario#(Integer tck_period, Integer idle_cycles)(TestHandler);
    let sys_clk <- exposeCurrentClock;
    let sys_rst <- exposeCurrentReset;
    let tck <- mkAbsoluteClock(1, tck_period);
    let trst <- mkAsyncResetFromCR(2, tck);

    JTAG_Reg_ifc#(Bit#(32)) i_reg <- mkJTAG_Reg_SyncR('hDEADBEEF, tagged WithReset 0, sys_clk, sys_rst,
                                                   clocked_by tck, reset_by trst);
    SyncBitIfc#(Bool) i_start <- mkSyncBitFromCC(tck);

    Reg#(Bool) rg_started <- mkReg(False);
    Reg#(UInt#(16)) rg_timeout <- mkReg(0);
    Reg#(UInt#(5)) rg_updates <- mkReg(0);
    Reg#(UInt#(5)) rg_captures <- mkReg(0);
    Reg#(UInt#(4)) rg_settled <- mkReg(0);
    Reg#(Bool) rg_expect_capture <- mkReg(True);

    Reg#(UInt#(6)) rg_wait <- mkReg(0, clocked_by tck, reset_by trst);
    Reg#(UInt#(6)) rg_phase <- mkReg(0, clocked_by tck, reset_by trst);
    Reg#(UInt#(5)) rg_sent <- mkReg(0, clocked_by tck, reset_by trst);

    rule r_start;
        i_start.send(rg_started);
    endrule

    rule r_scan;
        Bool active = i_start.read && rg_wait == 32 && rg_sent < 16;
        Bool shifting = active && rg_phase >= 1 && rg_phase <= 32;
        let bit_index = rg_phase - 1;
        Bit#(32) write_value = update_value(rg_sent);
        Bit#(32) read_value = 'hDEADBEEF;

        i_reg.scan.ctrl.sel(True);
        i_reg.scan.ctrl.capture(active && rg_phase == 0);
        i_reg.scan.ctrl.shift(shifting);
        i_reg.scan.ctrl.update(active && rg_phase == 33);
        i_reg.scan.tdi(truncate(write_value >> bit_index));

        if(i_start.read && rg_wait < 32)
            rg_wait <= rg_wait + 1;
        if(active) begin
            if(shifting && i_reg.scan.tdo != truncate(read_value >> bit_index))
                $fatal(1, "readback mismatch, TCK period %0d", tck_period);
            if(rg_phase == fromInteger(34 + idle_cycles)) begin
                rg_phase <= 0;
                rg_sent <= rg_sent + 1;
            end else
                rg_phase <= rg_phase + 1;
        end
    endrule

    rule r_check_events;
        if(i_reg.cap_o) begin
            if(!rg_expect_capture || i_reg.wr_o || rg_captures >= 16)
                $fatal(1, "capture ordering/count mismatch, TCK period %0d", tck_period);
            rg_captures <= rg_captures + 1;
            rg_expect_capture <= False;
        end else if(i_reg.wr_o) begin
            if(rg_expect_capture || rg_updates >= 16 || i_reg.reg_o != update_value(rg_updates))
                $fatal(1, "update data/order/count mismatch, TCK period %0d, index %0d, data %0h",
                       tck_period, rg_updates, i_reg.reg_o);
            rg_updates <= rg_updates + 1;
            rg_expect_capture <= True;
        end
    endrule

    rule r_settle if(rg_updates == 16 && rg_captures == 16 && rg_settled < 8);
        rg_settled <= rg_settled + 1;
        if(rg_settled == 7)
            $display("PASS: 16 ordered capture/update transfers and readbacks, TCK period %0d", tck_period);
    endrule

    rule r_timeout if(rg_started);
        rg_timeout <= rg_timeout + 1;
        if(rg_timeout == 20000)
            $fatal(1, "CDC test timed out, TCK period %0d", tck_period);
    endrule

    method Action go();
        rg_started <= True;
    endmethod

    method done = rg_settled == 8;
endmodule

module mkSyncRegResetScenario(TestHandler);
    let sys_clk <- exposeCurrentClock;
    let sys_rst <- mkInitialReset(50);
    let tck <- mkAbsoluteClock(1, 10);
    let trst <- mkAsyncResetFromCR(2, tck);
    let sys_in_reset <- isResetAsserted(reset_by sys_rst);

    JTAG_Reg_ifc#(Bit#(8)) i_reg <- mkJTAG_Reg_Sync(0, sys_clk, sys_rst,
                                                 clocked_by tck, reset_by trst);
    SyncBitIfc#(Bool) i_done <- mkSyncBitToCC(sys_clk, sys_rst);
    Reg#(UInt#(6)) rg_phase <- mkReg(0, clocked_by tck, reset_by trst);
    Reg#(Bool) rg_updated <- mkReg(False, reset_by sys_rst);
    Reg#(UInt#(8)) rg_timeout <- mkReg(0, reset_by sys_rst);

    rule r_scan;
        if(rg_phase < 20)
            rg_phase <= rg_phase + 1;
        i_reg.scan.ctrl.sel(True);
        i_reg.scan.ctrl.capture(False);
        i_reg.scan.ctrl.update(rg_phase == 13);
        i_reg.scan.ctrl.shift(rg_phase >= 5 && rg_phase <= 12);
        i_reg.scan.tdi(0);
    endrule

    rule r_check;
        if(i_reg.cap_o || (sys_in_reset && i_reg.wr_o))
            $fatal(1, "unexpected capture or event delivered during system reset");
        if(i_reg.wr_o) begin
            if(rg_updated || i_reg.reg_o != 0)
                $fatal(1, "queued update lost or corrupted by system reset");
            rg_updated <= True;
            $display("PASS: pending update held during system reset and delivered after release");
        end
        if(rg_timeout < 200)
            rg_timeout <= rg_timeout + 1;
        else if(!rg_updated)
            $fatal(1, "system reset CDC test timed out");
    endrule

    rule r_done;
        i_done.send(rg_updated);
    endrule

    method Action go();
        noAction;
    endmethod

    method done = i_done.read;
endmodule

module mkSyncRegCaptureScenario(TestHandler);
    let sys_clk <- exposeCurrentClock;
    let sys_rst <- exposeCurrentReset;
    let tck <- mkAbsoluteClock(1, 17);
    let trst <- mkAsyncResetFromCR(2, tck);
    JTAG_Reg_ifc#(Bit#(8)) i_reg <- mkJTAG_Reg_Sync('h5A, sys_clk, sys_rst,
                                                 clocked_by tck, reset_by trst);
    Reg#(UInt#(6)) rg_phase <- mkReg(0, clocked_by tck, reset_by trst);
    Reg#(Bool) rg_captured <- mkReg(False);
    Reg#(UInt#(4)) rg_settled <- mkReg(0);
    Reg#(UInt#(8)) rg_timeout <- mkReg(0);

    rule r_scan;
        if(rg_phase < 33)
            rg_phase <= rg_phase + 1;
        i_reg.scan.ctrl.sel(True);
        i_reg.scan.ctrl.capture(rg_phase == 32);
        i_reg.scan.ctrl.update(False);
        i_reg.scan.ctrl.shift(False);
        i_reg.scan.tdi(0);
    endrule

    rule r_check;
        if(i_reg.wr_o)
            $fatal(1, "capture-only scan generated an update");
        if(i_reg.cap_o) begin
            if(rg_captured)
                $fatal(1, "capture-only scan generated a duplicate capture");
            rg_captured <= True;
            $display("PASS: capture-only event delivered without an update payload");
        end
        if(rg_timeout < 200)
            rg_timeout <= rg_timeout + 1;
        else if(!rg_captured)
            $fatal(1, "capture-only event waited for a nonexistent update");
    endrule

    rule r_settle if(rg_captured && rg_settled < 8);
        rg_settled <= rg_settled + 1;
    endrule

    method Action go();
        noAction;
    endmethod

    method done = rg_settled == 8;
endmodule

(* synthesize *)
module mkTestJTAGRegSync(TestHandler);
    let i_fast <- mkSyncRegScenario(2, 16);
    let i_equal <- mkSyncRegScenario(10, 4);
    let i_slow <- mkSyncRegScenario(34, 1);
    let i_reset <- mkSyncRegResetScenario;
    let i_capture <- mkSyncRegCaptureScenario;

    method Action go();
        i_fast.go;
        i_equal.go;
        i_slow.go;
        i_reset.go;
        i_capture.go;
    endmethod

    method done = i_fast.done && i_equal.done && i_slow.done && i_reset.done && i_capture.done;
endmodule

endpackage
