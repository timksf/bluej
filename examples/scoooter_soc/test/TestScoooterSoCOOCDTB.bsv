package TestScoooterSoCOOCDTB;

import Clocks :: *;
import Connectable :: *;
import GetPut :: *;

import ClockUtil :: *;
import JTAG_BDPI :: *;
import JTAG_System :: *;
import JTAG_Types :: *;
import ScoooterSystem :: *;

(* synthesize *)
module mkTestScoooterSoCOOCDTB(Empty);
    let system_clk <- mkAbsoluteClock(0, 2);
    let system_rst <- mkAsyncResetFromCR(2, system_clk);

    JTAG_TDO_Delay#(1) tdo_delay = ?;
    let i_oocd_driver <- mkJTAG_Driver_OOCD(tdo_delay, clocked_by system_clk, reset_by system_rst);
    JTAG_Stim_ifc i_jtag_stim <- mkJTAGShim(clocked_by system_clk, reset_by system_rst);
    let tck = i_jtag_stim.tck_out;
    let trst = i_jtag_stim.trst_out;
    let tdo_clk = i_jtag_stim.tdo_clk;
    let tdo_rst = i_jtag_stim.tdo_rst;
    ScoooterSystem_ifc i_system <- mkScoooterSystem(tdo_clk, tdo_rst, system_clk, system_rst, clocked_by tck, reset_by trst);
    let i_tdo_crossing <- mkJTAGTDONullCrossing(i_system.tdo, tdo_clk, tdo_rst, clocked_by system_clk, reset_by system_rst);

    mkConnection(toGet(i_oocd_driver.ext_tck), toPut(i_jtag_stim.ext_tck));
    mkConnection(toGet(i_oocd_driver.ext_tdi), toPut(i_jtag_stim.ext_tdi));
    mkConnection(toGet(i_oocd_driver.ext_tms), toPut(i_jtag_stim.ext_tms));
    mkConnection(toGet(i_tdo_crossing.ext_tdo), toPut(i_oocd_driver.ext_tdo));
    mkConnection(toGet(i_jtag_stim.int_tms), toPut(i_system.tms));
    mkConnection(toGet(i_jtag_stim.int_tdi), toPut(i_system.tdi));

    rule r_drive_idle_inputs;
        i_system.gpio_i(0);
        i_system.uart_rx(1);
    endrule
endmodule

endpackage
