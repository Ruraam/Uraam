#!/usr/bin/env python3
"""Optional GTK4 frontend for URAAM's read-only JSON bridge.

The Bash engine remains authoritative. This first GUI milestone only displays
device information and the installed Android user-0 package inventory.
"""
from __future__ import annotations

import json
import subprocess
import threading
from pathlib import Path
from typing import Any

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402


ROOT_DIR = Path(__file__).resolve().parent.parent
API_PATH = ROOT_DIR / "uraam-api.sh"


class UraamWindow(Gtk.ApplicationWindow):
    def __init__(self, application: Gtk.Application) -> None:
        super().__init__(application=application, title="URAAM Desktop")
        self.add_css_class("uraam-window")
        self._load_theme()
        self.set_default_size(1000, 680)
        self.set_size_request(760, 520)
        self._loading = False

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(outer)

        header = Gtk.HeaderBar()
        header.set_title_widget(Gtk.Label(label="URAAM Desktop"))
        refresh_button = Gtk.Button(label="Refresh")
        refresh_button.set_tooltip_text("Refresh device information")
        refresh_button.connect("clicked", self._on_refresh)
        header.pack_end(refresh_button)
        outer.append(header)

        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        outer.append(body)

        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        sidebar.add_css_class("uraam-sidebar")
        sidebar.set_size_request(190, -1)
        sidebar.set_margin_top(16)
        sidebar.set_margin_bottom(16)
        sidebar.set_margin_start(12)
        sidebar.set_margin_end(12)
        body.append(sidebar)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.set_hexpand(True)
        self.stack.set_vexpand(True)
        body.append(self.stack)

        dashboard_button = Gtk.Button(label="Dashboard")
        dashboard_button.connect("clicked", lambda _button: self.stack.set_visible_child_name("dashboard"))
        sidebar.append(dashboard_button)
        packages_button = Gtk.Button(label="Packages")
        packages_button.connect("clicked", self._on_packages)
        sidebar.append(packages_button)

        self.status_label = Gtk.Label(label="Checking device connection…", xalign=0)
        self.status_label.set_wrap(True)
        self.status_label.add_css_class("dim-label")
        sidebar.append(self.status_label)

        self._build_dashboard()
        self._build_packages()
        self.stack.set_visible_child_name("dashboard")
        self._refresh_device()

    def _load_theme(self) -> None:
        """Load the BubbleOS-derived GTK stylesheet when it is available."""
        theme_path = Path(__file__).resolve().parent / "theme.css"
        if not theme_path.is_file():
            return
        display = Gdk.Display.get_default()
        if display is None:
            return
        provider = Gtk.CssProvider()
        try:
            provider.load_from_path(str(theme_path))
        except GLib.Error as exc:
            print(f"URAAM: unable to load GUI theme: {exc}", flush=True)
            return
        Gtk.StyleContext.add_provider_for_display(
            display,
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )
        self._theme_provider = provider

    def _build_dashboard(self) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_margin_top(28)
        page.set_margin_bottom(28)
        page.set_margin_start(28)
        page.set_margin_end(28)

        title = Gtk.Label(label="Device overview", xalign=0)
        title.add_css_class("title-1")
        page.append(title)

        self.device_label = Gtk.Label(label="No device information yet", xalign=0)
        self.device_label.set_selectable(True)
        page.append(self.device_label)

        self.backend_label = Gtk.Label(label="Backend: —", xalign=0)
        page.append(self.backend_label)

        self.rom_label = Gtk.Label(label="ROM: —", xalign=0)
        page.append(self.rom_label)

        note = Gtk.Label(
            label=(
                "This initial desktop build is read-only. Package changes, "
                "debloat, APK installation and restoration remain in the "
                "existing Bash interface until their GUI workflows receive "
                "dedicated safety review and tests."
            ),
            xalign=0,
        )
        note.set_wrap(True)
        note.add_css_class("dim-label")
        page.append(note)
        self.stack.add_named(page, "dashboard")

    def _build_packages(self) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        page.set_margin_top(28)
        page.set_margin_bottom(28)
        page.set_margin_start(28)
        page.set_margin_end(28)

        title = Gtk.Label(label="Installed packages · Android user 0", xalign=0)
        title.add_css_class("title-1")
        page.append(title)

        self.package_summary = Gtk.Label(label="Open this page to load the package inventory.", xalign=0)
        self.package_summary.add_css_class("dim-label")
        page.append(self.package_summary)

        scroller = Gtk.ScrolledWindow()
        scroller.set_vexpand(True)
        scroller.set_hexpand(True)
        self.package_list = Gtk.ListBox()
        self.package_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self.package_list.add_css_class("boxed-list")
        scroller.set_child(self.package_list)
        page.append(scroller)
        self.stack.add_named(page, "packages")

    def _api_call(self, command: str) -> dict[str, Any]:
        if not API_PATH.is_file():
            raise RuntimeError(f"URAAM JSON bridge not found: {API_PATH}")
        result = subprocess.run(
            ["bash", str(API_PATH), command],
            cwd=str(ROOT_DIR),
            capture_output=True,
            text=True,
            timeout=45,
            check=False,
        )
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            detail = result.stderr.strip() or "The bridge returned invalid JSON."
            raise RuntimeError(detail) from exc
        if result.returncode != 0 or payload.get("status") == "error":
            raise RuntimeError(payload.get("error", "URAAM request failed."))
        return payload

    def _run_async(self, command: str, callback: Any) -> None:
        if self._loading:
            return
        self._loading = True
        self.status_label.set_text(f"Loading {command}…")

        def worker() -> None:
            try:
                payload = self._api_call(command)
                error = None
            except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
                payload = None
                error = str(exc)
            GLib.idle_add(self._finish_async, callback, payload, error)

        threading.Thread(target=worker, daemon=True).start()

    def _finish_async(self, callback: Any, payload: Any, error: str | None) -> bool:
        self._loading = False
        callback(payload, error)
        return GLib.SOURCE_REMOVE

    def _refresh_device(self) -> None:
        self._run_async("device-info", self._show_device)

    def _show_device(self, payload: Any, error: str | None) -> None:
        if error:
            self.status_label.set_text("Bridge unavailable")
            self.device_label.set_text(error)
            self.backend_label.set_text("Backend: unavailable")
            self.rom_label.set_text("ROM: —")
            return
        if payload.get("status") != "connected":
            self.status_label.set_text("No Android device connected")
            self.device_label.set_text("Connect a device using ADB, Root or Shizuku.")
            self.backend_label.set_text("Backend: —")
            self.rom_label.set_text("ROM: —")
            return

        self.status_label.set_text("Android device connected")
        self.device_label.set_text(payload.get("model") or "Unknown device")
        self.backend_label.set_text(
            f"Backend: {payload.get('backend', 'unknown')} · Serial: {payload.get('serial') or 'local'}"
        )
        rom = payload.get("rom") or {}
        self.rom_label.set_text(
            f"ROM: {rom.get('name', 'Unknown')} · Android/ROM version: {rom.get('version', 'unknown')}"
        )

    def _on_refresh(self, _button: Gtk.Button) -> None:
        self._refresh_device()

    def _on_packages(self, _button: Gtk.Button) -> None:
        self.stack.set_visible_child_name("packages")
        self._run_async("list-packages", self._show_packages)

    def _show_packages(self, payload: Any, error: str | None) -> None:
        while child := self.package_list.get_first_child():
            self.package_list.remove(child)
        if error:
            self.package_summary.set_text(error)
            return
        packages = payload.get("packages", [])
        self.package_summary.set_text(f"{len(packages)} installed package(s) · read-only inventory")
        for package in packages:
            row = Gtk.ListBoxRow()
            label = Gtk.Label(label=package, xalign=0)
            label.set_selectable(True)
            label.set_margin_top(8)
            label.set_margin_bottom(8)
            label.set_margin_start(12)
            label.set_margin_end(12)
            row.set_child(label)
            self.package_list.append(row)


class UraamApplication(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id="org.ruraam.uraam", flags=0)

    def do_activate(self) -> None:
        window = self.props.active_window
        if window is None:
            window = UraamWindow(self)
        window.present()


def main() -> int:
    application = UraamApplication()
    return application.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
