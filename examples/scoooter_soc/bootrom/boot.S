/* First-stage boot ROM.  A debugger/programmer places the second stage at
 * 0x80000000, then reset enters here at 0x00000000. */
.section .text.init
.globl _start
_start:
    lui     sp, 0x80001          /* stack: 0x80001000 */
    lui     t0, 0x80000          /* RAM entry: 0x80000000 */
    jalr    x0, 0(t0)
1:  j       1b
