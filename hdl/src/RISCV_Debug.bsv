package RISCV_Debug;

import Clocks :: *;
import Connectable :: *;

import AXI4_Lite_Master :: *;

import JTAG_System :: *;
import JTAG_Types :: *;
import RISCV_DM :: *;
import RISCV_JTAG_DTM :: *;

interface RISCVDebugDevice_ifc;
    interface AXI4_Lite_Master_Rd_Fab#(32, 32) m_system_rd;
    interface AXI4_Lite_Master_Wr_Fab#(32, 32) m_system_wr;

    interface RISCVDMHartPort_ifc hart;

    method Bool ndmreset;
    method Bool dmactive;
    method Bool dtm_hard_reset;
endinterface

module [Module] mkRISCVJTAGDebug#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock tdo_clk,
    Reset tdo_rst,
    Clock debug_clk,
    Reset debug_rst
)(JTAGSystem_ifc#(RISCVDebugDevice_ifc));

    JTAGSystem_ifc#(RISCVJTAGDTMDevice_ifc#(7)) i_dtm <-
        mkRISCVJTAGDTMAXI4Lite(tap_meta, tdo_clk, tdo_rst, debug_clk, debug_rst);
    RISCVDM_ifc i_dm <- mkRISCVDM(clocked_by debug_clk, reset_by debug_rst);

    mkConnection(i_dtm.device_ifc.m_axi_rd, i_dm.s_dmi_rd);
    mkConnection(i_dtm.device_ifc.m_axi_wr, i_dm.s_dmi_wr);

    method tms = i_dtm.tms;
    method tdi = i_dtm.tdi;
    method tdo = i_dtm.tdo;

    interface RISCVDebugDevice_ifc device_ifc;
        interface m_system_rd = i_dm.m_system_rd;
        interface m_system_wr = i_dm.m_system_wr;
        interface hart = i_dm.hart;

        method ndmreset = i_dm.ndmreset;
        method dmactive = i_dm.dmactive;
        method dtm_hard_reset = i_dtm.device_ifc.hard_reset;
    endinterface

endmodule

endpackage
