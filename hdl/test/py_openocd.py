#!/usr/bin/env python3

import argparse
import re
import socket
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


OPENOCD_IDCODE_RE = re.compile(r"tap/device found:\s+0x([0-9a-fA-F]+)")


class OpenOCDError(RuntimeError):
    pass


def write_log(stream, text):
    stream.write(text)
    if text and not text.endswith("\n"):
        stream.write("\n")


@dataclass
class OpenOCDResult:
    stdout: str
    stderr: str
    returncode: int

    @property
    def output(self):
        return f"{self.stdout}\n{self.stderr}"

    @property
    def idcode(self):
        match = OPENOCD_IDCODE_RE.search(self.output)
        if match is None:
            return None
        return int(match.group(1), 16)


class OpenOCD:
    def __init__(
        self,
        *,
        config=None,
        openocd="openocd",
        timeout=20.0,
        variables=None,
        show_log=False,
    ):
        self.config = Path(config) if config is not None else None
        self.openocd = openocd
        self.timeout = timeout
        self.variables = dict(variables or {})
        self.show_log = show_log

    def run(self, commands=(), *, shutdown=True):
        if isinstance(commands, str):
            commands = [commands]

        cmd = [self.openocd]
        for name, value in self.variables.items():
            cmd.extend(["-c", f"set {name} {{{value}}}"])

        if self.config is not None:
            cmd.extend(["-f", str(self.config)])

        for command in commands:
            cmd.extend(["-c", command])

        if shutdown:
            cmd.extend(["-c", "shutdown"])

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=self.timeout)
        except subprocess.TimeoutExpired as exc:
            raise OpenOCDError(f"OpenOCD timed out after {self.timeout:g}s") from exc
        except FileNotFoundError as exc:
            raise OpenOCDError(f"could not run {self.openocd!r}") from exc

        if self.show_log or result.returncode != 0:
            write_log(sys.stdout, result.stdout)
            write_log(sys.stderr, result.stderr)

        if result.returncode != 0:
            raise OpenOCDError(f"OpenOCD exited with status {result.returncode}")

        return OpenOCDResult(
            stdout=result.stdout,
            stderr=result.stderr,
            returncode=result.returncode,
        )


class OpenOCDTclClient:
    def __init__(self, *, host="127.0.0.1", port=6666, timeout=20.0, show_log=False):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.show_log = show_log
        self.sock = None

    def connect(self):
        if self.sock is None:
            self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
            self.sock.settimeout(self.timeout)
        return self

    def close(self):
        if self.sock is not None:
            self.sock.close()
            self.sock = None

    def __enter__(self):
        return self.connect()

    def __exit__(self, exc_type, exc, tb):
        self.close()

    def run(self, commands=(), *, shutdown=False):
        if isinstance(commands, str):
            commands = [commands]

        script = "\n".join(commands)
        if shutdown:
            script = "\n".join([script, "shutdown"]) if script else "shutdown"

        sock = self.connect().sock
        try:
            sock.sendall(script.encode("utf-8") + b"\x1a")
            output = self._recv_response()
        except OSError as exc:
            raise OpenOCDError(f"OpenOCD Tcl connection failed: {exc}") from exc

        if self.show_log:
            write_log(sys.stdout, output)

        return OpenOCDResult(
            stdout=output,
            stderr="",
            returncode=0,
        )

    def _recv_response(self):
        chunks = []
        while True:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise OpenOCDError("OpenOCD Tcl connection closed")
            if b"\x1a" in chunk:
                before, _sep, _after = chunk.partition(b"\x1a")
                chunks.append(before)
                return b"".join(chunks).decode("utf-8", errors="replace")
            chunks.append(chunk)


def tcl_arg(value):
    if isinstance(value, str):
        return value
    return f"0x{value:x}"


def parse_tagged_hex(output, tag):
    pattern = re.compile(rf"^\s*{re.escape(tag)}\s+(?:0x)?([0-9a-fA-F]+)\s*$")
    values = []
    for line in output.splitlines():
        match = pattern.match(line)
        if match is not None:
            values.append(int(match.group(1), 16))
    if not values:
        raise OpenOCDError(f"OpenOCD did not print {tag}")
    return values[-1]


class OpenOCDJTAGTap:
    def __init__(self, openocd, tap):
        self.openocd = openocd
        self.tap = tap

    def irscan_command(self, instruction):
        return f"irscan {self.tap} {tcl_arg(instruction)}"

    def drscan_command(self, width, value):
        return f"drscan {self.tap} {width} {tcl_arg(value)}"

    @staticmethod
    def runtest_command(cycles):
        return f"runtest {cycles}"

    @staticmethod
    def discard_command(command):
        return f"set _openocd_unused [{command}]; unset _openocd_unused"

    def tagged_drscan_command(self, tag, width, value):
        return f'format "{tag} %s" [{self.drscan_command(width, value)}]'

    def irscan(self, instruction):
        return self.openocd.run(self.irscan_command(instruction))

    def drscan(self, width, value, *, tag="OPENOCD_DRSCAN"):
        result = self.openocd.run(self.tagged_drscan_command(tag, width, value))
        return parse_tagged_hex(result.output, tag)

    def runtest(self, cycles):
        return self.openocd.run(self.runtest_command(cycles))


def parse_variables(assignments):
    variables = {}
    for assignment in assignments:
        if "=" not in assignment:
            raise SystemExit(f"ERROR: expected NAME=VALUE, got {assignment!r}")
        name, value = assignment.split("=", 1)
        if not name:
            raise SystemExit(f"ERROR: expected NAME=VALUE, got {assignment!r}")
        variables[name] = value
    return variables


def parse_args():
    parser = argparse.ArgumentParser(description="Small generic OpenOCD command runner")
    parser.add_argument("--openocd", default="openocd")
    parser.add_argument("--config", type=Path)
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--set", dest="variables", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("-c", "--command", action="append", default=[])
    parser.add_argument("--no-shutdown", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    openocd = OpenOCD(
        config=args.config,
        openocd=args.openocd,
        timeout=args.timeout,
        variables=parse_variables(args.variables),
        show_log=not args.quiet,
    )

    try:
        openocd.run(args.command, shutdown=not args.no_shutdown)
    except OpenOCDError as exc:
        raise SystemExit(f"ERROR: {exc}") from exc


if __name__ == "__main__":
    main()
