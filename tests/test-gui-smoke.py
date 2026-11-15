#!/usr/bin/env python3
"""Headless GTK4 construction and navigation smoke test for URAAM."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import time
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "GUI"))

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

import bridge_process  # noqa: E402
from bridge_process import BridgeProcessCancelled, communicate_process  # noqa: E402
from main import UraamApplication, UraamWindow  # noqa: E402


def drain_main_context() -> None:
    context = GLib.MainContext.default()
    while context.pending():
        context.iteration(False)


def test_shutdown_kills_and_reaps_unresponsive_bridge() -> None:
    # The child deliberately ignores SIGTERM. Shutdown must escalate to
    # SIGKILL and reap it rather than leaving an orphaned bridge process.
    process = subprocess.Popen(
        [
            sys.executable,
            "-c",
            (
                "import signal, time; "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                "print('READY', flush=True); time.sleep(30)"
            ),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        if process.stdout is None or process.stdout.readline().strip() != "READY":
            raise AssertionError("The test bridge process did not become ready")

        shutdown_event = threading.Event()
        shutdown_event.set()
        try:
            communicate_process(
                process,
                shutdown_event,
                timeout_seconds=2.0,
                poll_interval=0.01,
                shutdown_grace_seconds=0.05,
            )
        except BridgeProcessCancelled:
            pass
        else:
            raise AssertionError("An active bridge process ignored shutdown")

        if process.poll() is None:
            raise AssertionError("An unresponsive bridge process was not reaped")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=2.0)
        if process.stdout is not None:
            process.stdout.close()
        if process.stderr is not None:
            process.stderr.close()


def test_shutdown_races_natural_bridge_exit() -> None:
    # Shutdown may race with a bridge that handles SIGTERM and exits cleanly.
    graceful = subprocess.Popen(
        [
            sys.executable,
            "-c",
            (
                "import signal, sys, time; "
                "signal.signal(signal.SIGTERM, lambda *_: sys.exit(0)); "
                "print('READY', flush=True); time.sleep(30)"
            ),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        if graceful.stdout is None or graceful.stdout.readline().strip() != "READY":
            raise AssertionError("The graceful-exit bridge did not become ready")
        shutdown_event = threading.Event()
        shutdown_event.set()
        try:
            communicate_process(
                graceful,
                shutdown_event,
                timeout_seconds=2.0,
                poll_interval=0.01,
                shutdown_grace_seconds=0.2,
            )
        except BridgeProcessCancelled:
            pass
        else:
            raise AssertionError("Shutdown did not take precedence over late output")
        if graceful.poll() is None:
            raise AssertionError("The gracefully stopping bridge was not reaped")
        if graceful.returncode != 0:
            raise AssertionError("The bridge did not complete its graceful SIGTERM handler")
    finally:
        if graceful.poll() is None:
            graceful.kill()
            graceful.wait(timeout=2.0)
        if graceful.stdout is not None:
            graceful.stdout.close()
        if graceful.stderr is not None:
            graceful.stderr.close()

    # Also cover the narrow ordering where the child has exited naturally,
    # but its pipe EOF/result has not yet been consumed when shutdown begins.
    completed = subprocess.Popen(
        [
            sys.executable,
            "-c",
            "print('COMPLETE', flush=True)",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        completed.wait(timeout=2.0)
        shutdown_event = threading.Event()
        shutdown_event.set()
        try:
            communicate_process(
                completed,
                shutdown_event,
                timeout_seconds=2.0,
                poll_interval=0.01,
                shutdown_grace_seconds=0.05,
            )
        except BridgeProcessCancelled:
            pass
        else:
            raise AssertionError("A completed result was delivered after shutdown")
        if completed.poll() is None or completed.returncode != 0:
            raise AssertionError("The naturally completed bridge was not reaped cleanly")
    finally:
        if completed.poll() is None:
            completed.kill()
            completed.wait(timeout=2.0)
        if completed.stdout is not None:
            completed.stdout.close()
        if completed.stderr is not None:
            completed.stderr.close()


def test_shutdown_closes_pipes_with_pending_output() -> None:
    # Keep both output pipes busy when shutdown arrives. The reader must stop
    # the process, reap it, and close both pipe handles on the cancellation path.
    process = subprocess.Popen(
        [
            sys.executable,
            "-c",
            (
                "import os, time; "
                "os.write(2, b'READY\\n'); "
                "chunk = b'x' * 65536; "
                "exec('while True:\\n os.write(1, chunk)\\n os.write(2, chunk)')"
            ),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        if process.stderr is None or process.stderr.readline().strip() != b"READY":
            raise AssertionError("The pipe-stress bridge did not become ready")

        shutdown_event = threading.Event()
        shutdown_event.set()
        try:
            communicate_process(
                process,
                shutdown_event,
                timeout_seconds=3.0,
                poll_interval=0.01,
                shutdown_grace_seconds=0.1,
            )
        except BridgeProcessCancelled:
            pass
        else:
            raise AssertionError("Shutdown did not cancel the pipe-stress bridge")

        if process.poll() is None:
            raise AssertionError("The pipe-stress bridge process was not reaped")
        if process.stdout is None or not process.stdout.closed:
            raise AssertionError("The bridge stdout pipe was not closed")
        if process.stderr is None or not process.stderr.closed:
            raise AssertionError("The bridge stderr pipe was not closed")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=2.0)
        if process.stdout is not None and not process.stdout.closed:
            process.stdout.close()
        if process.stderr is not None and not process.stderr.closed:
            process.stderr.close()


def test_reader_failure_kills_and_reaps_bridge() -> None:
    # Simulate a selector/pipe setup failure after the child has started.
    # The exceptional path must still kill the process group and close pipes.
    process = subprocess.Popen(
        [
            sys.executable,
            "-c",
            "import time; print('READY', flush=True); time.sleep(30)",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    original_selector = bridge_process.selectors.DefaultSelector

    class BrokenSelector:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def register(self, *_args, **_kwargs):
            raise OSError("simulated selector registration failure")

    try:
        if process.stdout is None or process.stdout.readline().strip() != "READY":
            raise AssertionError("The reader-failure bridge did not become ready")

        bridge_process.selectors.DefaultSelector = BrokenSelector
        try:
            communicate_process(
                process,
                threading.Event(),
                timeout_seconds=3.0,
                poll_interval=0.01,
            )
        except OSError as exc:
            if "simulated selector registration failure" not in str(exc):
                raise
        else:
            raise AssertionError("The simulated reader failure was not propagated")

        if process.poll() is None:
            raise AssertionError("Reader failure left the bridge process running")
        if process.stdout is None or not process.stdout.closed:
            raise AssertionError("Reader failure did not close stdout")
        if process.stderr is None or not process.stderr.closed:
            raise AssertionError("Reader failure did not close stderr")
    finally:
        bridge_process.selectors.DefaultSelector = original_selector
        if process.poll() is None:
            process.kill()
            process.wait(timeout=2.0)
        if process.stdout is not None and not process.stdout.closed:
            process.stdout.close()
        if process.stderr is not None and not process.stderr.closed:
            process.stderr.close()


def test_natural_leader_exit_kills_descendant_process_group() -> None:
    # The leader exits after its child is ready. The child deliberately closes
    # the bridge pipes, so only process-group cleanup can prevent its later work.
    with tempfile.TemporaryDirectory(prefix="uraam-bridge-descendant-") as temp_dir:
        ready_path = Path(temp_dir) / "descendant-ready"
        late_path = Path(temp_dir) / "descendant-ran-after-leader"
        child_code = (
            "import pathlib, time; "
            f"pathlib.Path({str(ready_path)!r}).write_text('ready'); "
            "time.sleep(1.0); "
            f"pathlib.Path({str(late_path)!r}).write_text('late')"
        )
        leader_code = (
            "import pathlib, subprocess, sys, time; "
            f"subprocess.Popen([sys.executable, '-c', {child_code!r}], "
            "stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); "
            "deadline = time.monotonic() + 2.0; "
            f"ready = pathlib.Path({str(ready_path)!r}); "
            "while not ready.exists() and time.monotonic() < deadline: "
            "time.sleep(0.01); "
            "assert ready.exists(), 'descendant did not become ready'; "
            "print('LEADER_DONE', flush=True)"
        )
        process = subprocess.Popen(
            [sys.executable, "-c", leader_code],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            stdout, _stderr = communicate_process(
                process,
                threading.Event(),
                timeout_seconds=3.0,
                poll_interval=0.01,
            )
            if stdout.strip() != "LEADER_DONE":
                raise AssertionError("The bridge leader did not finish normally")
            if process.poll() is None or process.returncode != 0:
                raise AssertionError("The bridge leader was not reaped cleanly")

            # The descendant would write this marker after one second if the
            # process group had not been terminated when the leader exited.
            time.sleep(1.2)
            if late_path.exists():
                raise AssertionError("A bridge descendant survived leader exit")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=2.0)
            if process.stdout is not None and not process.stdout.closed:
                process.stdout.close()
            if process.stderr is not None and not process.stderr.closed:
                process.stderr.close()


def main() -> int:
    test_natural_leader_exit_kills_descendant_process_group()
    test_reader_failure_kills_and_reaps_bridge()
    test_shutdown_closes_pipes_with_pending_output()
    test_shutdown_races_natural_bridge_exit()
    test_shutdown_kills_and_reaps_unresponsive_bridge()
    # Keep this smoke test isolated from ADB, Root, Shizuku and the device API.
    original_refresh = UraamWindow._refresh_device
    UraamWindow._refresh_device = lambda self: None
    application = UraamApplication()
    try:
        if not application.register(None):
            raise RuntimeError("Unable to register the GTK application")

        window = UraamWindow(application)
        # Keep page visibility assertions deterministic: the production UI uses
        # a crossfade, whose outgoing child can remain mapped during animation.
        window.stack.set_transition_duration(0)
        window.present()
        drain_main_context()

        if window.stack.get_visible_child_name() != "dashboard":
            raise AssertionError("The dashboard was not selected at startup")
        if window.package_list is None or window.package_search is None:
            raise AssertionError("The applications view was not constructed")
        if window.package_detail_name.get_text() != "Select an application":
            raise AssertionError("The package inspector was not initialized")

        # Stress the current metadata rendering path with the protocol's
        # maximum component count. This checks GTK construction/layout work
        # without connecting to Android or invoking package operations.
        stress_metadata = "\n".join(
            f"com.example.component.Entry{index}" for index in range(4096)
        )
        permission_card = window.package_detail_permissions
        window._replace_card(
            permission_card,
            "Requested permissions",
            "4096 requested",
            stress_metadata,
        )
        content = permission_card.get_child()
        value_label = content.get_first_child().get_next_sibling()
        metadata_scroller = value_label.get_next_sibling()
        if not isinstance(metadata_scroller, Gtk.ScrolledWindow):
            raise AssertionError("Large metadata is not placed in a dedicated scroller")
        if metadata_scroller.get_max_content_height() != 240:
            raise AssertionError("The metadata viewport does not have its expected height cap")
        metadata_viewport = metadata_scroller.get_child()
        detail_label = (
            metadata_viewport.get_child()
            if isinstance(metadata_viewport, Gtk.Viewport)
            else metadata_viewport
        )
        if not isinstance(detail_label, Gtk.Label):
            raise AssertionError("The metadata scroller does not contain a GTK label")
        if detail_label.get_text() != stress_metadata:
            raise AssertionError("The GTK metadata card truncated a large value")
        if not detail_label.get_selectable():
            raise AssertionError("Large metadata is not selectable for copying")
        if detail_label.get_focusable():
            raise AssertionError("Scrollable metadata exposes a redundant label focus stop")
        if not metadata_scroller.get_focusable():
            raise AssertionError("Scrollable metadata cannot receive keyboard focus")
        drain_main_context()

        window._packages = [
            "com.example.system",
            "com.example.user",
        ]
        window._package_types = {
            "com.example.system": "system",
            "com.example.user": "user",
        }
        window._package_classification = "1 system · 1 user · 0 unclassified"
        window.package_filter.set_selected(1)
        window._filter_packages()

        first_row = window.package_list.get_first_child()
        if first_row is None:
            raise AssertionError("The GTK package filter produced no system row")
        if first_row.get_child().get_first_child().get_text() != "com.example.system":
            raise AssertionError("The GTK package filter displayed the wrong row")
        if not first_row.get_focusable():
            raise AssertionError("A package result is not a keyboard focus target")
        if first_row.get_child().get_first_child().get_selectable():
            raise AssertionError("A package result exposes a redundant child focus target")
        if window.package_count_label.get_text() != "Showing 1 of 2 package(s)":
            raise AssertionError("The GTK package count is inconsistent")

        window._show_view("packages")
        if window.stack.get_visible_child_name() != "packages":
            raise AssertionError("Applications navigation failed")
        window._show_view("package-detail")
        if window.stack.get_visible_child_name() != "package-detail":
            raise AssertionError("Package inspector navigation failed")
        window.package_detail_back_button.grab_focus()
        if window.get_focus() is not window.package_detail_back_button:
            raise AssertionError("Opening the inspector did not move keyboard focus to its back control")

        for control in (
            window.refresh_button,
            window.dashboard_button,
            window.packages_button,
            window.package_detail_back_button,
        ):
            control.grab_focus()
            if window.get_focus() is not control:
                raise AssertionError("A primary GTK control cannot receive keyboard focus")

        permissions_expander = window.package_detail_permissions_expander
        components_expander = window.package_detail_components_expander
        if not permissions_expander.get_focusable() or not components_expander.get_focusable():
            raise AssertionError("Inspector disclosure controls are not keyboard focus targets")
        if permissions_expander.get_expanded() or components_expander.get_expanded():
            raise AssertionError("Inspector metadata sections should start collapsed")

        metadata_scrollers = [
            window.package_detail_path,
            window.package_detail_permissions,
            *window.package_detail_components.values(),
        ]
        for card in metadata_scrollers:
            content = card.get_child()
            value_label = content.get_first_child().get_next_sibling()
            scroller = value_label.get_next_sibling()
            if not isinstance(scroller, Gtk.ScrolledWindow):
                raise AssertionError("An inspector metadata card has no scrollable detail")
            if not scroller.get_focusable():
                raise AssertionError("An inspector metadata viewport is not keyboard focusable")

        permissions_expander.set_expanded(True)
        components_expander.set_expanded(True)
        drain_main_context()
        if not permissions_expander.get_expanded() or not components_expander.get_expanded():
            raise AssertionError("Inspector metadata sections cannot be expanded")
        if not window.package_detail_permissions.get_mapped():
            raise AssertionError("Permission metadata is not mapped when its section is expanded")
        if not window.package_detail_components["activities"].get_mapped():
            raise AssertionError("Component metadata is not mapped when its section is expanded")

        # Repeated disclosure changes must not leave keyboard focus inside a
        # subtree that GTK has just hidden.
        permission_scroller = metadata_scrollers[1]
        component_scroller = metadata_scrollers[2]
        for _ in range(5):
            permissions_expander.set_expanded(True)
            components_expander.set_expanded(True)
            drain_main_context()
            if not permission_scroller.get_mapped() or not component_scroller.get_mapped():
                raise AssertionError("Repeated expansion did not map the metadata content")

            for expander, scroller, section_name in (
                (permissions_expander, permission_scroller, "permissions"),
                (components_expander, component_scroller, "components"),
            ):
                # The disclosure itself is the stable keyboard target. GTK
                # backends may not focus a nested scroller directly while it
                # belongs to an Expander, so don't assume it becomes a Tab stop.
                expander.grab_focus()
                if window.get_focus() is not expander:
                    raise AssertionError(f"{section_name} disclosure cannot receive focus")
                expander.set_expanded(False)
                drain_main_context()
                if expander.get_expanded() or scroller.get_mapped():
                    raise AssertionError(f"{section_name} metadata remained mapped after collapse")
                focused = window.get_focus()
                if focused is not None and not focused.get_visible():
                    raise AssertionError(
                        f"Collapsing {section_name} left keyboard focus in hidden content"
                    )
                if focused is not None and focused is not expander:
                    raise AssertionError(
                        f"Collapsing {section_name} unexpectedly moved focus to another control"
                    )
                expander.set_expanded(True)
                drain_main_context()
                if not scroller.get_mapped():
                    raise AssertionError(f"Reopening {section_name} did not map its metadata")
                expander.grab_focus()
                if window.get_focus() is not expander:
                    raise AssertionError(f"Reopened {section_name} disclosure lost keyboard focus")

        # Exercise the real production crossfade briefly. Keyboard focus
        # must leave the outgoing inspector immediately, even while GTK keeps
        # that page mapped for the animation.
        window.stack.set_transition_duration(250)
        permissions_expander.grab_focus()
        if window.get_focus() is not permissions_expander:
            raise AssertionError("Could not focus the inspector before crossfade navigation")
        window._show_view("packages")
        focused_during_transition = window.get_focus()
        inspector = window.stack.get_child_by_name("package-detail")
        while focused_during_transition is not None:
            if focused_during_transition is inspector:
                raise AssertionError("Crossfade navigation left keyboard focus in the outgoing inspector")
            focused_during_transition = focused_during_transition.get_parent()
        if window.stack.get_visible_child_name() != "packages":
            raise AssertionError("Crossfade navigation did not select the applications page")
        # Finish the transition before returning to deterministic mapping tests.
        transition_loop = GLib.MainLoop()
        GLib.timeout_add(350, lambda: (transition_loop.quit(), GLib.SOURCE_REMOVE)[1])
        transition_loop.run()
        drain_main_context()
        window.stack.set_transition_duration(0)
        window._show_view("package-detail")
        drain_main_context()
        if window.stack.get_visible_child_name() != "package-detail":
            raise AssertionError("Returning from crossfade navigation failed")

        # Keyboard shortcuts must remain deterministic when several
        # navigation requests arrive during an active crossfade.
        window.stack.set_transition_duration(250)
        permissions_expander.grab_focus()
        if not window._on_key_pressed(
            None, Gdk.KEY_1, 0, Gdk.ModifierType.CONTROL_MASK
        ):
            raise AssertionError("Ctrl+1 was not handled during navigation")
        if window.stack.get_visible_child_name() != "dashboard":
            raise AssertionError("Ctrl+1 did not select the dashboard during crossfade")

        original_run_async = window._run_async
        original_show_device = window._show_device
        captured_requests = []
        device_updates = []
        window._run_async = lambda action, callback: captured_requests.append(
            (action, callback)
        )
        window._show_device = lambda *args: device_updates.append(args)
        try:
            if not window._on_key_pressed(
                None, Gdk.KEY_2, 0, Gdk.ModifierType.CONTROL_MASK
            ):
                raise AssertionError("Ctrl+2 was not handled during crossfade")
            if window.stack.get_visible_child_name() != "packages":
                raise AssertionError("Ctrl+2 did not select the applications page")
            if not captured_requests or captured_requests[-1][0] != "device-info":
                raise AssertionError("Ctrl+2 did not schedule the read-only inventory preflight")

            # A later shortcut must invalidate the earlier inventory callback.
            if not window._on_key_pressed(
                None, Gdk.KEY_1, 0, Gdk.ModifierType.CONTROL_MASK
            ):
                raise AssertionError("A second Ctrl+1 was not handled during crossfade")
            stale_callback = captured_requests[-1][1]
            stale_callback({"status": "connected"}, None)
            if device_updates:
                raise AssertionError("A stale shortcut callback updated device state after navigation")
            if window.stack.get_visible_child_name() != "dashboard":
                raise AssertionError("The latest shortcut did not win during crossfade")

            if window._on_key_pressed(None, Gdk.KEY_Escape, 0, Gdk.ModifierType(0)):
                raise AssertionError("Escape should not navigate away from the dashboard")
            if window.stack.get_visible_child_name() != "dashboard":
                raise AssertionError("Escape changed the dashboard while no inspector was open")

            # Navigation shortcuts require an exact modifier combination.
            # Extra Shift/Alt modifiers must not accidentally trigger a page
            # change, and modified Escape must not close the inspector.
            invalid_shortcuts = (
                (Gdk.KEY_1, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK),
                (Gdk.KEY_2, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK),
                (Gdk.KEY_1, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK),
                (Gdk.KEY_Escape, Gdk.ModifierType.SHIFT_MASK),
                (Gdk.KEY_Escape, Gdk.ModifierType.ALT_MASK),
                (Gdk.KEY_3, Gdk.ModifierType.CONTROL_MASK),
            )
            for keyval, modifiers in invalid_shortcuts:
                if window._on_key_pressed(None, keyval, 0, modifiers):
                    raise AssertionError(
                        f"Unsupported shortcut was handled: key={keyval}, modifiers={modifiers}"
                    )
                if window.stack.get_visible_child_name() != "dashboard":
                    raise AssertionError("An unsupported shortcut changed the active page")
        finally:
            window._run_async = original_run_async
            window._show_device = original_show_device

        window._show_view("package-detail")
        permissions_expander.grab_focus()
        if not window._on_key_pressed(None, Gdk.KEY_Escape, 0, Gdk.ModifierType(0)):
            raise AssertionError("Escape was not handled during crossfade")
        if window.stack.get_visible_child_name() != "packages":
            raise AssertionError("Escape did not return to applications during crossfade")
        if window.get_focus() is not window.package_list:
            raise AssertionError("Escape during crossfade did not restore package-list focus")

        transition_loop = GLib.MainLoop()
        GLib.timeout_add(350, lambda: (transition_loop.quit(), GLib.SOURCE_REMOVE)[1])
        transition_loop.run()
        drain_main_context()
        window.stack.set_transition_duration(0)
        window._show_view("package-detail")
        drain_main_context()

        # Rapid state changes are queued before the main context is drained.
        # The final requested state must win, and switching pages immediately
        # afterwards must not leave the hidden inspector mapped or lose its state.
        for index in range(20):
            expanded = index % 2 == 0
            permissions_expander.set_expanded(expanded)
            components_expander.set_expanded(expanded)
        drain_main_context()
        if permissions_expander.get_expanded() or components_expander.get_expanded():
            raise AssertionError("Rapid disclosure changes did not preserve the final collapsed state")
        if permission_scroller.get_mapped() or component_scroller.get_mapped():
            raise AssertionError("Rapid collapse left inspector metadata mapped")

        permissions_expander.set_expanded(True)
        components_expander.set_expanded(True)
        drain_main_context()
        if not permission_scroller.get_mapped() or not component_scroller.get_mapped():
            raise AssertionError("Inspector metadata did not map before immediate navigation")
        window._show_view("packages")
        drain_main_context()
        if window.stack.get_visible_child_name() != "packages":
            raise AssertionError("Immediate navigation after disclosure changes failed")
        if permission_scroller.get_mapped() or component_scroller.get_mapped():
            raise AssertionError("Hidden inspector metadata remained mapped after navigation")
        window._show_view("package-detail")
        drain_main_context()
        if not permissions_expander.get_expanded() or not components_expander.get_expanded():
            raise AssertionError("Returning to the inspector lost disclosure state")
        if not permission_scroller.get_mapped() or not component_scroller.get_mapped():
            raise AssertionError("Returning to the inspector did not restore expanded metadata")

        permissions_expander.set_expanded(False)
        components_expander.set_expanded(False)
        drain_main_context()
        if permission_scroller.get_mapped() or component_scroller.get_mapped():
            raise AssertionError("Final inspector cleanup left metadata mapped")

        # GTK4's container focus chain is layout/backend dependent under Xvfb.
        # Verify the actual focus contract directly instead of assuming an exact
        # traversal sequence from child_focus().
        for control in (
            window.package_detail_back_button,
            permissions_expander,
            components_expander,
        ):
            control.grab_focus()
            if window.get_focus() is not control:
                raise AssertionError("An inspector keyboard control cannot receive focus")

        if not window._on_key_pressed(
            None, Gdk.KEY_Escape, 0, Gdk.ModifierType(0)
        ):
            raise AssertionError("Escape did not handle inspector navigation")
        if window.stack.get_visible_child_name() != "packages":
            raise AssertionError("Escape did not return to the applications page")
        if window.get_focus() is not window.package_list:
            raise AssertionError("Escape did not restore keyboard focus to the package list")

        # If a newer request is queued while an older worker is running,
        # the older result must be discarded and only the latest request started.
        original_start_async = window._start_async
        started_requests = []
        stale_result_callbacks = []
        latest_callback = lambda *_: None
        window._closing = False
        window._loading = True
        window._pending_request = ("latest-device-info", latest_callback)
        window._start_async = lambda command, callback: started_requests.append(
            (command, callback)
        )
        try:
            finish_result = window._finish_async(
                lambda *args: stale_result_callbacks.append(args),
                {"status": "connected", "serial": "stale-result"},
                None,
            )
            if finish_result != GLib.SOURCE_REMOVE:
                raise AssertionError("Superseded async result was not removed from the GLib queue")
            if stale_result_callbacks:
                raise AssertionError("A superseded async result invoked its stale callback")
            if started_requests != [("latest-device-info", latest_callback)]:
                raise AssertionError("The latest queued async request was not started exactly once")
            if window._pending_request is not None or window._loading:
                raise AssertionError("Superseded request handling left stale loading state")
        finally:
            window._start_async = original_start_async

        # Multiple requests arriving during one active operation follow
        # latest-wins semantics: intermediate pending callbacks are discarded.
        queued_starts = []
        superseded_callbacks = []
        first_pending_callback = lambda *args: superseded_callbacks.append(("first", args))
        middle_pending_callback = lambda *args: superseded_callbacks.append(("middle", args))
        newest_pending_callback = lambda *args: superseded_callbacks.append(("newest", args))
        window._loading = True
        window._pending_request = None
        window._start_async = lambda command, callback: queued_starts.append((command, callback))
        try:
            window._run_async("first-pending", first_pending_callback)
            window._run_async("middle-pending", middle_pending_callback)
            window._run_async("newest-pending", newest_pending_callback)
            if window._pending_request != ("newest-pending", newest_pending_callback):
                raise AssertionError("A newer request did not replace the older pending request")
            if window.status_label.get_text() != "Waiting to load newest-pending…":
                raise AssertionError("The waiting status did not reflect the newest request")

            finish_result = window._finish_async(
                lambda *args: superseded_callbacks.append(("active", args)),
                {"status": "connected", "serial": "superseded-active-result"},
                None,
            )
            if finish_result != GLib.SOURCE_REMOVE:
                raise AssertionError("The superseded active result was not removed")
            if superseded_callbacks:
                raise AssertionError("An obsolete active or pending callback was invoked")
            if queued_starts != [("newest-pending", newest_pending_callback)]:
                raise AssertionError("The newest pending request was not started exactly once")
            if window._pending_request is not None or window._loading:
                raise AssertionError("Latest-wins request handoff left stale async state")
        finally:
            window._start_async = original_start_async

        # A failing active request must not block the newest pending request.
        error_handoff_starts = []
        active_error_callbacks = []
        pending_after_error = lambda *args: None
        window._closing = False
        window._loading = True
        window._pending_request = ("latest-after-error", pending_after_error)
        window._start_async = lambda command, callback: error_handoff_starts.append(
            (command, callback)
        )
        try:
            finish_result = window._finish_async(
                lambda payload, error: active_error_callbacks.append((payload, error)),
                None,
                "simulated bridge failure",
            )
            if finish_result != GLib.SOURCE_REMOVE:
                raise AssertionError("A failed active request was not removed from the GLib queue")
            if active_error_callbacks:
                raise AssertionError("A superseded failing request invoked its obsolete callback")
            if error_handoff_starts != [
                ("latest-after-error", pending_after_error)
            ]:
                raise AssertionError("The newest request did not start after active failure")
            if window._pending_request is not None or window._loading:
                raise AssertionError("Error handoff left stale async state")
        finally:
            window._start_async = original_start_async

        # If the newest request also fails after being handed off, its
        # own callback must run and the complete UI state must be restored.
        chained_error_starts = []
        chained_active_callbacks = []
        chained_latest_callbacks = []
        chained_latest_callback = lambda payload, error: chained_latest_callbacks.append(
            (payload, error)
        )
        window._closing = False
        window._loading = True
        window._pending_request = ("latest-then-fails", chained_latest_callback)
        window._start_async = lambda command, callback: chained_error_starts.append(
            (command, callback)
        )
        try:
            first_finish = window._finish_async(
                lambda *args: chained_active_callbacks.append(args),
                {"status": "obsolete"},
                None,
            )
            if first_finish != GLib.SOURCE_REMOVE:
                raise AssertionError("The superseded successful result was not removed")
            if chained_active_callbacks:
                raise AssertionError("The superseded callback ran before the latest request")
            if chained_error_starts != [
                ("latest-then-fails", chained_latest_callback)
            ]:
                raise AssertionError("The latest request was not handed off exactly once")

            window._loading = True
            window._pending_request = None
            window.refresh_button.set_sensitive(False)
            window.loading_spinner.start()
            window.status_label.set_text("Loading latest-then-fails…")
            second_finish = window._finish_async(
                chained_latest_callback,
                None,
                "simulated latest bridge failure",
            )
            if second_finish != GLib.SOURCE_REMOVE:
                raise AssertionError("The latest failed result was not removed")
            if chained_latest_callbacks != [
                (None, "simulated latest bridge failure")
            ]:
                raise AssertionError("The latest request failure was not delivered exactly once")
            if window._loading or window._pending_request is not None:
                raise AssertionError("Chained request failure left stale async state")
            if window.loading_spinner.get_spinning():
                raise AssertionError("Chained request failure left the spinner running")
            if not window.refresh_button.get_sensitive():
                raise AssertionError("Chained request failure left refresh disabled")
        finally:
            window._start_async = original_start_async

        # Thread startup can fail before any worker runs. The UI must be
        # restored synchronously and the callback must receive a bounded error.
        import main as gui_main

        original_thread = gui_main.threading.Thread
        startup_callbacks = []

        class FailingThread:
            def __init__(self, *args, **kwargs):
                pass

            def start(self):
                raise RuntimeError("simulated thread startup failure")

        gui_main.threading.Thread = FailingThread
        try:
            window._loading = False
            window.refresh_button.set_sensitive(True)
            window._start_async(
                "device-info",
                lambda payload, error: startup_callbacks.append((payload, error)),
            )
            if window._loading:
                raise AssertionError("Thread startup failure left the UI in loading state")
            if window.loading_spinner.get_spinning():
                raise AssertionError("Thread startup failure left the spinner running")
            if not window.refresh_button.get_sensitive():
                raise AssertionError("Thread startup failure left refresh disabled")
            if window.status_label.get_text() != "Unable to start bridge request":
                raise AssertionError("Thread startup failure did not publish its status")
            if len(startup_callbacks) != 1 or startup_callbacks[0][0] is not None:
                raise AssertionError("Thread startup failure did not invoke the callback exactly once")
            if not startup_callbacks[0][1] or "simulated thread startup failure" not in startup_callbacks[0][1]:
                raise AssertionError("Thread startup failure did not provide the expected bounded error")
        finally:
            gui_main.threading.Thread = original_thread

        # A page callback may itself fail after the worker has completed.
        # Keep the exception out of GLib's idle dispatcher and restore a clear
        # UI state rather than leaving a stale loading indicator.
        callback_failures = []

        def failing_page_callback(payload, error):
            callback_failures.append((payload, error))
            raise RuntimeError("simulated page callback failure")

        window._loading = True
        window._pending_request = None
        window.refresh_button.set_sensitive(False)
        window.loading_spinner.start()
        window.status_label.set_text("Loading device-info…")
        finish_result = window._finish_async(
            failing_page_callback,
            {"status": "connected"},
            None,
        )
        if finish_result != GLib.SOURCE_REMOVE:
            raise AssertionError("A completed async callback was not removed from the GLib queue")
        if len(callback_failures) != 1:
            raise AssertionError("A failing page callback was not invoked exactly once")
        if window._loading or window.loading_spinner.get_spinning():
            raise AssertionError("A failing page callback left async loading active")
        if not window.refresh_button.get_sensitive():
            raise AssertionError("A failing page callback left refresh disabled")
        if window.status_label.get_text() != "Unable to update interface":
            raise AssertionError("A failing page callback left a stale loading status")

        # Repeated callback failures must not poison later requests.
        repeated_failures = []

        def another_failing_callback(payload, error):
            repeated_failures.append((payload, error))
            raise RuntimeError("second simulated page callback failure")

        for callback, payload in (
            (failing_page_callback, {"status": "first"}),
            (another_failing_callback, {"status": "second"}),
        ):
            window._loading = True
            window._pending_request = None
            window.refresh_button.set_sensitive(False)
            window.loading_spinner.start()
            finish_result = window._finish_async(callback, payload, None)
            if finish_result != GLib.SOURCE_REMOVE:
                raise AssertionError("A failing callback was not removed from the GLib queue")
            if window._loading or window.loading_spinner.get_spinning():
                raise AssertionError("Repeated callback failure left async loading active")
            if not window.refresh_button.get_sensitive():
                raise AssertionError("Repeated callback failure left refresh disabled")

        successful_callbacks = []
        window._loading = True
        window._pending_request = None
        window.refresh_button.set_sensitive(False)
        window.loading_spinner.start()
        window.status_label.set_text("Loading device-info…")
        finish_result = window._finish_async(
            lambda payload, error: successful_callbacks.append((payload, error)),
            {"status": "recovered"},
            None,
        )
        if finish_result != GLib.SOURCE_REMOVE:
            raise AssertionError("Recovery callback was not removed from the GLib queue")
        if successful_callbacks != [({"status": "recovered"}, None)]:
            raise AssertionError("A successful callback did not run after earlier failures")
        if window._loading or window.loading_spinner.get_spinning():
            raise AssertionError("Recovery callback left async loading active")
        if not window.refresh_button.get_sensitive():
            raise AssertionError("Recovery callback left refresh disabled")

        # Once shutdown starts, keyboard events must be inert: no page
        # navigation and, in particular, no new inventory preflight.
        window._show_view("package-detail")
        drain_main_context()
        closing_view = window.stack.get_visible_child_name()
        closing_navigation = []
        closing_async = []
        original_show_view = window._show_view
        original_run_async = window._run_async
        window._show_view = lambda name: closing_navigation.append(name)
        window._run_async = lambda action, callback: closing_async.append(action)
        window._closing = True
        try:
            for keyval, modifiers in (
                (Gdk.KEY_1, Gdk.ModifierType.CONTROL_MASK),
                (Gdk.KEY_2, Gdk.ModifierType.CONTROL_MASK),
                (Gdk.KEY_Escape, Gdk.ModifierType(0)),
            ):
                if window._on_key_pressed(None, keyval, 0, modifiers):
                    raise AssertionError("A keyboard shortcut was handled while closing")
            if closing_navigation or closing_async:
                raise AssertionError("Keyboard input triggered work while the window was closing")
            if window.stack.get_visible_child_name() != closing_view:
                raise AssertionError("Keyboard input changed the page while the window was closing")
        finally:
            window._show_view = original_show_view
            window._run_async = original_run_async

        # Closing with a pending request must discard it and prevent any
        # later async completion or new action from starting more work.
        close_pending_starts = []
        close_pending_callbacks = []
        close_pending_callback = lambda *args: close_pending_callbacks.append(args)
        original_start_for_close = window._start_async
        window._closing = False
        window._loading = True
        window._pending_request = ("must-not-start-after-close", close_pending_callback)
        window._start_async = lambda command, callback: close_pending_starts.append(
            (command, callback)
        )
        try:
            window._on_close_request(window)
            if not window._closing:
                raise AssertionError("Close request did not set the shutdown guard")
            if window._pending_request is not None:
                raise AssertionError("Close request did not discard the pending request")

            finish_result = window._finish_async(
                lambda *args: close_pending_callbacks.append(args),
                {"status": "connected", "serial": "completed-during-close"},
                None,
            )
            if finish_result != GLib.SOURCE_REMOVE:
                raise AssertionError("A completion during shutdown was not removed")
            window._run_async("new-action-after-close", close_pending_callback)
            if close_pending_starts:
                raise AssertionError("A pending or new request started after close")
            if close_pending_callbacks:
                raise AssertionError("A callback ran after the window began closing")
            if window._loading or window._pending_request is not None:
                raise AssertionError("Close with pending work left stale async state")
        finally:
            window._start_async = original_start_for_close
            window._closing = False
            window._shutdown_event.clear()

        # Exercise the real close-request path, then deliver late key events
        # through the retained handler. The closing guard must return before
        # touching the stack or any other GTK widget.
        window._closing = False
        window.close()
        drain_main_context()
        if not window._closing:
            raise AssertionError("The close-request handler did not enter shutdown state")

        # A worker may finish after close-request and enqueue its idle callback.
        # _finish_async must discard that result without touching GTK widgets
        # or invoking the page-specific callback.
        late_callback_calls = []
        window._loading = True
        window._pending_request = ("device-info", lambda *_: None)
        finish_result = window._finish_async(
            lambda *args: late_callback_calls.append(args),
            {"status": "connected", "serial": "late-result"},
            None,
        )
        if finish_result != GLib.SOURCE_REMOVE:
            raise AssertionError("A late async result was not removed from the GLib queue")
        if window._loading or window._pending_request is not None:
            raise AssertionError("Shutdown did not clear async loading and pending state")
        if late_callback_calls:
            raise AssertionError("A late async result invoked its UI callback after close")

        for keyval, modifiers in (
            (Gdk.KEY_1, Gdk.ModifierType.CONTROL_MASK),
            (Gdk.KEY_2, Gdk.ModifierType.CONTROL_MASK),
            (Gdk.KEY_Escape, Gdk.ModifierType(0)),
        ):
            if window._on_key_pressed(None, keyval, 0, modifiers):
                raise AssertionError("A late keyboard event was handled after close")
        print("PASS: GTK4 window construction, package filtering and navigation")
        return 0
    finally:
        UraamWindow._refresh_device = original_refresh


if __name__ == "__main__":
    raise SystemExit(main())
