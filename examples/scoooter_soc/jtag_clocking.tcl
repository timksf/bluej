proc configure_jtag_tdo_falling_edge {} {
    set tdo_registers [get_cells -quiet -hierarchical \
        -filter {REF_NAME == FDRE && NAME =~ *tap_rg_ext_tdo_reg}]

    if {[llength $tdo_registers] != 1} {
        error "Expected one synthesized JTAG TDO FDRE, found [llength $tdo_registers]: $tdo_registers"
    }

    set tdo_register [lindex $tdo_registers 0]
    set_property IS_C_INVERTED 1'b1 $tdo_register

    puts "Configured falling-edge JTAG TDO register: $tdo_register"
}
