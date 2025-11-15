package TestNull;

import StmtFSM :: *;
import Clocks :: *;

module mkTestNull(Empty);

    let clk_inv <- invertCurrentClock;
    let rst_inv <- mkAsyncResetFromCR(0, clk_inv);

    Reg#(Bit#(32)) rg_A0 <- mkReg(0);
    Reg#(Bit#(32)) rg_A1 <- mkReg(0);
    let rg_sel <- mkReg(2'b00);
    let rg_B <- mkNullCrossingRegU(clk_inv);
    let rg_C <- mkRegU(clocked_by clk_inv, reset_by rst_inv);

    let w_null <- mkNullCrossingWire(clk_inv, rg_A0);
    let rg_D <- mkRegU(clocked_by clk_inv, reset_by rst_inv);

    //MUX
    Bit#(32) mux_E = 
        case(rg_sel)
            2'b00: return rg_A0;
            2'b01: return rg_A1;
            default: return 99;
        endcase;

    let w_E <- mkNullCrossingWire(clk_inv, mux_E);
    let rg_E <- mkRegU(clocked_by clk_inv, reset_by rst_inv);

    rule r;
        rg_B <= rg_A0;
    endrule
    
    rule r1;
        rg_C <= rg_B.crossed();
    endrule

    rule r2;
        rg_D <= w_null;
    endrule

    rule rsel;
        rg_E <= w_E;
    endrule
    
    rule fin;
        let t <- $time();
        if(t == 50) begin
            rg_A0 <= 77;
            rg_A1 <= 66;
        end
        if(t > 100)
            $finish;
    endrule

endmodule

endpackage