package FPGATop;

import BRAM :: *;
import Clocks :: *;

import BlueJ :: *;

`define N_LEDS 4

(* always_enabled *)
interface FPGATest_ifc;

    (* result = "LED" *)
    method Bit#(`N_LEDS) leds;

endinterface

typedef struct {
    Bit#(w) blink_div;
    Bit#(n) blink_en;
} JTAG_LED_Ctrl#(numeric type n, numeric type w) deriving (Eq, Bits, FShow);

(* synthesize *)
module mkFPGATestSimpleTop(FPGATest_ifc);
    /*
        Instantiates BSCANE2, connects JTAG bus adapter to configurable user register slot
        and provides access to some 2 ported BRAM.
        On the other side of the BRAM sits a small FSM that controls LEDs based on contents of the BRAM.
        The FSM is notified of an updated configuration in the BRAM or it periodically polls from the BRAM.
    */
    let bscan_cfg = BSCANE2_Config {
        p_DISABLE_JTAG: False,
        p_JTAG_CHAIN: 3
    };

    let sys_clk <- exposeCurrentClock;
    let sys_rst <- exposeCurrentReset;
    
    let bscane2 <- mkBSCANE2(bscan_cfg);

    let tck = bscane2.bscan_tck;
    let trst <- mkAsyncResetFromCR(2, tck);

    Reg#(JTAG_LED_Ctrl#(`N_LEDS, 32)) rg_led_ctrl <- mkRegU;
    JTAG_Reg_ifc#(JTAG_LED_Ctrl#(`N_LEDS, 32)) jtag_led_ctrl <- mkJTAG_Reg_Sync(unpack('hDEADBEEF), sys_clk, sys_rst, clocked_by tck, reset_by trst);

    Reg#(Bit#(32)) rg_div <- mkReg(0);
    Reg#(Bit#(`N_LEDS)) rg_leds <- mkReg(0);

    connect_bscane2_to_bluej(bscane2, jtag_led_ctrl.ctrl);

    //tck domain
    rule rjtag_data;
        jtag_led_ctrl.tdi(bscane2.tdi());
        bscane2.tdo(jtag_led_ctrl.tdo());
    endrule
    
    (* descending_urgency="rupd_ctrl, rdiv" *)
    rule rupd_ctrl if(jtag_led_ctrl.wr_o());
        rg_led_ctrl <= jtag_led_ctrl.reg_o();
        rg_div <= 0;
        $display("Updating control to: ", fshow(jtag_led_ctrl.reg_o()));
    endrule

    rule rdiv;
        if(rg_div < zeroExtend(rg_led_ctrl.blink_div))
            rg_div <= rg_div + 1;
        else
            rg_div <= 0;
    endrule

    rule rtoggle if(rg_div == zeroExtend(rg_led_ctrl.blink_div));
        //turn off disabled leds and toggle enabled leds
        rg_leds <= (rg_leds ^ rg_led_ctrl.blink_en) & rg_led_ctrl.blink_en;
    endrule

    method leds = rg_leds;

endmodule

(* synthesize *)
module mkFPGATestSimplestTop(FPGATest_ifc);
    let bscan_cfg = BSCANE2_Config {
        p_DISABLE_JTAG: False,
        p_JTAG_CHAIN: 3
    };

    let sys_clk <- exposeCurrentClock;
    let sys_rst <- exposeCurrentReset;
    
    let bscane2 <- mkBSCANE2(bscan_cfg);

    let tck = bscane2.bscan_tck;
    let trst <- mkAsyncResetFromCR(2, tck);

    JTAG_Reg_ifc#(Bit#(32)) jreg <- mkJTAGRegR(unpack('hBAADBEEF), tagged WithReset 'hC0DEAFFE, clocked_by tck, reset_by trst);

    Reg#(Bit#(29)) rg_count <- mkReg(0);

    connect_bscane2_to_bluej(bscane2, jreg.ctrl);

    //tck domain, BSCANE2 data connection
    rule rjtag_data;
        jreg.tdi(bscane2.tdi());
        bscane2.tdo(jreg.tdo());
    endrule
    
    rule rdiv;
        rg_count <= rg_count + 1;
    endrule

    method leds = rg_count[28:28-`N_LEDS+1];

endmodule

// module mkFPGATestBusTop();
//     /*
//         Instantiates BSCANE2, connects JTAG bus adapter to configurable user register slot
//         and provides access to some 2 ported BRAM.
//         On the other side of the BRAM sits a small FSM that controls LEDs based on contents of the BRAM.
//         The FSM is notified of an updated configuration in the BRAM or it periodically polls from the BRAM.
//     */

//     let bscane2 <- mkBSCANE2_BlueJ(bscan_cfg, tck_inv, vec(as_read_only(user_reg.tdo)));

//     JTAG_BusAdapter_ifc#(32, 32) ifc <- mkJTAG_BusAdapter(bus_clk, bus_rst);

//     BRAM2Port#(Bit#(32), Bit#(32)) bram <- mkBRAM2Server(bram_cfg, clocked_by bus_clk, reset_by bus_rst);


// endmodule

endpackage