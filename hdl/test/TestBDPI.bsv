package TestBDPI;

import StmtFSM :: *;

import TestHelper :: *;

import "BDPI" function ActionValue#(Bit#(64)) c_test(Bit#(32) b);
import "BDPI" function ActionValue#(Bit#(64)) c_test_f();

module mkTestBDPI(TestHandler);

    Stmt s = (seq
        $display("e %016X", c_test('hC0DEAFFE));
        $display("e1 %016X", c_test_f());
    endseq);

    FSM f <- mkFSM(s);
    method go = f.start;
    method done = f.done;

endmodule

endpackage