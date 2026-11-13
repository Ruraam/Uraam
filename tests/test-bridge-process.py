#!/usr/bin/env python3
"""Real-process regression tests for the GUI bridge lifecycle helpers."""

import os
import signal
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
from api_protocol import request_is_current, take_pending_request
import main as uraam_gui


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
        shutdown = threading.Event()
        threading.Timer(0.1, shutdown.set).start()
        started = time.monotonic()
        with self.assertRaises(BridgeProcessCancelled):
            communicate_process(process, shutdown, shutdown_grace_seconds=0.3)
        self.assertIsNotNone(process.poll())
        self.assertLess(time.monotonic() - started, 3.0)

    def test_shutdown_kills_descendant_that_ignores_sigterm_and_closes_pipes(self):
        child = (
            "import os, signal, time; "
            "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "os.close(1); os.close(2); time.sleep(30)"
        )
        code = (
            "import subprocess, sys, time; "
            f"child = subprocess.Popen([sys.executable, '-c', {child!r}]); "
            "print(child.pid, flush=True); time.sleep(0.15); "
            "print('ready', flush=True); time.sleep(30)"
        )
        process = self._start(code)
        child_pid = int(process.stdout.readline().strip())
        self.assertEqual(process.stdout.readline().strip(), "ready")

        shutdown = threading.Event()
        shutdown.set()
        with self.assertRaises(BridgeProcessCancelled):
            communicate_process(process, shutdown, shutdown_grace_seconds=0.3)
        self.assertIsNotNone(process.poll())

        # SIGKILL may leave an orphaned zombie briefly; it must not remain runnable.
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            stat_path = Path(f"/proc/{child_pid}/stat")
            if not stat_path.exists():
                break
            state = stat_path.read_text().split(") ", 1)[1].split()[0]
            if state == "Z":
                break
            time.sleep(0.02)
        else:
            self.fail("descendant survived shutdown as a running process")

    def test_repeated_shutdown_signals_are_safe_for_active_process_group(self):
        process = self._start("import time; time.sleep(30)")
        signal_process_group(process, signal.SIGTERM)
        signal_process_group(process, signal.SIGTERM)

        shutdown = threading.Event()
        shutdown.set()
        with self.assertRaises(BridgeProcessCancelled):
            communicate_process(process, shutdown, shutdown_grace_seconds=0.3)
        self.assertIsNotNone(process.poll())

    def test_gtk_completion_callback_discards_result_after_window_close(self):
        pending = ("list-packages", lambda _payload, _error: None)
        window = type(
            "WindowState",
            (),
            {
                "_closing": True,
                "_loading": True,
                "_pending_request": pending,
            },
        )()
        delivered = []

        for _ in range(2):
            result = uraam_gui.UraamWindow._finish_async(
                window,
                lambda payload, error: delivered.append((payload, error)),
                {"status": "ok"},
                None,
            )
            self.assertEqual(result, uraam_gui.GLib.SOURCE_REMOVE)

        self.assertEqual(delivered, [])
        self.assertFalse(window._loading)
        self.assertIsNone(window._pending_request)

    def test_rapid_navigation_invalidates_an_older_inventory_callback(self):
        class FakeStack:
            def __init__(self):
                self.visible = "packages"

            def get_visible_child_name(self):
                return self.visible

            def set_visible_child_name(self, name):
                self.visible = name

        delivered = []
        window = type(
            "WindowState",
            (),
            {
                "_view_generation": 4,
                "_closing": False,
                "stack": FakeStack(),
                "_show_device": lambda self, payload, error: delivered.append(
                    (payload, error)
                ),
            },
        )()

        uraam_gui.UraamWindow._show_view(window, "dashboard")
        uraam_gui.UraamWindow._show_view(window, "packages")
        self.assertEqual(window._view_generation, 6)

        uraam_gui.UraamWindow._begin_package_inventory(
            window, {"status": "connected"}, None, 4
        )
        self.assertEqual(delivered, [])

    def test_selecting_the_already_visible_view_does_not_invalidate_request(self):
        class FakeStack:
            def __init__(self):
                self.visible = "packages"
                self.set_calls = 0

            def get_visible_child_name(self):
                return self.visible

            def set_visible_child_name(self, name):
                self.set_calls += 1
                self.visible = name

        window = type(
            "WindowState",
            (),
            {"_view_generation": 9, "stack": FakeStack()},
        )()
        uraam_gui.UraamWindow._show_view(window, "packages")
        self.assertEqual(window._view_generation, 9)
        self.assertEqual(window.stack.set_calls, 1)

    def test_completed_response_is_discarded_when_close_precedes_ui_dispatch(self):
        process = self._start("print('response-ready', flush=True)")
        stdout, stderr = communicate_process(process, threading.Event())
        self.assertEqual(stdout.strip(), "response-ready")
        self.assertEqual(stderr, "")

        # The worker has completed, but its queued GTK idle callback has not run.
        # Closing in this gap must invalidate delivery and discard newer queued work.
        shutdown = threading.Event()
        shutdown.set()
        self.assertFalse(request_is_current(12, 12, shutdown.is_set()))
        pending = ("list-packages", lambda _payload, _error: None)
        self.assertIsNone(take_pending_request(pending, shutdown.is_set()))

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

    def test_timeout_kills_descendant_after_leader_exits(self):
        code = (
            "import subprocess, sys; "
            "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])"
        )
        process = self._start(code)
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
        process.communicate(timeout=2)
        signal_process_group(process, 15)
        self.assertEqual(process.returncode, 0)


if __name__ == "__main__":
    unittest.main()
