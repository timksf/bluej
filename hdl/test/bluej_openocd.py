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
BLUEJ_BUS_WRITE32_TAG = "BLUEJ_BUS_WRITE32"
BLUEJ_BUS_WIDTH = 76
BLUEJ_BUS_IGNORE = 1 << 75
BLUEJ_BUS_ERROR = 1 << 74
BLUEJ_BUS_RESP_VALID = 1 << 73
BLUEJ_BUS_BUSY = 1 << 72
BLUEJ_BUS_DROPPED = 1 << 71
BLUEJ_BUS_WRITE = 1 << 70
BLUEJ_BUS_ADDR_SHIFT = 38
BLUEJ_BUS_DATA_SHIFT = 6
BLUEJ_BUS_STRB_SHIFT = 2
BLUEJ_BUS_RESP_MASK = 0x3
BLUEJ_BUS_REQUEST = 0x3


@dataclass(frozen=True)
class BlueJBusControl:
    raw: int
    ignore: bool
    error: bool
    resp_valid: bool
    busy: bool
    dropped: bool
    write: bool
    addr: int
    data: int
    strb: int
    resp: int


def encode_bus_request(addr, *, write=False, data=0, strb=0):
    return (
        (BLUEJ_BUS_WRITE if write else 0)
        | ((addr & 0xFFFFFFFF) << BLUEJ_BUS_ADDR_SHIFT)
        | ((data & 0xFFFFFFFF) << BLUEJ_BUS_DATA_SHIFT)
        | ((strb & 0xF) << BLUEJ_BUS_STRB_SHIFT)
        | BLUEJ_BUS_REQUEST
    )


def decode_bus_control(raw):
    raw &= (1 << BLUEJ_BUS_WIDTH) - 1
    return BlueJBusControl(
        raw=raw,
        ignore=bool(raw & BLUEJ_BUS_IGNORE),
        error=bool(raw & BLUEJ_BUS_ERROR),
        resp_valid=bool(raw & BLUEJ_BUS_RESP_VALID),
        busy=bool(raw & BLUEJ_BUS_BUSY),
        dropped=bool(raw & BLUEJ_BUS_DROPPED),
        write=bool(raw & BLUEJ_BUS_WRITE),
        addr=(raw >> BLUEJ_BUS_ADDR_SHIFT) & 0xFFFFFFFF,
        data=(raw >> BLUEJ_BUS_DATA_SHIFT) & 0xFFFFFFFF,
        strb=(raw >> BLUEJ_BUS_STRB_SHIFT) & 0xF,
        resp=raw & BLUEJ_BUS_RESP_MASK,
    )


def require_bus_response(raw):
    control = decode_bus_control(raw)
    if control.dropped:
        raise OpenOCDError("JTAG bus request was dropped")
    if control.busy or not control.resp_valid:
        raise OpenOCDError("JTAG bus response is not ready")
    if control.error:
        raise OpenOCDError(f"JTAG bus returned error response {control.resp}")
    return control


@dataclass
class BlueJBusRead32Result:
    idcode: Optional[int]
    addr: int
    response: int
    data: int
    stdout: str
    stderr: str

    @property
    def control(self):
        return decode_bus_control(self.response)


@dataclass
class BlueJBusWrite32Result:
    idcode: Optional[int]
    addr: int
    data: int
    strb: int
    response: int
    stdout: str
    stderr: str

    @property
    def control(self):
        return decode_bus_control(self.response)


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
        request = encode_bus_request(addr)
        result = self.openocd.run([
            self.irscan_command(self.bus_instruction),
            self.runtest_command(1),
            self.discard_command(self.drscan_command(BLUEJ_BUS_WIDTH, request)),
            self.runtest_command(10),
            self.tagged_drscan_command(BLUEJ_BUS_READ32_TAG, BLUEJ_BUS_WIDTH, BLUEJ_BUS_IGNORE),
        ])
        response = parse_tagged_hex(result.output, BLUEJ_BUS_READ32_TAG)
        control = require_bus_response(response)

        return BlueJBusRead32Result(
            idcode=result.idcode,
            addr=addr,
            response=response,
            data=control.data,
            stdout=result.stdout,
            stderr=result.stderr,
        )

    def bus_read32(self, addr):
        return self.bus_read32_result(addr).data

    def bus_write32_result(self, addr, data, strb=0xF):
        addr &= 0xFFFFFFFF
        data &= 0xFFFFFFFF
        strb &= 0xF
        request = encode_bus_request(addr, write=True, data=data, strb=strb)
        result = self.openocd.run([
            self.irscan_command(self.bus_instruction),
            self.runtest_command(1),
            self.discard_command(self.drscan_command(BLUEJ_BUS_WIDTH, request)),
            self.runtest_command(10),
            self.tagged_drscan_command(BLUEJ_BUS_WRITE32_TAG, BLUEJ_BUS_WIDTH, BLUEJ_BUS_IGNORE),
        ])
        response = parse_tagged_hex(result.output, BLUEJ_BUS_WRITE32_TAG)
        require_bus_response(response)

        return BlueJBusWrite32Result(
            idcode=result.idcode,
            addr=addr,
            data=data,
            strb=strb,
            response=response,
            stdout=result.stdout,
            stderr=result.stderr,
        )

    def bus_write32(self, addr, data, strb=0xF):
        self.bus_write32_result(addr, data, strb)


def bitbang_bus_read32(jtag, addr):
    request = encode_bus_request(addr)
    jtag.shift_ir(BLUEJ_BUS_INSTRUCTION, 8)
    jtag.runtest(1)
    jtag.shift_dr(request, BLUEJ_BUS_WIDTH)
    jtag.runtest(10)
    response = jtag.shift_dr(BLUEJ_BUS_IGNORE, BLUEJ_BUS_WIDTH)
    control = require_bus_response(response)
    return control.data, response


def bitbang_bus_write32(jtag, addr, data, strb=0xF):
    request = encode_bus_request(addr, write=True, data=data, strb=strb)
    jtag.shift_ir(BLUEJ_BUS_INSTRUCTION, 8)
    jtag.runtest(1)
    jtag.shift_dr(request, BLUEJ_BUS_WIDTH)
    jtag.runtest(10)
    response = jtag.shift_dr(BLUEJ_BUS_IGNORE, BLUEJ_BUS_WIDTH)
    require_bus_response(response)
    return response


def bus_read32(addr, **kwargs):
    return BlueJOpenOCD(**kwargs).bus_read32(addr)


def bus_write32(addr, data, strb=0xF, **kwargs):
    BlueJOpenOCD(**kwargs).bus_write32(addr, data, strb)


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
            print(f"bus_response=0x{response:019x}")
            print(f"bus_read32[0x{args.addr:08x}]=0x{data:08x}")
            check_expectations(args, idcode, data)
        else:
            response = bitbang_bus_write32(jtag, args.addr, args.write_data, args.write_strobe)
            data = args.write_data & 0xFFFFFFFF
            print(f"bus_response=0x{response:019x}")
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
                    result = client.bus_write32_result(args.addr, args.write_data, args.write_strobe)
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
                result = client.bus_write32_result(args.addr, args.write_data, args.write_strobe)
    except OpenOCDError as exc:
        raise SystemExit(f"ERROR: {exc}") from exc

    if result.idcode is not None:
        print(f"idcode=0x{result.idcode:08x}")
    else:
        print("idcode=<not reported>")

    if args.write_data is None:
        print(f"bus_response=0x{result.response:019x}")
        print(f"bus_read32[0x{result.addr:08x}]=0x{result.data:08x}")
        check_expectations(args, result.idcode, result.data)
    else:
        print(f"bus_response=0x{result.response:019x}")
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
    parser.add_argument("--write-strobe", type=lambda v: int(v, 0), default=0xF)
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
