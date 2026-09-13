# Constraint entry point for standalone or inlined mkJTAG2AXI instances.
# root is empty for OOC, an RTL hierarchy path, or a BSC flattened prefix.
proc bluej_constrain_bscane2 {bscan jtag_clock} {
    if {[llength $bscan] != 1 || [llength $jtag_clock] != 1} {
        error "BSCANE2: expected exactly one primitive and one JTAG clock"
    }

    # UG570 specifies TDI/TMS relative to the falling TCK edge.  These are
    # dedicated internal timing pins on UltraScale devices, not package ports.
    set_input_delay -max 15.000 -clock_fall -clock $jtag_clock \
        [get_pins ${bscan}/INTERNAL_TDI]
    set_input_delay -max 15.000 -clock_fall -clock $jtag_clock \
        [get_pins ${bscan}/INTERNAL_TMS]
}

proc bluej_constrain_jtag2axi {root jtag_clock axi_clock} {
    if {[llength $jtag_clock] != 1 || [llength $axi_clock] != 1} {
        error "JTAG2AXI: expected exactly one JTAG and one AXI clock"
    }

    if {$root eq ""} {
        set prefix ""
    } elseif {[llength [get_cells -quiet $root]] == 1} {
        set prefix "${root}/"
    } else {
        set prefix "${root}_"
    }

    set_clock_groups -asynchronous -group $jtag_clock -group $axi_clock

    set fifos [get_cells -quiet -hierarchical \
        -filter "NAME =~ ${prefix}i_jtag_bus_f_sync_* && REF_NAME =~ SyncFIFO1*"]

    if {[llength $fifos] != 2} {
        error "JTAG2AXI: expected two SyncFIFO1 instances, found [llength $fifos]"
    }

    foreach fifo $fifos {
        set sync_regs [list]
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

        set_property ASYNC_REG     TRUE $sync_regs
        set_property SHREG_EXTRACT NO   $sync_regs
    }
}
