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

    interface Clock tdo_clk;
    interface Reset tdo_rst;

endinterface

module mkJTAGClockAdapter#(Bit#(1) clk_idle)(JTAGClock_ifc);
    /*
        This is a somewhat cursed module allowing the generation of an arbitrary clock on tck_out
        based on the input supplied to tck_in.
        I have not found a better way of clocking the JTAG only sporadically when data is present
        on the JTAG signal lines.
        One remaining caveat is that we cannot use a Wire as input to mkNullCrossingWire, otherwise 
        this wire would have to be written before the clock domain crossing, although the compiler 
        requires the null crossing rule to be the *very* first action in a cycle.
    */

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;
    
    MakeClockIfc#(Bit#(1)) tck_clock <- mkUngatedClock(clk_idle);
    MakeResetIfc trst <- mkReset(0, True, tck_clock.new_clk);

    let clk_inv <- mkClockInverter(clocked_by tck_clock.new_clk, reset_by trst.new_rst);
    let rst_inv <- mkAsyncReset(0, trst.new_rst, clk_inv.slowClock);
    
    method tck_in = tck_clock.setClockValue;
    method Action trst_in(Bit#(1) w);
        //active low
        if(w == 0) trst.assertReset();
    endmethod

    interface tck_out  = tck_clock.new_clk;
    interface trst_out = trst.new_rst;

    interface tdo_clk = clk_inv.slowClock;
    interface tdo_rst = rst_inv;

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

    interface Clock tdo_clk;
    interface Reset tdo_rst;
endinterface

/*
    This module translates JTAG signals from bit inputs into bluespec clock&reset and control signals 
    in the right clock domain.
    TMS and TDI are transferred from the default clock domain into the TCK domain
    TDO is transferred from {tck, reset} into the default clock domain associated with the bluespec interface 
    of this module.
    This module inadvertently delays all JTAG signals through the introduction of registers, this needs to be handled in
    the testbench!
*/
(* synthesize *)
module mkJTAGShim(JTAG_Stim_ifc);

    let clk <- exposeCurrentClock();
    let rst <- exposeCurrentReset();

    let jtag_clk <- mkJTAGClockAdapter(1);

    // CrossingReg#(Bit#(1)) tms_in  <- mkNullCrossingReg(jtag_clk.tck_out, 0);
    Reg#(Bit#(1)) tms_in <- mkReg(0);
    let tms_int <- mkNullCrossingWire(jtag_clk.tck_out, tms_in);
    CrossingReg#(Bit#(1)) tdi_in  <- mkNullCrossingReg(jtag_clk.tck_out, 0);
    CrossingReg#(Bit#(1)) tdo_out <- mkNullCrossingReg(clk, 0, clocked_by jtag_clk.tdo_clk, reset_by jtag_clk.tdo_rst);

    method ext_trst = jtag_clk.trst_in;
    method ext_tck = jtag_clk.tck_in;
    method ext_tdi = tdi_in._write;
    method ext_tms = tms_in._write;
    method ext_tdo = tdo_out.crossed;

    method int_tdi = tdi_in.crossed;
    method int_tms = tms_int; //tms_in.crossed;
    method int_tdo = tdo_out._write;

    interface tck_out = jtag_clk.tck_out;
    interface trst_out = jtag_clk.trst_out;

    interface tdo_clk = jtag_clk.tdo_clk;
    interface tdo_rst = jtag_clk.tdo_rst;

endmodule

interface JTAG_TDO_NullCrossing_ifc;
    method Bit#(1) ext_tdo();
endinterface

module mkJTAGTDONullCrossing#(Bit#(1) int_tdo, Clock tdo_clk, Reset tdo_rst)(JTAG_TDO_NullCrossing_ifc);

    let clk <- exposeCurrentClock();
    let tdo_crossed <- mkNullCrossingWire(clk, int_tdo, clocked_by tdo_clk, reset_by tdo_rst);

    method ext_tdo = tdo_crossed;

endmodule

// module mkJTAGShim_old#(
//     Clock tck,
//     Reset trst,
//     Bit#(1) ext_tms, 
//     Bit#(1) ext_tdi,
//     Bit#(1) int_tdo
//     )(JTAG_Stim_ifc);

//     let clk <- exposeCurrentClock();
//     let rst <- exposeCurrentReset();

//     // let jtag_clk <- mkJTAGClockAdapter(1);

//     let tms_in <- mkNullCrossingWire(tck, ext_tms);
//     let tdi_in <- mkNullCrossingWire(tck, ext_tdi);
//     let tdo_out <- mkNullCrossingWire(clk, int_tdo);

//     // method ext_trst = jtag_clk.trst_in;
//     // method ext_tck = jtag_clk.tck_in;
//     // method ext_tdi = tdi_in._write;
//     // method ext_tms = tms_in._write;
//     method ext_tdo = tdo_out;

//     method int_tdi = tdi_in;
//     method int_tms = tms_in;
//     // method int_tdo = tdo_out._write;

//     // interface tck_out = jtag_clk.tck_out;
//     // interface trst_out = jtag_clk.trst_out;

//     // interface tdo_clk = jtag_clk.tdo_clk;
//     // interface tdo_rst = jtag_clk.tdo_rst;

// endmodule

endpackage
