package ScoooterJTAG;

import ClientServer :: *;
import Clocks :: *;

import JTAG_BusAdapter :: *;
import JTAG_System :: *;
import JTAG_Types :: *;
import RISCV_Debug :: *;

interface ScoooterJTAG_ifc;
    interface RISCVDebugDevice_ifc#(1) debug;
    interface Client#(BusRequest#(32, 32), BusResponse#(32)) bus;
endinterface

module [JTAGSystem#(3, 5)] scoooter_jtag_device#(JTAG_TAP_Meta_Config_t tap_meta, Clock bus_clk, Reset bus_rst)(ScoooterJTAG_ifc);
    //single HART debug module with TAP
    RISCVDebugDevice_ifc#(1)        i_debug <- riscv_jtag_debug(tap_meta, bus_clk, bus_rst);
    JTAG_BusAdapter_ifc#(32, 32)    i_bus   <- mkJTAG_BusAdapter(5'h12, bus_clk, bus_rst);

    interface debug = i_debug;
    interface bus   = i_bus.bus;
endmodule

module [Module] mkScoooterJTAG#(JTAG_TAP_Meta_Config_t tap_meta, Clock tdo_clk, Reset tdo_rst, Clock bus_clk, Reset bus_rst)(JTAGSystem_ifc#(ScoooterJTAG_ifc));
    let system <- build_jtag_system(
        scoooter_jtag_device(tap_meta, bus_clk, bus_rst),
        tdo_clk,
        tdo_rst
    );
    return system;
endmodule

endpackage
