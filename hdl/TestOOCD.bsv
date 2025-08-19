package TestOOCD;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import BRAM :: *;
import StmtFSM :: *;
import ClientServer :: *;
import BuildVector :: *;
import Connectable :: *;

import BlueJ :: *;

module mkTestOOCD();

    let bus_clk <- mkAbsoluteClock(0, 2);
    let bus_rst <- mkAsyncResetFromCR(2, bus_clk);

    let oocd_driver <- mkJTAG_Driver_OOCD;

    Stmt s = seq
        $display("Hello");
        await(False);
    endseq;

    mkAutoFSM(s, clocked_by bus_clk, reset_by bus_rst);

endmodule

endpackage