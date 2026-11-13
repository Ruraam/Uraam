#!/usr/bin/env python3
"""Real-process regression tests for the GUI bridge lifecycle helpers."""

import subprocess
import sys
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "GUI"))
from bridge_process import (
    BridgeProcessCancelled,
    BridgeProcessTimeout,
    communicate_process,
    signal_process_group,
)


class BridgeProcessLifecycleTests(unittest.TestCase):
    def _start(self, code):
        return subprocess.Popen(
            [sys.executable, "-c", code],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )

    def test_normal_process_returns_stdout_and_stderr(self):
        process = self._start("print('bridge-ok'); import sys; print('note', file=sys.stderr)")
        stdout, stderr = communicate_process(process, threading.Event())
        self.assertEqual(stdout.strip(), "bridge-ok")
        self.assertEqual(stderr.strip(), "note")
        self.assertEqual(process.returncode, 0)

    def test_shutdown_cancels_process_group(self):
        code = (
            "import subprocess, sys, time; "
            "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
            "print('ready', flush=True); time.sleep(30)"
        )
        process = self._start(code)
        self.assertEqual(process.stdout.readline().strip(), "ready")
        started = time.monotonic()
        with self.assertRaises(BridgeProcessCancelled):
            communicate_process(process, threading.Event(), shutdown_grace_seconds=0.3)
        self.assertIsNotNone(process.poll())
        self.assertLess(time.monotonic() - started, 3.0)

    def test_shutdown_already_requested_before_communicate(self):
        process = self._start("import time; time.sleep(30)")
        shutdown = threading.Event()
        shutdown.set()
        with self.assertRaises(BridgeProcessCancelled):
            communicate_process(process, shutdown, shutdown_grace_seconds=0.3)
        self.assertIsNotNone(process.poll())

    def test_timeout_kills_and_reaps_process(self):
        process = self._start("import time; time.sleep(30)")
        started = time.monotonic()
        with self.assertRaises(BridgeProcessTimeout):
            communicate_process(
                process, threading.Event(), timeout_seconds=0.2,
                poll_interval=0.05, shutdown_grace_seconds=0.2
            )
        self.assertIsNotNone(process.poll())
        self.assertLess(time.monotonic() - started, 3.0)

    def test_signal_skips_process_that_has_already_exited(self):
        process = self._start("pass")
        process.wait(timeout=2)
        signal_process_group(process, 15)
        self.assertEqual(process.returncode, 0)


if __name__ == "__main__":
    unittest.main()
