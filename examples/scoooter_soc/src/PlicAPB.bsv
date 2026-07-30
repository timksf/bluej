package PlicAPB;

import GetPut :: *;
import ClientServer :: *;
import Vector :: *;

import BlueFabric :: *;
import Config :: *;
import Interfaces :: *;
import PLIC :: *;
import Types :: *;

interface PlicAPB_ifc;
    (* always_enabled *) method Action interrupt_sources(Vector#(16, Bool) value);
    (* always_ready *) method Vector#(NUM_HARTS, Bool) external_interrupts;
    interface ApbSlaveFabric_ifc#(32, 32, 0) s_apb;
endinterface

module mkPlicAPB(PlicAPB_ifc);
    PLICIFC#(16, 8) i_plic <- mkPLIC;
    ApbSlave_ifc#(32, 32, 0) i_apb <- mkApbSlave(True);
    Reg#(Bool) rg_pending <- mkReg(False);
    Reg#(Bool) rg_write <- mkReg(False);

    rule r_request if(!rg_pending);
        let request <- i_apb.request.get;
        Bit#(TAdd#(TLog#(NUM_CPU), 1)) transaction_id = 0;
        if(request.write) begin
            i_plic.memory_bus.mem_w.request.put(tuple4(unpack(truncate(request.address)), request.write_data, request.write_strobe, transaction_id));
        end
        else begin
            i_plic.memory_bus.mem_r.request.put(tuple2(unpack(truncate(request.address)), transaction_id));
        end
        rg_pending <= True;
        rg_write <= request.write;
    endrule

    rule r_response if(rg_pending);
        Bit#(32) read_data = 0;
        if(rg_write) begin
            let _ <- i_plic.memory_bus.mem_w.response.get;
        end
        else begin
            let response <- i_plic.memory_bus.mem_r.response.get;
            read_data = tpl_1(response);
        end
        i_apb.response.put(ApbResponse_t { read_data: read_data, slave_error: False, read_user: 0, response_user: 0 });
        rg_pending <= False;
    endrule

    method interrupt_sources = i_plic.interrupts_in;
    method external_interrupts = i_plic.ext_interrupts_out;
    interface s_apb = i_apb.fabric;
endmodule

endpackage
