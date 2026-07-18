package RISCV_Debug;

import Clocks :: *;
import Connectable :: *;

import AXI4_Lite_Master :: *;

import JTAG_System :: *;
import JTAG_Types :: *;
import RISCV_DM :: *;
import RISCV_DTM :: *;

interface RISCVDebugDevice_ifc;
    interface AXI4_Lite_Master_Rd_Fab#(32, 32) m_system_rd;
    interface AXI4_Lite_Master_Wr_Fab#(32, 32) m_system_wr;

    interface RISCVDMHartPort_ifc hart;

    method Bool ndmreset;
    method Bool dmactive;
    method Bool dtm_hard_reset;
endinterface

module [JTAGSystem#(2, 5)] riscv_jtag_debug#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock debug_clk,
    Reset debug_rst
)(RISCVDebugDevice_ifc);

    jtag_meta_config(tap_meta.idcode_ver, tap_meta.idcode_man, tap_meta.idcode_part);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(5'h01);
    jtag_rst_to_idcode;

    RISCVDTMDevice_ifc#(7) i_dtm <- riscv_dtm(debug_clk, debug_rst);
    RISCVDM_ifc i_dm <- liftModule(mkRISCVDM(clocked_by debug_clk, reset_by debug_rst));

    mkConnection(i_dtm.m_axi_rd, i_dm.s_dmi_rd);
    mkConnection(i_dtm.m_axi_wr, i_dm.s_dmi_wr);

    interface m_system_rd = i_dm.m_system_rd;
    interface m_system_wr = i_dm.m_system_wr;
    interface hart = i_dm.hart;

    method ndmreset = i_dm.ndmreset;
    method dmactive = i_dm.dmactive;
    method dtm_hard_reset = i_dtm.hard_reset;

endmodule

module [Module] mkRISCVJTAGDebug#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock tdo_clk,
    Reset tdo_rst,
    Clock debug_clk,
    Reset debug_rst
)(JTAGSystem_ifc#(RISCVDebugDevice_ifc));

    let system <- build_jtag_system(
        riscv_jtag_debug(tap_meta, debug_clk, debug_rst),
        tdo_clk,
        tdo_rst
    );
    return system;

endmodule

endpackage
