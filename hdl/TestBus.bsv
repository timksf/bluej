package TestBus;

import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import StmtFSM :: *;
import BuildVector :: *;
import Connectable :: *;

import BlueJ :: *;
import ClockUtil :: *;

module mkTestBus();

    Stmt s = seq
        $display("T");
    endseq;

    mkAutoFSM(s);

endmodule

endpackage