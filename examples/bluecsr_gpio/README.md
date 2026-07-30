# BlueCSR GPIO

This example implements a small, parameterized GPIO controller with a native
BlueCSR register interface. Its register semantics follow the conventional
FE310-style map used by CORE-V Wally's `gpio_apb.sv`.

The GPIO input is masked by `INPUT_EN` and passes through a three-register
synchronizer. Interrupt pending bits are sticky and are cleared by writing one.
All interrupt sources are ORed onto the single `interrupt` output.
Peripheral-function routing is intentionally left to an external pinmux or I/O
matrix, so offsets `0x38` and `0x3c` are unmapped.

| Offset | Register | Access | Description |
| ---: | --- | :---: | --- |
| `0x00` | `INPUT_VAL` | RO | Synchronized, enabled GPIO inputs |
| `0x04` | `INPUT_EN` | RW | Input enable mask |
| `0x08` | `OUTPUT_EN` | RW | Output enable mask |
| `0x0c` | `OUTPUT_VAL` | RW | Software output value |
| `0x18` | `RISE_IE` | RW | Rising-edge interrupt enable |
| `0x1c` | `RISE_IP` | W1C | Rising-edge interrupt pending |
| `0x20` | `FALL_IE` | RW | Falling-edge interrupt enable |
| `0x24` | `FALL_IP` | W1C | Falling-edge interrupt pending |
| `0x28` | `HIGH_IE` | RW | High-level interrupt enable |
| `0x2c` | `HIGH_IP` | W1C | High-level interrupt pending |
| `0x30` | `LOW_IE` | RW | Low-level interrupt enable |
| `0x34` | `LOW_IP` | W1C | Low-level interrupt pending |
| `0x40` | `OUT_XOR` | RW | Invert final output value |

`mkBlueCSRGPIO` has a native `BlueCSR_ifc#(8, 32, 1)` slave interface.
`mkBlueCSRAPBAdapter` or `mkBlueCSRAXI4LiteAdapter` can wrap it when a standard
bus interface is needed.

Run the example test with:

```sh
make -C examples/bluecsr_gpio sim
```
