package TestBDPI;

import StmtFSM :: *;

import "BDPI" function ActionValue#(Bit#(64)) c_test(Bit#(32) b);
import "BDPI" function ActionValue#(Bit#(64)) c_test_f();

module mkTestBDPI();

    mkAutoFSM(seq
        $display("yo0 %016X", c_test('hC0DEAFFE));
        $display("yo1 %016X", c_test_f());
    endseq);

endmodule

endpackage