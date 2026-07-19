package TestScoooterNoDebug;

import GetPut :: *;
import ClientServer :: *;
import Vector :: *;

import Config :: *;
import Dave :: *;
import Interfaces :: *;

import TestHelper :: *;

(* synthesize *)
module [Module] mkTestScoooterNoDebug(TestHandler);

    DaveIFC core <- mkDave;
    Reg#(Bool) rg_started <- mkReg(False);
    Reg#(Bool) rg_done <- mkReg(False);

    rule r_core_instruction_read;
        let request <- core.imem_r.request.get;
        core.imem_r.response.put(tuple2(32'h0000006f, tpl_2(request)));
    endrule

    rule r_core_data_read;
        let request <- core.dmem_r.request.get;
        core.dmem_r.response.put(tuple2(0, tpl_2(request)));
    endrule

    rule r_core_data_write;
        let request <- core.dmem_w.request.get;
        core.dmem_w.response.put(tpl_4(request));
    endrule

    rule r_drive_interrupts;
        core.sw_int(replicate(replicate(False)));
        core.timer_int(replicate(replicate(False)));
        core.ext_int(replicate(replicate(False)));
    endrule

    rule r_finish(rg_started);
        rg_done <= True;
    endrule

    method Action go;
        rg_started <= True;
    endmethod

    method Bool done = rg_done;

endmodule

endpackage
