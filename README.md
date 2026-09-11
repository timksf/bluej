# BlueJ

BlueJ is a Bluespec library for exposing FPGA design internals through JTAG.
It provides reusable TAP, register, clock-domain crossing, bus-access, Xilinx
`BSCANE2`, OpenOCD simulation, and RISC-V debug building blocks.

The current hardware flow targets Xilinx FPGAs through `BSCANE2`. The generic
TAP and register logic can also be used with external JTAG pins or in
simulation.

## Status

Available now:

- IEEE 1149.1-style TAP state machine with IDCODE and BYPASS registers.
- Read-only, write-only, read/write, pulse, and synchronized JTAG endpoints.
- A system builder that collects endpoints and derives their instruction map.
- A simple clock-crossing JTAG bus adapter.
- Xilinx `BSCANE2` integration and a nested-TAP tunnel.
- Bluesim, Verilog, and OpenOCD remote-bitbang simulation support.
- A RISC-V Debug Specification 0.13.2 JTAG DTM and parameterized RV32 Debug
  Module with multi-hart support and 8/16/32-bit System Bus Access.

Still experimental:

- Host tooling for driving the nested TAP tunnel through a Xilinx USER chain.
- FPGA examples outside the default Xilinx target.
- Hardware validation on additional boards.

## Requirements

- Git with submodule support.
- Nix flakes, or local installations of Bluespec, GCC, CMake, and Icarus
  Verilog.
- OpenOCD for the remote-bitbang example.
- Vivado for the Xilinx FPGA flow.

The provided Nix development shell currently supports `x86_64-linux`. OpenOCD
and Vivado are not included in that shell.

## Getting Started

Clone BlueJ and initialize only its direct dependencies:

```bash
git clone https://github.com/timksf/bluej.git
cd bluej
git submodule update --init
```

Do not add `--recursive`: BlueCSR has an optional BlueFabric submodule used by
its APB adapter, while BlueJ only uses the BlueCSR core.

Enter the development shell and run the smoke tests:

```bash
nix develop ./nix
make -C hdl smoke
```

## Using BlueJ

Add `hdl/src`, `dep/bluexlnx/src`, and `dep/bluecsr/src` to the Bluespec search
path. Projects based on BSVTools can include `BlueJ.mk`, which adds those paths
and the simulation support files automatically.

A small JTAG system is constructed in two stages. First, define the endpoints
and TAP metadata inside a `JTAGSystem` context:

```bsv
import BlueJ :: *;

interface DebugRegs_ifc;
    method ActionValue#(Bit#(32)) control_updated;
endinterface

module [JTAGSystem#(1, 8)] debug_regs(DebugRegs_ifc);
    jtag_meta_config(0, 11'h23, 16'h4567);
    jtag_set_reg_tdo(True);
    jtag_set_idcode_instr(8'h01);
    jtag_rst_to_idcode;

    Reg#(Bit#(32)) rg_control <- mkReg(0);
    JTAGRegAccess_ifc#(Bit#(32)) i_control <- jtag_reg_rw(rg_control, 8'h10);

    method control_updated = i_control.updated;
endmodule
```

Then build the pin-level TAP using a rising-edge TCK clock and an inverted-TCK
clock for registered TDO:

```bsv
module mkDebugTAP#(Clock tdo_clk, Reset tdo_rst)(JTAGSystem_ifc#(DebugRegs_ifc));
    let system <- build_jtag_system(debug_regs, tdo_clk, tdo_rst);
    return system;
endmodule
```

The resulting interface exposes `tms`, `tdi`, and `tdo`, plus the design-side
interface returned by the context module. See
[`TestSystemAPI.bsv`](hdl/test/TestSystemAPI.bsv) for all endpoint variants and
[`jtag_clocking.md`](docs/jtag_clocking.md) for clocking requirements.

## Modules

Library modules and FPGA examples in `hdl/src`:

| Source file | Module | Description |
| --- | --- | --- |
| [JTAG_TAP.bsv](hdl/src/JTAG_TAP.bsv) | `mkJTAG_TAP_FSM` | Implements the 16-state JTAG TAP state machine. |
| [JTAG_TAP.bsv](hdl/src/JTAG_TAP.bsv) | `mkJTAG_TAP_Controller` | Decodes instructions and controls endpoint scans with IDCODE, BYPASS, and optional registered TDO. |
| [JTAG_TAP.bsv](hdl/src/JTAG_TAP.bsv) | `tapConnect` | Connects a TAP controller to an indexed JTAG endpoint. |
| [JTAG_Types.bsv](hdl/src/JTAG_Types.bsv) | `jtagConnect` | Forwards TAP control signals to an indexed downstream endpoint. |
| [JTAG_Reg.bsv](hdl/src/JTAG_Reg.bsv) | `mkJTAGReg` | Implements a capture, shift, and update data register without a reset value. |
| [JTAG_Reg.bsv](hdl/src/JTAG_Reg.bsv) | `mkJTAGRegR` | Implements a data register with an optional reset value for its update register. |
| [JTAG_Reg.bsv](hdl/src/JTAG_Reg.bsv) | `mkJTAGInstructionReg` | Implements an instruction register with configurable capture and TAP-reset values. |
| [JTAG_Reg.bsv](hdl/src/JTAG_Reg.bsv) | `mkJTAGBypass` | Implements the single-bit BYPASS data register. |
| [JTAG_Reg_Sync.bsv](hdl/src/JTAG_Reg_Sync.bsv) | `mkJTAG_Reg_Sync` | Transfers register data and JTAG events between TCK and the system clock domain. |
| [JTAG_Reg_Sync.bsv](hdl/src/JTAG_Reg_Sync.bsv) | `mkJTAG_Reg_SyncR` | Provides a synchronized JTAG register with an optional update-register reset value. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_meta_config` | Sets the IDCODE version, manufacturer, and part fields. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_set_reg_tdo` | Configures whether the TAP registers TDO. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_set_idcode_instr` | Assigns the IDCODE instruction encoding. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_rst_to_idcode` | Selects IDCODE after TAP reset. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_rst_to_bypass` | Selects BYPASS after TAP reset. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_enable_debug` | Enables TAP debug output. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_scan_endpoint` | Registers a standard scan target at a specified instruction. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_endpoint` | Registers a data-register endpoint at a specified instruction. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_reg_ro` | Adds a read-only data-register endpoint. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_reg_wo` | Adds a write-only data-register endpoint with update notification. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_reg_rw` | Adds a read/write endpoint connected to a design register. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_reg_pulse` | Adds an endpoint that generates a pulse on update. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_sync_reg_ro` | Adds a read-only endpoint synchronized from the system clock domain. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_sync_reg_wo` | Adds a write-only endpoint synchronized to the system clock domain. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_sync_reg_rw` | Adds a read/write endpoint connected to a system-clocked design register. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `jtag_sync_reg_pulse` | Adds an endpoint that delivers update pulses to the system clock domain. |
| [JTAG_System.bsv](hdl/src/JTAG_System.bsv) | `build_jtag_system` | Builds a pin-level TAP from the collected endpoints and configuration. |
| [JTAG_BusAdapter.bsv](hdl/src/JTAG_BusAdapter.bsv) | `mkJTAG_BusAdapterCore` | Converts data-register scans into bus requests and returns responses across clock domains. |
| [JTAG_BusAdapter.bsv](hdl/src/JTAG_BusAdapter.bsv) | `mkJTAG_BusAdapter` | Registers the bus adapter as an instruction-selected system endpoint. |
| [JTAG2AXI.bsv](hdl/src/JTAG2AXI.bsv) | `mkJTAG2AXI` | Converts bus-adapter requests into AXI4-Lite reads and writes with one outstanding transaction. |
| [JTAG_Xilinx.bsv](hdl/src/JTAG_Xilinx.bsv) | `mkBSCANE2_BlueJ_` | Wraps BSCANE2 as a single-endpoint TAP controller interface. |
| [JTAG_Xilinx.bsv](hdl/src/JTAG_Xilinx.bsv) | `connect_bscane2_to_target` | Forwards BSCANE2 control and TDI/TDO to a scan target. |
| [JTAG_Xilinx.bsv](hdl/src/JTAG_Xilinx.bsv) | `connect_bscane2_ctrl` | Forwards BSCANE2 capture, shift, update, and select signals to a BlueJ endpoint. |
| [JTAG_Xilinx.bsv](hdl/src/JTAG_Xilinx.bsv) | `mkBSCAN2JTAG` | Decodes a Xilinx USER-chain tunnel into nested-TAP signals and clocks. |
| [ClockUtil.bsv](hdl/src/ClockUtil.bsv) | `pack_clock` | Exposes a Bluespec clock as a single-bit signal. |
| [ClockUtil.bsv](hdl/src/ClockUtil.bsv) | `unpack_clock` | Converts a single-bit signal into a Bluespec clock. |
| [ClockUtil.bsv](hdl/src/ClockUtil.bsv) | `unpack_reset` | Converts a single-bit signal into a reset associated with the supplied clock. |
| [ClockUtil.bsv](hdl/src/ClockUtil.bsv) | `mkJTAGClockAdapter` | Generates TCK, inverted TCK, and their resets from bit-level clock and reset inputs. |
| [ClockUtil.bsv](hdl/src/ClockUtil.bsv) | `mkJTAGShim` | Adapts bit-level JTAG stimulus to the generated JTAG clock domains with registered signal transfers. |
| [ClockUtil.bsv](hdl/src/ClockUtil.bsv) | `mkJTAGTDONullCrossing` | Exposes TDO in the calling clock domain through a null crossing. |
| [JTAG_BDPI.bsv](hdl/src/JTAG_BDPI.bsv) | `mkJTAG_Driver_OOCD` | Drives simulation JTAG signals through a BDPI OpenOCD remote-bitbang connection. |
| [RISCV_DTM.bsv](hdl/src/RISCV_DTM.bsv) | `riscv_dtm` | Adds DTMCS and DMI endpoints with a clock-crossing DMI client to a JTAG system. |
| [RISCV_DTM.bsv](hdl/src/RISCV_DTM.bsv) | `riscv_dtm_system` | Configures a two-endpoint RISC-V DTM system and its TAP metadata. |
| [RISCV_DTM.bsv](hdl/src/RISCV_DTM.bsv) | `mkRISCVDTM` | Builds a standalone pin-level RISC-V JTAG DTM. |
| [RISCV_DM.bsv](hdl/src/RISCV_DM.bsv) | `riscv_dm_register_map` | Defines the Debug Module CSR map in a BlueCSR context. |
| [RISCV_DM.bsv](hdl/src/RISCV_DM.bsv) | `mkRISCVDM` | Implements a multi-hart RV32 Debug Module with abstract register access and System Bus Access. |
| [RISCV_Debug.bsv](hdl/src/RISCV_Debug.bsv) | `riscv_jtag_debug` | Connects a JTAG DTM to a Debug Module within an extensible JTAG system. |
| [RISCV_Debug.bsv](hdl/src/RISCV_Debug.bsv) | `riscv_jtag_debug_default` | Instantiates the combined debug system with two JTAG endpoints. |
| [RISCV_Debug.bsv](hdl/src/RISCV_Debug.bsv) | `mkRISCVJTAGDebug` | Builds a pin-level RISC-V debug system exposing hart ports and a system-memory client. |
| [fpga/FPGATop.bsv](hdl/src/fpga/FPGATop.bsv) | `mkFPGATestSimpleTop` | Wraps the JTAG LED example with a differential input clock. |
| [fpga/FPGATop.bsv](hdl/src/fpga/FPGATop.bsv) | `mkFPGATestSimple` | Controls LED enables and blink timing through a synchronized BSCANE2 USER3 register. |
| [fpga/FPGATop.bsv](hdl/src/fpga/FPGATop.bsv) | `mkFPGATestSimplestTop` | Exposes a test register on BSCANE2 USER3 and drives LEDs from a free-running counter. |

## Bus Adapter

`mkJTAG_BusAdapterCore` exposes a JTAG data register and a typed bus client;
`mkJTAG_BusAdapter` also assigns the register a configurable JTAG instruction.
Address width `aw` and data width `dw` are type parameters, with `dw/8` byte
strobes and a total DR width of `aw + dw + dw/8 + 8` bits.

```text
MSB                                                                    LSB
| ignore | error | resp_valid | busy | dropped | write | addr | data | strb | resp |
|   1    |   1   |     1      |  1   |    1    |   1   |  aw  |  dw  | dw/8 |  2   |

Example: aw=32, dw=32, DR width=76 bits
  75       74       73         72      71        70     69:38  37:6   5:2    1:0
 ignore   error  resp_valid   busy   dropped    write   addr   data   strb   resp
```

Scans shift least-significant bit first. Capture-DR snapshots the current
response/status, and Update-DR submits the shifted request when `ignore=0`
and the adapter is idle. `write=1` selects a write; `write=0` selects a read.
`addr`, `data`, and `strb` become the bus request fields; incoming status fields
are ignored. Requests and responses cross between TCK and `bus_clk` through
depth-one asynchronous FIFOs.

Only one request may be outstanding. Acceptance sets `busy` and clears
`resp_valid`, `error`, and `dropped`; another request while busy is discarded
and sets `dropped`. Poll with `ignore=1` to avoid submitting another request.
A response updates `data`, sets `resp_valid`, clears `busy`, and sets `error`
for any response other than `OKAY`; completion remains visible until the next
accepted request. Continue clocking TCK to transfer the response and capture
it in a subsequent scan.

The AXI4-Lite version, `mkJTAG2AXI` in [`JTAG2AXI.bsv`](hdl/src/JTAG2AXI.bsv),
uses the same DR layout and exposes separate AXI4-Lite master read and write
interfaces through BlueAXI. It forwards byte strobes, sets `AxPROT=0`, maps
non-`OKAY` responses to `ERROR`, and returns zero data for write responses.

## Tests

Run one simulation by selecting its package through `RUN_TEST`:

```bash
make -C hdl RUN_TEST=TestTAP sim
```

Run the focused RISC-V debug tests with:

```bash
make -C hdl RUN_TEST=TestRISCVJTAGDTM sim
make -C hdl RUN_TEST=TestRISCVDM sim
make -C hdl RUN_TEST=TestRISCVDMMulti sim
make -C hdl RUN_TEST=TestBlueCSRUnmapped sim
```

Use `SIM_TYPE=VERILOG` to compile a test through Icarus Verilog:

```bash
make -C hdl RUN_TEST=TestTAP SIM_TYPE=VERILOG sim
```

## OpenOCD Simulation

The OpenOCD testbench exposes a remote-bitbang UNIX socket. Start the
simulation in one terminal:

```bash
make -C hdl RUN_TEST=TestOOCD sim
```

Then run the client in another terminal:

```bash
python3 hdl/test/bluej_openocd.py \
    --expect-idcode 0x474f \
    --expect-data 0x34fad707
```

The Python client starts OpenOCD with [`bluej.cfg`](hdl/test/bluej.cfg), then
uses ordinary `irscan`, `drscan`, and `runtest` Tcl commands. Its `--backend
bitbang` mode bypasses OpenOCD and is intended only for transport diagnostics.

## RISC-V Debug

`mkRISCVDTM` provides a standalone five-bit JTAG DTM with a typed DMI client.
`mkRISCVDM` provides the Debug Module, direct per-hart register-access ports,
and a typed system-memory client. `mkRISCVJTAGDebug` connects the two into a
pin-level debug system.

The implementation targets the
[RISC-V External Debug Support Specification 0.13.2](https://docs.riscv.org/reference/debug-trace-ras/debug/v0.13.2/_attachments/riscv-debug.pdf).
See [`riscv_dtm.md`](docs/riscv_dtm.md) for the implemented profile,
interfaces, register map, reset behavior, and verification scope.

## Xilinx FPGA Flow

The default example, `mkFPGATestSimpleTop`, uses `BSCANE2` USER3 and exposes a
synchronized register controlling four LED outputs.

Generate Bluespec Verilog:

```bash
make -C hdl fpga-verilog
```

Run the default Vivado Tcl flow:

```bash
make -C hdl fpga-vivado
```

The defaults are:

- Top module: `mkFPGATestSimpleTop`
- Main package: `FPGATop`
- Part: `xcku3p-ffvb676-2-e`
- Constraints: `hdl/src/bluej_simple.xdc`
- Vivado script: `hdl/src/synth.tcl`
- `BSCANE2` chain: USER3

Override `FPGA_TOP_MODULE`, `FPGA_MAIN_MODULE`, `PART`, `CONSTRAINTS`, or
`SCRIPT` as needed for another design.

## Project Layout

```text
.
├── BlueJ.mk              BSVTools integration fragment
├── hdl/
│   ├── Makefile          simulation and FPGA build entry point
│   ├── src/              synthesizable BlueJ sources and FPGA wrappers
│   └── test/             Bluesim, Verilog, and OpenOCD tests
├── docs/                 clocking and RISC-V debug design notes
├── dep/                  pinned direct Git submodules
└── nix/                  reproducible x86_64-linux development shell
```

The main public package is [`BlueJ.bsv`](hdl/src/BlueJ.bsv). Lower-level
packages can also be imported directly when a design needs only part of the
library.

## Documentation

- [`docs/jtag_clocking.md`](docs/jtag_clocking.md): JTAG clocks, resets, TDO
  timing, and clock-domain crossings.
- [`docs/riscv_dtm.md`](docs/riscv_dtm.md): RISC-V DTM/DM architecture,
  supported profile, register map, and tests.
- [`TestSystemAPI.bsv`](hdl/test/TestSystemAPI.bsv): endpoint and system-builder
  examples.
- [`TestBSCANNested.bsv`](hdl/test/TestBSCANNested.bsv): Xilinx nested-TAP
  tunnel protocol example.

## License
MIT.

### Scan interface migration

Scan registers (including instruction and synchronized registers) expose an
`IJTAG_ifc scan`: replace `reg.ctrl`, `reg.tdi`, and `reg.tdo` with
`reg.scan.ctrl`, `reg.scan.tdi`, and `reg.scan.tdo`. Register access (`reg_o`,
`wr_o`, `cap_o`) and instruction `test_logic_reset` remain separate.

Bus adapter cores and JTAG-to-AXI interfaces expose `scan` instead of the full
`jtag_bus_ctrl` or `jtag_ctrl` register. Register a scan-only target in a
`JTAGSystem` with `jtag_scan_endpoint(adapter.scan, instr)`; `jtag_endpoint(reg,
instr)` still provides register update access. Collected `IJTAG_` entries now
contain `instr` and `scan` instead of wrapped TDI/TDO and control fields.

For a direct BSCANE2 connection, use:

```bsv
connect_bscane2_to_target(bscane2, adapter.scan);
```

For custom serial chains, rename `connect_bscane2_to_bluej` to
`connect_bscane2_ctrl` and pass each target's `scan.ctrl`; retain your independent
TDI/TDO wiring. The full helper composes this control helper with direct TDI/TDO
forwarding. Neither helper adds clock crossings or resets: retain the existing
TCK clock and reset setup. Controllers retain their selection vector, while each
`IJTAG_ifc` target accepts one selection input through `scan.ctrl.sel`.

Downstream repositories must migrate these API uses separately.
