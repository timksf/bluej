package Testbench;

import StmtFSM :: *;

import BlueJ :: *;

module mkTestbench();

    Stmt s = {
        seq
        action
            Bit#(32) v = 1024;
            $display(log2(v));
        endaction
        endseq
    };

    mkAutoFSM(s);

endmodule

endpackage