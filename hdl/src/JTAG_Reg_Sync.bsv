package JTAG_Reg_Sync;

import BUtils :: *;
import DReg :: *;
import Clocks :: *;

import JTAG_Types :: *;
import JTAG_Reg :: *;

module mkJTAG_Reg_Sync#(t reg_i, Clock sysclk, Reset sysrst)(JTAG_Reg_ifc#(t))
    provisos(
        Bits#(t, w),
        Add#(1, __b, w)
    );
    
    let i <- mkJTAG_Reg_SyncR(reg_i, tagged NoReset, sysclk, sysrst);
    return i;
endmodule

//.. clocked_by tck, reset_by trst
module mkJTAG_Reg_SyncR#(t reg_i, JTAG_Reg_Reset#(t) r, Clock sysclk, Reset sysrst)(JTAG_Reg_ifc#(t)) 
    provisos(
        Bits#(t, w),
        Add#(1, __b, w)
    );

    Reg#(t)             rg_sync_o       <- mkSyncRegFromCC(unpack(0), sysclk);
    SyncBitIfc#(Bool)   rg_sync_wr_o    <- mkSyncBitFromCC(sysclk);

    Reg#(t)             rg_sync_i       <- mkSyncRegToCC(unpack(0), sysclk, sysrst);

    JTAG_Reg_ifc#(t)    jreg_int        <- mkJTAGRegR(rg_sync_i, r);

    rule rsync_to_sys;
        rg_sync_o <= jreg_int.reg_o;
        rg_sync_wr_o.send(jreg_int.wr_o);
    endrule

    rule rsync_to_tck;
        rg_sync_i <= reg_i;
    endrule

    method reg_o = rg_sync_o;
    method wr_o = rg_sync_wr_o.read;

    method tdo = jreg_int.tdo;
    method tdi = jreg_int.tdi;

    interface ctrl = jreg_int.ctrl;

endmodule

endpackage