# RISC-V JTAG DTM and DMI AXI4-Lite Bridge

The implementation targets the supplied **RISC-V External Debug Support
0.13.2** document. The new transport logic was derived from sections 3.1 and
6.1 and appendix B.1 of that document. It does not use another DTM or DMI
implementation as a source.

## Layers

- `riscv_dtm` is a `JTAGSystem#(2, 5)` context module. It owns DTMCS/DMI
  state, sticky busy and error behavior, native JTAG capture/update events,
  and the DMI AXI4-Lite master interface.
- `mkRISCVDMIAXI4Lite` is independent of JTAG. It converts DMI requests to a
  32-bit AXI4-Lite master interface.
- `riscv_dtm_system` configures the standalone DTM TAP and
  `mkRISCVDTMAXI4Lite` builds the generic pin-level system. The same
  module can sit behind `mkBSCAN2JTAG` when a nested TAP is required on a
  Xilinx BSCANE2 USER chain.
- `mkRISCVDM` implements a minimal single-hart RV32 Debug Module. It exposes
  a DMI AXI4-Lite slave, a direct abstract-register hart port, and a separate
  AXI4-Lite master for System Bus Access.
- `mkRISCVJTAGDebug` connects the standard JTAG DTM to `mkRISCVDM` and exposes
  the hart and system-bus interfaces as one pin-level JTAG system.

The standard instruction assignments are fixed in the wrapper:

| IR | Data register |
|---:|---|
| `0x01` | IDCODE |
| `0x10` | DTMCS (32 bits) |
| `0x11` | DMI (`abits + 34` bits) |
| other | BYPASS (1 bit) |

The TAP uses a 5-bit IR and restores IDCODE after Test-Logic-Reset.

A parent with the same `JTAGSystem#(2, 5)` context can instantiate
`riscv_dtm` directly, provide its own TAP configuration, and call
`build_jtag_system`. The current type-indexed collection cannot merge the DTM
into a larger endpoint count; that would require a composable endpoint-bundle
API.

## DTM state and DM BlueCSR fields

DTMCS and DMI are the two native JTAG registers. The generic JTAG register
captures the current DTM value; its capture pulse supplies DMI's busy side
effect, so no custom DMI scan-register implementation or private BlueCSR map
is required.

The DM register map also uses BlueCSR for field storage and metadata. Its
offsets are the DMI word indices converted to byte addresses by the DMI AXI
bridge: `DATA0` at `0x010`, `DMCONTROL` at `0x040`, `DMSTATUS` at `0x044`,
`ABSTRACTCS` at `0x058`, `COMMAND` at `0x05c`, `SBCS` at `0x0e0`,
`SBADDRESS0` at `0x0e4`, `SBDATA0` at `0x0f0`, and `HALTSUM0` at `0x100`.
BlueCSR is the live address decoder and its AXI4-Lite adapter is the DM's DMI
slave. `csr_reg_hu`, `csr_reg_ho`, and `csr_reg_w1c` keep the live field state
inside BlueCSR. Register writes use the field's normal access semantics, then
delayed triggers let DM rules inspect the updated fields and add side effects;
there is no second DM address decoder. The map selects
`CSR_OKAY` with zero read data for addresses outside the declared map, so
unimplemented DMI registers read as zero and ignore writes as required by the
debug specification. Every declared DM register has explicit read and write
behavior, so the fallback is reached only for an unmapped address without
requiring a second address-membership decoder.

## Minimal Debug Module profile

The DM implements one RV32 hart with `HARTSELLEN=0`, no hart array mask, no
authentication block, and no Program Buffer. Mandatory Access Register
commands are forwarded through `RISCVDMHartPort_ifc` for GPRs, `dcsr`, and
`dpc`. The hart integration supplies current running/halted/unavailable status,
accepts halt/resume/reset-acknowledge requests, and services the typed abstract
register client.

System Bus Access implements version 1 with a 32-bit address and 32-bit data
path. `sbreadonaddr`, `sbreadondata`, and `sbautoincrement` are supported.
Alignment, unsupported-size, busy, and AXI response failures are reported
through the sticky `sbbusyerror` and `sberror` fields. A transaction already
accepted by AXI is drained and discarded if `dmactive` resets the DM.

## AXI4-Lite mapping

DMI addresses are word indices. The bridge produces the AXI byte address
`zeroExtend(dmi_address) << 2`, uses full write strobes, and permits one AXI
transaction at a time. AXI `OKAY` and `EXOKAY` map to DMI success; `SLVERR`
and `DECERR` map to the sticky DMI failure response.

`dmihardreset` changes an epoch tag and forgets the outstanding transaction in
the DTM. An AXI response from the old epoch is still drained but cannot modify
new DTM state. Since AXI4-Lite has no cancellation operation, a target that
never completes an already accepted transaction still requires coordinated
system/interconnect reset. The AXI-domain `hard_reset` pulse is exposed for
that purpose.

## Verification

Run the focused simulations with:

```bash
make -C hdl RUN_TEST=TestRISCVDMIAXI4Lite sim
make -C hdl RUN_TEST=TestRISCVJTAGDTM sim
make -C hdl RUN_TEST=TestRISCVDM sim
make -C hdl RUN_TEST=TestBlueCSRUnmapped sim
```

The tests cover DTMCS packing, successful DMI access, sticky busy and error,
`dmireset`, `dmihardreset` with a stale response, AXI address/data/error
mapping, clock-domain crossing, reserved-instruction BYPASS, and IDCODE
restoration through Test-Logic-Reset. The DM test additionally covers
activation, hart halt/resume, abstract GPR reads and writes, unimplemented DMI
registers, SBA reads and writes, auto-increment, alignment faults, and AXI
errors. The BlueCSR test checks the legacy and configurable fallback responses
for unmatched accesses.
