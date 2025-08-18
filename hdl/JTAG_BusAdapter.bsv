package JTAG_BusAdapter;

import Clocks :: *;
import FIFO :: *;
import ClientServer :: *;

import JTAG_Types :: *;
import JTAG_Reg :: *;

typedef struct {
    Bool write_not_read;
    Bit#(aw) addr;
    Bit#(dw) data;
} BusRequest#(numeric type aw, numeric type dw) deriving(FShow, Eq, Bits);

typedef struct {
    Bit#(dw) data;
} BusResponse#(numeric type dw) deriving(FShow, Eq, Bits);

typedef union tagged {
    BusRequest#(aw, dw) Request;
    struct {
        Bool error;
        Bool valid;
        BusResponse#(dw) resp;
    } Response;
} JTAG_BusControl#(numeric type aw, numeric type dw) deriving(Eq, Bits, FShow);

interface JTAG_BusAdapter_ifc#(numeric type aw, numeric type dw);
    interface JTAG_Reg_ifc#(JTAG_BusControl#(aw, dw)) jtag_bus_ctrl;
    interface Client#(BusRequest#(aw, dw), BusResponse#(dw)) bus;
endinterface

module mkJTAG_BusAdapter#(Clock bus_clk, Reset bus_rst)(JTAG_BusAdapter_ifc#(aw, dw));

    SyncFIFOIfc#(BusRequest#(aw, dw)) f_sync_req <- mkSyncFIFOFromCC(2, bus_clk);
    SyncFIFOIfc#(Bit#(dw)) f_sync_resp <- mkSyncFIFOToCC(2, bus_clk, bus_rst);

    Reg#(JTAG_BusControl#(aw, dw)) jrg_ctrl_i <- mkReg(tagged Response { error: False, valid: False, resp: ? });

    //this jtag register is used both for issuing requests and reading responses
    //requests are shifted in while responses are "captured"
    JTAG_Reg_ifc#(JTAG_BusControl#(aw, dw)) jrg_bus_ctrl <- mkJTAGReg(jrg_ctrl_i);

    rule rqueue_req if(jrg_bus_ctrl.wr_o() &&& jrg_bus_ctrl.reg_o() matches tagged Request .bus_req);
        f_sync_req.enq(bus_req);
        //ToDo scheduling fine?
        jrg_ctrl_i <= tagged Response {
            error: False,
            valid: False,
            resp: ?
        };
    endrule

    rule rdeq_resp;
        //when a response arrives from the bus, update the input to the jtag register
        f_sync_resp.deq;
        jrg_ctrl_i <= tagged Response {
            error: False, //ToDo
            valid: True, //ToDo, when false?
            resp: BusResponse { data: f_sync_resp.first }
        };
    endrule

    interface jtag_bus_ctrl = jrg_bus_ctrl.ctrl;
    interface bus = toGPClient(toGet(f_sync_req), toPut(f_sync_resp));

endmodule

endpackage