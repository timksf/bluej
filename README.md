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
