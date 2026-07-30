package RISCV_Debug;

import Clocks :: *;
import Connectable :: *;
import Vector :: *;

import ClientServer :: *;
import Memory :: *;

import JTAG_System :: *;
import JTAG_Types :: *;
import RISCV_DM :: *;
import RISCV_DTM :: *;

interface RISCVDebugDevice_ifc#(numeric type n_harts);
    interface Client#(MemoryRequest#(32, 32), MemoryResponse#(32)) m_system;

    interface Vector#(n_harts, RISCVDMHartPort_ifc) harts;

    method Bool ndmreset;
    method Bool dmactive;
    method Bool dtm_hard_reset;
endinterface

module [JTAGSystem#(n, 5)] riscv_jtag_debug#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock debug_clk,
    Reset debug_rst
)(RISCVDebugDevice_ifc#(n_harts)) provisos (
    Add#(1, _n_harts_minus_one, n_harts),
    Add#(_hartsel_pad, TLog#(n_harts), 20)
);

    jtag_meta_config(tap_meta.idcode_ver, tap_meta.idcode_man, tap_meta.idcode_part);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(5'h01);
    jtag_rst_to_idcode;

    RISCVDTMDevice_ifc#(7) i_dtm <- riscv_dtm(debug_clk, debug_rst);
    RISCVDM_ifc#(n_harts) i_dm <- liftModule(mkRISCVDM(clocked_by debug_clk, reset_by debug_rst));

    mkConnection(i_dtm.dmi, i_dm.dmi);

    interface m_system = i_dm.m_system;
    interface harts = i_dm.harts;

    method ndmreset = i_dm.ndmreset;
    method dmactive = i_dm.dmactive;
    method dtm_hard_reset = i_dtm.hard_reset;

endmodule

// Preserve the standalone two-instruction DTM wrapper while allowing a
// larger JTAGSystem context to add further endpoints.
module [JTAGSystem#(2, 5)] riscv_jtag_debug_default#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock debug_clk,
    Reset debug_rst
)(RISCVDebugDevice_ifc#(n_harts)) provisos (
    Add#(1, _n_harts_minus_one, n_harts),
    Add#(_hartsel_pad, TLog#(n_harts), 20)
);
    let debug <- riscv_jtag_debug(tap_meta, debug_clk, debug_rst);
    return debug;
endmodule

module [Module] mkRISCVJTAGDebug#(
    JTAG_TAP_Meta_Config_t tap_meta,
    Clock tdo_clk,
    Reset tdo_rst,
    Clock debug_clk,
    Reset debug_rst
)(JTAGSystem_ifc#(RISCVDebugDevice_ifc#(n_harts))) provisos (
    Add#(1, _n_harts_minus_one, n_harts),
    Add#(_hartsel_pad, TLog#(n_harts), 20)
);

    let system <- build_jtag_system(
        riscv_jtag_debug_default(tap_meta, debug_clk, debug_rst),
        tdo_clk,
        tdo_rst
    );
    return system;

endmodule

endpackage
