package JTAG_BusAdapter;

import Clocks :: *;
import FIFO :: *;
import GetPut :: *;
import ClientServer :: *;
import DefaultValue :: *;

import JTAG_Types :: *;
import JTAG_Reg :: *;
import JTAG_System :: *;

typedef enum { OKAY, ERROR, INVALID, REQUEST } BusResponseCode_t deriving(FShow, Eq, Bits);

typedef struct {
    Bool                write;
    Bit#(aw)            addr;
    Bit#(dw)            data;
    Bit#(TDiv#(dw, 8))  strb;
} BusRequest_t#(numeric type aw, numeric type dw) deriving(FShow, Eq, Bits);

typedef struct {
    Bit#(dw)            data;
    BusResponseCode_t   resp;
} BusResponse_t#(numeric type dw) deriving(FShow, Eq, Bits);

//unified bit layout for request and response -> easier decoding
typedef struct {
    Bool                ignore;         //perform a drscan without issuing another request
    Bool                error;          //a response != OKAY was returned
    Bool                resp_valid;     //a response was returned
    Bool                busy;           //internal use only
    Bool                dropped;        //a drscan was performed while the adapter waited for a response
    Bool                write;
    Bit#(aw)            addr;
    Bit#(dw)            data;
    Bit#(TDiv#(dw, 8))  strb;
    BusResponseCode_t   resp;
} JTAG_BusControl_t#(numeric type aw, numeric type dw) deriving(Eq, Bits, FShow);

instance DefaultValue#(JTAG_BusControl_t#(aw, dw));
    function JTAG_BusControl_t#(aw, dw) defaultValue = JTAG_BusControl_t {
        ignore:         True,
        error:          False,
        resp_valid:     False,
        busy:           False,
        dropped:        False,
        write:          False,
        addr:           0,
        data:           0,
        strb:           0,
        resp:           INVALID
    };
endinstance

interface JTAG_BusAdapterCore_ifc#(numeric type aw, numeric type dw);
    interface IJTAG_ifc scan;
    interface Client#(BusRequest_t#(aw, dw), BusResponse_t#(dw)) bus;
endinterface

interface JTAG_BusAdapter_ifc#(numeric type aw, numeric type dw);
    interface Client#(BusRequest_t#(aw, dw), BusResponse_t#(dw)) bus;
endinterface

module mkJTAG_BusAdapterCore#(Clock bus_clk, Reset bus_rst)(JTAG_BusAdapterCore_ifc#(aw, dw));
    SyncFIFOIfc#(BusRequest_t#(aw, dw))  f_sync_req  <- mkSyncFIFOFromCC(1, bus_clk);
    SyncFIFOIfc#(BusResponse_t#(dw))     f_sync_resp <- mkSyncFIFOToCC(1,   bus_clk, bus_rst);

    Reg#(JTAG_BusControl_t#(aw, dw)) jrg_ctrl_i <- mkReg(defaultValue);

    //this jtag register is used both for issuing requests and reading responses
    //requests are shifted in while responses are "captured"
    JTAG_Reg_ifc#(JTAG_BusControl_t#(aw, dw)) jrg_bus_ctrl <- mkJTAGReg(jrg_ctrl_i);

    function Bool is_request(JTAG_BusControl_t#(aw, dw) request);
        return !request.ignore && request.resp == REQUEST;
    endfunction

    //we queue the request first as that would get lost otherwise, the response can remain in the fifo another cycle
    (* descending_urgency="r_queue_req, r_deq_resp" *)
    (* descending_urgency="r_drop_req,  r_deq_resp" *)
    rule r_queue_req if(jrg_bus_ctrl.wr_o() && is_request(jrg_bus_ctrl.reg_o()) && !jrg_ctrl_i.busy);
        let request = jrg_bus_ctrl.reg_o();
        let bus_req = BusRequest_t {
            write: request.write,
            addr:  request.addr,
            data:  request.data,
            strb:  request.strb
        };
        f_sync_req.enq(bus_req);
        let response = jrg_ctrl_i;
        response.error      = False;
        response.resp_valid = False; //indicates finished request
        response.busy       = True;
        response.dropped    = False;
        jrg_ctrl_i <= response;
    endrule

    //drscan despite running request
    rule r_drop_req if(jrg_bus_ctrl.wr_o() && is_request(jrg_bus_ctrl.reg_o()) && jrg_ctrl_i.busy);
        jrg_ctrl_i.dropped <= True; //this weird syntax work as long as we only write one field in a rule
    endrule

    //CAPTURE-DR snapshots this response into the shift register.  Clear the
    //valid flag afterwards so a later access cannot mistake it for a new
    //completion.  A response arriving on the same TCK takes precedence.
    (* descending_urgency = "r_deq_resp, r_consume_resp" *)
    rule r_consume_resp if(jrg_bus_ctrl.cap_o() && jrg_ctrl_i.resp_valid);
        jrg_ctrl_i.resp_valid <= False;
    endrule

    rule r_deq_resp;
        //when a response arrives from the bus, update the input to the jtag register
        f_sync_resp.deq;
        let response = jrg_ctrl_i;
        response.data       = f_sync_resp.first.data;
        response.resp       = f_sync_resp.first.resp;
        response.resp_valid = True;
        response.ignore     = False;
        response.error      = f_sync_resp.first.resp != OKAY;
        response.busy       = False;
        jrg_ctrl_i <= response;
    endrule
    
    interface scan  = jrg_bus_ctrl.scan;
    interface bus   = toGPClient(toGet(f_sync_req), toPut(f_sync_resp));
endmodule

module [JTAGSystem#(n, iw)] mkJTAG_BusAdapter#(JTAGInstruction_t#(iw) instr, Clock bus_clk, Reset bus_rst)(JTAG_BusAdapter_ifc#(aw, dw));
    JTAG_BusAdapterCore_ifc#(aw, dw)               i_core       <- mkJTAG_BusAdapterCore(bus_clk, bus_rst);
    jtag_scan_endpoint(i_core.scan, instr);

    interface bus = i_core.bus;
endmodule

endpackage
