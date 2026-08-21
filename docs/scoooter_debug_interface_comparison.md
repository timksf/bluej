# SCOoOTER debug interface portability note

## Conclusion

The RISC-V Debug Specification standardizes the externally visible Debug
Module behavior, DMI semantics, and architectural debug behavior. It does not
define one universal RTL wire bundle between a Debug Module (DM) and a hart.
The exact DM-to-hart ports, bus protocol, clock-domain crossings, and register
access transport are implementation choices. See the [Debug Module
specification](https://docs.riscv.org/reference/debug/v1.0/debug_module.html)
and its [implementation guidance](https://docs.riscv.org/reference/debug/implementations.html).

## Common PULP/OpenHW pattern

PULP's `riscv-dbg`, CV32E40P, and Ibex use the execution-based debug model:

- a level-sensitive `debug_req` asks the hart to enter Debug Mode;
- the hart reports halted/running status and reset state;
- the DM supplies the debug ROM or halt/exception addresses;
- abstract register access is performed by executing debug-ROM or Program
  Buffer instructions;
- the core implements the standard debug state, including `dcsr`, `dpc`,
  `dscratch0`, `dscratch1`, and `dret`.

The PULP interface is described in the [`riscv-dbg` debug-system
documentation](https://github.com/pulp-platform/riscv-dbg/blob/master/doc/debug-system.md).
The CV32E40P top-level ports show the usual separation between `debug_req_i`
and the `debug_halted_o`, `debug_running_o`, and `debug_havereset_o` status
signals ([source](https://github.com/openhwgroup/cv32e40p/blob/master/rtl/cv32e40p_top.sv)).

This does not mean that PULP has a mandatory physical DM bus either. Its DMI
and internal DM buses are also implementation-specific; the important part is
the debugger-visible behavior and the execution-based hart contract.

## Current SCOoTER interface

SCOoTER currently exposes [`ScoooterDebugHartIFC`](../examples/SCOoOTER/core/src/src_core/Interfaces.bsv),
which contains:

- `halt_request` and `resume_request` inputs;
- `halted` and `running` status outputs;
- direct `read_register` and `write_register` methods.

The SoC connects these methods directly to the BlueJ DM in
[`ScoooterSystem.bsv`](../examples/scoooter_soc/src/ScoooterSystem.bsv). The
DM-side BSV interface is defined in
[`RISCV_DM.bsv`](../hdl/src/RISCV_DM.bsv).

| Area | PULP/OpenHW execution-based model | Current SCOoTER model |
|---|---|---|
| Halt control | `debug_req` plus resume protocol | `halt_request`, `resume_request` |
| Status | halted/running/havereset, often resume acknowledgement | halted/running; reset status is not exposed by the hart interface |
| Register access | Debug ROM/Program Buffer execution | Direct register-number read/write methods |
| Halt entry | Enter Debug Mode at a DM-provided address | Drain the pipeline, capture the PC, and halt internally |
| Debug state | `dcsr`, `dpc`, `dscratch0/1`, `dret` | `dcsr` and `dpc` with custom single-step; no debug-ROM path |
| Reset reporting | Sticky `havereset` and reset acknowledgement | BlueJ has `reset_seen`, but the SCOoTER SoC does not currently connect it |

## Compatibility assessment

The SCOoTER run-control concept is close enough for the current BlueJ DM and
OpenOCD flow, but its core-facing interface is not a drop-in target for the
generic PULP `riscv-dbg` core port. In particular, PULP expects a hart that
executes debug-ROM/Program Buffer operations; SCOoTER instead gives the DM
direct access to committed architectural state.

That direct path is a reasonable private implementation choice. It is not
necessary for an external debugger to know whether the DM implements an
abstract command by direct wires or by executing instructions. It does mean
that the current implementation should be described as a SCOoTER/BlueJ
integration backend rather than as a generally reusable PULP-compatible hart
debug interface.

One concrete integration gap is reset reporting: the DM already has a
`reset_seen` method, but [`ScoooterSystem.bsv`](../examples/scoooter_soc/src/ScoooterSystem.bsv)
only drives halted/running/unavailable status. Wiring reset observation would
improve OpenOCD's ability to report external hart resets.

## Suggested upstream split

The SCOoTER core does not need to contain a DM or depend on BlueCSR. A clean
split is:

1. Keep the current direct-debug support in SCOoTER, clearly documented as a
   core-specific interface, if the goal is the smallest working bring-up PR.
2. Keep the BlueJ DM and its adapter in the SoC/integration repository.
3. Add a later execution-based compatibility layer only if SCOoTER should be
   usable with generic PULP/OpenHW-style DMs. That layer would need
   `debug_req`, halted/running/havereset, debug-ROM addresses, the complete
   debug CSR set, and `dret` semantics.

This keeps a DM out of the processor repository and avoids making BlueCSR a
submodule merely to upstream the current SCOoTER debug support.
