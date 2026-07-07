package TestBSCANNested;

import StmtFSM :: *;
import Connectable :: *;
import GetPut :: *;
import BuildVector :: *;
import Clocks :: *;

import TestHelper :: *;

import BlueJ :: *;
import GLBL :: *;
import JTAG_SIME2 :: *;
import JTAG_TB :: *;

`define IR_WIDTH 8

interface MyJTAGSystem_ifc;
    method ActionValue#(Bit#(32)) myreg_read();
endinterface

module [JTAGSystem#(1, `IR_WIDTH)] myJTAGSystem(MyJTAGSystem_ifc);

    jtag_meta_config(0, 'b00000010111, 'h04);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(0);
    jtag_rst_to_idcode();
    jtag_enable_debug();

    //we expect this module to be clocked/reset by tck and trst
    Reg#(Bit#(32))                my_reg_value <- mkReg('hDEADBEEF);
    JTAGRegAccess_ifc#(Bit#(32))  my_reg       <- jtag_reg_rw(my_reg_value, 'h02);

    //blocks if no value loaded into register
    method myreg_read = my_reg.updated;

endmodule

(* synthesize *)
module mkNestedTAP#(Clock tdo_clk, Reset tdo_rst)(JTAGSystem_ifc#(MyJTAGSystem_ifc));
    let jtag_sys <- build_jtag_system(myJTAGSystem, tdo_clk, tdo_rst);
    return jtag_sys;
endmodule

function Bit#(TAdd#(2, TMul#(2, w))) bscan_tunnel_sequence(Bit#(w) tms_vec, Bit#(w) tdi_vec);
    Bit#(TAdd#(2, TMul#(2, w))) payload = 0;

    // Mode 0 carries one TMS/TDI pair for every tunneled JTAG clock.
    payload[0] = 0;
    for(Integer i = 0; i < valueof(w); i = i + 1) begin
        payload[1 + 2 * i] = tms_vec[valueof(w) - 1 - i];
        payload[2 + 2 * i] = tdi_vec[valueof(w) - 1 - i];
    end

    return payload;
endfunction

function Stmt bscan_tunnel_jtag_reset(
    Wire#(Bit#(1)) tck,
    Wire#(Bit#(1)) tms,
    Wire#(Bit#(1)) tdi
);
    return jtag_dr(tck, tms, tdi, bscan_tunnel_sequence(6'b111110, 6'b0));
endfunction

function Stmt bscan_tunnel_jtag_ir(
    Wire#(Bit#(1))        tck,
    Wire#(Bit#(1))        tms,
    Wire#(Bit#(1))        tdi,
    JTAGInstruction_t#(w) instr
)
    provisos(
        Add#(w1, 1, w)
    );
    Bit#(w1) z = 0;
    Bit#(TAdd#(w, 6)) tms_v = {4'b1100, z, 3'b110};
    Bit#(TAdd#(w, 6)) tdi_v = {4'b0000, reverseBits(instr), 2'b00};
    return jtag_dr(tck, tms, tdi, bscan_tunnel_sequence(tms_v, tdi_v));
endfunction

function Stmt bscan_tunnel_jtag_dr(
    Wire#(Bit#(1)) tck,
    Wire#(Bit#(1)) tms,
    Wire#(Bit#(1)) tdi,
    Bit#(w)        inp
)
    provisos(
        Add#(w1, 1, w)
    );
    Bit#(w1) z = 0;
    Bit#(TAdd#(w, 6)) tms_v = {4'b100, z, 3'b110};
    Bit#(TAdd#(w, 6)) tdi_v = {4'b0000, reverseBits(inp), 2'b00};
    return jtag_dr(tck, tms, tdi, bscan_tunnel_sequence(tms_v, tdi_v));
endfunction

(* synthesize *)
module [Module] mkTestBSCANNested(TestHandler);

    //required for simulation of Xilinx IP (this handles driving BSCANE2)
    let glbl <- vMkGLBL;

    Wire#(Bit#(1)) wtck     <- mkWire;
    Wire#(Bit#(1)) wtrst    <- mkWire;
    Wire#(Bit#(1)) ext_tdi  <- mkWire;
    Wire#(Bit#(1)) ext_tms  <- mkWire;
    Wire#(Bit#(1)) ext_tdo  <- mkBypassWire;

    Reg#(Bit#(32)) rOut     <- mkRegU;
    Bit#(32) expected_update = 32'h12345678;

    //handles clocking
    let jtag_stim <- mkJTAGShim();

    let tck         = jtag_stim.tck_out;

    //xilinx JTAG simulation primitives
    let jtag_sime2 <- mkJTAG_SIME2("xcku3p", clocked_by tck);
    
    let bscan_cfg = BSCANE2_Config { p_DISABLE_JTAG: False, p_JTAG_CHAIN: 3 };
    let bscane2 <- mkBSCANE2(bscan_cfg, clocked_by tck);
    let tunnel <- mkBSCAN2JTAG(bscane2, clocked_by bscane2.bscan_tck, reset_by noReset);
    let nested_tap <- mkNestedTAP(tunnel.tdo_clk, tunnel.tdo_rst, clocked_by tunnel.tck, reset_by tunnel.rst);
    let tdo_tunnel <- mkNullCrossingWire(bscane2.bscan_tck, nested_tap.tdo,
                                         clocked_by tunnel.tdo_clk, reset_by tunnel.tdo_rst);

    Reg#(Bool) saw_update_tck <- mkReg(False, clocked_by tunnel.tck, reset_by noReset);

    //testbench jtag wires to jtag stimulator
    mkConnection(toGet(wtck),               toPut(jtag_stim.ext_tck));
    mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(ext_tdi),            toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(ext_tms),            toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(ext_tdo)));

    //correctly clocked signals to hard jtag tap
    mkConnection(toGet(jtag_stim.int_tms),  toPut(jtag_sime2.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(jtag_sime2.tdi));
    mkConnection(toGet(jtag_sime2.tdo),     toPut(jtag_stim.int_tdo));

    //connect nested tap to BSCANE2
    mkConnection(toGet(tunnel.tms), toPut(nested_tap.tms));
    mkConnection(toGet(tunnel.tdi), toPut(nested_tap.tdi));

    rule forward_nested_tdo;
        tunnel.tdo(tdo_tunnel);
    endrule

    //this only fires when the user register behind the nested tap is updated
    rule capture_update if(!saw_update_tck);
        let v <- nested_tap.device_ifc.myreg_read();
        saw_update_tck <= True;
        if(v != expected_update) begin
            $display("ERROR: nested TAP update mismatch: got %0x expected %0x", v, expected_update);
        end
    endrule

    Stmt s = seq
        $display("Hello");
        delay(10050);

        jtag_reset(wtck, ext_tms, ext_tdi);
        jtag_ir(wtck, ext_tms, ext_tdi, c_INSTR_BYPASS);
        jtag_idle(wtck, ext_tms, ext_tdi, 10);

        jtag_ir(wtck, ext_tms, ext_tdi, c_INSTR_IDCODE);
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
        $display("IDCODE: %0x", rOut);

        jtag_ir(wtck, ext_tms, ext_tdi, c_INSTR_USER3);
        jtag_dr(wtck, ext_tms, ext_tdi, 8'h00);
        jtag_idle(wtck, ext_tms, ext_tdi, 2);

        bscan_tunnel_jtag_reset(wtck, ext_tms, ext_tdi);
        bscan_tunnel_jtag_ir(wtck, ext_tms, ext_tdi, 8'h02);
        bscan_tunnel_jtag_dr(wtck, ext_tms, ext_tdi, expected_update);
        jtag_idle(wtck, ext_tms, ext_tdi, 10);

    endseq;

    FSM f <- mkFSM(s);
    method go = f.start;
    method done = f.done;

endmodule

endpackage
