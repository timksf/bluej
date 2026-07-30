# SPDX-License-Identifier: MIT

set bitstream_path [lindex $argv 0]
set flash_image_path [lindex $argv 1]

if {$bitstream_path eq "" || $flash_image_path eq ""} {
    error "usage: vivado -mode batch -source create_flash_image.tcl -tclargs <bitstream.bit> <flash.mcs>"
}

set bitstream_path [file normalize $bitstream_path]
set flash_image_path [file normalize $flash_image_path]

if {![file exists $bitstream_path]} {
    error "bitstream does not exist: $bitstream_path"
}

file mkdir [file dirname $flash_image_path]

write_cfgmem -force \
    -format mcs \
    -size 4 \
    -interface SPIx4 \
    -loadbit [format "up 0x00000000 %s" $bitstream_path] \
    -file $flash_image_path

puts "Created Cmod A7 Quad-SPI image: $flash_image_path"
exit
