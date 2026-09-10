package TestOOCD;

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

`define IR_WIDTH 8

interface MyJTAGSystem_ifc;
    method ActionValue#(Bit#(32)) user_reg0();
    interface Client#(BusRequest_t#(32, 32), BusResponse_t#(32)) bus;
endinterface

module [JTAGSystem#(2, `IR_WIDTH)] oocdJTAGSystem#(Clock bus_clk, Reset bus_rst)(MyJTAGSystem_ifc);

    jtag_meta_config(0, 'h3A7, 'h04);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(0);
    jtag_rst_to_idcode();
    jtag_enable_debug();

    Reg#(Bit#(32))                reg0_value <- mkReg('hBEEFAFFE);
    JTAGRegAccess_ifc#(Bit#(32))  reg0       <- jtag_reg_rw(reg0_value, 'h02);
    JTAG_BusAdapter_ifc#(32, 32)  ifc        <- mkJTAG_BusAdapter('hDE, bus_clk, bus_rst);

    method user_reg0 = reg0.updated;

    interface bus = ifc.bus;

endmodule

(* synthesize *)
module mkTAP#(Clock tdo_clk, Reset tdo_rst, Clock bus_clk, Reset bus_rst)(JTAGSystem_ifc#(MyJTAGSystem_ifc));
    let jtag_sys <- build_jtag_system(oocdJTAGSystem(bus_clk, bus_rst), tdo_clk, tdo_rst);
    return jtag_sys;
endmodule

(* synthesize *)
module [Module] mkTestOOCD(TestHandler);

    let bus_clk <- mkAbsoluteClock(0, 2);
    let bus_rst <- mkAsyncResetFromCR(2, bus_clk);

    JTAG_TDO_Delay#(1) tdo_delay = ?;
    let oocd_driver <- mkJTAG_Driver_OOCD(tdo_delay, clocked_by bus_clk, reset_by bus_rst);
    JTAG_Stim_ifc jtag_stim <- mkJTAGShim(clocked_by bus_clk, reset_by bus_rst);
    
    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;
    let tck_inv = jtag_stim.tdo_clk;
    let trst_inv = jtag_stim.tdo_rst;

    let tap <- mkTAP(tck_inv, trst_inv, bus_clk, bus_rst, clocked_by tck, reset_by trst);
    let tdo_crossing <- mkJTAGTDONullCrossing(tap.tdo, tck_inv, trst_inv, clocked_by bus_clk, reset_by bus_rst);

    //test memory connected to bus ifc
    BRAM_Configure bram_cfg = defaultValue;
    bram_cfg.memorySize = 32;
    bram_cfg.loadFormat = tagged Hex "../test/test_data.txt";

    BRAM1Port#(Bit#(32), Bit#(32)) bram <- mkBRAM1Server(bram_cfg, clocked_by bus_clk, reset_by bus_rst);

    //synchronization of FSM start and stop
    SyncPulseIfc        pStart          <- mkSyncPulseFromCC(bus_clk);
    SyncPulseIfc        pStopped        <- mkSyncPulseToCC(bus_clk, bus_rst);
    SyncBitIfc#(Bool)   syncStarted     <- mkSyncBitToCC(bus_clk, bus_rst);

    //connect TAP to driver
    mkConnection(toGet(oocd_driver.ext_tck),    toPut(jtag_stim.ext_tck));
    // mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(oocd_driver.ext_tdi),    toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(oocd_driver.ext_tms),    toPut(jtag_stim.ext_tms));
    mkConnection(toGet(tdo_crossing.ext_tdo),   toPut(oocd_driver.ext_tdo));
    
    mkConnection(toGet(jtag_stim.int_tms),  toPut(tap.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(tap.tdi));

    rule rbus_req;
        let req <- tap.device_ifc.bus.request.get();
        $display("[%0t] Got Bus request: ", $time, fshow(req));
        bram.portA.request.put(BRAMRequest {
            write: req.write,
            responseOnWrite: True,
            address: req.addr,
            datain: req.data
        });
    endrule

    rule rbus_resp;
        let resp <- bram.portA.response.get();
        tap.device_ifc.bus.response.put(BusResponse_t { data: resp, resp: OKAY });
        $display("[%0t] BRAM response: ", $time, fshow(resp));
    endrule

    Stmt s = seq
        syncStarted.send(True);
        await(oocd_driver.connected());
        await(!oocd_driver.connected());
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
