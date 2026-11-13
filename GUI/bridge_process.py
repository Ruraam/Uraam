"""Bounded lifecycle helpers for the GUI's isolated read-only bridge process."""

from __future__ import annotations

import os
import selectors
import signal
import subprocess
import time
from typing import BinaryIO
from threading import Event

MAX_BRIDGE_STDOUT_BYTES = 8 * 1024 * 1024
MAX_BRIDGE_STDERR_BYTES = 256 * 1024
_READ_CHUNK_BYTES = 64 * 1024


class BridgeProcessCancelled(RuntimeError):
    """Raised when GUI shutdown cancels an active bridge request."""


class BridgeProcessTimeout(RuntimeError):
    """Raised when a bridge request exceeds its wall-clock deadline."""


class BridgeProcessOutputLimit(RuntimeError):
    """Raised when a bridge process exceeds a bounded output stream."""


def signal_process_group(process: subprocess.Popen[bytes], sig: int) -> None:
    """Signal only the isolated process group created with start_new_session=True."""
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass


def _kill_and_reap(process: subprocess.Popen[bytes]) -> None:
    """Kill the isolated process group and reap its leader without collecting output."""
    signal_process_group(process, signal.SIGKILL)
    try:
        process.wait(timeout=2.0)
    except subprocess.TimeoutExpired:
        process.wait()


def _stop_and_reap(
    process: subprocess.Popen[bytes], grace_seconds: float
) -> None:
    """Give the process group a short shutdown grace period, then kill it."""
    signal_process_group(process, signal.SIGTERM)
    try:
        process.wait(timeout=grace_seconds)
    except subprocess.TimeoutExpired:
        _kill_and_reap(process)
        return
    signal_process_group(process, signal.SIGKILL)


def _close_pipe(pipe: BinaryIO | None) -> None:
    if pipe is not None:
        try:
            pipe.close()
        except OSError:
            pass


def communicate_process(
    process: subprocess.Popen[bytes],
    shutdown_event: Event,
    timeout_seconds: float = 45.0,
    poll_interval: float = 0.1,
    shutdown_grace_seconds: float = 1.0,
) -> tuple[str, str]:
    """Collect bounded output while observing shutdown and enforcing a hard deadline."""
    deadline = time.monotonic() + timeout_seconds
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    limits = {
        "stdout": MAX_BRIDGE_STDOUT_BYTES,
        "stderr": MAX_BRIDGE_STDERR_BYTES,
    }
    pipes = {"stdout": process.stdout, "stderr": process.stderr}

    try:
        with selectors.DefaultSelector() as selector:
            for name, pipe in pipes.items():
                if pipe is not None:
                    selector.register(pipe, selectors.EVENT_READ, name)

            while selector.get_map() or process.poll() is None:
                if shutdown_event.is_set():
                    _stop_and_reap(process, shutdown_grace_seconds)
                    raise BridgeProcessCancelled(
                        "The read-only bridge request was cancelled during shutdown."
                    )

                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    _kill_and_reap(process)
                    raise BridgeProcessTimeout(
                        "The read-only bridge request timed out."
                    )

                events = selector.select(timeout=min(poll_interval, remaining))
                for key, _mask in events:
                    name = key.data
                    chunk = os.read(key.fd, _READ_CHUNK_BYTES)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue

                    buffer = buffers[name]
                    if len(buffer) + len(chunk) > limits[name]:
                        _kill_and_reap(process)
                        raise BridgeProcessOutputLimit(
                            f"The read-only bridge {name} output exceeds its "
                            f"{limits[name] // 1024} KiB safety limit."
                        )
                    buffer.extend(chunk)

        process.wait()
        # A descendant may close inherited pipes and outlive its leader.
        signal_process_group(process, signal.SIGKILL)
        return (
            buffers["stdout"].decode("utf-8", errors="replace"),
            buffers["stderr"].decode("utf-8", errors="replace"),
        )
    finally:
        _close_pipe(process.stdout)
        _close_pipe(process.stderr)
