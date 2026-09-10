proc bluej_constrain_jtag2axi {root jtag_clock axi_clock} {
    if {[llength $jtag_clock] != 1 || [llength $axi_clock] != 1} {
        error "JTAG2AXI: expected exactly one JTAG and one AXI clock"
    }

    #JTAG TCK and AXI ACLK are unrelated.
    set_clock_groups -asynchronous -group $jtag_clock -group $axi_clock

    set prefix [expr {$root eq "" ? "" : "${root}/"}]
    set fifos [get_cells -quiet -hierarchical -filter "NAME =~ ${prefix}i_jtag_bus_f_sync_* && REF_NAME =~ SyncFIFO1*"]

    if {[llength $fifos] != 2} {
        error "JTAG2AXI: expected two SyncFIFO1 instances, found [llength $fifos]"
    }

    foreach fifo $fifos {
        set sync_regs {}
        foreach name {
            dSyncReg1_reg
            dEnqToggle_reg
            sSyncReg1_reg
            sDeqToggle_reg
        } {
            set sync_regs [concat $sync_regs [get_cells -quiet "${fifo}/${name}"]]
        }

        if {[llength $sync_regs] != 4} {
            error "JTAG2AXI: synchronizer structure changed below $fifo"
        }

        set_property ASYNC_REG TRUE $sync_regs
        set_property SHREG_EXTRACT NO $sync_regs
    }
}