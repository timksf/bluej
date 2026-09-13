package TestBus;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import BRAM :: *;
import StmtFSM :: *;
import ClientServer :: *;
import BuildVector :: *;
import Connectable :: *;

import TestHelper :: *;

import BlueJ :: *;
import ClockUtil :: *;
import JTAG_TB :: *;

`define IR_WIDTH 8

interface MyJTAGSystem_ifc;
    method ActionValue#(Bit#(32)) user_reg0();
    interface Client#(BusRequest_t#(32, 32), BusResponse_t#(32)) bus_client;
endinterface

module [JTAGSystem#(2, `IR_WIDTH)] myJTAGSystem#(Clock bus_clk, Reset bus_rst)(MyJTAGSystem_ifc);

    jtag_meta_config(0, 'b00000010111, 'h04);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(0);
    jtag_rst_to_idcode();
    jtag_enable_debug();

    Reg#(Bit#(32))                reg0_value <- mkReg('hC0DEAFFE);
    JTAGRegAccess_ifc#(Bit#(32))  reg0       <- jtag_reg_rw(reg0_value, 'h02);
    JTAG_BusAdapter_ifc#(32, 32)  ifc        <- mkJTAG_BusAdapter('hDE, bus_clk, bus_rst);

    method user_reg0 = reg0.updated;

    interface bus_client = ifc.bus;

endmodule

(* synthesize *)
module mkDUT#(Clock tdo_clk, Reset tdo_rst, Clock bus_clk, Reset bus_rst)(JTAGSystem_ifc#(MyJTAGSystem_ifc));
    let jtag_sys <- build_jtag_system(myJTAGSystem(bus_clk, bus_rst), tdo_clk, tdo_rst);
    return jtag_sys;
endmodule

(* synthesize *)
module [Module] mkTestBus(TestHandler);

    let bus_clk <- mkAbsoluteClock(0, 2);
    let bus_rst <- mkAsyncResetFromCR(2, bus_clk);

    let jtag_stim <- mkJTAGShim(clocked_by bus_clk, reset_by bus_rst);

    Wire#(Bit#(1)) wtck     <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) wtrst    <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) ext_tdi  <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) ext_tms  <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) ext_tdo  <- mkBypassWire(clocked_by bus_clk, reset_by bus_rst);

    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;
    let tck_inv = jtag_stim.tdo_clk;
    let trst_inv = jtag_stim.tdo_rst;

    let dut <- mkDUT(tck_inv, trst_inv, bus_clk, bus_rst, clocked_by tck, reset_by trst);

    //connect TAP controller to stimulus
    mkConnection(toGet(wtck),               toPut(jtag_stim.ext_tck));
    mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(ext_tdi),            toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(ext_tms),            toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(ext_tdo)));
    
    mkConnection(toGet(jtag_stim.int_tms),  toPut(dut.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(dut.tdi));
    mkConnection(toGet(dut.tdo),            toPut(jtag_stim.int_tdo));
    
    //testbench counter

    Reg#(JTAG_BusControl_t#(32, 32)) rg_req           <- mkRegU(clocked_by bus_clk, reset_by bus_rst);
    Reg#(Bit#(76))                    rg_out           <- mkReg(0, clocked_by bus_clk, reset_by bus_rst);
    Reg#(Bool)                        rg_hold_response <- mkReg(False, clocked_by bus_clk, reset_by bus_rst);

    //test memory connected to bus ifc
    BRAM_Configure bram_cfg = defaultValue;
    bram_cfg.memorySize = 32;
    bram_cfg.loadFormat = tagged Hex "../test/test_data.txt";

    BRAM1Port#(Bit#(32), Bit#(32)) bram <- mkBRAM1Server(bram_cfg, clocked_by bus_clk, reset_by bus_rst);

    //synchronization of FSM start and stop
    SyncPulseIfc        pStart          <- mkSyncPulseFromCC(bus_clk);
    SyncPulseIfc        pStopped        <- mkSyncPulseToCC(bus_clk, bus_rst);
    SyncBitIfc#(Bool)   syncStarted     <- mkSyncBitToCC(bus_clk, bus_rst);

    rule rbus_req;
        let req <- dut.device_ifc.bus_client.request.get();
        $display("[%0t] Got Bus request: ", $time, fshow(req));
        bram.portA.request.put(BRAMRequest {
            write: req.write,
            responseOnWrite: True,
            address: req.addr,
            datain: req.data
        });
        if(req.write && req.strb != 4'hF) begin
            $display("ERROR: write strobe mismatch: got %x expected f", req.strb);
            $finish(1);
        end
    endrule

    rule rbus_resp if(!rg_hold_response);
        let d <- bram.portA.response.get();
        dut.device_ifc.bus_client.response.put(BusResponse_t { data: d, resp: OKAY });
        $display("[%0t] BRAM response: ", $time, fshow(d));
    endrule

    function JTAG_BusControl_t#(32, 32) bus_request(
        Bool     write,
        Bit#(32) addr,
        Bit#(32) data,
        Bit#(4)  strb
    );
        let request = defaultValue;
        request.ignore = False;
        request.write  = write;
        request.addr   = addr;
        request.data   = data;
        request.strb   = strb;
        request.resp   = REQUEST;
        return request;
    endfunction

    function JTAG_BusControl_t#(32, 32) bus_poll();
        return defaultValue;
    endfunction

    function Action expect_status(String label, Bool busy, Bool dropped, Bool resp_valid);
        action
            JTAG_BusControl_t#(32, 32) status = unpack(rg_out);
            $display("[%0t] %s: ", $time, label, fshow(status));
            if(status.busy != busy || status.dropped != dropped || status.resp_valid != resp_valid || status.error) begin
                $display("ERROR: %s status mismatch", label);
                $finish(1);
            end
        endaction
    endfunction

    function Action expect_response(String label, Bit#(32) data);
        action
            JTAG_BusControl_t#(32, 32) response = unpack(rg_out);
            $display("[%0t] %s: ", $time, label, fshow(response));
            if(!response.resp_valid || response.busy || response.error || response.data != data) begin
                $display("ERROR: %s response mismatch: got %08x expected %08x", label, response.data, data);
                $finish(1);
            end
        endaction
    endfunction

    Stmt s = seq
        syncStarted.send(True);
        jtag_reset(wtck, ext_tms, ext_tdi);
        jtag_ir(wtck, ext_tms, ext_tdi, 8'h02);
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rg_out, 1);
        $display("[%0t] JTAG returned %08X", $time, rg_out);
        delay(10);
        jtag_ir(wtck, ext_tms, ext_tdi, 8'hDE);
        action
            rg_hold_response <= True;
            rg_req           <= bus_request(False, 'h08, 0, 0);
        endaction
        $display("Request: ", fshow(rg_req));
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, pack(rg_req), rg_out, 1);

        // A second request while the first is pending is dropped.
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, pack(rg_req), rg_out, 1);
        expect_status("busy", True, False, False);
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, pack(bus_poll()), rg_out, 1);
        expect_status("dropped", True, True, False);

        rg_hold_response <= False;
        jtag_idle(wtck, ext_tms, ext_tdi, 4);
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, pack(bus_poll()), rg_out, 1);
        expect_response("read", 32'h34FAD707);

        rg_req <= bus_request(True, 'h08, 32'hDEADBEEF, 4'hF);
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, pack(rg_req), rg_out, 1);
        jtag_idle(wtck, ext_tms, ext_tdi, 4);
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, pack(bus_poll()), rg_out, 1);
        expect_status("write", False, False, True);

        rg_req <= bus_request(False, 'h08, 0, 0);
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, pack(rg_req), rg_out, 1);
        jtag_idle(wtck, ext_tms, ext_tdi, 4);
        jtag_dr_ret_del(wtck, ext_tms, ext_tdi, ext_tdo, pack(bus_poll()), rg_out, 1);
        expect_response("write readback", 32'hDEADBEEF);
        delay(10);
    endseq;

    FSM f <- mkFSM(s, clocked_by bus_clk, reset_by bus_rst);

    rule start if(pStart.pulse());
        f.start();
    endrule

    rule stopped if(f.done());
        pStopped.send();
    endrule

    method go = pStart.send;
    method done = pStopped.pulse && syncStarted.read;

endmodule

endpackage
