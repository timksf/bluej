package JTAG_BusAdapter;

import Clocks :: *;
import FIFO :: *;
import GetPut :: *;
import ClientServer :: *;
import DefaultValue :: *;

import JTAG_Types :: *;
import JTAG_Reg :: *;
import JTAG_System :: *;

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
        Bool              error;
        Bool              valid;
        BusResponse#(dw) resp;
    } Response;
} JTAG_BusControl#(numeric type aw, numeric type dw) deriving(Eq, Bits, FShow);

//unified bit layout for request and response -> easier decoding
//has 1 more bit since there is no sharing of positions
typedef struct {
    Bool     ignore; //we need to be able to perform a DRSCAN without issuing another request
    Bool     error;
    Bool     resp_valid;
    Bool     write_not_read;
    Bit#(aw) addr;
    Bit#(dw) data;
} JTAG_BusControl_Simple#(numeric type aw, numeric type dw) deriving(Eq, Bits, FShow);

instance DefaultValue#(JTAG_BusControl_Simple#(aw, dw));
    function JTAG_BusControl_Simple#(aw, dw) defaultValue = JTAG_BusControl_Simple {
        ignore:         True,
        error:          False,
        resp_valid:     False,
        write_not_read: False,
        addr:           0,
        data:           0
    };
endinstance

interface JTAG_BusAdapter_ifc#(numeric type aw, numeric type dw);
    interface Client#(BusRequest#(aw, dw), BusResponse#(dw)) bus;
endinterface

/*
    Very simple module providing access to some abstract bus interface in another clock domain.
    - no bus error support (yet)
    - no support for congestion detection
    ...
*/
module [JTAGSystem#(n, iw)] mkJTAG_BusAdapter#(JTAGInstruction_t#(iw) instr, Clock bus_clk, Reset bus_rst)(JTAG_BusAdapter_ifc#(aw, dw));

    SyncFIFOIfc#(BusRequest#(aw, dw))      f_sync_req  <- mkSyncFIFOFromCC(2, bus_clk);
    SyncFIFOIfc#(BusResponse#(dw))         f_sync_resp <- mkSyncFIFOToCC(2, bus_clk, bus_rst);

    Reg#(JTAG_BusControl_Simple#(aw, dw)) jrg_ctrl_i <- mkRegU;

    //this jtag register is used both for issuing requests and reading responses
    //requests are shifted in while responses are "captured"
    //ignore scans must not write jrg_ctrl_i, so this needs a custom endpoint rather than jtag_reg_rw
    JTAG_Reg_ifc#(JTAG_BusControl_Simple#(aw, dw))      jrg_bus_ctrl_jtag <- mkJTAGReg(jrg_ctrl_i);
    JTAGRegAccess_ifc#(JTAG_BusControl_Simple#(aw, dw)) jrg_bus_ctrl      <- jtag_endpoint(jrg_bus_ctrl_jtag, instr);

    //we queue the request first as that would get lost otherwise, the response can remain in the fifo another cycle
    (* descending_urgency="rqueue_req, rdeq_resp" *)
    rule rqueue_req;
        let request <- jrg_bus_ctrl.updated();
        //TODO: could insert address checking w/ error indication
        if(!request.ignore) begin
            let bus_req = BusRequest {
                write_not_read: request.write_not_read,
                addr:           request.addr,
                data:           request.data
            };
            f_sync_req.enq(bus_req);
            let response = jrg_ctrl_i;
            response.error      = False;
            response.resp_valid = False; //indicates finished request
            jrg_ctrl_i <= response;
        end
    endrule

    rule rdeq_resp;
        //when a response arrives from the bus, update the input to the jtag register
        f_sync_resp.deq;
        let response = jrg_ctrl_i;
        response.data       = f_sync_resp.first.data;
        response.resp_valid = True;
        response.error      = False; //could indicate bus error here
        jrg_ctrl_i <= response;
    endrule

    interface bus = toGPClient(toGet(f_sync_req), toPut(f_sync_resp));

endmodule

endpackage
