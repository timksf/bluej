package TestScoooterOOCD;

import BRAM :: *;
import Clocks :: *;
import Connectable :: *;
import FIFOF :: *;
import GetPut :: *;
import StmtFSM :: *;
import Vector :: *;

import AXI4_Lite_Slave :: *;
import AXI4_Lite_Types :: *;

import ClockUtil :: *;
import JTAG_BDPI :: *;
import JTAG_System :: *;
import JTAG_Types :: *;
import RISCV_Debug :: *;
import RISCV_DM :: *;

import Config :: *;
import Dave :: *;
import Interfaces :: *;
import Types :: *;

import TestHelper :: *;

typedef TMul#(NUM_CPU, NUM_THREADS) ScoooterHartCount;
typedef 10 DebugRAMAddressWidth;

function Bool is_boot_rom_address(Bit#(32) address);
    return address < 32'h00001000;
endfunction

function Bool is_ram_address(Bit#(32) address);
    return address >= 32'h80000000 && address < 32'h80001000;
endfunction

function UInt#(DebugRAMAddressWidth) ram_index(Bit#(32) address);
    return unpack(truncate((address - 32'h80000000) >> 2));
endfunction

function Bit#(32) boot_rom_word(Bit#(32) address);
    return 32'h0000006f; // jal x0, 0
endfunction

function Bit#(32) merge_write_data(Bit#(32) previous, Bit#(32) value, Bit#(4) strobes);
    Bit#(32) merged = previous;
    for(Integer i = 0; i < 4; i = i + 1) begin
        if(strobes[i] == 1) begin
            Bit#(32) byte_mask = 32'h000000ff << (i * 8);
            merged = (merged & ~byte_mask) | (value & byte_mask);
        end
    end
    return merged;
endfunction

(* synthesize *)
module mkScoooterDebugTAP#(
    Clock tdo_clk,
    Reset tdo_rst,
    Clock debug_clk,
    Reset debug_rst
)(JTAGSystem_ifc#(RISCVDebugDevice_ifc#(ScoooterHartCount)));

    JTAG_TAP_Meta_Config_t tap_meta = JTAG_TAP_Meta_Config_t {
        idcode_ver:  4'h1,
        idcode_man:  11'h023,
        idcode_part: 16'h4567
    };

    let system <- mkRISCVJTAGDebug(tap_meta, tdo_clk, tdo_rst, debug_clk, debug_rst);
    return system;

endmodule

(* synthesize *)
module [Module] mkTestScoooterOOCD(TestHandler);

    let debug_clk <- mkAbsoluteClock(0, 2);
    let debug_rst <- mkAsyncResetFromCR(2, debug_clk);

    JTAG_TDO_Delay#(1) tdo_delay = ?;
    let oocd_driver <- mkJTAG_Driver_OOCD(tdo_delay, clocked_by debug_clk, reset_by debug_rst);
    JTAG_Stim_ifc jtag_stim <- mkJTAGShim(clocked_by debug_clk, reset_by debug_rst);

    let tck = jtag_stim.tck_out;
    let trst = jtag_stim.trst_out;
    let tdo_clk = jtag_stim.tdo_clk;
    let tdo_rst = jtag_stim.tdo_rst;

    let tap <- mkScoooterDebugTAP(tdo_clk, tdo_rst, debug_clk, debug_rst, clocked_by tck, reset_by trst);
    let tdo_crossing <- mkJTAGTDONullCrossing(tap.tdo, tdo_clk, tdo_rst, clocked_by debug_clk, reset_by debug_rst);
    DaveIFC core <- mkDave(clocked_by debug_clk, reset_by debug_rst);

    mkConnection(toGet(oocd_driver.ext_tck), toPut(jtag_stim.ext_tck));
    mkConnection(toGet(oocd_driver.ext_tdi), toPut(jtag_stim.ext_tdi));
    mkConnection(toGet(oocd_driver.ext_tms), toPut(jtag_stim.ext_tms));
    mkConnection(toGet(tdo_crossing.ext_tdo), toPut(oocd_driver.ext_tdo));

    mkConnection(toGet(jtag_stim.int_tms), toPut(tap.tms));
    mkConnection(toGet(jtag_stim.int_tdi), toPut(tap.tdi));

    Vector#(TExp#(DebugRAMAddressWidth), Reg#(Bit#(32))) rg_ram <- replicateM(mkReg(0, clocked_by debug_clk, reset_by debug_rst));

    AXI4_Lite_Slave_Rd#(32, 32) i_system_rd <- mkAXI4_Lite_Slave_Rd(2, clocked_by debug_clk, reset_by debug_rst);
    AXI4_Lite_Slave_Wr#(32, 32) i_system_wr <- mkAXI4_Lite_Slave_Wr(2, clocked_by debug_clk, reset_by debug_rst);
    mkConnection(tap.device_ifc.m_system_rd, i_system_rd.fab);
    mkConnection(tap.device_ifc.m_system_wr, i_system_wr.fab);

    rule r_core_instruction_read;
        let request <- core.imem_r.request.get;
        let address = pack(tpl_1(request));
        Vector#(IFUINST, Bit#(XLEN)) words = newVector;
        for(Integer i = 0; i < valueOf(IFUINST); i = i + 1) begin
            let word_address = address + fromInteger(i * 4);
            if(is_boot_rom_address(word_address)) begin
                words[i] = boot_rom_word(word_address);
            end
            else if(is_ram_address(word_address)) begin
                words[i] = rg_ram[ram_index(word_address)];
            end
            else begin
                words[i] = 0;
            end
        end
        core.imem_r.response.put(tuple2(pack(words), tpl_2(request)));
    endrule

    rule r_core_data_read;
        let request <- core.dmem_r.request.get;
        let address = pack(tpl_1(request));
        Bit#(32) data = 0;
        if(is_boot_rom_address(address)) begin
            data = boot_rom_word(address);
        end
        else if(is_ram_address(address)) begin
            data = rg_ram[ram_index(address)];
        end
        core.dmem_r.response.put(tuple2(data, tpl_2(request)));
    endrule

    rule r_core_data_write;
        let request <- core.dmem_w.request.get;
        let address = pack(tpl_1(request));
        if(is_ram_address(address)) begin
            let index = ram_index(address);
            rg_ram[index] <= merge_write_data(rg_ram[index], tpl_2(request), tpl_3(request));
        end
        core.dmem_w.response.put(tpl_4(request));
    endrule

    rule r_debug_system_read;
        let request <- i_system_rd.request.get;
        Bit#(32) data = 0;
        AXI4_Lite_Response response = DECERR;
        if(is_boot_rom_address(request.addr)) begin
            data = boot_rom_word(request.addr);
            response = OKAY;
        end
        else if(is_ram_address(request.addr)) begin
            data = rg_ram[ram_index(request.addr)];
            response = OKAY;
        end
        i_system_rd.response.put(AXI4_Lite_Read_Rs_Pkg {
            data: data,
            resp: response
        });
    endrule

    rule r_debug_system_write;
        let request <- i_system_wr.request.get;
        AXI4_Lite_Response response = SLVERR;
        if(is_ram_address(request.addr)) begin
            let index = ram_index(request.addr);
            rg_ram[index] <= merge_write_data(rg_ram[index], request.data, request.strb);
            response = OKAY;
        end
        i_system_wr.response.put(AXI4_Lite_Write_Rs_Pkg { resp: response });
    endrule

    rule r_drive_interrupts;
        core.sw_int(replicate(replicate(False)));
        core.timer_int(replicate(replicate(False)));
        core.ext_int(replicate(replicate(False)));
    endrule

    for(Integer cpu = 0; cpu < valueOf(NUM_CPU); cpu = cpu + 1) begin
        for(Integer thread = 0; thread < valueOf(NUM_THREADS); thread = thread + 1) begin
            Integer hart = cpu * valueOf(NUM_THREADS) + thread;
            FIFOF#(DMHartRegRequest_t) f_abstract_request <- mkFIFOF(clocked_by debug_clk, reset_by debug_rst);

            rule r_drive_hart_debug;
                tap.device_ifc.harts[hart].status(DMHartStatus_t {
                    halted: core.debug_harts[cpu][thread].halted,
                    running: core.debug_harts[cpu][thread].running,
                    unavailable: False
                });
                core.debug_harts[cpu][thread].halt_request(tap.device_ifc.harts[hart].halt_request);
                core.debug_harts[cpu][thread].resume_request(tap.device_ifc.harts[hart].resume_request);
            endrule

            rule r_accept_abstract_register;
                let request <- tap.device_ifc.harts[hart].registers.request.get;
                f_abstract_request.enq(request);
            endrule

            rule r_write_abstract_register(f_abstract_request.first.write);
                let request = f_abstract_request.first;
                f_abstract_request.deq;
                core.debug_harts[cpu][thread].write_register(request.regno, request.data);
                tap.device_ifc.harts[hart].registers.response.put(DMHartRegResponse_t {
                    data: request.data,
                    error: 0,
                    epoch: request.epoch
                });
            endrule

            rule r_read_abstract_register(!f_abstract_request.first.write);
                let request = f_abstract_request.first;
                f_abstract_request.deq;
                let data <- core.debug_harts[cpu][thread].read_register(request.regno);
                tap.device_ifc.harts[hart].registers.response.put(DMHartRegResponse_t {
                    data: data,
                    error: 0,
                    epoch: request.epoch
                });
            endrule
        end
    end

    SyncPulseIfc p_start <- mkSyncPulseFromCC(debug_clk);
    SyncPulseIfc p_stopped <- mkSyncPulseToCC(debug_clk, debug_rst);
    SyncBitIfc#(Bool) sync_started <- mkSyncBitToCC(debug_clk, debug_rst);

    Stmt run = seq
        sync_started.send(True);
        await(oocd_driver.connected);
        await(!oocd_driver.connected);
    endseq;

    FSM f_run <- mkFSM(run, clocked_by debug_clk, reset_by debug_rst);

    rule r_start if(p_start.pulse);
        f_run.start;
    endrule

    rule r_stopped if(f_run.done);
        p_stopped.send;
    endrule

    method go = p_start.send;
    method done = p_stopped.pulse && sync_started.read;

endmodule

endpackage
