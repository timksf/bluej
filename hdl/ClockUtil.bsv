package ClockUtil;

import Clocks ::*;
import DReg :: *;
import Connectable ::*;

import JTAG_TAP :: *;

(* always_ready, always_enabled *)
interface OutputBit_ifc;
    method Bit#(1) out;
endinterface

import "BVI" ASSIGN1 =
module pack_clock#(Clock clk)(OutputBit_ifc);
    default_clock no_clock;
    default_reset no_reset;

    input_clock clk(IN) = clk;

    method OUT out;

    schedule (out) CF (out);
endmodule

(* always_ready, always_enabled *)
interface UnpackedClock_ifc;
    interface Clock clk;
    method Action in(Bit#(1) x);
endinterface

import "BVI" ASSIGN1 =
module unpack_clock(UnpackedClock_ifc);
    default_clock no_clock;
    default_reset no_reset;

    output_clock clk(OUT);

    method in(IN) enable((*inhigh*)en) clocked_by(clk);

    schedule (in) CF (in);
endmodule

(* always_ready, always_enabled *)
interface UnpackedReset_ifc;
   interface Reset rst;
   method Action in(Bit#(1) x);
endinterface

import "BVI" ASSIGN1 =
module unpack_reset#(Clock clk)(UnpackedReset_ifc);

   default_clock no_clock;
   default_reset no_reset;

   input_clock clk() = clk;
   output_reset rst(OUT);

   method in(IN) enable((*inhigh*)en) clocked_by(clk) reset_by(rst);

   schedule (in) CF (in);

endmodule

interface JTAGClock_ifc;

    method Action tck_in(Bit#(1) w);
    method Action trst_in(Bit#(1) w);

    interface Clock tck_out;
    interface Reset trst_out;

endinterface

module mkJTAGClockAdapter#(Bit#(1) clk_idle)(JTAGClock_ifc);
    /*
        This is a somewhat cursed module allowing the generation of an arbitrary clock on tck_out
        based on the input supplied to tck_in.
        I have not found a better way of clocking the JTAG only sporadically when data is present
        on the JTAG signal lines.
        One remaining caveat is that we cannot use a Wire as input to mkNullCrossingWire, otherwise 
        this wire would have to be written previous to the clock domain crossing, although the compiler 
        requires the null crossing rule to be the very first action in a cycle.
        We use a DReg such that the clock idle level can be selected upon module creation and does not 
        have to be remembered every time.
    
        ... or we'll just use MakeClockIfc and MakeResetIfc in combination with mkNullCrossingReg
    */

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    MakeClockIfc#(Bit#(1)) tck_clock <- mkUngatedClock(clk_idle);
    MakeResetIfc trst <- mkReset(0, True, tck_clock.new_clk);
    
    method tck_in = tck_clock.setClockValue;
    method Action trst_in(Bit#(1) w);
        //active low
        if(w == 0) trst.assertReset();
    endmethod

    interface tck_out  = tck_clock.new_clk;
    interface trst_out = trst.new_rst;
endmodule

interface JTAG_Stim_ifc;

    //TCK clock domain
    method Bit#(1) int_tms();
    method Bit#(1) int_tdi();
    method Action int_tdo(Bit#(1) b);

    //default clock domain
    method Action ext_trst(Bit#(1) b);
    method Action ext_tck(Bit#(1) b);
    method Action ext_tms(Bit#(1) b);
    method Action ext_tdi(Bit#(1) b);
    method Bit#(1) ext_tdo();

    interface Clock tck_out;
    interface Reset trst_out;
endinterface

module mkJTAGShim(JTAG_Stim_ifc);

    let clk <- exposeCurrentClock();
    let rst <- exposeCurrentReset();

    let jtag_clk <- mkJTAGClockAdapter(1);

    CrossingReg#(Bit#(1)) tms_in  <- mkNullCrossingReg(jtag_clk.tck_out, 0);
    CrossingReg#(Bit#(1)) tdi_in  <- mkNullCrossingReg(jtag_clk.tck_out, 0);
    CrossingReg#(Bit#(1)) tdo_out <- mkNullCrossingReg(clk, 0, clocked_by jtag_clk.tck_out, reset_by jtag_clk.trst_out);

    method ext_trst = jtag_clk.trst_in;
    method ext_tck = jtag_clk.tck_in;
    method ext_tdi = tdi_in._write;
    method ext_tms = tms_in._write;
    method ext_tdo = tdo_out.crossed;

    method int_tdi = tdi_in.crossed;
    method int_tms = tms_in.crossed;
    method int_tdo = tdo_out._write;

    interface tck_out = jtag_clk.tck_out;
    interface trst_out = jtag_clk.trst_out;

endmodule

endpackage