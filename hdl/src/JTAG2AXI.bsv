package JTAG2AXI;

import GetPut :: *;
import ClientServer :: *;

import BlueJ :: *;
import BlueAXI :: *;

interface JTAG2AXIL_ifc#(numeric type aw, numeric type dw);

    interface IJTAG_ifc scan;

    interface AXI4_Lite_Master_Rd_Fab#(aw, dw) m_axil_rd;
    interface AXI4_Lite_Master_Wr_Fab#(aw, dw) m_axil_wr;
endinterface

module [Module] mkJTAG2AXI#(Clock axi_clk, Reset axi_rstn)(JTAG2AXIL_ifc#(aw, dw));
    /*
        Translates bus requests and responses from a JTAG data scan register into 
        AXI4Lite transactions. Supports one outstanding transaction.
    */

    JTAG_BusAdapterCore_ifc#(aw, dw)    i_jtag_bus <- mkJTAG_BusAdapterCore(axi_clk, axi_rstn);
    AXI4_Lite_Master_Rd#(aw, dw)        i_m_rd     <- mkAXI4_Lite_Master_Rd(1, clocked_by axi_clk, reset_by axi_rstn);
    AXI4_Lite_Master_Wr#(aw, dw)        i_m_wr     <- mkAXI4_Lite_Master_Wr(1, clocked_by axi_clk, reset_by axi_rstn);

    rule r_request;
        let req <- i_jtag_bus.bus.request.get;
        if(req.write)
            i_m_wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                addr: req.addr,
                data: req.data,
                strb: req.strb,
                prot: unpack(0)
            });
        else
            i_m_rd.request.put(AXI4_Lite_Read_Rq_Pkg {
                addr: req.addr,
                prot: unpack(0)
            });
    endrule

    rule r_read_response;
        let rsp <- i_m_rd.response.get;
        BusResponseCode_t resp = (rsp.resp == AXI4_Lite_Types::OKAY) ? JTAG_BusAdapter::OKAY : ERROR;
        i_jtag_bus.bus.response.put(
            BusResponse_t { data: rsp.data, resp: resp }
        );
    endrule

    rule r_write_response;
        let rsp <- i_m_wr.response.get;
        BusResponseCode_t resp = (rsp.resp == AXI4_Lite_Types::OKAY) ? JTAG_BusAdapter::OKAY : ERROR;
        i_jtag_bus.bus.response.put(
            BusResponse_t { data: 0, resp: resp }
        );
    endrule

    interface scan = i_jtag_bus.scan;
    interface m_axil_rd  = i_m_rd.fab;
    interface m_axil_wr  = i_m_wr.fab;

endmodule

endpackage