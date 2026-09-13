package JTAG_Reg_Sync;

import BUtils :: *;
import DReg :: *;
import Clocks :: *;

import JTAG_Types :: *;
import JTAG_Reg :: *;

module mkJTAG_Reg_Sync#(t reg_i, Clock sysclk, Reset sysrst)(JTAG_Reg_ifc#(t))
    provisos(Bits#(t, w));

    let i <- mkJTAG_Reg_SyncR(reg_i, tagged NoReset, sysclk, sysrst);
    return i;

endmodule

typedef Tuple2#(t, Bool) JRgSync_t#(type t);

//.. clocked_by tck, reset_by trst
module mkJTAG_Reg_SyncR#(t reg_i, JTAG_Reg_Reset#(t) r, Clock sysclk, Reset sysrst)(JTAG_Reg_ifc#(t))
    provisos(Bits#(t, w));

    //only synchronize when the JTAG event outputs change
    Reg#(Bool)          rg_wr_o_old     <- mkReg(False);
    Reg#(Bool)          rg_cap_o_old    <- mkReg(False);

    Reg#(t)             rg_d_out        <- mkDRegU(unpack(0), clocked_by sysclk, reset_by sysrst);
    Reg#(Bool)          rg_wr_o_out     <- mkDReg(False, clocked_by sysclk, reset_by sysrst);
    Reg#(Bool)          rg_cap_o_out    <- mkDReg(False, clocked_by sysclk, reset_by sysrst);
    Reg#(Bool)          rg_data_pending <- mkReg(False, clocked_by sysclk, reset_by sysrst);

    Reg#(JRgSync_t#(t)) rg_sync_o       <- mkSyncRegFromCC(unpack(0), sysclk);
    SyncPulseIfc        rg_sync_wr_o    <- mkSyncPulseFromCC(sysclk);
    SyncPulseIfc        rg_sync_cap_o   <- mkSyncPulseFromCC(sysclk);

    Reg#(t)             rg_sync_i       <- mkSyncRegToCC(unpack(0), sysclk, sysrst);
    JTAG_Reg_ifc#(t)    jreg_int        <- mkJTAGRegR(rg_sync_i, r);

    rule rsync_to_sys if(jreg_int.wr_o != rg_wr_o_old);
        rg_sync_o <= tuple2(jreg_int.reg_o, jreg_int.wr_o);
        rg_wr_o_old <= jreg_int.wr_o;
        //this pulse will lead the data because word synchronization uses handshaking
        if(jreg_int.wr_o)
            rg_sync_wr_o.send();
    endrule

    rule rsync_cap_to_sys if(jreg_int.cap_o != rg_cap_o_old);
        rg_cap_o_old <= jreg_int.cap_o;
        if(jreg_int.cap_o)
            rg_sync_cap_o.send();
    endrule

    (* descending_urgency="rsync_wr_o, rout" *)
    rule rsync_wr_o if(rg_sync_wr_o.pulse());
        rg_data_pending <= True;
    endrule

    rule rout if(rg_data_pending && tpl_2(rg_sync_o));
        rg_data_pending <= False;
        rg_wr_o_out <= True;
        rg_d_out <= tpl_1(rg_sync_o);
    endrule

    rule rcap_out if(rg_sync_cap_o.pulse());
        rg_cap_o_out <= True;
    endrule

    rule rsync_to_tck;
        rg_sync_i <= reg_i;
    endrule

    method reg_o = rg_d_out;
    method wr_o  = rg_wr_o_out;
    method cap_o = rg_cap_o_out;

    interface scan = jreg_int.scan;

endmodule

endpackage
