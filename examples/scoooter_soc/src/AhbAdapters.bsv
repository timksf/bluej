package AhbAdapters;

import ClientServer :: *;
import FIFOF :: *;
import GetPut :: *;
import Memory :: *;

import Ahb :: *;
import BlueFabric :: *;
import JTAG_BusAdapter :: *;

function AhbSize_t memory_ahb_size(Bit#(4) byteen);
    return (byteen == 4'b0001 || byteen == 4'b0010 || byteen == 4'b0100 || byteen == 4'b1000) ? AHB_BYTE :
        (byteen == 4'b0011 || byteen == 4'b1100) ? AHB_HALFWORD : AHB_WORD;
endfunction

interface MemoryAhbAdapter_ifc;
    interface Server#(MemoryRequest#(32, 32), MemoryResponse#(32)) memory;
    interface AhbMasterFabric_ifc#(32, 32) m_ahb;
endinterface

module mkMemoryAhbAdapter(MemoryAhbAdapter_ifc);
    AhbMaster_ifc#(32, 32) i_ahb <- mkAhbMaster(2);
    FIFOF#(MemoryRequest#(32, 32)) f_request <- mkFIFOF;
    FIFOF#(MemoryResponse#(32)) f_response <- mkFIFOF;

    rule r_request;
        let request = f_request.first;
        f_request.deq;
        i_ahb.request.put(ahb_single_request(AhbRequest_t {
            address: request.address,
            write: request.write,
            write_data: request.data,
            size: memory_ahb_size(request.byteen),
            protection: ahb_protection(
                AHB_DATA_ACCESS, AHB_PRIVILEGED_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE
            ),
            lock: False
        }));
    endrule

    rule r_response;
        let response <- i_ahb.response.get;
        f_response.enq(MemoryResponse { data: response.read_data });
    endrule

    interface memory = toGPServer(f_request, f_response);
    interface m_ahb = i_ahb.fabric;
endmodule

interface JtagAhbAdapter_ifc;
    interface Server#(BusRequest#(32, 32), BusResponse#(32)) bus;
    interface AhbMasterFabric_ifc#(32, 32) m_ahb;
endinterface

module mkJtagAhbAdapter(JtagAhbAdapter_ifc);
    AhbMaster_ifc#(32, 32) i_ahb <- mkAhbMaster(2);
    FIFOF#(BusRequest#(32, 32)) f_request <- mkFIFOF;
    FIFOF#(BusResponse#(32)) f_response <- mkFIFOF;

    rule r_request;
        let request = f_request.first;
        f_request.deq;
        i_ahb.request.put(ahb_single_request(AhbRequest_t {
            address: request.addr,
            write: request.write_not_read,
            write_data: request.data,
            size: AHB_WORD,
            protection: ahb_protection(
                AHB_DATA_ACCESS, AHB_PRIVILEGED_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE
            ),
            lock: False
        }));
    endrule

    rule r_response;
        let response <- i_ahb.response.get;
        f_response.enq(BusResponse { data: response.read_data });
    endrule

    interface bus = toGPServer(f_request, f_response);
    interface m_ahb = i_ahb.fabric;
endmodule

endpackage
