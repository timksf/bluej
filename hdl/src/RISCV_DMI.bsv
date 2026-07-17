package RISCV_DMI;

import FIFOF :: *;
import GetPut :: *;
import ClientServer :: *;

import AXI4_Lite_Types :: *;
import AXI4_Lite_Master :: *;

typedef enum {
    DMI_NOP      = 2'b00,
    DMI_READ     = 2'b01,
    DMI_WRITE    = 2'b10,
    DMI_RESERVED = 2'b11
} DMI_Op_t deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(abits) address;
    Bit#(32)    data;
    DMI_Op_t    op;
} DMI_Scan_t#(numeric type abits) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(abits) address;
    Bit#(32)    data;
    DMI_Op_t    op;
    Bit#(1)     epoch;
} DMI_Request_t#(numeric type abits) deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(abits) address;
    Bit#(32)    data;
    Bool        error;
    Bit#(1)     epoch;
} DMI_Response_t#(numeric type abits) deriving(Bits, Eq, FShow);

interface RISCVDMIAXI4Lite_ifc#(numeric type abits);
    interface Server#(DMI_Request_t#(abits), DMI_Response_t#(abits)) dmi;
    interface AXI4_Lite_Master_Rd_Fab#(32, 32) m_rd;
    interface AXI4_Lite_Master_Wr_Fab#(32, 32) m_wr;
endinterface

function Bool axi_response_ok(AXI4_Lite_Response response);
    return response == OKAY || response == EXOKAY;
endfunction

module mkRISCVDMIAXI4Lite(RISCVDMIAXI4Lite_ifc#(abits))
    provisos(Add#(abits, address_padding, 32));

    AXI4_Lite_Master_Rd#(32, 32) i_axi_rd <- mkAXI4_Lite_Master_Rd(2);
    AXI4_Lite_Master_Wr#(32, 32) i_axi_wr <- mkAXI4_Lite_Master_Wr(2);

    FIFOF#(DMI_Request_t#(abits))  f_request  <- mkFIFOF;
    FIFOF#(DMI_Response_t#(abits)) f_response <- mkFIFOF;

    Reg#(Maybe#(DMI_Request_t#(abits))) rg_pending <- mkReg(tagged Invalid);

    rule r_issue_request if(rg_pending matches tagged Invalid);
        let request = f_request.first;
        f_request.deq;

        Bit#(32) byte_address = zeroExtend(request.address) << 2;
        if(request.op == DMI_READ) begin
            i_axi_rd.request.put(AXI4_Lite_Read_Rq_Pkg {
                addr: byte_address,
                prot: UNPRIV_SECURE_DATA
            });
            rg_pending <= tagged Valid request;
        end
        else if(request.op == DMI_WRITE) begin
            i_axi_wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                addr: byte_address,
                data: request.data,
                strb: '1,
                prot: UNPRIV_SECURE_DATA
            });
            rg_pending <= tagged Valid request;
        end
        else begin
            f_response.enq(DMI_Response_t {
                address: request.address,
                data:    0,
                error:   False,
                epoch:   request.epoch
            });
        end
    endrule

    rule r_read_response if(rg_pending matches tagged Valid .request &&& request.op == DMI_READ);
        let response <- i_axi_rd.response.get;
        f_response.enq(DMI_Response_t {
            address: request.address,
            data:    response.data,
            error:   !axi_response_ok(response.resp),
            epoch:   request.epoch
        });
        rg_pending <= tagged Invalid;
    endrule

    rule r_write_response if(rg_pending matches tagged Valid .request &&& request.op == DMI_WRITE);
        let response <- i_axi_wr.response.get;
        f_response.enq(DMI_Response_t {
            address: request.address,
            data:    0,
            error:   !axi_response_ok(response.resp),
            epoch:   request.epoch
        });
        rg_pending <= tagged Invalid;
    endrule

    interface Server dmi;
        interface request  = toPut(f_request);
        interface response = toGet(f_response);
    endinterface

    interface m_rd = i_axi_rd.fab;
    interface m_wr = i_axi_wr.fab;

endmodule

endpackage
