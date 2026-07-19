set pagination off
set confirm off
set architecture riscv:rv32
target extended-remote localhost:3333
monitor halt
load hdl/build/scoooter-gdb.elf
set $pc = _start
set $t0 = 0
set $sp = _stack_top

stepi
if $pc != (_start + 4)
    echo ERROR: stepi did not advance PC by one instruction\n
    quit 1
end
if $t0 != 1
    echo ERROR: stepi did not commit the first instruction\n
    quit 1
end

break breakpoint_site
continue
if $pc != breakpoint_site
    echo ERROR: software breakpoint stopped at the wrong PC\n
    quit 1
end
if $t0 != 3
    echo ERROR: execution before the software breakpoint was incorrect\n
    quit 1
end

delete breakpoints
stepi
if $pc != (breakpoint_site + 4)
    echo ERROR: stepping over the restored breakpoint instruction failed\n
    quit 1
end
if $t0 != 7
    echo ERROR: restored breakpoint instruction did not execute\n
    quit 1
end

echo SCOoOTER GDB test passed\n
disconnect
quit 0
