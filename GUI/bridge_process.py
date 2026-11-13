"""Bounded lifecycle helpers for the GUI's isolated read-only bridge process."""

from __future__ import annotations

import os
import signal
import subprocess
import time
from threading import Event


class BridgeProcessCancelled(RuntimeError):
    """Raised when GUI shutdown cancels an active bridge request."""


class BridgeProcessTimeout(RuntimeError):
    """Raised when a bridge request exceeds its wall-clock deadline."""


def signal_process_group(process: subprocess.Popen[str], sig: int) -> None:
    """Signal only the isolated process group created with start_new_session=True."""
    try:
        # The group can outlive its leader when a child inherited our pipes.
        # Keep signalling the original PGID until communicate() reaps the group.
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass


def _stop_and_reap(process: subprocess.Popen[str], grace_seconds: float) -> tuple[str, str]:
    signal_process_group(process, signal.SIGTERM)
    try:
        output = process.communicate(timeout=grace_seconds)
    except subprocess.TimeoutExpired:
        signal_process_group(process, signal.SIGKILL)
        return process.communicate()
    # The leader may exit while a child that closed its pipes remains alive.
    signal_process_group(process, signal.SIGKILL)
    return output


def communicate_process(
    process: subprocess.Popen[str],
    shutdown_event: Event,
    timeout_seconds: float = 45.0,
    poll_interval: float = 0.1,
    shutdown_grace_seconds: float = 1.0,
) -> tuple[str, str]:
    """Collect output while observing shutdown and enforcing a hard deadline."""
    deadline = time.monotonic() + timeout_seconds
    while True:
        if shutdown_event.is_set():
            _stop_and_reap(process, shutdown_grace_seconds)
            raise BridgeProcessCancelled("The read-only bridge request was cancelled during shutdown.")

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            signal_process_group(process, signal.SIGKILL)
            process.communicate()
            raise BridgeProcessTimeout("The read-only bridge request timed out.")

        try:
            output = process.communicate(timeout=min(poll_interval, remaining))
        except subprocess.TimeoutExpired:
            continue
        # A child may close inherited pipes and outlive the bridge leader.
        # Once the leader has completed, no process in its isolated group is
        # needed; terminate any remaining descendants before returning.
        signal_process_group(process, signal.SIGKILL)
        return output
