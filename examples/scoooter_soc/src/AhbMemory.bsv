package AhbMemory;

import GetPut :: *;
import FIFOF :: *;
import BRAM :: *;
import DefaultValue :: *;

import BlueFabric :: *;

interface AhbBootRom_ifc#(numeric type addr_w, numeric type data_w);
    interface AhbSlaveFabric_ifc#(addr_w, data_w) s_ahb;
endinterface

module mkAhbBootRom(AhbBootRom_ifc#(32, 32));
    BRAM_Configure cfg_memory = defaultValue;
    cfg_memory.memorySize   = 'h0400;
    cfg_memory.latency      = 1;
    cfg_memory.loadFormat   = tagged Hex "../bootrom/boot.hex";

    BRAM1Port#(Bit#(10), Bit#(32))  i_memory    <- mkBRAM1Server(cfg_memory);
    AhbSlave_ifc#(32, 32)           i_ahb       <- mkAhbSlave(False);
    FIFOF#(Bool)                    f_error     <- mkSizedFIFOF(2);

    rule r_request;
        let request <- i_ahb.request.get;
        Bool valid = request.address < 'h0000_1000;
        i_memory.portA.request.put(BRAMRequest { 
            write: False, 
            responseOnWrite: False, 
            address: request.address[11:2], 
            datain: 0 
        });
        f_error.enq(!valid || request.write);
    endrule

    rule r_response;
        let data <- i_memory.portA.response.get;
        let error = f_error.first;
        f_error.deq;
        i_ahb.response.put(AhbResponse_t { 
            read_data: error ? 0 : data, 
            slave_error: error 
        });
    endrule

    interface s_ahb = i_ahb.fabric;
endmodule

interface AhbRam_ifc#(numeric type addr_w, numeric type data_w);
    interface AhbSlaveFabric_ifc#(addr_w, data_w) s_ahb;
endinterface

function Bit#(4) ahb_write_strobe(AhbRequest_t#(32, 32) request);
    case(request.size)
        AHB_BYTE:     return 4'b0001 << request.address[1:0];
        AHB_HALFWORD: return 4'b0011 << {request.address[1], 1'b0};
        default:      return 4'b1111;
    endcase
endfunction

module mkAhbRam(AhbRam_ifc#(32, 32));
    BRAM_Configure cfg_memory = defaultValue;
    cfg_memory.memorySize   = 'h4000;
    cfg_memory.latency      = 1;

    BRAM1PortBE#(Bit#(14), Bit#(32), 4) i_memory    <- mkBRAM1ServerBE(cfg_memory);
    AhbSlave_ifc#(32, 32)               i_ahb       <- mkAhbSlave(False);
    FIFOF#(Bool)                        f_error     <- mkSizedFIFOF(2);

    rule r_request;
        let request <- i_ahb.request.get;
        Bool valid = request.address < 'h0001_0000;
        i_memory.portA.request.put(BRAMRequestBE { 
            writeen: valid && request.write ? ahb_write_strobe(request) : 0, 
            responseOnWrite: True, 
            address: request.address[15:2], 
            datain: request.write_data 
        });
        f_error.enq(!valid);
    endrule

    rule r_response;
        let data <- i_memory.portA.response.get;
        let error = f_error.first;
        f_error.deq;
        i_ahb.response.put(AhbResponse_t { 
            read_data: error ? 0 : data, 
            slave_error: error 
        });
    endrule

    interface s_ahb = i_ahb.fabric;
endmodule

endpackage
