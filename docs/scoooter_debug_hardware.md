# SCOoOTER hardware changes for external debugging

This document describes the changes made to SCOoOTER so that OpenOCD and GDB
can control it through the RISC-V Debug Module (DM). It focuses on hardware
inside SCOoOTER and explains why each change is necessary. The JTAG Debug
Transport Module (DTM), DM, and Bluesim memory model are described only where
they define a requirement at the core boundary.

## Debug path and ownership

The complete simulation path is:

For the relationship between this private SCOoTER/BlueJ interface and the
execution-based interfaces used by PULP/OpenHW cores, see the
[`SCOoTER debug interface portability note`](scoooter_debug_interface_comparison.md).

```text
GDB
 `- OpenOCD
     `- remote-bitbang JTAG
         `- RISC-V DTM
             `- RISC-V DM
                 |- per-hart halt, resume, status, and register requests
                 |   `- SCOoOTER debug_harts interface
                 `- System Bus Access
                     `- boot ROM / writable executable RAM
```

The DM implements the RISC-V external debug register protocol. SCOoOTER does
not decode DMI registers and does not contain the JTAG transport. Instead, it
exposes one `ScoooterDebugHartIFC` per hardware thread. This keeps transport
logic outside the processor and gives each hart only the controls it needs:

- halt and resume requests;
- halted and running status;
- architectural register reads and writes.

The per-hart interfaces are vectors at both the core and multicore `Dave`
levels. The DM-facing integration flattens them using
`cpu * NUM_THREADS + thread`. This was necessary because SCOoOTER already
supports configurable CPU and thread counts, while the DM addresses harts by
a single numeric index.

## Summary of core changes

| Requirement | SCOoOTER hardware change | Why it was needed |
|---|---|---|
| Select and control each hart independently | Added a vector of `ScoooterDebugHartIFC` ports to `Top` and `DaveIFC`, plus per-thread debug state | The DM must report and control the selected hart without assuming a fixed hart count |
| Stop at an architectural boundary | Stall new fetch and issue work, then wait for the selected hart's ROB and the store buffer to drain | Immediately freezing an out-of-order pipeline could expose speculative or partially completed state to GDB |
| Read and modify GPRs | Added halted-only access to the committed architectural register file | Abstract Access Register commands must see committed state; speculative rename state is not a valid debugger view |
| Read and modify CSRs | Added direct access through the existing CSR decode and write masks | OpenOCD reads machine state and may update CSRs without a Program Buffer |
| Represent debug state | Added per-hart `dpc`, `dcsr`, halt cause, pending, halted, and step state | These registers and state transitions are required to preserve the resume PC and explain why a hart stopped |
| Resume at a debugger-selected PC | Added a backend redirect sourced from `dpc` | GDB can write the PC, and resume must invalidate prefetched or speculative work from the old path |
| Execute exactly one instruction | Added commit-boundary step control, a redirect after the selected instruction, and a debug event | Stopping in fetch or issue does not identify a precise architectural instruction boundary |
| Support GDB software breakpoints | Intercept machine-mode `ebreak` at Commit when `dcsr.ebreakm` is set | A software breakpoint must enter debug at its own PC rather than take the normal machine breakpoint trap |
| Remove unused debug hardware | Guarded all ports and internal paths with `SCOOOTER_DISABLE_DEBUG` | Debug is optional and should not impose interface or implementation cost on non-debug builds |

## Per-hart halt and resume state

The main state machine is in `SCOOOTER_riscv.bsv`. Each thread has independent
halt-pending, capture-pending, halted, single-step, `dpc`, `dcsr`, and halt-cause
state.

An external halt proceeds in phases:

1. A halt request marks the selected hart halt-pending.
2. Fetch stops issuing new instruction-memory requests for that thread.
3. Issue removes already-decoded instructions for that thread without sending
   them to reservation stations or the ROB.
4. Instructions already in the backend are allowed to complete and retire.
5. The hart waits until its ROB contains no entries and the shared store buffer
   contains neither buffered nor pending stores.
6. The architectural next PC is copied into `dpc`, `dcsr.cause` is set, and the
   hart reports halted to the DM.

This drain-before-halt behavior is important for an out-of-order core. It
ensures that GDB observes committed register values and that a store accepted
before the halt is not left ambiguously half-completed. The current store
buffer is shared, so `memory_quiescent` is deliberately conservative: a hart
may wait for stores from other threads before it reports halted.

The store-buffer `empty` indication was also corrected to require both the
internal queue and the pending queue to be empty. Testing `pending_buf.notFull`
did not prove that there was no outstanding store and was therefore unsafe as
a halt-completion condition.

On resume, the hart clears its halted state and redirects the backend to
`dpc`. The normal redirect and epoch machinery flushes younger work and makes
the debugger-written PC authoritative. If `dcsr.step` is set, resume also arms
the per-hart single-step state.

## Fetch and issue controls

Debug stall controls were added at two different pipeline points:

- `Fetch` suppresses new memory requests for a halted or halt-pending thread.
- `Issue` prevents that thread's decoded instructions from being allocated to
  backend resources. Those decode entries are dequeued and discarded.

Both controls are required. A fetch-only stop would leave instructions already
buffered by decode free to enter the backend after a halt request. An
issue-only stop would allow fetch queues and instruction-memory traffic to
continue growing while the hart is halted.

The controls are vectors indexed by thread. Other threads can continue to
fetch and issue while one thread is being halted, subject to shared-resource
effects such as the conservative store-buffer drain.

## Detecting a quiescent architectural state

The reorder buffer gained a per-thread occupancy query. Each ROB row reports
whether it contains an entry for the selected thread; banks and the complete
ROB reduce those results into `hart_empty(thread_id)`.

This is different from checking whether the entire ROB is empty. A global
empty test would unnecessarily require all harts to stop before one selected
hart could be debugged. The per-thread query is what makes independent
multi-hart halt status possible.

The execution core also exports whether the store buffer is empty. SCOoOTER
does not currently track store-buffer emptiness per hart, so this part remains
global.

## Architectural register access

The Debug Module's abstract Access Register command uses the core's direct
register methods. They are enabled only while the selected hart reports
halted, preventing debugger writes from racing normal retirement.

### General-purpose registers

DM register numbers `0x1000` through `0x101f` map to `x0` through `x31`.
Debug reads use the committed architectural register file rather than the
speculative register state. Reads of `x0` always return zero and writes to
`x0` are ignored.

Both architectural register-file implementations gained equivalent debug
methods, so the external behavior does not depend on which implementation is
selected in the SCOoOTER configuration.

### CSRs, DPC, and DCSR

CSR-numbered accesses below `0x1000` are delegated to the existing CSR file.
The existing CSR lookup determines whether a CSR is implemented, and writes
retain the core's masks and alignment behavior for registers such as
`mstatus`, `mie`, and `mepc`.

`dcsr` (`0x7b0`) and `dpc` (`0x7b1`) are held in the debug integration rather
than the normal machine CSR file. Only the implemented DCSR controls are
writable: `step` and the `ebreakm`, `ebreaks`, and `ebreaku` bits. The debug
logic supplies the fixed fields and updates `cause` when the hart enters debug.
`dpc` writes are aligned before they are used as a resume target.

Direct access was chosen because the current DM has no Program Buffer. A
Program Buffer could make the hart execute CSR and memory-access instructions
on behalf of the debugger, but it would require a debug execution mode and
more pipeline machinery. Direct access is sufficient for the current GDB
workflow and keeps the first implementation smaller.

## Precise single-step

Single-step is implemented at Commit, which is the point where an instruction
becomes architecturally visible.

When a halted hart resumes with `dcsr.step` set:

1. The top-level debug state marks that hart step-active.
2. Commit masks normal interrupt entry for the stepping hart while the step is
   active.
3. The first instruction of that hart reaching Commit is allowed to produce
   its architectural result.
4. Commit redirects to the instruction's architectural next PC. This also
   invalidates younger speculative instructions, including another instruction
   that may be present in the same commit group.
5. Commit emits `ScoooterDebugEvent { dpc, cause }` with cause 4 (`step`).
6. The top-level halt state machine drains the remaining backend and memory
   state, records the supplied `dpc`, and reports the hart halted again.

Commit also emits a step event when the stepped instruction reaches Commit as
an exception, using the next PC selected by the existing exception path. This
keeps the debugger stop precise with respect to the instruction observed at
Commit.

The event is registered before the top-level state machine consumes it. This
breaks a potential combinational scheduling path between commit redirection
and halt control and makes the debug entry a normal state transition.

## Software breakpoints

GDB normally implements a software breakpoint by replacing an instruction in
writable memory with `ebreak`. On a hit, OpenOCD restores the original
instruction and uses single-step to execute it before reinserting the
breakpoint.

SCOoOTER already decoded `ebreak` as a breakpoint exception, but normal
exception handling would redirect it to `mtvec`. Commit now checks
`dcsr.ebreakm` for a machine-mode breakpoint. When enabled, it instead:

- suppresses the normal machine trap path;
- redirects to the breakpoint instruction's own PC;
- emits a debug event with cause 1 (`ebreak`);
- records that instruction PC in `dpc` and enters the normal drain-to-halt
  sequence.

Keeping `dpc` on the breakpoint instruction is required because OpenOCD must
restore and execute the displaced instruction. This provides GDB software
breakpoints without adding trigger CSRs or hardware comparators. Trigger-based
hardware breakpoints are still unimplemented.

## Memory changes required by the GDB flow

The boot ROM and writable RAM are integration changes in
`TestScoooterOOCD.bsv`, not modifications to the SCOoOTER pipeline:

| Address range | Model | Purpose |
|---|---|---|
| `0x00000000`-`0x00000fff` | Read-only boot ROM | Supplies a deterministic `jal x0, 0` reset loop so the hart has a safe state before GDB connects |
| `0x80000000`-`0x80000fff` | Writable executable RAM | Holds the ELF loaded by GDB and permits software-breakpoint patching |

The RAM is shared by instruction fetch, SCOoOTER data accesses, and the DM's
System Bus Access port. This is necessary because GDB `load` writes memory
through the DM while the core later fetches the same bytes as instructions.
The DM supports byte, halfword, and word System Bus Access because OpenOCD may
use sub-word writes while patching instructions.

A read-only boot ROM alone would allow halt and register inspection, but GDB
could neither load a new program nor insert software breakpoints. Flash/SPI
emulation was therefore unnecessary for the first implementation; the RAM
model supplies the same debugger-visible capability with much less peripheral
logic.

## Compile-time removal

Debug support is enabled by default. Defining
`SCOOOTER_DISABLE_DEBUG` removes:

- the public per-hart debug interfaces;
- per-hart halt, DPC, DCSR, and step state;
- fetch and issue debug-stall paths;
- ROB hart-occupancy and backend debug methods;
- direct architectural GPR and CSR access;
- commit-time step and `ebreak` debug-entry logic.

The guards are applied throughout the hierarchy rather than only hiding the
top-level ports. Consequently, a disabled build does not retain otherwise
unreachable debug state and datapaths. `TestScoooterNoDebug` elaborates and
runs this configuration.

The hart-count overrides `SCOOOTER_NUM_CPU` and `SCOOOTER_NUM_THREADS` are
separate macros. They allow the debug integration tests to exercise the same
configurable hart topology used by the core.

## Files changed inside SCOoOTER

| File | Debug-related responsibility |
|---|---|
| `core/src/Config.bsv` | Documents the disable macro and permits test-time CPU/thread-count overrides |
| `core/src/src_core/Interfaces.bsv` | Defines debug events, per-hart ports, and internal debug methods |
| `core/src/src_core/Dave.bsv` | Exposes every CPU/thread debug port at the multicore level |
| `core/src/src_core/SCOOOTER_riscv.bsv` | Owns per-hart halt/resume, DPC/DCSR, register routing, drain, and resume redirection |
| `core/src/src_core/frontend/Fetch.bsv` and `Frontend.bsv` | Stop new fetch traffic for selected threads |
| `core/src/src_core/exec_core/Issue.bsv` and `ExecCore.bsv` | Drop selected decoded work and report memory quiescence |
| `core/src/src_core/exec_core/StoreBuffer.bsv` | Provides a correct empty indication for safe halt completion |
| `core/src/src_core/backend/ReorderBuffer.bsv` | Reports per-thread ROB occupancy |
| `core/src/src_core/backend/Backend.bsv` | Routes debug control, status, events, redirects, GPRs, and CSRs |
| `core/src/src_core/backend/Commit.bsv` | Supplies precise PC capture, single-step, and `ebreak` debug entry |
| `core/src/src_core/backend/regfile/RegFileArch.bsv` | Provides halted architectural GPR access |
| `core/src/src_core/backend/regfile/CSRFile.bsv` | Provides direct access to implemented machine CSRs |

## Current scope and limitations

The implemented hardware supports the current single-hart GDB workflow and
keeps the interface parameterized for multiple harts. It does not yet provide:

- a Program Buffer or abstract command post-execution;
- trigger CSRs and hardware instruction/data breakpoints;
- `ndmreset` integration with SCOoOTER or the surrounding memory system;
- per-hart store-buffer quiescence;
- a synthesized boot ROM or RAM choice for a particular FPGA target.

The end-to-end regression in `hdl/test/scoooter_gdb.gdb` verifies ELF loading,
successive `stepi` operations, software-breakpoint entry, breakpoint removal,
and stepping over the restored instruction. The DTM/DM protocol and register
details are documented separately in [`riscv_dtm.md`](riscv_dtm.md).
