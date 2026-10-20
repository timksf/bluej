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

typedef struct {
    t data;
    Bool update;
    Bool capture;
} JTAG_Reg_Event#(type t) deriving(Bits);

//.. clocked_by tck, reset_by trst
module mkJTAG_Reg_SyncR#(t reg_i, JTAG_Reg_Reset#(t) r, Clock sysclk, Reset sysrst)(JTAG_Reg_ifc#(t))
    provisos(Bits#(t, w));

    Reg#(t)    rg_d_out     <- mkDRegU(unpack(0), clocked_by sysclk, reset_by sysrst);
    Reg#(Bool) rg_wr_o_out  <- mkDReg(False, clocked_by sysclk, reset_by sysrst);
    Reg#(Bool) rg_cap_o_out <- mkDReg(False, clocked_by sysclk, reset_by sysrst);

    SyncFIFOIfc#(JTAG_Reg_Event#(t)) f_events <- mkSyncFIFOFromCC(1, sysclk);
    let sys_in_reset <- isResetAsserted(clocked_by sysclk, reset_by sysrst);

    Reg#(t)          rg_sync_i <- mkSyncRegToCC(unpack(0), sysclk, sysrst);
    JTAG_Reg_ifc#(t) jreg_int  <- mkJTAGRegR(rg_sync_i, r);

    rule r_send_event if(jreg_int.wr_o || jreg_int.cap_o);
        f_events.enq(JTAG_Reg_Event {
            data:       jreg_int.reg_o,
            update:     jreg_int.wr_o,
            capture:    jreg_int.cap_o
        });
    endrule

    //for simulation, hardware drops an overflowed event
    rule r_event_overflow if((jreg_int.wr_o || jreg_int.cap_o) && !f_events.notFull);
        $fatal(1, "mkJTAG_Reg_Sync: event mailbox overflow; allow the CDC acknowledgement to return");
    endrule

    rule r_receive_event if(!sys_in_reset);
        let scan_event = f_events.first;
        f_events.deq;
        if(scan_event.update) begin
            rg_d_out        <= scan_event.data;
            rg_wr_o_out     <= True;
        end
        if(scan_event.capture)
            rg_cap_o_out    <= True;
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
