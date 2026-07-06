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

    print("Finished BRAM Test")
    print()

    jtag.irscan(0x02)
    d = jtag.drscan(32, 0xDEADBEEF)
    print(f"IR@0x02={d:08x}")
    d = jtag.drscan(32, 0x0)
    print(f"IR@0x02={d:08x}")
