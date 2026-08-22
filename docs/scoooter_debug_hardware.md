# SCOoOTER debug hardware

This document describes the debug hardware implemented inside SCOoOTER.

## Configuration

Debug support is opt-in. Define `SCOOOTER_DEBUG` when compiling the core. A
build without the define has no debug ports, debug state, or debug pipeline
controls.

The core exposes one `DebugHartIFC` for each hardware thread. `Dave` preserves
the same shape as `Vector#(NUM_CPU, Vector#(NUM_THREADS, DebugHartIFC))`.
The abstract register protocol and bridge contract are documented in
[`examples/SCOoOTER/docs/debug_interface.md`](../examples/SCOoOTER/docs/debug_interface.md).

## Run control

Each hart has independent halt-pending, halted, single-step, `dpc`, `dcsr`,
and reset-indication state.

An external halt request first stops fetch and issue for the selected hart.
Already-issued instructions are allowed to retire. The hart reports halted
only after its reorder-buffer entries and the shared store buffer are empty.
At that point the architectural next PC is recorded in `dpc` and a halt
request records cause 3 (halt request).

Resume redirects the backend to the aligned value of `dpc`. If `dcsr.step` is
set, Commit lets one instruction become architectural state, redirects to its
next PC, and enters debug again with cause 4. A machine-mode `ebreak` enters
debug with cause 1 when `dcsr.ebreakm` is set; `dpc` remains the breakpoint
instruction address so software breakpoints can be restored and stepped.

The core reports a sticky `havereset` indication after core reset. A consumer
may observe and acknowledge it with `ackhavereset`. A subsequent core reset
asserts it again. Generating a platform reset from an external consumer is
outside this core interface.

## Architectural state

Debug register access is accepted only while the hart is halted.

- `0x1000`–`0x101f` access committed `x0`–`x31`. `x0` reads as zero and ignores
  writes.
- CSR numbers below `0x1000` use the CSR file's implemented-register lookup
  and write masks.
- `dcsr` (`0x7b0`) and `dpc` (`0x7b1`) are debug-only CSRs stored in the CSR
  file. `dpc` is aligned to the core's 32-bit instruction alignment.

An unsupported CSR is reported as unsupported by the abstract interface. It
is not returned as zero and a write is not acknowledged.

`dcsr` implements the RISC-V Debug Specification 0.13.2 fields used by this
core: `xdebugver=4`, machine-mode privilege, `cause`, `step`, and `ebreakm`.
The `ebreaks` and `ebreaku` fields, along with other optional execution-mode
controls, are hardwired to their reset values because SCOoOTER implements
machine mode only.

## 0.13.2 scope

The SCOoOTER endpoint implements the 0.13.2 core-facing debug operations:
per-hart run control and status, GPR abstract access, `dcsr`/`dpc`, implemented
machine CSR access, halt causes, and reset indication. Program Buffer, trigger
CSRs, and supervisor/user debug execution are not implemented by the core.

## Source layout

- `core/src/src_core/Interfaces.bsv`: public debug types and `DebugHartIFC`.
- `core/src/src_core/SCOOOTER_riscv.bsv`: per-hart state machine and abstract
  access endpoint.
- `core/src/src_core/frontend/Fetch.bsv` and `Frontend.bsv`: fetch stopping.
- `core/src/src_core/exec_core/Issue.bsv`: issue stopping.
- `core/src/src_core/backend/Commit.bsv`: precise debug entry and stepping.
- `core/src/src_core/backend/ReorderBuffer.bsv`: per-hart quiescence.
- `core/src/src_core/backend/regfile/CSRFile.bsv`: debug CSRs and CSR access.
- `core/src/src_core/backend/regfile/RegFileArch.bsv`: committed GPR access.
