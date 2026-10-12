adapter driver ftdi
ftdi vid_pid 0x0403 0x6014
ftdi layout_init 0x0008 0x000b
adapter speed 1000

transport select jtag

jtag newtap pa200t tap -irlen 6 -expected-id 0x13636093

init
scan_chain

irscan pa200t.tap 0x22
drscan pa200t.tap 34 0x17D78403
runtest 5