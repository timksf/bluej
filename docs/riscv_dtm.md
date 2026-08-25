# RISC-V JTAG Debug

BlueJ implements the JTAG Debug Transport Module and a minimal Debug Module
profile from the
[RISC-V External Debug Support Specification 0.13.2](https://docs.riscv.org/reference/debug-trace-ras/debug/v0.13.2/_attachments/riscv-debug.pdf).

## Layers

- `riscv_dtm` owns DTMCS and DMI scan state, sticky busy/error behavior, and
  the clock-domain crossing between JTAG TCK and a typed DMI client.
- `riscv_dtm_system` supplies the standard five-bit TAP configuration.
- `mkRISCVDTM` builds the standalone pin-level DTM.
- `mkRISCVDM` implements a parameterized multi-hart RV32 Debug Module. It
  exposes a typed DMI server, direct per-hart abstract-register ports, and a
  typed system-memory client for System Bus Access.
- `mkRISCVJTAGDebug` connects the DTM and DM into one pin-level JTAG system.

The DTM and DM use `Client`/`Server` interfaces directly. Bus-specific adapters
belong at the integration boundary and are not part of this implementation.

## JTAG Registers

The standalone DTM uses these standard instruction assignments:

| IR | Data register |
|---:|---|
| `0x01` | IDCODE |
| `0x10` | DTMCS (32 bits) |
| `0x11` | DMI (`abits + 34` bits) |
| other | BYPASS (1 bit) |

The TAP has a five-bit instruction register and restores IDCODE after
Test-Logic-Reset.

A parent using the same `JTAGSystem#(2, 5)` context can instantiate
`riscv_dtm` directly, provide its TAP configuration, and call
`build_jtag_system`.

## DTM Behavior

The DMI scan register reports `DMI_RESERVED` while a request is outstanding.
Starting another operation or capturing DMI before that request completes sets
the sticky busy status. A failed response sets the sticky failure status.
`dmireset` clears the sticky status.

`dmihardreset` changes the DTM epoch, clears its visible request state, and
generates a pulse in the DMI clock domain. Responses from an older epoch are
drained but cannot modify current DTM state.

## Debug Module Profile

`mkRISCVDM` implements a type-parameterized vector of RV32 harts. `HARTSELLEN`
is derived from the configured vector size, out-of-range selections report
nonexistent, and `HALTSUM0` reports the first 32 harts. Hart array masks,
authentication, and a Program Buffer are not implemented.

Each `RISCVDMHartPort_ifc`:

- supplies current running, halted, and unavailable status;
- accepts halt, resume, and reset-acknowledge requests; and
- services typed abstract GPR and CSR accesses while halted.

The supported Debug Module registers use their standard DMI word indices. The
internal BlueCSR map converts those indices to byte offsets:

| DMI register | Byte offset |
|---|---:|
| `DATA0` | `0x010` |
| `DMCONTROL` | `0x040` |
| `DMSTATUS` | `0x044` |
| `ABSTRACTCS` | `0x058` |
| `COMMAND` | `0x05c` |
| `SBCS` | `0x0e0` |
| `SBADDRESS0` | `0x0e4` |
| `SBDATA0` | `0x0f0` |
| `HALTSUM0` | `0x100` |

Unimplemented DMI registers read as zero and ignore writes, as required by the
0.13.2 specification.

## System Bus Access

System Bus Access version 1 uses a 32-bit address and 32-bit data path. Byte,
halfword, and word transfers are supported. The DM aligns memory requests,
sets the appropriate byte lanes, and shifts narrow read data back into the low
bits of `SBDATA0`.

`sbreadonaddr`, `sbreadondata`, and `sbautoincrement` are supported. Alignment,
unsupported-size, and busy failures are reported through the sticky
`sbbusyerror` and `sberror` fields.

The memory interface uses `MemoryRequest#(32, 32)` and
`MemoryResponse#(32)`. That response type has no error indication, so
interconnect error reporting must be added by a bus-specific wrapper if the
integration requires it.

## Verification

Run the focused simulations with:

```bash
make -C hdl RUN_TEST=TestRISCVJTAGDTM sim
make -C hdl RUN_TEST=TestRISCVDM sim
make -C hdl RUN_TEST=TestRISCVDMMulti sim
make -C hdl RUN_TEST=TestBlueCSRUnmapped sim
```

The tests cover:

- DTMCS packing, DMI reads and writes, clock-domain crossing,
  `dmihardreset`, BYPASS, and IDCODE restoration;
- DM activation, halt/resume, abstract GPR access, unmapped DMI registers,
  byte/halfword/word SBA access, auto-increment, and alignment faults;
- multi-hart selection, per-hart request routing, `HALTSUM0`, and nonexistent
  selectors; and
- BlueCSR fallback responses for unmapped accesses.
