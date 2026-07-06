#!/usr/bin/env python3

import argparse
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from jtag_bitbang import JTAG, RemoteBitbang
from py_openocd import OpenOCD, OpenOCDError, OpenOCDJTAGTap, OpenOCDTclClient, parse_tagged_hex


DEFAULT_CONFIG = Path(__file__).resolve().with_name("bluej.cfg")
DEFAULT_SOCKET = "/tmp/jtag.sock"
BLUEJ_TAP = "bluej.tap"
BLUEJ_BUS_INSTRUCTION = 0xDE
BLUEJ_BUS_READ32_TAG = "BLUEJ_BUS_READ32"
BLUEJ_BUS_IGNORE = 1 << 67
BLUEJ_BUS_WRITE = 1 << 64


@dataclass
class BlueJBusRead32Result:
    idcode: Optional[int]
    addr: int
    response: int
    data: int
    stdout: str
    stderr: str


@dataclass
class BlueJBusWrite32Result:
    idcode: Optional[int]
    addr: int
    data: int
    stdout: str
    stderr: str


class BlueJOpenOCD(OpenOCDJTAGTap):
    def __init__(
        self,
        *,
        runner=None,
        tap=BLUEJ_TAP,
        socket_path=DEFAULT_SOCKET,
        config=DEFAULT_CONFIG,
        openocd="openocd",
        timeout=20.0,
        show_log=False,
        bus_instruction=BLUEJ_BUS_INSTRUCTION,
    ):
        self.bus_instruction = bus_instruction
        if runner is None:
            runner = OpenOCD(
                config=config,
                openocd=openocd,
                timeout=timeout,
                variables={"BLUEJ_JTAG_SOCKET": socket_path},
                show_log=show_log,
            )
        super().__init__(runner, tap)

    def bus_read32_result(self, addr):
        addr &= 0xFFFFFFFF
        request = addr << 32
        result = self.openocd.run([
            self.irscan_command(self.bus_instruction),
            self.runtest_command(1),
            self.discard_command(self.drscan_command(68, request)),
            self.runtest_command(10),
            self.tagged_drscan_command(BLUEJ_BUS_READ32_TAG, 68, BLUEJ_BUS_IGNORE),
        ])
        response = parse_tagged_hex(result.output, BLUEJ_BUS_READ32_TAG)

        return BlueJBusRead32Result(
            idcode=result.idcode,
            addr=addr,
            response=response,
            data=response & 0xFFFFFFFF,
            stdout=result.stdout,
            stderr=result.stderr,
        )

    def bus_read32(self, addr):
        return self.bus_read32_result(addr).data

    def bus_write32_result(self, addr, data):
        addr &= 0xFFFFFFFF
        data &= 0xFFFFFFFF
        request = BLUEJ_BUS_WRITE | (addr << 32) | data
        result = self.openocd.run([
            self.irscan_command(self.bus_instruction),
            self.runtest_command(1),
            self.discard_command(self.drscan_command(68, request)),
            self.runtest_command(10),
        ])

        return BlueJBusWrite32Result(
            idcode=result.idcode,
            addr=addr,
            data=data,
            stdout=result.stdout,
            stderr=result.stderr,
        )

    def bus_write32(self, addr, data):
        self.bus_write32_result(addr, data)


def bitbang_bus_read32(jtag, addr):
    request = (addr & 0xFFFFFFFF) << 32
    jtag.shift_ir(0xDE, 8)
    jtag.runtest(1)
    jtag.shift_dr(request, 68)
    jtag.runtest(10)
    response = jtag.shift_dr(BLUEJ_BUS_IGNORE, 68)
    return response & 0xFFFFFFFF, response


def bitbang_bus_write32(jtag, addr, data):
    request = BLUEJ_BUS_WRITE | ((addr & 0xFFFFFFFF) << 32) | (data & 0xFFFFFFFF)
    jtag.shift_ir(0xDE, 8)
    jtag.runtest(1)
    jtag.shift_dr(request, 68)
    jtag.runtest(10)


def bus_read32(addr, **kwargs):
    return BlueJOpenOCD(**kwargs).bus_read32(addr)


def bus_write32(addr, data, **kwargs):
    BlueJOpenOCD(**kwargs).bus_write32(addr, data)


def check_expectations(args, idcode, data):
    if args.expect_idcode is not None:
        if idcode is None:
            raise SystemExit("ERROR: OpenOCD did not report an IDCODE")
        if idcode != args.expect_idcode:
            raise SystemExit(f"ERROR: expected IDCODE 0x{args.expect_idcode:08x}, got 0x{idcode:08x}")

    if args.expect_data is not None:
        if data is None:
            raise SystemExit("ERROR: --expect-data only applies to bus reads")
        if data != args.expect_data:
            raise SystemExit(f"ERROR: expected data 0x{args.expect_data:08x}, got 0x{data:08x}")


def run_bitbang(args):
    remote = RemoteBitbang(args.socket, args.timeout)
    remote.connect()
    try:
        jtag = JTAG(remote, args.sample_phase, args.tdo_delay)
        jtag.reset()

        idcode = jtag.shift_dr(0, 32)
        print(f"idcode=0x{idcode:08x}")

        if args.write_data is None:
            data, response = bitbang_bus_read32(jtag, args.addr)
            print(f"bus_response=0x{response:017x}")
            print(f"bus_read32[0x{args.addr:08x}]=0x{data:08x}")
            check_expectations(args, idcode, data)
        else:
            bitbang_bus_write32(jtag, args.addr, args.write_data)
            data = args.write_data & 0xFFFFFFFF
            print(f"bus_write32[0x{args.addr:08x}]=0x{data:08x}")
            check_expectations(args, idcode, None)
    finally:
        time.sleep(args.settle)
        remote.close()


def run_openocd(args):
    try:
        if args.openocd_mode == "tcl":
            runner = OpenOCDTclClient(
                host=args.tcl_host,
                port=args.tcl_port,
                timeout=args.openocd_timeout,
                show_log=args.show_openocd_log,
            )
            with runner:
                client = BlueJOpenOCD(runner=runner)
                if args.write_data is None:
                    result = client.bus_read32_result(args.addr)
                else:
                    result = client.bus_write32_result(args.addr, args.write_data)
        else:
            client = BlueJOpenOCD(
                socket_path=args.socket,
                config=args.config,
                openocd=args.openocd,
                timeout=args.openocd_timeout,
                show_log=args.show_openocd_log,
            )
            if args.write_data is None:
                result = client.bus_read32_result(args.addr)
            else:
                result = client.bus_write32_result(args.addr, args.write_data)
    except OpenOCDError as exc:
        raise SystemExit(f"ERROR: {exc}") from exc

    if result.idcode is not None:
        print(f"idcode=0x{result.idcode:08x}")
    else:
        print("idcode=<not reported>")

    if args.write_data is None:
        print(f"bus_response=0x{result.response:017x}")
        print(f"bus_read32[0x{result.addr:08x}]=0x{result.data:08x}")
        check_expectations(args, result.idcode, result.data)
    else:
        print(f"bus_write32[0x{result.addr:08x}]=0x{result.data:08x}")
        check_expectations(args, result.idcode, None)


def run(args):
    if args.backend == "openocd":
        run_openocd(args)
    else:
        run_bitbang(args)


def parse_args():
    parser = argparse.ArgumentParser(description="BlueJ OpenOCD smoke test client")
    parser.add_argument("--backend", choices=["openocd", "bitbang"], default="openocd")
    parser.add_argument("--openocd-mode", choices=["process", "tcl"], default="process")
    parser.add_argument("--socket", default=DEFAULT_SOCKET)
    parser.add_argument("--tcl-host", default="127.0.0.1")
    parser.add_argument("--tcl-port", type=int, default=6666)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--addr", type=lambda v: int(v, 0), default=0x08)
    parser.add_argument("--write-data", type=lambda v: int(v, 0))
    parser.add_argument("--expect-idcode", type=lambda v: int(v, 0))
    parser.add_argument("--expect-data", type=lambda v: int(v, 0))
    parser.add_argument("--sample-phase", choices=["before-rise", "high", "after-fall"], default="high")
    parser.add_argument("--tdo-delay", type=int, default=0)
    parser.add_argument("--settle", type=float, default=0.01)
    parser.add_argument("--openocd", default="openocd")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--openocd-timeout", type=float, default=20.0)
    parser.add_argument("--show-openocd-log", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    run(parse_args())
