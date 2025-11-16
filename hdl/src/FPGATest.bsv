package FPGATest;

import BRAM :: *;

import BlueJ :: *;

interface FPGATest_ifc;

    interface Clock bus_clk;
    interface Reset bus_rst;

endinterface

module mkFPGATestTop();
    /*
        Instantiates BSCANE2, connects JTAG bus adapter to configurable user register slot
        and provides access to some 2 ported BRAM.
        On the other side of the BRAM sits a small FSM that controls LEDs based on contents of the BRAM.
        The FSM is notified of an updated configuration in the BRAM or it periodically polls from the BRAM.
    */

    let bscane2 <- mkBSCANE2_BlueJ(bscan_cfg, tck_inv, vec(as_read_only(user_reg.tdo)));

    JTAG_BusAdapter_ifc#(32, 32) ifc <- mkJTAG_BusAdapter(bus_clk, bus_rst);

    BRAM2Port#(Bit#(32), Bit#(32)) bram <- mkBRAM2Server(bram_cfg, clocked_by bus_clk, reset_by bus_rst);


endmodule

endpackage