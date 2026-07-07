package JTAG_Xilinx;

import Vector :: *;
import Clocks :: *;
import BuildVector :: *;
import DefaultValue :: *;

import BSCANE2 :: *;
import JTAG_Types :: *;
import JTAG_TAP :: *;
import BUFGCE :: *;

//these are the same for 7-series and ultrascale (though some devices have larger IRs)
Bit#(6) c_INSTR_USER1   = 6'b000010;
Bit#(6) c_INSTR_USER2   = 6'b000011;
Bit#(6) c_INSTR_USER3   = 6'b100010;
Bit#(6) c_INSTR_USER4   = 6'b100011;

Bit#(6) c_INSTR_IDCODE  = 6'b001001;
Bit#(6) c_INSTR_NOOP    = 6'b010100;
Bit#(6) c_INSTR_BYPASS  = 6'b111111;

Bit#(32) c_BSCAN2JTAG_IDCODE = 32'h04900601;

interface BSCAN2JTAG_ifc;

    method Bit#(1) tms();
    method Bit#(1) tdi();
    method Action tdo(Bit#(1) b);

    interface Clock tck;
    interface Reset rst;

    interface Clock tdo_clk;
    interface Reset tdo_rst;

endinterface

//this is only useful for situations in which tck is not source from BSCANE2
module mkBSCANE2_BlueJ_#(BSCANE2_Config cfg, Clock tck_inv, Vector#(n, ReadOnly#(Bit#(1))) tdo_up)(JTAG_TAP_Controller_ifc#(1));

    BSCANE2_ifc _int <- mkBSCANE2(cfg);
    //bscan.tck and tck are the same clocks, just not for bsc
    let tdo_bscane2 <- mkNullCrossingWire(_int.bscan_tck, tdo_up[0]);

    rule fwd_tdo;
        _int.tdo(tdo_bscane2);
    endrule

    //tms and tdi are supplied via simulation model, so no external inputs to this IP
    method tms(t) = noAction;
    method tdi(t) = noAction;
    //similarly, this IP does not provide a TDO output
    method tdo = 0;

    method int_tdi = _int.tdi;

    interface JTAG_Ctrl_Up_ifc tap_ctrl;
        method update = _int.update;
        method capture = _int.capture;
        method shift = _int.shift;
        
        interface select = vec(_int.sel);
    endinterface

endmodule

module connect_bscane2_to_bluej#(BSCANE2_ifc bscane2, JTAG_Ctrl_Dn_ifc jtag_target)(Empty);

    //this rule is in the tck domain
    rule rjctrl;
        jtag_target.update(bscane2.update());
        jtag_target.capture(bscane2.capture());
        jtag_target.shift(bscane2.shift());
        jtag_target.sel(bscane2.sel());
    endrule

endmodule

module mkBSCAN2JTAG#(BSCANE2_ifc bscan)(BSCAN2JTAG_ifc);
    /*
        BSCAN-to-JTAG tunnel following the packet protocol used by
        eugene-tarassov/vivado-risc-v bscan2jtag.vhdl.

        The outer Xilinx TAP selects a USER data register.  The first selected
        DR scan after reset configures the number of bypass bits before the
        tunneled TAP.  Later selected DR scans contain prefix bits, a mode bit,
        and either TDI-only bits or TMS/TDI pairs for the tunneled JTAG port.
    */

    Reg#(Bit#(8)) tap_cnt <- mkReg(0);
    Reg#(Bool) tap_cnt_ok <- mkReg(False);
    Reg#(Bit#(8)) bit_cnt <- mkReg(0);
    Reg#(Bool) mode_reg <- mkReg(False);
    Reg#(Bit#(1)) tms_reg <- mkReg(0);
    Reg#(Bool) tms_ok <- mkReg(False);

    Reg#(Bit#(5)) id_cnt <- mkReg(0);
    Reg#(Bit#(1)) id_tdo <- mkReg(0);

    Wire#(Bit#(1)) jtag_tdo <- mkDWire(0);

    let tck_buf <- mkBUFGCE(defaultValue, tms_ok);
    MakeResetIfc inner_rst <- mkReset(0, True, tck_buf.clk_out);
    let tck_inv <- mkClockInverter(clocked_by tck_buf.clk_out, reset_by inner_rst.new_rst);
    let tdo_rst_inv <- mkAsyncReset(0, inner_rst.new_rst, tck_inv.slowClock);

    ReadOnly#(Bit#(1)) tms_crossed <- mkNullCrossingWire(tck_buf.clk_out, tms_reg);

    Bool id_en = (bscan.capture() || bscan.shift()) && bscan.sel() && !tap_cnt_ok;
    Bit#(1) bscan_tdo = id_en ? id_tdo : jtag_tdo;

    rule drive_bscan_tdo;
        bscan.tdo(bscan_tdo);
    endrule

    rule assert_inner_reset if(bscan.reset());
        inner_rst.assertReset();
    endrule

    rule tunnel_ctrl;
        if(bscan.reset()) begin
            tap_cnt_ok <= False;
        end
        else if(bscan.update() && bscan.sel()) begin
            tap_cnt_ok <= True;
        end

        if(!id_en) begin
            id_tdo <= 0;
            id_cnt <= 0;
        end
        else begin
            id_tdo <= c_BSCAN2JTAG_IDCODE[id_cnt];
            id_cnt <= id_cnt + 1;
        end

        if(bscan.capture() || bscan.update()) begin
            bit_cnt <= 0;
            mode_reg <= False;
            tms_reg <= 0;
            tms_ok <= False;
        end
        else if(bscan.shift() && bscan.sel()) begin
            if(!tap_cnt_ok) begin
                tap_cnt <= { bscan.tdi(), tap_cnt[7:1] };
            end
            else if(bscan.tms() == 1) begin
                bit_cnt <= 0;
                mode_reg <= False;
                tms_reg <= 0;
                tms_ok <= False;
            end
            else if(bit_cnt < tap_cnt) begin
                bit_cnt <= bit_cnt + 1;
            end
            else if(bit_cnt == tap_cnt) begin
                bit_cnt <= bit_cnt + 1;
                if(bscan.tdi() == 1) begin
                    mode_reg <= True;
                    tms_reg <= 0;
                    tms_ok <= True;
                end
            end
            else if(!mode_reg) begin
                if(!tms_ok) begin
                    tms_reg <= bscan.tdi();
                end
                tms_ok <= !tms_ok;
            end
        end
    endrule

    method tms = tms_crossed;
    method tdi = bscan.tdi;
    method tdo = jtag_tdo._write;

    interface tck = tck_buf.clk_out;
    interface rst = inner_rst.new_rst;

    interface tdo_clk = tck_inv.slowClock;
    interface tdo_rst = tdo_rst_inv;

endmodule

endpackage
