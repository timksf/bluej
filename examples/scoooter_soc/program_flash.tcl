# SPDX-License-Identifier: MIT

set flash_image_path [lindex $argv 0]
set bitstream_path [lindex $argv 1]
set cfgmem_part_name [lindex $argv 2]

if {$flash_image_path eq "" || $bitstream_path eq ""} {
    error "usage: vivado -mode batch -source program_flash.tcl -tclargs <flash.mcs> <bitstream.bit> ?cfgmem-part?"
}
if {$cfgmem_part_name eq ""} {
    set cfgmem_part_name mx25l3273f-spi-x1_x2_x4
}

set flash_image_path [file normalize $flash_image_path]
set bitstream_path [file normalize $bitstream_path]

if {![file exists $flash_image_path]} {
    error "flash image does not exist: $flash_image_path"
}
if {![file exists $bitstream_path]} {
    error "bitstream does not exist: $bitstream_path"
}

open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices] 0]
if {$device eq ""} {
    error "no FPGA was found on the Digilent hardware target"
}
current_hw_device $device

set cfgmem_part [lindex [get_cfgmem_parts $cfgmem_part_name] 0]
if {$cfgmem_part eq ""} {
    error "Vivado does not provide configuration-memory part $cfgmem_part_name"
}

set cfgmem [create_hw_cfgmem -hw_device $device $cfgmem_part]
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
set_property PROGRAM.FILES [list $flash_image_path] $cfgmem
set_property PROGRAM.PRM_FILE {} $cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
set_property PROGRAM.BLANK_CHECK 0 $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
set_property PROGRAM.VERIFY 1 $cfgmem
set_property PROGRAM.CHECKSUM 0 $cfgmem

if {![string equal \
        [get_property PROGRAM.HW_CFGMEM_TYPE $device] \
        [get_property MEM_TYPE [get_property CFGMEM_PART $cfgmem]]]} {
    create_hw_bitstream -hw_device $device \
        [get_property PROGRAM.HW_CFGMEM_BITFILE $device]
    program_hw_devices $device
}

program_hw_cfgmem -hw_cfgmem $cfgmem
puts "Programmed and verified Cmod A7 Quad-SPI flash: $flash_image_path"

# Indirect flash programming leaves a helper design in the FPGA. Restore the
# requested SoC immediately; the flash image itself will be used on power-up.
set_property PROGRAM.FILE $bitstream_path $device
program_hw_devices $device
refresh_hw_device $device
puts "Restored volatile FPGA configuration: $bitstream_path"

close_hw_manager
exit
