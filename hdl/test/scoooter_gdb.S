    .section .text.start, "ax", @progbits
    .global _start
    .global breakpoint_site

_start:
    addi t0, zero, 1
    addi t0, t0, 2

breakpoint_site:
    addi t0, t0, 4

park:
    jal zero, park
