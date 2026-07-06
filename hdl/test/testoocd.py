from bluej_openocd import BlueJOpenOCD
from py_openocd import OpenOCDTclClient

with OpenOCDTclClient() as runner:
    jtag = BlueJOpenOCD(runner=runner)
    jtag.bus_write32(0x8, 0x12345678)

    a = 0
    for i in range(32):
        d = jtag.bus_read32(a)
        print(f"BRAM@{a:02x}={d:08x}")
        a += 1
