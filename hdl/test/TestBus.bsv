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

`define IR_WIDTH 8

interface MyJTAGSystem_ifc;
    method ActionValue#(Bit#(32)) user_reg0();
    interface Client#(BusRequest#(32, 32), BusResponse#(32)) bus_client;
endinterface

module [JTAGSystem#(2, `IR_WIDTH)] myJTAGSystem#(Clock bus_clk, Reset bus_rst)(MyJTAGSystem_ifc);

    JTAG_TAP_Config_t#(2, `IR_WIDTH) jtag_config = JTAG_TAP_Config_t {
        idcode_man: 'b00000010111,
        idcode_part: 'h04,
        idcode_ver: 0,
        reg_tdo: True, //tdo is registered (on falling tck) in real applications
        instrs: vec(
            'h02, //dummy register
            'hDE //bus control register
        ),
        debug: True,
        instr_idcode: 0,
        reset_idcode_not_bypass: True //reset to idcode not bypass
    };

    JTAG_Reg_ifc#(Bit#(32)) reg0 <- mkJTAGReg('hC0DEAFFE);
    JTAG_BusAdapter_ifc#(32, 32) ifc <- mkJTAG_BusAdapter(bus_clk, bus_rst);

    setTAPConfig(jtag_config);
    addJTAGReg(reg0);
    addJTAGReg(ifc.jtag_bus_ctrl);

    method user_reg0 if(reg0.wr_o()) = actionvalue return reg0.reg_o(); endactionvalue;

    interface bus_client = ifc.bus;
        
endmodule

(* synthesize *)
module mkDUT#(Clock tdo_clk, Reset tdo_rst, Clock bus_clk, Reset bus_rst)(JTAGSystem_ifc#(MyJTAGSystem_ifc));
    let jtag_sys <- buildJTAGSystem(myJTAGSystem(bus_clk, bus_rst), tdo_clk, tdo_rst);
    return jtag_sys;
endmodule

(* synthesize *)
module [Module] mkTestBus(TestHandler);

    let bus_clk <- mkAbsoluteClock(0, 2);
    let bus_rst <- mkAsyncResetFromCR(2, bus_clk);

    let jtag_stim <- mkJTAGShim(clocked_by bus_clk, reset_by bus_rst);

    Wire#(Bit#(1)) wtck <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) wtrst <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) ext_tdi <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) ext_tms <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) ext_tdo <- mkBypassWire(clocked_by bus_clk, reset_by bus_rst);

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
    Reg#(Bit#(32)) rCount <- mkRegU(clocked_by bus_clk, reset_by bus_rst);

    Reg#(JTAG_BusControl_Simple#(32, 32)) rg_req <- mkRegU(clocked_by bus_clk, reset_by bus_rst);
    Reg#(Bit#(68)) rOut <- mkReg(0, clocked_by bus_clk, reset_by bus_rst);

    //test memory connected to bus ifc
    BRAM_Configure bram_cfg = defaultValue;
    bram_cfg.memorySize = 32;
    bram_cfg.loadFormat = tagged Hex "test_data.txt";

    BRAM1Port#(Bit#(32), Bit#(32)) bram <- mkBRAM1Server(bram_cfg, clocked_by bus_clk, reset_by bus_rst);

    //synchronization of FSM start and stop
    SyncPulseIfc        pStart          <- mkSyncPulseFromCC(bus_clk);
    SyncPulseIfc        pStopped        <- mkSyncPulseToCC(bus_clk, bus_rst);
    SyncBitIfc#(Bool)   syncStarted     <- mkSyncBitToCC(bus_clk, bus_rst);


    rule rbus_req;
        let req <- dut.device_ifc.bus_client.request.get();
        $display("[%0t] Got Bus request: ", $time, fshow(req));
        bram.portA.request.put(BRAMRequest {
            write: req.write_not_read,
            responseOnWrite: False,
            address: req.addr,
            datain: req.data
        });
    endrule

    rule rbus_resp;
        let resp <- bram.portA.response.get();
        dut.device_ifc.bus_client.response.put(BusResponse { data: resp });
        $display("[%0t] BRAM response: ", $time, fshow(resp));
    endrule

    Stmt s = seq
        syncStarted.send(True);
        jtag_reset(rCount, wtck, ext_tms, ext_tdi);
        jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'h02);
        jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut, 1);
        $display("[%0t] JTAG returned %08X", $time, rOut);
        delay(10);
        jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'hDE);
        action
            JTAG_BusControl_Simple#(32, 32) rq = defaultValue;
            rq.write_not_read = False;
            rq.addr = 'h08;
            rg_req <= rq;
        endaction
        $display("Request: %0X ~ ", rg_req, fshow(rg_req));
        jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, pack(rg_req), rOut, 1);
        //some idling to let data arrive
        jtag_idle(rCount, wtck, ext_tms, ext_tdi, 4);
        jtag_dr_ret_del(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 0, rOut, 1);
        $display("[%0t] ", $time, fshow(JTAG_BusControl_Simple#(32,32)'(unpack(rOut))));
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