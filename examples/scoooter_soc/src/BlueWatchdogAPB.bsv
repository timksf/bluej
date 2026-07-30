package BlueWatchdogAPB;

import BlueCSR :: *;
import BlueFabric :: *;

interface WatchdogRegs_ifc;
endinterface

module [BlueCSRCtx_t#(32, 32)] watchdog_csrs(WatchdogRegs_ifc);
    PulseWire pw_timeout <- mkPulseWire;

    csr_regmap_def("BlueWatchdog", "BlueCSR watchdog register map");

    csr_reg_def('h00, "CONTROL", "Watchdog control register");
    Reg#(Bool) rg_enable <- csr_reg_rw('h00, False, 0, "ENABLE", "Enable", "Enables countdown operation.");

    csr_reg_def('h04, "RELOAD_LO", "Watchdog reload value low word");
    Reg#(Bit#(32)) rg_reload_lo <- csr_reg_rw('h04, 0, 0, "VALUE", "Reload Value Low", "Low 32 bits of the value loaded by KICK.");

    csr_reg_def('h08, "RELOAD_HI", "Watchdog reload value high word");
    Reg#(Bit#(32)) rg_reload_hi <- csr_reg_rw('h08, 0, 0, "VALUE", "Reload Value High", "High 32 bits of the value loaded by KICK.");

    csr_reg_def('h0C, "COUNT_LO", "Watchdog current count low word");
    Reg#(Bit#(32)) rg_count_lo <- csr_reg_ro('h0C, 0, 0, "VALUE", "Count Low", "Low 32 bits of the current countdown value.");

    csr_reg_def('h10, "COUNT_HI", "Watchdog current count high word");
    Reg#(Bit#(32)) rg_count_hi <- csr_reg_ro('h10, 0, 0, "VALUE", "Count High", "High 32 bits of the current countdown value.");

    csr_reg_def('h14, "IRQ_ENABLE", "Watchdog interrupt enable register");
    csr_reg_def('h18, "IRQ_PENDING", "Watchdog interrupt pending register");
    csr_irq('h18, 'h14, 0, 0, pw_timeout, "TIMEOUT", "Watchdog Timeout", "The watchdog reached zero.");

    csr_reg_def('h1C, "KICK", "Watchdog reload trigger");
    Reg#(Bit#(1)) rg_kick <- csr_reg_trigw('h1C, True);

    rule r_count;
        Bit#(64) count = { rg_count_hi, rg_count_lo };
        Bit#(64) reload = { rg_reload_hi, rg_reload_lo };

        if(rg_kick == 1) begin
            count = reload;
        end
        else if(rg_enable && count != 0) begin
            count = count - 1;
            if(count == 0)
                pw_timeout.send;
        end

        rg_count_lo <= truncate(count);
        rg_count_hi <= truncateLSB(count);
    endrule
endmodule

interface BlueWatchdogAPB_ifc;
    (* always_ready *) method Bool interrupt;
    interface ApbSlaveFabric_ifc#(32, 32, 0) s_apb;
endinterface

module [Module] mkBlueWatchdogAPB(BlueWatchdogAPB_ifc);
    BlueCSRAccess_ifc#(32, 32, 1, WatchdogRegs_ifc) i_csrs <- create_blue_csr(watchdog_csrs, False);
    BlueCSR_APB_ifc#(32, 32, 0, 1) i_apb <- mkBlueCSRAPBAdapter(i_csrs.external, True);

    method interrupt = i_apb.irqs[0];
    interface s_apb = i_apb.s_apb;
endmodule

endpackage
