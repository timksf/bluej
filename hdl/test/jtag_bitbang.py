import socket
import time


class RemoteBitbang:
    def __init__(self, path, timeout):
        self.path = path
        self.timeout = timeout
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

    def connect(self):
        deadline = time.monotonic() + self.timeout
        while True:
            try:
                self.sock.connect(self.path)
                return
            except FileNotFoundError:
                pass
            except ConnectionRefusedError:
                pass

            if time.monotonic() >= deadline:
                raise TimeoutError(f"timed out waiting for {self.path}")
            time.sleep(0.01)

    def close(self):
        try:
            self.sock.sendall(b"Q")
        finally:
            self.sock.close()

    def write_pins(self, tck, tms, tdi):
        cmd = ord("0") + ((tck & 1) << 2) + ((tms & 1) << 1) + (tdi & 1)
        self.sock.sendall(bytes([cmd]))

    def read_tdo(self):
        self.sock.sendall(b"R")
        value = self.sock.recv(1)
        if value == b"1":
            return 1
        if value == b"0":
            return 0
        raise RuntimeError(f"unexpected TDO response {value!r}")


class JTAG:
    def __init__(self, remote, sample_phase, tdo_delay):
        self.remote = remote
        self.sample_phase = sample_phase
        self.tdo_delay = tdo_delay
        self.tms = 1
        self.tdi = 0
        self.remote.write_pins(0, self.tms, self.tdi)

    def clock(self, tms, tdi, sample=False):
        self.tms = tms & 1
        self.tdi = tdi & 1
        self.remote.write_pins(0, self.tms, self.tdi)
        if sample and self.sample_phase == "before-rise":
            tdo = self.remote.read_tdo()
        else:
            tdo = 0
        self.remote.write_pins(1, self.tms, self.tdi)
        if sample and self.sample_phase == "high":
            tdo = self.remote.read_tdo()
        self.remote.write_pins(0, self.tms, self.tdi)
        if sample and self.sample_phase == "after-fall":
            tdo = self.remote.read_tdo()
        return tdo

    def reset(self):
        for _ in range(5):
            self.clock(1, 0)
        self.clock(0, 0)

    def runtest(self, cycles):
        for _ in range(cycles):
            self.clock(0, 0)

    def shift_ir(self, instr, width):
        self.clock(1, 0)  # Run-Test/Idle -> Select-DR-Scan
        self.clock(1, 0)  # Select-DR-Scan -> Select-IR-Scan
        self.clock(0, 0)  # Select-IR-Scan -> Capture-IR
        self.clock(0, 0)  # Capture-IR -> Shift-IR
        value = self._shift_bits(instr, width)
        self.clock(1, 0)  # Exit1-IR -> Update-IR
        self.clock(0, 0)  # Update-IR -> Run-Test/Idle
        return value

    def shift_dr(self, value, width, align_tdo=True):
        self.clock(1, 0)  # Run-Test/Idle -> Select-DR-Scan
        self.clock(0, 0)  # Select-DR-Scan -> Capture-DR
        self.clock(0, 0)  # Capture-DR -> Shift-DR
        scan_width = width + self.tdo_delay if align_tdo else width
        raw = self._shift_bits(value, scan_width, width)
        self.clock(1, 0)  # Exit1-DR -> Update-DR
        self.clock(0, 0)  # Update-DR -> Run-Test/Idle
        if align_tdo:
            return (raw >> self.tdo_delay) & ((1 << width) - 1)
        return raw

    def _shift_bits(self, value, scan_width, tdi_width=None):
        if tdi_width is None:
            tdi_width = scan_width
        readback = 0
        for bit in range(scan_width):
            tdi = ((value >> bit) & 1) if bit < tdi_width else 0
            tms = 1 if bit == scan_width - 1 else 0
            tdo = self.clock(tms, tdi, sample=True)
            readback |= tdo << bit
        return readback
