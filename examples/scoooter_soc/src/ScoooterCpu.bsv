`ifndef SCOOOTER_CPU_CONFIG
`define SCOOOTER_CPU_CONFIG

`define SCOOOTER_CFG_IFU_INST              1
`define SCOOOTER_CFG_ISSUE_WIDTH           1
`define SCOOOTER_CFG_RESET_VECTOR          0
`define SCOOOTER_CFG_BASE_IMEM             'h00000
`define SCOOOTER_CFG_SIZE_IMEM             'h10000
`define SCOOOTER_CFG_BASE_DMEM             'h10000
`define SCOOOTER_CFG_SIZE_DMEM             'h10000
`define SCOOOTER_CFG_ROB_BANK_DEPTH        2
`define SCOOOTER_CFG_INST_WINDOW           2
`define SCOOOTER_CFG_MUL_DIV_STRATEGY      1
`define SCOOOTER_CFG_NUM_ALU               1
`define SCOOOTER_CFG_NUM_MUL_DIV           0
`define SCOOOTER_CFG_NUM_BRANCH            1
`define SCOOOTER_CFG_RS_DEPTH_ALU          1
`define SCOOOTER_CFG_RS_DEPTH_MEM          1
`define SCOOOTER_CFG_RS_DEPTH_CSR          1
`define SCOOOTER_CFG_RS_DEPTH_MUL_DIV      1
`define SCOOOTER_CFG_RS_DEPTH_BRANCH       1
`define SCOOOTER_CFG_STORE_BUFFER_DEPTH    4
`define SCOOOTER_CFG_BRANCH_PREDICTOR      0
`define SCOOOTER_CFG_BTB_INDEX_BITS        0
`define SCOOOTER_CFG_PHT_INDEX_BITS        4
`define SCOOOTER_CFG_BRANCH_HISTORY_BITS   0

`endif

`ifndef SCOOOTER_CONFIG_ONLY
package ScoooterCpu;

import FIFOF :: *;
import GetPut :: *;
import ClientServer :: *;
import Vector :: *;

import BlueFabric :: *;
import Ahb :: *;
import Config :: *;
import Dave :: *;
import Interfaces :: *;

typedef enum { FetchResponse, DataReadResponse, DataWriteResponse } CpuResponseKind deriving(Bits, Eq);

interface ScoooterCpu_ifc;
    interface AhbMasterFabric_ifc#(32, 32) m_ahb;
    interface DebugHartIFC debug_hart;
    method Action sw_interrupt(Bool value);
    method Action timer_interrupt(Bool value);
    method Action external_interrupt(Bool value);
endinterface

module mkScoooterCpu(ScoooterCpu_ifc);

    DaveIFC i_core <- mkDave;

    AhbMaster_ifc#(32, 32) i_ahb <- mkAhbMaster(4);

    FIFOF#(CpuResponseKind) f_response_kind <- mkSizedFIFOF(4);

    //IDs are constant in this design
    FIFOF#(Bit#(TLog#(1)))              f_fetch_id      <- mkSizedFIFOF(4);
    FIFOF#(Bit#(TAdd#(TLog#(1), 1)))    f_data_read_id  <- mkSizedFIFOF(4);
    FIFOF#(Bit#(TAdd#(TLog#(1), 1)))    f_data_write_id <- mkSizedFIFOF(4);

    function AhbSize_t write_size(Bit#(4) strobe);
        return
            (strobe == 4'b0001 || strobe == 4'b0010 || strobe == 4'b0100 || strobe == 4'b1000) ? AHB_BYTE :
            (strobe == 4'b0011 || strobe == 4'b1100) ? AHB_HALFWORD :
            AHB_WORD;
    endfunction

    (* descending_urgency = "r_fetch_request, r_data_read_request, r_data_write_request" *)
    rule r_fetch_request;
        let request <- i_core.imem_r.request.get;
        i_ahb.request.put(ahb_single_request(AhbRequest_t {
            address: pack(tpl_1(request)), write: False, write_data: 0,
            size: AHB_WORD, protection: ahb_protection(
                AHB_DATA_ACCESS, AHB_PRIVILEGED_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE
            ), lock: False
        }));
        f_response_kind.enq(FetchResponse);
        f_fetch_id.enq(tpl_2(request));
    endrule

    rule r_data_read_request;
        let request <- i_core.dmem_r.request.get;
        i_ahb.request.put(ahb_single_request(AhbRequest_t {
            address: pack(tpl_1(request)), write: False, write_data: 0,
            size: AHB_WORD, protection: ahb_protection(
                AHB_DATA_ACCESS, AHB_PRIVILEGED_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE
            ), lock: False
        }));
        f_response_kind.enq(DataReadResponse);
        f_data_read_id.enq(tpl_2(request));
    endrule

    rule r_data_write_request;
        let request <- i_core.dmem_w.request.get;
        i_ahb.request.put(ahb_single_request(AhbRequest_t {
            address: pack(tpl_1(request)), write: True, write_data: tpl_2(request),
            size: write_size(tpl_3(request)), protection: ahb_protection(
                AHB_DATA_ACCESS, AHB_PRIVILEGED_ACCESS, AHB_NON_BUFFERABLE, AHB_NON_CACHEABLE
            ), lock: False
        }));
        f_response_kind.enq(DataWriteResponse);
        f_data_write_id.enq(tpl_4(request));
    endrule

    rule r_response;
        let response <- i_ahb.response.get;
        case(f_response_kind.first)
            FetchResponse: begin
                f_fetch_id.deq;
                i_core.imem_r.response.put(tuple2(response.read_data, f_fetch_id.first));
            end
            DataReadResponse: begin
                f_data_read_id.deq;
                i_core.dmem_r.response.put(tuple2(response.read_data, f_data_read_id.first));
            end
            DataWriteResponse: begin
                f_data_write_id.deq;
                i_core.dmem_w.response.put(f_data_write_id.first);
            end
        endcase
        f_response_kind.deq;
    endrule

    interface m_ahb         = i_ahb.fabric;
    interface debug_hart    = i_core.debug_harts[0][0];

    method Action sw_interrupt(Bool value);
        i_core.sw_int(replicate(replicate(value)));
    endmethod

    method Action timer_interrupt(Bool value);
        i_core.timer_int(replicate(replicate(value)));
    endmethod

    method Action external_interrupt(Bool value);
        i_core.ext_int(replicate(replicate(value)));
    endmethod
endmodule

endpackage
`endif
