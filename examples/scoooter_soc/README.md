# SCOoOTER BlueFabric SoC

This deployable example places SCOoOTER, boot ROM, RAM, UART, eight GPIOs, and
a watchdog on a BlueFabric AHB/APB system. SPI is intentionally omitted.
`ScoooterSystem` combines a synchronous 50 MHz SoC domain with a TCK-domain
TAP. The TAP provides standard RISC-V DTM/DM access (instructions `0x10` and
`0x11`) plus BlueJ's JTAG bus adapter (`0x12`).

The Cmod A7 top is a hand-written Verilog wrapper. It uses the on-board 12 MHz
oscillator as the reference for an `MMCME2_BASE` that generates the 50 MHz
system clock. `STARTUPE2.EOS`, MMCM lock, and button 0 produce the power-on and
manual reset. Reset assertion is asynchronous and release is synchronized.

The SoC AHB address map is:

| Base | Size | Target |
| --- | ---: | --- |
| `0x0000_0000` | 4 KiB | Boot ROM |
| `0x4000_0000` | 8 MiB | APB bridge |
| `0x8000_0000` | 64 KiB | RAM |

APB peripherals occupy the bridge window:

| Offset | Size | Target |
| --- | ---: | --- |
| `0x0000` | 4 KiB | BlueUART |
| `0x1000` | 4 KiB | BlueGPIO |
| `0x2000` | 4 KiB | Watchdog |
| `0x0040_0000` | 4 MiB | PLIC |

## Cmod A7 connections

| Function | Board connection | FPGA pin |
| --- | --- | --- |
| Reset | button 0 | A18 |
| GPIO 2 / interrupt input | button 1 | B18 |
| GPIO 0 | LED 0 | A17 |
| GPIO 1 | LED 1 | C16 |
| JTAG TCK/TMS/TDI/TDO | DIP 18/19/20/21 | N3/P3/M2/N1 |
| GPIO 3/4/5/6 | JA7/JA8/JA9/JA10 | H17/H19/J19/K18 |
| GPIO 7 | DIP pin 1 | M3 |
| UART RX/TX | FT2232HQ USB UART | J17/J18 |

The five external GPIOs instantiate `IOBUF` explicitly. GPIO 0 and 1 are
output-only at the board boundary, and GPIO 2 is input-only there. The GPIO
peripheral itself still exposes input, output, and output-enable registers for
all eight logical pins.

JTAG TCK uses the MRCC input on DIP pin 18. TDO changes on TCK's falling edge
using the FDRE clock-inversion attribute, so both edges use the same global
clock tree without a LUT clock inverter.

## CPU bring-up configuration

The example-local SCOoOTER configuration is at the top of
`src/ScoooterCpu.bsv`; `src/Config.bsv` adapts those definitions to the
package name expected by the upstream core. The bring-up profile is scalar
and uses a two-entry reorder buffer and instruction window, one-entry
reservation stations, a four-entry store buffer, no dynamic branch predictor
or BTB, and no multiplier/divider units.

The current upstream CSR file hard-codes the M bit in `misa`, even when
`NUM_MULDIV` is zero. The decoder does reject M-extension instructions in
this configuration, so bring-up software must not emit multiply or divide
instructions despite the advertised bit.

## FPGA build

The Makefile uses BSVTools for Verilog generation and Vivado project setup.
For a synthesis-only checkpoint and reports:

```sh
make -C examples/scoooter_soc synth
```

This uses `synth_only.tcl` and writes
`build/ScoooterCmodA7/ScoooterCmodA7_synth.dcp`. For the complete flow:

```sh
make -C examples/scoooter_soc bitstream
```

The complete flow uses `synth.tcl` and runs synthesis, optimization, placement,
routing, physical optimization, reports, checkpoints, and bitstream
generation. Program the resulting bitstream with:

```sh
make -C examples/scoooter_soc program
```

The tested Cmod A7 is populated with a 4 MiB Macronix MX25L3273F configuration
flash, as identified from its JEDEC ID by Vivado. The bitstream is generated
for Quad-SPI x4 boot. Create an MCS image and program, erase, and verify the
flash through the onboard Digilent JTAG connection with:

```sh
make -C examples/scoooter_soc flash-image
make -C examples/scoooter_soc program-flash
```

`program-flash` restores the volatile SoC bitstream after indirect flash
programming. On the next power cycle, the FPGA loads the same design from
Quad-SPI flash. For a board revision populated with a different compatible
device, override the Vivado configuration-memory part, for example:

```sh
make -C examples/scoooter_soc program-flash \
    CFGMEM_PART=n25q32-3.3v-spi-x1_x2_x4
```

At 50 MHz, program the UART `BAUD` register with the number of system-clock
cycles per bit (for example, 434 for approximately 115200 baud), then enable
the UART in `CTRL`. The Cmod OpenOCD configuration provides helpers that
perform this setup and poll the FIFO status:

```tcl
scoooter_uart_init 115200
scoooter_uart_send "Hello from SCOoOTER!\r\n"
```

For a fixed smoke test, run:

```tcl
scoooter_uart_test
```

This sends `UART OK!` followed by CR/LF. The helpers can be entered in the
OpenOCD telnet console on port 4444 or supplied after the configuration on the
command line:

```sh
openocd -f examples/scoooter_soc/openocd-cmod.cfg \
    -c "scoooter_uart_test"
```

Use `mwb 0x40000010 <byte>` for manual TXDATA writes. A 32-bit `mww` uses all
four byte strobes and is intentionally rejected by the byte-wide FIFO CSR.

Connect the external debugger to DIP pins 18 through 21 and a common ground.
Use 3.3 V signaling. `openocd-cmod.cfg` selects the J-Link adapter and defaults
to 4 MHz, the maximum supported by the tested J-Link EDU Mini:

```sh
openocd -f examples/scoooter_soc/openocd-cmod.cfg
```

Override the adapter speed in kHz when using a faster J-Link:

```sh
openocd -c "set SCOOOTER_JTAG_KHZ 10000" \
    -f examples/scoooter_soc/openocd-cmod.cfg
```

The boot ROM initializes `sp` to `0x8000_1000` and jumps to the RAM entry at
`0x8000_0000`. JTAG debug or the JTAG bus adapter can load the RAM before
reset is released.

`bootrom/boot.S` is compiled into `bootrom/boot.hex`; `mkAhbBootRom` loads that
file with `BRAM_Configure.loadFormat`. Regenerate it with `make -C bootrom`.

## OpenOCD simulation

Build and run the remote-bitbang simulation in one terminal:

```sh
make -C examples/scoooter_soc oocd-sim
```

Then attach OpenOCD from a second terminal:

```sh
openocd -f examples/scoooter_soc/openocd.cfg
```

The simulation listens on `/tmp/jtag.sock`. OpenOCD connects through the
RISC-V DTM and accesses system memory through the debug module's SBA port;
the JTAG bus-adapter instruction remains available separately at `0x12`.
