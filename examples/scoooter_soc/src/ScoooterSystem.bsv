package ScoooterSystem;

import Assert :: *;
import ClientServer :: *;
import Clocks :: *;
import Connectable :: *;
import FIFOF :: *;
import GetPut :: *;
import Vector :: *;

import AhbAdapters :: *;
import BlueFabric :: *;
import Config :: *;
import Interfaces :: *;
import JTAG_System :: *;
import JTAG_Types :: *;
import RISCV_DM :: *;
import RISCV_Debug :: *;
import ScoooterBus :: *;
import ScoooterCpu :: *;
import ScoooterJTAG :: *;

interface ScoooterSystem_ifc;
    (* always_enabled, prefix = "" *)
        method Action gpio_i((* port = "gpio_input" *) Bit#(8) value);
    (* always_ready, result = "gpio_output" *)
        method Bit#(8) gpio_o;
    (* always_ready, result = "gpio_output_enable" *)
        method Bit#(8) gpio_oe;
    (* always_enabled, prefix = "" *)
        method Action uart_rx((* port = "uart_rx" *) Bit#(1) value);
    (* always_ready, result = "uart_tx" *)
        method Bit#(1) uart_tx;

    (* always_enabled, always_ready, prefix = "" *)
        method Action tms((* port = "jtag_tms" *) Bit#(1) value);
    (* always_enabled, always_ready, prefix = "" *)
        method Action tdi((* port = "jtag_tdi" *) Bit#(1) value);
    (* always_ready, prefix = "", result = "jtag_tdo" *)
        method Bit#(1) tdo;
endinterface

(* synthesize, default_clock_osc = "jtag_tck", default_reset = "jtag_reset_n", clock_prefix = "" *)
module [Module] mkScoooterSystem#(
    Clock tdo_clk,
    Reset tdo_rst_n,
    Clock system_clk,
    Reset system_rst_n)(ScoooterSystem_ifc);

    JTAG_TAP_Meta_Config_t tap_meta = JTAG_TAP_Meta_Config_t { idcode_ver: 4'h1, idcode_man: 11'h023, idcode_part: 16'h4567 };
    let jtag_system <- mkScoooterJTAG(tap_meta, tdo_clk, tdo_rst_n, system_clk, system_rst_n);

    ScoooterCpu_ifc  i_cpu  <- mkScoooterCpu(clocked_by system_clk, reset_by system_rst_n);
    ScoooterBus_ifc  i_bus  <- mkScoooterBus(clocked_by system_clk, reset_by system_rst_n);
    ScoooterJTAG_ifc i_jtag = jtag_system.device_ifc;

    AhbMasterMux_ifc#(3, 32, 32) i_ahb_mux          <- mkAhbMasterMux(clocked_by system_clk, reset_by system_rst_n);
    MemoryAhbAdapter_ifc         i_dm_ahb           <- mkMemoryAhbAdapter(clocked_by system_clk, reset_by system_rst_n);
    JtagAhbAdapter_ifc           i_jtag_ahb         <- mkJtagAhbAdapter(clocked_by system_clk, reset_by system_rst_n);
    FIFOF#(DMHartRegRequest_t)    f_abstract_request <- mkFIFOF(clocked_by system_clk, reset_by system_rst_n);
    FIFOF#(DMHartRegRequest_t)    f_abstract_inflight <- mkFIFOF(clocked_by system_clk, reset_by system_rst_n);

    //jtag RISCV DM system bus to ahb adapter
    mkConnection(i_jtag.debug.m_system, i_dm_ahb.memory);
    //jtag generic bus master to ahb adapter
    mkConnection(i_jtag.bus, i_jtag_ahb.bus);

    //bus master MUX upstream 
    mkConnection(i_cpu.m_ahb,       i_ahb_mux.up[0]);
    mkConnection(i_dm_ahb.m_ahb,    i_ahb_mux.up[1]);
    mkConnection(i_jtag_ahb.m_ahb,  i_ahb_mux.up[2]);
    //=> downstream
    mkConnection(i_ahb_mux.down,    i_bus.s_ahb);

    rule r_interrupts;
        i_cpu.sw_interrupt(False);
        i_cpu.timer_interrupt(False);
        i_cpu.external_interrupt(i_bus.ext_irq[0]);
    endrule

    rule r_drive_hart_debug;
        i_jtag.debug.harts[0].status(DMHartStatus_t {
            halted: i_cpu.debug_hart.halted,
            running: i_cpu.debug_hart.running,
            unavailable: False
        });
        i_cpu.debug_hart.haltreq(i_jtag.debug.harts[0].halt_request);
        i_cpu.debug_hart.resumereq(i_jtag.debug.harts[0].resume_request);
        i_cpu.debug_hart.ackhavereset(i_jtag.debug.harts[0].acknowledge_reset);
        if(i_cpu.debug_hart.havereset && !i_jtag.debug.harts[0].acknowledge_reset) begin
            i_jtag.debug.harts[0].reset_seen;
        end
    endrule

    rule r_accept_abstract_register;
        let request <- i_jtag.debug.harts[0].registers.request.get;
        f_abstract_request.enq(request);
    endrule

    rule r_forward_abstract_register;
        let request = f_abstract_request.first;
        f_abstract_request.deq;
        i_cpu.debug_hart.abstract.request.put(DebugRequest {
            regno: request.regno,
            write: request.write,
            data: request.data
        });
        f_abstract_inflight.enq(request);
    endrule

    rule r_return_abstract_register;
        let request = f_abstract_inflight.first;
        f_abstract_inflight.deq;
        let response <- i_cpu.debug_hart.abstract.response.get;
        i_jtag.debug.harts[0].registers.response.put(DMHartRegResponse_t {
            data: response.data,
            error: response.supported ? 0 : 2,
            epoch: request.epoch
        });
    endrule

    method gpio_i   = i_bus.gpio_i;
    method gpio_o   = i_bus.gpio_o;
    method gpio_oe  = i_bus.gpio_oe;
    method uart_rx  = i_bus.uart_rx;
    method uart_tx  = i_bus.uart_tx;
    method tms      = jtag_system.tms;
    method tdi      = jtag_system.tdi;
    method tdo      = jtag_system.tdo;
endmodule

endpackage
