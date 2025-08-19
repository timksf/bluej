package TestBus;

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
module mkTAP(JTAG_TAP_Controller_ifc#(2));

    let tck <- exposeCurrentClock;
    let trst <- exposeCurrentReset;

    JTAG_TAP_Config_t#(2, `IR_WIDTH) jtag_config = JTAG_TAP_Config_t {
        idcode_man: 'b00000010111,
        idcode_part: 'h04,
        idcode_ver: 0,
        instrs: vec(
            'h02, //dummy register
            'hDE //bus control register
        )
    };
    
    JTAG_TAP_Controller_ifc#(2) ifc <- mkJTAG_TAP_Controller(jtag_config, 0, True, clocked_by tck, reset_by trst);

    return ifc;
endmodule

(* synthesize *)
module mkDUT#(Clock bus_clk, Reset bus_rst)(JTAG_BusAdapter_ifc#(32, 32));

    // let bus_clk <- exposeCurrentClock;
    // let bus_rst <- exposeCurrentReset;

    JTAG_BusAdapter_ifc#(32, 32) ifc <- mkJTAG_BusAdapter(bus_clk, bus_rst);

    return ifc;
endmodule

module mkTestBus();

    let bus_clk <- mkAbsoluteClock(0, 6);
    let bus_rst <- mkAsyncResetFromCR(2, bus_clk);

    let jtag_stim <- mkJTAGShim(clocked_by bus_clk, reset_by bus_rst);

    Wire#(Bit#(1)) wtck <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) wtrst <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) ext_tdi <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) ext_tms <- mkWire(clocked_by bus_clk, reset_by bus_rst);
    Wire#(Bit#(1)) ext_tdo <- mkBypassWire(clocked_by bus_clk, reset_by bus_rst);

    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;

    let tap <- mkTAP(clocked_by tck, reset_by trst);
    
    //JTAG registers
    JTAG_Reg_ifc#(Bit#(32)) reg0 <- mkJTAGReg('hC0DEAFFE, clocked_by tck, reset_by trst);
    JTAG_BusAdapter_ifc#(32, 32) dut <- mkDUT(bus_clk, bus_rst, clocked_by tck, reset_by trst);

    mkConnection(reg0.tdi, jtag_stim.int_tdi);
    jtagConnect(tap.tap_ctrl, reg0.ctrl, 0);

    mkConnection(dut.jtag_bus_ctrl.tdi, jtag_stim.int_tdi);
    jtagConnect(tap.tap_ctrl, dut.jtag_bus_ctrl.ctrl, 1);

    //connect TAP controller to stimulus
    mkConnection(toGet(wtck),               toPut(jtag_stim.ext_tck));
    mkConnection(toGet(wtrst),              toPut(jtag_stim.ext_trst));
    mkConnection(toGet(ext_tdi),            toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(ext_tms),            toPut(jtag_stim.ext_tms));
    mkConnection(toGet(jtag_stim.ext_tdo),  toPut(asReg(ext_tdo)));
    
    mkConnection(toGet(jtag_stim.int_tms),  toPut(tap.tms));
    mkConnection(toGet(jtag_stim.int_tdi),  toPut(tap.tdi));
    mkConnection(toGet(tap.tdo),            toPut(jtag_stim.int_tdo));
    
    //testbench counter
    Reg#(Bit#(32)) rCount <- mkRegU(clocked_by bus_clk, reset_by bus_rst);

    Reg#(JTAG_BusControl#(32, 32)) rg_req <- mkRegU(clocked_by bus_clk, reset_by bus_rst);
    Reg#(Bit#(66)) rOut <- mkReg(0, clocked_by bus_clk, reset_by bus_rst);

    //test memory connected to bus ifc
    BRAM_Configure bram_cfg = defaultValue;
    bram_cfg.memorySize = 32;
    bram_cfg.loadFormat = tagged Hex "test_data.txt";

    BRAM1Port#(Bit#(32), Bit#(32)) bram <- mkBRAM1Server(bram_cfg, clocked_by bus_clk, reset_by bus_rst);

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
        jtag_reset(rCount, wtck, ext_tms, ext_tdi);
        jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'h02);
        jtag_dr_ret(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 'h0, rOut);
        $display("[%0t] JTAG returned %08X", $time, rOut);
        delay(10);
        jtag_ir(rCount, wtck, ext_tms, ext_tdi, 8'hDE);
        rg_req <= tagged Request BusRequest { write_not_read: False, addr: 'h08, data: ? };
        jtag_dr_ret(rCount, wtck, ext_tms, ext_tdi, ext_tdo, pack(rg_req), rOut);
        //some idling to let data arrive
        jtag_idle(rCount, wtck, ext_tms, ext_tdi, 4);
        jtag_dr_ret(rCount, wtck, ext_tms, ext_tdi, ext_tdo, 0, rOut);
        $display(fshow(JTAG_BusControl#(32,32)'(unpack(rOut))));
        delay(10);
    endseq;

    mkAutoFSM(s, clocked_by bus_clk, reset_by bus_rst);

endmodule

endpackage