package TestOOCD;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import BRAM :: *;
import StmtFSM :: *;
import ClientServer :: *;
import BuildVector :: *;
import Connectable :: *;

import BlueJ :: *;
import ClockUtil :: *;

`define IR_WIDTH 8

(* synthesize *)
module mkTAP#(Clock tdo_clk, Reset tdo_rst)(JTAG_TAP_Controller_ifc#(1));

    let tck <- exposeCurrentClock;
    let trst <- exposeCurrentReset;

    JTAG_TAP_Config_t#(1, `IR_WIDTH) jtag_config = JTAG_TAP_Config_t {
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
    
    JTAG_Reg_ifc#(Bit#(32)) reg0 <- mkJTAGReg('hC0DEAFFE, clocked_by tck, reset_by trst);
    JTAG_TAP_Controller_ifc#(1) ifc <- mkJTAG_TAP_Controller(
        jtag_config,
        vec(as_read_only(reg0.tdo)),
        tdo_clk, tdo_rst,
        clocked_by tck, reset_by trst
    );

    mkConnection(reg0.tdi, ifc.int_tdi);
    jtagConnect(ifc.tap_ctrl, reg0.ctrl, 0);

    return ifc;
endmodule

module mkTestOOCD();

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

    let tap <- mkTAP(tck_inv, trst_inv, clocked_by tck, reset_by trst);

    JTAG_BusAdapter_ifc#(32, 32) jtag_bus_adapter <- mkJTAG_BusAdapter(bus_clk, bus_rst);

    //test memory connected to bus ifc
    BRAM_Configure bram_cfg = defaultValue;
    bram_cfg.memorySize = 32;
    bram_cfg.loadFormat = tagged Hex "test_data.txt";

    BRAM1Port#(Bit#(32), Bit#(32)) bram <- mkBRAM1Server(bram_cfg, clocked_by bus_clk, reset_by bus_rst);

    mkConnection(jtag_bus_adapter.jtag_bus_ctrl.tdi, jtag_stim.int_tdi);
    jtagConnect(tap.tap_ctrl, jtag_bus_adapter.jtag_bus_ctrl.ctrl, 1);

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
        let req <- dut.bus.request.get();
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
        dut.bus.response.put(BusResponse { data: resp });
        $display("[%0t] BRAM response: ", $time, fshow(resp));
    endrule

    Stmt s = seq
        await(oocd_driver.connected());
        await(!oocd_driver.connected());
    endseq;

    mkAutoFSM(s, clocked_by bus_clk, reset_by bus_rst);

endmodule

endpackage