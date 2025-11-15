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
    method Bit#(32) user_reg0();
    interface Client#(BusRequest#(32, 32), BusResponse#(32)) bus;
endinterface

module [JTAGSystem#(2, `IR_WIDTH)] oocdJTAGSystem#(Clock bus_clk, Reset bus_rst)(MyJTAGSystem_ifc);

    JTAG_TAP_Config_t#(2, `IR_WIDTH) jtag_config = JTAG_TAP_Config_t {
        idcode_man: 'h3A7,
        idcode_part: 'h04,
        idcode_ver: 0,
        //could not get OpenOCD with remote bitbang to work when TDO is delayed..
        reg_tdo: False,
        debug: True,
        instrs: vec(
            'h02,   //dummy register
            'hDE    //bus adapter register
        ),
        instr_idcode: 0, //IDCODE instruction
        reset_idcode_not_bypass: True //reset to idcode not bypass
    };
    
    JTAG_Reg_ifc#(Bit#(32)) reg0 <- mkJTAGReg('hBEEFAFFE);
    JTAG_BusAdapter_ifc#(32, 32) ifc <- mkJTAG_BusAdapter(bus_clk, bus_rst);

    setTAPConfig(jtag_config);
    addJTAGReg(reg0);
    addJTAGReg(ifc.jtag_bus_ctrl);

    method user_reg0 if(reg0.wr_o()) = reg0.reg_o;

    interface bus = ifc.bus;

endmodule

(* synthesize *)
module mkTAP#(Clock tdo_clk, Reset tdo_rst, Clock bus_clk, Reset bus_rst)(JTAGSystem_ifc#(MyJTAGSystem_ifc));
    let jtag_sys <- buildJTAGSystem(oocdJTAGSystem(bus_clk, bus_rst), tdo_clk, tdo_rst);
    return jtag_sys;
endmodule

(* synthesize *)
module [Module] mkTestOOCD(TestHandler);

    let bus_clk <- mkAbsoluteClock(0, 2);
    let bus_rst <- mkAsyncResetFromCR(2, bus_clk);

    //for sampling TDO at the correct time, does not work with registered TDO output of the TAP
    //but since this driver is only for simulation, accept this for now
    JTAG_TDO_Delay#(1) tdo_delay = ?;
    let oocd_driver <- mkJTAG_Driver_OOCD(tdo_delay, clocked_by bus_clk, reset_by bus_rst);
    JTAG_Stim_ifc jtag_stim <- mkJTAGShim(clocked_by bus_clk, reset_by bus_rst);
    
    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;
    let tck_inv = jtag_stim.tdo_clk;
    let trst_inv = jtag_stim.tdo_rst;

    let tap <- mkTAP(tck_inv, trst_inv, bus_clk, bus_rst, clocked_by tck, reset_by trst);

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
    mkConnection(toGet(jtag_stim.ext_tdo),      toPut(oocd_driver.ext_tdo));
    
    mkConnection(toGet(jtag_stim.int_tms),  toPut(tap.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(tap.tdi));
    mkConnection(toGet(tap.tdo),            toPut(jtag_stim.int_tdo));

    rule rbus_req;
        let req <- tap.device_ifc.bus.request.get();
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
        tap.device_ifc.bus.response.put(BusResponse { data: resp });
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