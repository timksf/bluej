package RISCV_JTAG_DTM;

import Clocks :: *;
import GetPut :: *;
import ClientServer :: *;
import ModuleContext :: *;

import AXI4_Lite_Master :: *;

import JTAG_Reg :: *;
import JTAG_System :: *;
import JTAG_Types :: *;
import RISCV_DMI :: *;
import RISCV_DTM :: *;

interface RISCVJTAGDTMDevice_ifc#(numeric type abits);
    method Bool hard_reset;
    interface AXI4_Lite_Master_Rd_Fab#(32, 32) m_axi_rd;
    interface AXI4_Lite_Master_Wr_Fab#(32, 32) m_axi_wr;
endinterface

module [JTAGSystem#(2, 5)] riscv_jtag_dtm#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock axi_clk,
    Reset axi_rst
)(RISCVJTAGDTMDevice_ifc#(abits))
    provisos(
        Add#(7, abits_extra, abits),
        Add#(abits, abits_unused, 32),
        Add#(abits, 34, dmi_width),
        Add#(dmi_width, dmi_padding, 72),
        Add#(abits, register_padding, 72)
    );

    jtag_meta_config(tap_meta.idcode_ver, tap_meta.idcode_man, tap_meta.idcode_part);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(5'h01);
    jtag_rst_to_idcode;

    RISCVDTM_ifc#(abits) i_dtm <- liftModule(mkRISCVDTM);

    JTAG_Reg_ifc#(Bit#(32)) i_dtmcs_jtag <- mkJTAGRegR(i_dtm.dtmcs, tagged WithReset 0);
    JTAGRegAccess_ifc#(Bit#(32)) i_dtmcs_access <- jtag_endpoint(i_dtmcs_jtag, 5'h10);

    JTAG_Reg_ifc#(DMI_Scan_t#(abits)) i_dmi_jtag <- mkRISCVDMIScanReg(i_dtm);
    JTAGRegAccess_ifc#(DMI_Scan_t#(abits)) _dmi_access <- jtag_endpoint(i_dmi_jtag, 5'h11);

    SyncFIFOIfc#(DMI_Request_t#(abits))  f_dmi_request  <- mkSyncFIFOFromCC(2, axi_clk);
    SyncFIFOIfc#(DMI_Response_t#(abits)) f_dmi_response <- mkSyncFIFOToCC(2, axi_clk, axi_rst);
    SyncPulseIfc p_hard_reset <- mkSyncPulseFromCC(axi_clk);

    RISCVDMIAXI4Lite_ifc#(abits) i_dmi_axi <- mkRISCVDMIAXI4Lite(clocked_by axi_clk, reset_by axi_rst);

    rule r_update_dtmcs;
        let value <- i_dtmcs_access.updated;
        i_dtm.update_dtmcs(value);
    endrule

    rule r_send_request;
        let request <- i_dtm.dmi_bus.request.get;
        f_dmi_request.enq(request);
    endrule

    rule r_receive_response;
        i_dtm.dmi_bus.response.put(f_dmi_response.first);
        f_dmi_response.deq;
    endrule

    rule r_cross_hard_reset if(i_dtm.hard_reset);
        p_hard_reset.send;
    endrule

    rule r_axi_request;
        i_dmi_axi.dmi.request.put(f_dmi_request.first);
        f_dmi_request.deq;
    endrule

    rule r_axi_response;
        let response <- i_dmi_axi.dmi.response.get;
        f_dmi_response.enq(response);
    endrule

    method hard_reset = p_hard_reset.pulse;
    interface m_axi_rd = i_dmi_axi.m_rd;
    interface m_axi_wr = i_dmi_axi.m_wr;

endmodule

module [Module] mkRISCVJTAGDTMAXI4Lite#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock tdo_clk,
    Reset tdo_rst,
    Clock axi_clk,
    Reset axi_rst
)(JTAGSystem_ifc#(RISCVJTAGDTMDevice_ifc#(abits)))
    provisos(
        Add#(7, abits_extra, abits),
        Add#(abits, abits_unused, 32),
        Add#(abits, 34, dmi_width),
        Add#(dmi_width, dmi_padding, 72),
        Add#(abits, register_padding, 72)
    );

    let system <- build_jtag_system(
        riscv_jtag_dtm(tap_meta, axi_clk, axi_rst),
        tdo_clk,
        tdo_rst
    );
    return system;

endmodule

endpackage
