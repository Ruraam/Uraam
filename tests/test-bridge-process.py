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

    def test_completed_leader_does_not_leave_pipe_closing_descendant(self):
        child = (
            "import os, signal, time; "
            "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "os.close(1); os.close(2); time.sleep(30)"
        )
        code = (
            "import subprocess, sys, time; "
            f"child = subprocess.Popen([sys.executable, '-c', {child!r}]); "
            "print(child.pid, flush=True); time.sleep(0.1)"
        )
        process = self._start(code)
        stdout, _stderr = communicate_process(process, threading.Event())
        child_pid = int(stdout.strip())
        self.assertIsNotNone(process.poll())

        # The bridge leader has exited and its child closed both inherited
        # pipes, but the child must not remain runnable in the isolated group.
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
            self.fail("descendant survived successful bridge completion")

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

    def test_repeated_close_requests_cancel_active_process_only_once(self):
        from unittest.mock import patch

        process = object()
        pending = ("list-packages", lambda _payload, _error: None)
        shutdown = threading.Event()
        window = type(
            "WindowState",
            (),
            {
                "_closing": False,
                "_process_lock": threading.Lock(),
                "_shutdown_event": shutdown,
                "_active_process": process,
                "_pending_request": pending,
            },
        )()
        signalled = []

        with patch.object(
            uraam_gui,
            "signal_process_group",
            side_effect=lambda target, sig: signalled.append((target, sig)),
        ):
            first_result = uraam_gui.UraamWindow._on_close_request(window, window)
            second_result = uraam_gui.UraamWindow._on_close_request(window, window)

        self.assertFalse(first_result)
        self.assertFalse(second_result)
        self.assertTrue(window._closing)
        self.assertTrue(shutdown.is_set())
        self.assertIsNone(window._pending_request)
        self.assertEqual(signalled, [(process, signal.SIGTERM)])


    def test_process_created_during_close_is_cancelled_before_communication(self):
        from unittest.mock import patch

        popen_entered = threading.Event()
        allow_popen_return = threading.Event()
        shutdown = threading.Event()
        process = type("FakeProcess", (), {"returncode": None})()
        window = type(
            "WindowState",
            (),
            {
                "_closing": False,
                "_process_lock": threading.Lock(),
                "_shutdown_event": shutdown,
                "_active_process": None,
            },
        )()
        errors = []
        communicate_events = []

        def delayed_popen(*_args, **_kwargs):
            popen_entered.set()
            if not allow_popen_return.wait(timeout=3):
                raise AssertionError("test did not release process creation")
            return process

        def observe_communication(_process, shutdown_event, **_kwargs):
            communicate_events.append(shutdown_event.is_set())
            raise BridgeProcessCancelled("The read-only bridge is shutting down.")

        def run_api_call():
            try:
                uraam_gui.UraamWindow._api_call(window, "device-info")
            except Exception as exc:
                errors.append(exc)

        with (
            patch.object(uraam_gui, "API_PATH", Path(__file__)),
            patch.object(uraam_gui.subprocess, "Popen", side_effect=delayed_popen),
            patch.object(
                uraam_gui, "communicate_process", side_effect=observe_communication
            ),
        ):
            worker = threading.Thread(target=run_api_call)
            worker.start()
            self.assertTrue(popen_entered.wait(timeout=3))

            close_result = uraam_gui.UraamWindow._on_close_request(window, window)
            allow_popen_return.set()
            worker.join(timeout=3)

        self.assertFalse(worker.is_alive())
        self.assertFalse(close_result)
        self.assertTrue(shutdown.is_set())
        self.assertIsNone(window._active_process)
        self.assertEqual(communicate_events, [True])
        self.assertEqual(len(errors), 1)
        self.assertIsInstance(errors[0], RuntimeError)
        self.assertIn("shutting down", str(errors[0]))


    def test_start_async_does_not_create_worker_after_shutdown(self):
        from unittest.mock import patch

        class ForbiddenWidget:
            def __getattr__(self, name):
                raise AssertionError(f"closed window widget accessed: {name}")

        delivered = []
        window = type(
            "WindowState",
            (),
            {
                "_closing": True,
                "_loading": False,
                "loading_spinner": ForbiddenWidget(),
                "refresh_button": ForbiddenWidget(),
                "status_label": ForbiddenWidget(),
            },
        )()

        with patch.object(uraam_gui.threading, "Thread") as thread_factory:
            uraam_gui.UraamWindow._start_async(
                window,
                "list-packages",
                lambda payload, error: delivered.append((payload, error)),
            )

        thread_factory.assert_not_called()
        self.assertFalse(window._loading)
        self.assertEqual(delivered, [])


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

    def test_queued_completion_after_close_request_does_not_touch_gtk_widgets(self):
        class ForbiddenWidget:
            def __getattr__(self, name):
                raise AssertionError(f"closed window widget accessed: {name}")

        pending = ("list-packages", lambda _payload, _error: None)
        shutdown = threading.Event()
        window = type(
            "WindowState",
            (),
            {
                "_closing": False,
                "_loading": True,
                "_pending_request": pending,
                "_process_lock": threading.Lock(),
                "_shutdown_event": shutdown,
                "_active_process": None,
                "loading_spinner": ForbiddenWidget(),
                "refresh_button": ForbiddenWidget(),
                "status_label": ForbiddenWidget(),
            },
        )()
        delivered = []

        close_result = uraam_gui.UraamWindow._on_close_request(window, window)
        completion_result = uraam_gui.UraamWindow._finish_async(
            window,
            lambda payload, error: delivered.append((payload, error)),
            {"status": "ok"},
            None,
        )

        self.assertFalse(close_result)
        self.assertTrue(window._closing)
        self.assertTrue(shutdown.is_set())
        self.assertIsNone(window._pending_request)
        self.assertFalse(window._loading)
        self.assertEqual(completion_result, uraam_gui.GLib.SOURCE_REMOVE)
        self.assertEqual(delivered, [])


    def test_multiple_queued_completions_after_close_are_all_discarded(self):
        class ForbiddenWidget:
            def __getattr__(self, name):
                raise AssertionError(f"closed window widget accessed: {name}")

        shutdown = threading.Event()
        window = type(
            "WindowState",
            (),
            {
                "_closing": False,
                "_loading": True,
                "_pending_request": ("list-packages", lambda *_args: None),
                "_process_lock": threading.Lock(),
                "_shutdown_event": shutdown,
                "_active_process": None,
                "loading_spinner": ForbiddenWidget(),
                "refresh_button": ForbiddenWidget(),
                "status_label": ForbiddenWidget(),
            },
        )()
        delivered = []
        callbacks = [
            lambda payload, error, index=index: delivered.append(
                (index, payload, error)
            )
            for index in range(3)
        ]

        close_result = uraam_gui.UraamWindow._on_close_request(window, window)
        completion_results = [
            uraam_gui.UraamWindow._finish_async(
                window, callback, {"sequence": index}, None
            )
            for index, callback in enumerate(callbacks)
        ]

        self.assertFalse(close_result)
        self.assertTrue(shutdown.is_set())
        self.assertTrue(window._closing)
        self.assertIsNone(window._pending_request)
        self.assertFalse(window._loading)
        self.assertEqual(
            completion_results,
            [uraam_gui.GLib.SOURCE_REMOVE] * len(callbacks),
        )
        self.assertEqual(delivered, [])


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

    def test_inventory_response_is_discarded_after_same_serial_reconnect(self):
        class FakeLabel:
            def __init__(self):
                self.text = ""

            def set_text(self, value):
                self.text = value

        window = type("WindowState", (), {})()
        window._view_generation = 8
        window._closing = False
        window._device_generation = 12
        window._device_identity = ("adb", "device-123")
        window.status_label = FakeLabel()
        shown_devices = []
        reset_messages = []
        published_inventories = []
        window._show_device = lambda payload, error: shown_devices.append(
            (payload, error)
        )
        window._reset_package_views = lambda message: reset_messages.append(message)
        window._show_packages = lambda *args: published_inventories.append(args)

        # The inventory request started on generation 10. The same physical
        # device has reconnected with the same serial, but its generation is now
        # 12. Identity equality alone must not authorize the old inventory.
        device = {
            "status": "connected",
            "backend": "adb",
            "serial": "device-123",
        }
        inventory = {
            "backend": "adb",
            "serial": "device-123",
            "packages": ["com.example.stale"],
        }
        uraam_gui.UraamWindow._finish_package_inventory_validation(
            window,
            inventory,
            None,
            10,
            ("adb", "device-123"),
            device,
            None,
            8,
        )

        self.assertEqual(shown_devices, [(device, None)])
        self.assertEqual(len(reset_messages), 1)
        self.assertEqual(
            window.status_label.text,
            "Device changed; inventory discarded",
        )
        self.assertEqual(published_inventories, [])

    def test_inventory_response_is_discarded_when_navigation_and_device_change_race(self):
        class FakeLabel:
            def __init__(self):
                self.text = ""

            def set_text(self, value):
                self.text = value

        window = type("WindowState", (), {})()
        window._view_generation = 9
        window._closing = False
        window._device_generation = 12
        window.status_label = FakeLabel()
        calls = []
        window._show_device = lambda *_args: calls.append("device")
        window._reset_package_views = lambda *_args: calls.append("reset")
        window._show_packages = lambda *_args: calls.append("inventory")

        uraam_gui.UraamWindow._finish_package_inventory_validation(
            window,
            {"backend": "adb", "serial": "device-123", "packages": ["stale"]},
            None,
            10,
            ("adb", "device-123"),
            {
                "status": "connected",
                "backend": "adb",
                "serial": "device-123",
            },
            None,
            8,
        )

        # Navigation is checked first; a callback from the old view must not
        # mutate the new screen, even if the device generation also changed.
        self.assertEqual(calls, [])
        self.assertEqual(window.status_label.text, "")

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

    def test_reselecting_package_invalidates_an_older_same_package_callback(self):
        class FakeStack:
            def __init__(self):
                self.visible = "packages"

            def get_visible_child_name(self):
                return self.visible

            def set_visible_child_name(self, name):
                self.visible = name

        class FakeLabel:
            def __init__(self):
                self.text = ""

            def set_text(self, value):
                self.text = value

        callbacks = []
        window = type("WindowState", (), {})()
        window._package_request_generation = 0
        window._device_generation = 3
        window._device_identity = ("adb", "device-123")
        window._view_generation = 0
        window._closing = False
        window._inventory_loaded = True
        window._selected_package = None
        window.stack = FakeStack()
        window.package_detail_name = FakeLabel()
        window.package_detail_status = FakeLabel()
        window.status_label = FakeLabel()
        window.device_card = object()
        window.backend_card = object()
        window.rom_card = object()
        window.version_card = object()
        window._reset_package_views = lambda _message: None
        window.package_detail_version = object()
        window.package_detail_path = object()
        window.package_detail_permissions = object()
        window.package_detail_components = {}
        window._replace_card = lambda *_args: None
        window._run_async = lambda _command, callback: callbacks.append(callback)
        window._show_view = lambda name: uraam_gui.UraamWindow._show_view(window, name)
        window._show_package_info = lambda *args: uraam_gui.UraamWindow._show_package_info(window, *args)

        class FakeLabelWidget:
            def __init__(self, label=""):
                self.text = label

            def get_text(self):
                return self.text

        class FakeBoxWidget:
            def __init__(self):
                self.child = None

            def get_first_child(self):
                return self.child

        class FakeRow:
            def __init__(self, child):
                self.child = child

            def get_child(self):
                return self.child

        def activate(package):
            child = FakeBoxWidget()
            child.child = FakeLabelWidget(package)
            row = FakeRow(child)
            uraam_gui.UraamWindow._on_package_activated(window, None, row)

        # Patch only the GTK type checks for this headless unit test. No GTK
        # widgets are instantiated, so the test is safe without a display.
        original_label = uraam_gui.Gtk.Label
        original_box = uraam_gui.Gtk.Box
        try:
            uraam_gui.Gtk.Label = FakeLabelWidget
            uraam_gui.Gtk.Box = FakeBoxWidget
            activate("com.example.alpha")
            first_generation = window._package_request_generation
            activate("com.example.beta")
            activate("com.example.alpha")
        finally:
            uraam_gui.Gtk.Label = original_label
            uraam_gui.Gtk.Box = original_box

        self.assertEqual(len(callbacks), 3)
        self.assertEqual(window._package_request_generation, first_generation + 2)
        self.assertEqual(window._selected_package, "com.example.alpha")
        self.assertEqual(
            window.package_detail_status.text,
            "Querying Android using read-only commands…",
        )

        # The first Alpha response has the same package name as the current
        # selection, but belongs to an older activation and must be discarded.
        callbacks[0]({"package": "com.example.alpha"}, None)
        self.assertEqual(
            window.package_detail_status.text,
            "Querying Android using read-only commands…",
        )

        # The newest Alpha response is accepted while its originating view is
        # still active and its request/device generations remain current.
        callbacks[2](
            {
                "package": "com.example.alpha",
                "backend": "adb",
                "paths": ["/data/app/com.example.alpha/base.apk"],
                "version_name": "1.2",
                "version_code": "12",
                "requested_permissions": [],
                "components": {},
                "metadata_limited": False,
                "read_only": True,
            },
            None,
        )
        self.assertEqual(
            window.package_detail_status.text,
            "Backend: ADB · Read-only inspection · Requested names only",
        )

        # Disconnecting and reconnecting the same serial must still invalidate
        # the in-flight response: identity equality cannot revive its generation.
        window.package_detail_status.set_text("Device reconnected; waiting for fresh details…")
        previous_device_generation = window._device_generation
        uraam_gui.UraamWindow._show_device(
            window, {"status": "disconnected"}, None
        )
        uraam_gui.UraamWindow._show_device(
            window,
            {
                "status": "connected",
                "backend": "adb",
                "serial": "device-123",
                "model": "Pixel",
                "oem": "google",
                "version": "5.1.0",
                "rom": {"name": "Android", "version": "15"},
            },
            None,
        )
        self.assertEqual(window._device_identity, ("adb", "device-123"))
        self.assertGreater(window._device_generation, previous_device_generation)
        callbacks[2](
            {
                "package": "com.example.alpha",
                "backend": "adb",
                "paths": ["/data/app/com.example.alpha/base.apk"],
                "version_name": "stale-reconnected-device",
                "version_code": "99",
                "requested_permissions": [],
                "components": {},
                "metadata_limited": False,
                "read_only": True,
            },
            None,
        )
        self.assertEqual(
            window.package_detail_status.text,
            "Device reconnected; waiting for fresh details…",
        )

        # Leaving the detail view and returning creates a new view generation;
        # an already delivered callback must not overwrite the refreshed view.
        uraam_gui.UraamWindow._show_view(window, "dashboard")
        uraam_gui.UraamWindow._show_view(window, "package-detail")
        window.package_detail_status.set_text("Waiting for a fresh selection…")
        callbacks[2](
            {"package": "com.example.alpha", "backend": "adb"},
            None,
        )
        self.assertEqual(
            window.package_detail_status.text,
            "Waiting for a fresh selection…",
        )

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

    def test_shutdown_wins_when_requested_at_timeout_boundary(self):
        from unittest.mock import patch

        shutdown = threading.Event()
        signals = []

        class BoundaryProcess:
            def __init__(self):
                self.pid = 4242
                self.returncode = None
                self.communicate_calls = 0

            def communicate(self, timeout=None):
                self.communicate_calls += 1
                if self.communicate_calls == 1:
                    # Model the poll expiring at the same instant shutdown lands.
                    shutdown.set()
                    raise subprocess.TimeoutExpired("bridge", timeout)
                self.returncode = -signal.SIGTERM
                return ("", "")

        process = BoundaryProcess()
        with (
            patch("bridge_process.time.monotonic", side_effect=[10.0, 10.5]),
            patch(
                "bridge_process.signal_process_group",
                side_effect=lambda target, sig: signals.append((target, sig)),
            ),
        ):
            with self.assertRaises(BridgeProcessCancelled):
                communicate_process(
                    process,
                    shutdown,
                    timeout_seconds=0.5,
                    poll_interval=0.05,
                    shutdown_grace_seconds=0.2,
                )

        self.assertTrue(shutdown.is_set())
        self.assertEqual(process.communicate_calls, 2)
        self.assertEqual(
            signals,
            [(process, signal.SIGTERM), (process, signal.SIGKILL)],
        )

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

    def test_timeout_kills_descendant_that_ignores_sigterm_and_closes_pipes(self):
        child = (
            "import os, signal, time; "
            "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "os.close(1); os.close(2); time.sleep(30)"
        )
        code = (
            "import subprocess, sys, time; "
            f"child = subprocess.Popen([sys.executable, '-c', {child!r}]); "
            "print(child.pid, flush=True); time.sleep(30)"
        )
        process = self._start(code)
        child_pid = int(process.stdout.readline().strip())

        started = time.monotonic()
        with self.assertRaises(BridgeProcessTimeout):
            communicate_process(
                process,
                threading.Event(),
                timeout_seconds=0.2,
                poll_interval=0.05,
                shutdown_grace_seconds=0.2,
            )
        self.assertIsNotNone(process.poll())
        self.assertLess(time.monotonic() - started, 3.0)

        # SIGKILL can leave an orphaned zombie briefly, but never a runnable child.
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
            self.fail("descendant survived timeout as a running process")

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


class AsyncRequestCoalescingTests(unittest.TestCase):
    def test_latest_pending_request_replaces_intermediate_requests(self):
        class FakeStatusLabel:
            def __init__(self):
                self.message = ""

            def set_text(self, message):
                self.message = message

        callbacks = [lambda _payload, _error: None for _ in range(3)]
        window = type(
            "WindowState",
            (),
            {
                "_closing": False,
                "_loading": True,
                "_pending_request": None,
                "status_label": FakeStatusLabel(),
            },
        )()

        for command, callback in zip(
            ("device-info", "list-packages", "device-info"), callbacks
        ):
            uraam_gui.UraamWindow._run_async(window, command, callback)

        self.assertEqual(window._pending_request, ("device-info", callbacks[-1]))
        self.assertEqual(window.status_label.message, "Waiting to load device-info…")

    def test_completion_starts_latest_pending_request_without_delivering_old_result(self):
        old_deliveries = []
        started = []
        latest_callback = lambda payload, error: None
        window = type(
            "WindowState",
            (),
            {
                "_closing": False,
                "_loading": True,
                "_pending_request": ("device-info", latest_callback),
                "_start_async": lambda self, command, callback: started.append(
                    (command, callback)
                ),
            },
        )()

        result = uraam_gui.UraamWindow._finish_async(
            window,
            lambda payload, error: old_deliveries.append((payload, error)),
            {"status": "ok", "source": "superseded"},
            None,
        )

        self.assertEqual(result, uraam_gui.GLib.SOURCE_REMOVE)
        self.assertEqual(started, [("device-info", latest_callback)])
        self.assertEqual(old_deliveries, [])
        self.assertFalse(window._loading)
        self.assertIsNone(window._pending_request)

    def test_intermediate_response_cannot_overwrite_latest_queued_action(self):
        deliveries = []
        started = []
        callbacks = {
            command: (lambda payload, error, name=command: deliveries.append(
                (name, payload, error)
            ))
            for command in ("first", "second", "latest")
        }
        window = type(
            "WindowState",
            (),
            {
                "_closing": False,
                "_loading": True,
                "_pending_request": ("latest", callbacks["latest"]),
                "_start_async": lambda self, command, callback: started.append(
                    (command, callback)
                ),
            },
        )()

        uraam_gui.UraamWindow._finish_async(
            window, callbacks["first"], {"value": "first"}, None
        )

        self.assertEqual([command for command, _ in started], ["latest"])
        self.assertEqual(deliveries, [])




    def test_run_async_rejects_new_work_after_shutdown(self):
        started = []
        window = type(
            "WindowState",
            (),
            {
                "_closing": True,
                "_loading": False,
                "_pending_request": None,
                "_start_async": lambda self, command, callback: started.append(
                    (command, callback)
                ),
            },
        )()
        callback = lambda _payload, _error: None

        uraam_gui.UraamWindow._run_async(window, "device-info", callback)

        self.assertEqual(started, [])
        self.assertIsNone(window._pending_request)

    def test_start_async_restores_ui_and_reports_thread_start_failure(self):
        class FakeSpinner:
            def __init__(self):
                self.started = 0
                self.stopped = 0

            def start(self):
                self.started += 1

            def stop(self):
                self.stopped += 1

        class FakeButton:
            def __init__(self):
                self.sensitivity = []

            def set_sensitive(self, value):
                self.sensitivity.append(value)

        class FakeLabel:
            def __init__(self):
                self.messages = []

            def set_text(self, value):
                self.messages.append(value)

        class BrokenThread:
            def __init__(self, **_kwargs):
                pass

            def start(self):
                raise RuntimeError("thread creation denied\n" + ("x" * 3000))

        window = type("WindowState", (), {})()
        window._closing = False
        window._loading = False
        window.refresh_button = FakeButton()
        window.loading_spinner = FakeSpinner()
        window.status_label = FakeLabel()
        delivered = []
        original_thread = uraam_gui.threading.Thread
        try:
            uraam_gui.threading.Thread = BrokenThread
            uraam_gui.UraamWindow._start_async(
                window,
                "device-info",
                lambda payload, error: delivered.append((payload, error)),
            )
        finally:
            uraam_gui.threading.Thread = original_thread

        self.assertFalse(window._loading)
        self.assertEqual(window.loading_spinner.started, 1)
        self.assertEqual(window.loading_spinner.stopped, 1)
        self.assertEqual(window.refresh_button.sensitivity, [False, True])
        self.assertEqual(
            window.status_label.messages[-1],
            "Unable to start bridge request",
        )
        self.assertEqual(len(delivered), 1)
        self.assertIsNone(delivered[0][0])
        self.assertIn("device-info", delivered[0][1])
        self.assertTrue(delivered[0][1].startswith("Unable to start the read-only bridge request"))
        self.assertEqual(len(delivered[0][1]), 2048)
        self.assertTrue(delivered[0][1].endswith("..."))
        self.assertNotIn("\n", delivered[0][1])

    def test_worker_exception_is_sanitized_and_bounded(self):
        class FakeSpinner:
            def __init__(self):
                self.started = 0
                self.stopped = 0

            def start(self):
                self.started += 1

            def stop(self):
                self.stopped += 1

        class FakeButton:
            def __init__(self):
                self.sensitivity = []

            def set_sensitive(self, value):
                self.sensitivity.append(value)

        class InlineThread:
            def __init__(self, target, **_kwargs):
                self.target = target

            def start(self):
                self.target()

        queued_callbacks = []

        class FakeGLib:
            SOURCE_REMOVE = False

            @staticmethod
            def idle_add(callback, *args):
                queued_callbacks.append((callback, args))
                return 1

        window = type("WindowState", (), {})()
        window._closing = False
        window._loading = False
        window._finish_async = uraam_gui.UraamWindow._finish_async.__get__(
            window, uraam_gui.UraamWindow
        )
        window.refresh_button = FakeButton()
        window.loading_spinner = FakeSpinner()
        window.status_label = type(
            "FakeLabel", (), {"set_text": lambda self, _message: None}
        )()
        window._api_call = lambda _command: (_ for _ in ()).throw(
            RuntimeError("bridge failure\n" + ("y" * 3000))
        )
        original_thread = uraam_gui.threading.Thread
        original_glib = uraam_gui.GLib
        try:
            uraam_gui.threading.Thread = InlineThread
            uraam_gui.GLib = FakeGLib
            uraam_gui.UraamWindow._start_async(
                window,
                "device-info",
                lambda _payload, _error: self.fail(
                    "GTK callback must remain queued in this worker-isolation test"
                ),
            )
        finally:
            uraam_gui.threading.Thread = original_thread
            uraam_gui.GLib = original_glib

        self.assertTrue(window._loading)
        self.assertEqual(len(queued_callbacks), 1)
        callback, args = queued_callbacks[0]
        self.assertIs(callback.__self__, window)
        self.assertIs(callback.__func__, uraam_gui.UraamWindow._finish_async)
        self.assertIsNone(args[1])
        error = args[2]
        self.assertTrue(error.startswith("bridge failure"))
        self.assertEqual(len(error), 2048)
        self.assertTrue(error.endswith("..."))
        self.assertNotIn("\n", error)

    def test_async_api_error_restores_ui_and_allows_next_request(self):
        class FakeSpinner:
            def __init__(self):
                self.stopped = 0

            def stop(self):
                self.stopped += 1

        class FakeButton:
            def __init__(self):
                self.sensitivity = []

            def set_sensitive(self, value):
                self.sensitivity.append(value)

        window = type("WindowState", (), {})()
        window._closing = False
        window._loading = True
        window._pending_request = None
        window.loading_spinner = FakeSpinner()
        window.refresh_button = FakeButton()
        delivered = []

        result = uraam_gui.UraamWindow._finish_async(
            window,
            lambda payload, error: delivered.append((payload, error)),
            None,
            "bridge temporarily unavailable",
        )

        self.assertEqual(result, uraam_gui.GLib.SOURCE_REMOVE)
        self.assertFalse(window._loading)
        self.assertEqual(window.loading_spinner.stopped, 1)
        self.assertEqual(window.refresh_button.sensitivity, [True])
        self.assertEqual(
            delivered,
            [(None, "bridge temporarily unavailable")],
        )

        # A transient API error must not leave the request pipeline wedged.
        started = []
        window._start_async = lambda command, callback: started.append(
            (command, callback)
        )
        next_callback = lambda _payload, _error: None
        uraam_gui.UraamWindow._run_async(window, "list-packages", next_callback)
        self.assertEqual(started, [("list-packages", next_callback)])


    def test_long_gui_pages_are_wrapped_in_scrollable_containers(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        class FakeScroller:
            def __init__(self):
                self.policy = None
                self.child = None
                self.hexpand = False
                self.vexpand = False

            def set_policy(self, horizontal, vertical):
                self.policy = (horizontal, vertical)

            def set_hexpand(self, value):
                self.hexpand = value

            def set_vexpand(self, value):
                self.vexpand = value

            def set_child(self, child):
                self.child = child

        class FakeStack:
            def __init__(self):
                self.pages = []

            def add_named(self, child, name):
                self.pages.append((child, name))

        stack = FakeStack()
        window = SimpleNamespace(stack=stack)
        page = object()
        automatic = object()
        fake_gtk = SimpleNamespace(
            ScrolledWindow=FakeScroller,
            PolicyType=SimpleNamespace(AUTOMATIC=automatic),
        )

        with patch.object(uraam_gui, "Gtk", fake_gtk):
            uraam_gui.UraamWindow._add_scrollable_page(
                window, page, "package-detail"
            )

        self.assertEqual(len(stack.pages), 1)
        scroller, name = stack.pages[0]
        self.assertEqual(name, "package-detail")
        self.assertIs(scroller.child, page)
        self.assertEqual(scroller.policy, (automatic, automatic))
        self.assertTrue(scroller.hexpand)
        self.assertTrue(scroller.vexpand)


    def test_show_view_updates_active_navigation_state(self):
        class FakeStack:
            def __init__(self):
                self.visible = "dashboard"

            def get_visible_child_name(self):
                return self.visible

            def set_visible_child_name(self, name):
                self.visible = name

        class FakeButton:
            def __init__(self):
                self.classes = set()

            def add_css_class(self, name):
                self.classes.add(name)

            def remove_css_class(self, name):
                self.classes.discard(name)

            def update_property(self, properties, values):
                self.accessible_description = (properties, values)

        window = type("WindowState", (), {})()
        window.stack = FakeStack()
        window.dashboard_button = FakeButton()
        window.packages_button = FakeButton()
        window._view_generation = 0
        window._set_accessible_description = (
            uraam_gui.UraamWindow._set_accessible_description
        )

        uraam_gui.UraamWindow._show_view(window, "package-detail")

        self.assertEqual(window.stack.visible, "package-detail")
        self.assertIn("active", window.packages_button.classes)
        self.assertNotIn("active", window.dashboard_button.classes)
        self.assertEqual(
            window.packages_button.accessible_description[1],
            ["Current page. Keyboard shortcut: Ctrl+2."],
        )
        self.assertEqual(
            window.dashboard_button.accessible_description[1],
            ["Open page. Keyboard shortcut: Ctrl+1."],
        )
        self.assertEqual(window._view_generation, 1)

        uraam_gui.UraamWindow._show_view(window, "dashboard")
        self.assertIn("active", window.dashboard_button.classes)
        self.assertNotIn("active", window.packages_button.classes)
        self.assertEqual(
            window.dashboard_button.accessible_description[1],
            ["Current page. Keyboard shortcut: Ctrl+1."],
        )
        self.assertEqual(
            window.packages_button.accessible_description[1],
            ["Open page. Keyboard shortcut: Ctrl+2."],
        )

    def test_keyboard_shortcuts_navigate_and_escape_detail(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        calls = []
        window = type("WindowState", (), {})()
        window._show_view = lambda name: calls.append(("view", name))
        window._on_packages = lambda _button: calls.append(("packages", None))
        window.stack = SimpleNamespace(
            get_visible_child_name=lambda: "package-detail"
        )
        fake_gdk = SimpleNamespace(
            ModifierType=SimpleNamespace(
                CONTROL_MASK=4,
                SHIFT_MASK=1,
                ALT_MASK=8,
            ),
            KEY_1=49,
            KEY_2=50,
            KEY_Escape=65307,
        )
        with patch.object(uraam_gui, "Gdk", fake_gdk):
            self.assertTrue(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 49, 0, 4)
            )
            self.assertTrue(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 50, 0, 4)
            )
            self.assertTrue(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 65307, 0, 0)
            )
            self.assertFalse(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 65, 0, 0)
            )

        self.assertEqual(
            calls,
            [
                ("view", "dashboard"),
                ("packages", None),
                ("view", "packages"),
            ],
        )

    def test_keyboard_controller_is_connected_and_attached_to_window(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        class FakeController:
            def __init__(self):
                self.connections = []

            def connect(self, signal_name, callback):
                self.connections.append((signal_name, callback))

        controller = FakeController()
        added = []
        handler = lambda *_args: False
        window = type("WindowState", (), {})()
        window._on_key_pressed = handler
        window.add_controller = added.append

        with patch.object(
            uraam_gui,
            "Gtk",
            SimpleNamespace(EventControllerKey=lambda: controller),
        ):
            uraam_gui.UraamWindow._install_keyboard_controller(window)

        self.assertEqual(added, [controller])
        self.assertEqual(controller.connections, [("key-pressed", handler)])


    def test_keyboard_shortcuts_are_ignored_while_window_is_closing(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        calls = []
        window = type("WindowState", (), {})()
        window._closing = True
        window._show_view = lambda name: calls.append(("view", name))
        window._on_packages = lambda _button: calls.append(("packages", None))
        window.stack = SimpleNamespace(
            get_visible_child_name=lambda: "package-detail"
        )
        fake_gdk = SimpleNamespace(
            ModifierType=SimpleNamespace(
                CONTROL_MASK=4,
                SHIFT_MASK=1,
                ALT_MASK=8,
            ),
            KEY_1=49,
            KEY_2=50,
            KEY_Escape=65307,
        )
        with patch.object(uraam_gui, "Gdk", fake_gdk):
            for keyval, state in ((49, 4), (50, 4), (65307, 0)):
                self.assertFalse(
                    uraam_gui.UraamWindow._on_key_pressed(
                        window, None, keyval, 0, state
                    )
                )

        self.assertEqual(calls, [])


    def test_escape_is_ignored_outside_package_detail(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        calls = []
        window = type("WindowState", (), {})()
        window._show_view = lambda name: calls.append(name)
        window.stack = SimpleNamespace(
            get_visible_child_name=lambda: "dashboard"
        )
        fake_gdk = SimpleNamespace(
            ModifierType=SimpleNamespace(
                CONTROL_MASK=4,
                SHIFT_MASK=1,
                ALT_MASK=8,
            ),
            KEY_1=49,
            KEY_2=50,
            KEY_Escape=65307,
        )
        with patch.object(uraam_gui, "Gdk", fake_gdk):
            self.assertFalse(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 65307, 0, 0)
            )

        self.assertEqual(calls, [])

    def test_repeated_navigation_shortcuts_are_handled_in_order(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        calls = []
        window = type("WindowState", (), {})()
        window._show_view = lambda name: calls.append(("view", name))
        window._on_packages = lambda _button: calls.append(("packages", None))
        window.stack = SimpleNamespace(
            get_visible_child_name=lambda: "dashboard"
        )
        fake_gdk = SimpleNamespace(
            ModifierType=SimpleNamespace(
                CONTROL_MASK=4,
                SHIFT_MASK=1,
                ALT_MASK=8,
            ),
            KEY_1=49,
            KEY_2=50,
            KEY_Escape=65307,
        )
        with patch.object(uraam_gui, "Gdk", fake_gdk):
            for keyval in (49, 50, 49, 50):
                self.assertTrue(
                    uraam_gui.UraamWindow._on_key_pressed(
                        window, None, keyval, 0, 4
                    )
                )

        self.assertEqual(
            calls,
            [
                ("view", "dashboard"),
                ("packages", None),
                ("view", "dashboard"),
                ("packages", None),
            ],
        )


    def test_keyboard_shortcuts_ignore_extra_or_wrong_modifiers(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        calls = []
        window = type("WindowState", (), {})()
        window._show_view = lambda name: calls.append(("view", name))
        window._on_packages = lambda _button: calls.append(("packages", None))
        window.stack = SimpleNamespace(
            get_visible_child_name=lambda: "package-detail"
        )
        fake_gdk = SimpleNamespace(
            ModifierType=SimpleNamespace(
                CONTROL_MASK=4,
                SHIFT_MASK=1,
                ALT_MASK=8,
            ),
            KEY_1=49,
            KEY_2=50,
            KEY_Escape=65307,
        )
        with patch.object(uraam_gui, "Gdk", fake_gdk):
            self.assertFalse(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 49, 0, 1)
            )
            self.assertFalse(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 49, 0, 5)
            )
            self.assertFalse(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 50, 0, 8)
            )
            self.assertFalse(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 65307, 0, 4)
            )
            self.assertFalse(
                uraam_gui.UraamWindow._on_key_pressed(window, None, 65307, 0, 1)
            )

        self.assertEqual(calls, [])


    def test_accessible_description_helper_updates_widget_description(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        class FakeWidget:
            def __init__(self):
                self.update = None

            def update_property(self, properties, values):
                self.update = (properties, values)

        widget = FakeWidget()
        accessible_description = object()
        fake_gtk = SimpleNamespace(
            AccessibleProperty=SimpleNamespace(DESCRIPTION=accessible_description)
        )
        with patch.object(uraam_gui, "Gtk", fake_gtk):
            uraam_gui.UraamWindow._set_accessible_description(
                widget, "Current page. Keyboard shortcut: Ctrl+1."
            )

        self.assertEqual(
            widget.update,
            ([accessible_description], ["Current page. Keyboard shortcut: Ctrl+1."]),
        )


    def test_accessible_label_helper_updates_widget_label_property(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        class FakeWidget:
            def __init__(self):
                self.update = None

            def update_property(self, properties, values):
                self.update = (properties, values)

        widget = FakeWidget()
        accessible_label = object()
        fake_gtk = SimpleNamespace(
            AccessibleProperty=SimpleNamespace(LABEL=accessible_label)
        )
        with patch.object(uraam_gui, "Gtk", fake_gtk):
            uraam_gui.UraamWindow._set_accessible_label(
                widget, "Search installed packages"
            )

        self.assertEqual(
            widget.update,
            ([accessible_label], ["Search installed packages"]),
        )


    def test_accessible_control_name_and_guidance_are_both_exposed(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        class FakeWidget:
            def __init__(self):
                self.updates = []

            def update_property(self, properties, values):
                self.updates.append((properties, values))

        label_property = object()
        description_property = object()
        fake_gtk = SimpleNamespace(
            AccessibleProperty=SimpleNamespace(
                LABEL=label_property,
                DESCRIPTION=description_property,
            )
        )
        widget = FakeWidget()
        with patch.object(uraam_gui, "Gtk", fake_gtk):
            uraam_gui.UraamWindow._set_accessible_label(
                widget, "Filter packages by category"
            )
            uraam_gui.UraamWindow._set_accessible_description(
                widget, "Choose all, system, user, or unclassified packages."
            )

        self.assertEqual(
            widget.updates,
            [
                ([label_property], ["Filter packages by category"]),
                (
                    [description_property],
                    ["Choose all, system, user, or unclassified packages."],
                ),
            ],
        )


    def test_package_metadata_expander_starts_collapsed_and_keeps_child(self):
        from types import SimpleNamespace
        from unittest.mock import patch

        class FakeExpander:
            def __init__(self, title):
                self.title = title
                self.classes = []
                self.expanded = None
                self.child = None

            @classmethod
            def new(cls, title):
                return cls(title)

            def add_css_class(self, name):
                self.classes.append(name)

            def set_expanded(self, value):
                self.expanded = value

            def set_child(self, child):
                self.child = child

        child = object()
        fake_gtk = SimpleNamespace(Expander=FakeExpander)
        with patch.object(uraam_gui, "Gtk", fake_gtk):
            expander = uraam_gui.UraamWindow._make_expander(
                "Requested permissions", child
            )

        self.assertEqual(expander.title, "Requested permissions")
        self.assertEqual(expander.classes, ["uraam-detail-expander"])
        self.assertFalse(expander.expanded)
        self.assertIs(expander.child, child)


if __name__ == "__main__":
    unittest.main()
