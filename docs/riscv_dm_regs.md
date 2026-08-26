| Address | Register | Register Description | Field | Bits | Access | Reset | Field Description |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0x010 | DATA0 | Abstract command argument and result | DATA | [31:00] | RW | 0x0 | Abstract command argument zero. |
| 0x040 | DMCONTROL | Debug Module control | HALTREQ | [31:31] | WO | 0x0 | Requests that the selected hart halt. |
|  |  |  | RESUMEREQ | [30:30] | WO | 0x0 | Requests that the selected hart resume. |
|  |  |  | ACKHAVERESET | [28:28] | WO | 0x0 | Clears the selected hart's reset indication. |
|  |  |  | HASEL | [26:26] | RC | 0x0 | Hart array selection is not implemented. |
|  |  |  | HARTSELLO | [25:16] | RW | 0x0 | Low ten bits of the selected hart index. |
|  |  |  | HARTSELHI | [15:06] | RW | 0x0 | High ten bits of the selected hart index. |
|  |  |  | NDMRESET | [01:01] | RW | 0x0 | Resets the platform outside the Debug Module. |
|  |  |  | DMACTIVE | [00:00] | RW | 0x0 | Enables Debug Module operation. |
| 0x044 | DMSTATUS | Debug Module status | ALLHAVERESET | [19:19] | RO | 0x0 | All selected harts have reset. |
|  |  |  | ANYHAVERESET | [18:18] | RO | 0x0 | Any selected hart has reset. |
|  |  |  | ALLRESUMEACK | [17:17] | RO | 0x0 | All selected harts acknowledged resume. |
|  |  |  | ANYRESUMEACK | [16:16] | RO | 0x0 | Any selected hart acknowledged resume. |
|  |  |  | ALLNONEXISTENT | [15:15] | RO | 0x0 | All selected harts are nonexistent. |
|  |  |  | ANYNONEXISTENT | [14:14] | RO | 0x0 | Any selected hart is nonexistent. |
|  |  |  | ALLUNAVAIL | [13:13] | RO | 0x1 | All selected harts are unavailable. |
|  |  |  | ANYUNAVAIL | [12:12] | RO | 0x1 | Any selected harts are unavailable. |
|  |  |  | ALLRUNNING | [11:11] | RO | 0x0 | All selected harts are running. |
|  |  |  | ANYRUNNING | [10:10] | RO | 0x0 | Any selected harts are running. |
|  |  |  | ALLHALTED | [09:09] | RO | 0x0 | All selected harts are halted. |
|  |  |  | ANYHALTED | [08:08] | RO | 0x0 | Any selected hart is halted. |
|  |  |  | AUTHENTICATED | [07:07] | RC | 0x1 | Authentication is not implemented and access is permitted. |
|  |  |  | VERSION | [03:00] | RC | 0x2 | RISC-V Debug Specification version 0.13. |
| 0x058 | ABSTRACTCS | Abstract command status | DATACOUNT | [03:00] | RC | 0x1 | One data register is implemented. |
|  |  |  | CMDERR | [10:08] | W1C | 0x0 | Sticky abstract command error. |
|  |  |  | BUSY | [12:12] | RO | 0x0 | An abstract command is executing. |
|  |  |  | PROGBUFSIZE | [28:24] | RC | 0x0 | No Program Buffer is implemented. |
| 0x05c | COMMAND | Abstract command | CONTROL | [31:00] | WO | 0x0 | Access Register command encoding. |
| 0x0e0 | SBCS | System Bus Access control and status | SBVERSION | [31:29] | RC | 0x1 | System Bus Access version 1. |
|  |  |  | SBBUSYERROR | [22:22] | W1C | 0x0 | An access was attempted while busy. |
|  |  |  | SBBUSY | [21:21] | RO | 0x0 | A system bus transaction is outstanding. |
|  |  |  | SBREADONADDR | [20:20] | RW | 0x0 | Writing SBADDRESS0 starts a read. |
|  |  |  | SBACCESS | [19:17] | RW | 0x2 | System bus access size. |
|  |  |  | SBAUTOINCREMENT | [16:16] | RW | 0x0 | Increment the address after a successful access. |
|  |  |  | SBREADONDATA | [15:15] | RW | 0x0 | Reading SBDATA0 starts another read. |
|  |  |  | SBERROR | [14:12] | W1C | 0x0 | Sticky system bus access error. |
|  |  |  | SBASIZE | [11:05] | RC | 0x20 | System bus address width. |
|  |  |  | SBACCESS32 | [02:02] | RC | 0x1 | 32-bit system bus access is supported. |
|  |  |  | SBACCESS16 | [01:01] | RC | 0x1 | 16-bit system bus access is supported. |
|  |  |  | SBACCESS8 | [00:00] | RC | 0x1 | 8-bit system bus access is supported. |
| 0x0e4 | SBADDRESS0 | System Bus Access address | ADDRESS | [31:00] | RW | 0x0 | System bus byte address. |
| 0x0f0 | SBDATA0 | System Bus Access data | DATA | [31:00] | RW | 0x0 | System bus access data. |
| 0x100 | HALTSUM0 | Halted hart summary | HALTED | [31:00] | RO | 0x0 | One bit per halted hart for hart indices zero through 31. |