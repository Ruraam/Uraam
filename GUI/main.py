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
        self._packages: list[str] = []
        self._package_types: dict[str, str] = {}

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

        brand = Gtk.Label(label="URAAM", xalign=0)
        brand.add_css_class("uraam-brand")
        sidebar.append(brand)
        subtitle = Gtk.Label(label="ANDROID CONTROL CENTER", xalign=0)
        subtitle.add_css_class("uraam-subtitle")
        sidebar.append(subtitle)
        sidebar.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        dashboard_button = Gtk.Button(label="◈  Dashboard")
        dashboard_button.add_css_class("uraam-nav-button")
        dashboard_button.connect("clicked", lambda _button: self.stack.set_visible_child_name("dashboard"))
        sidebar.append(dashboard_button)
        packages_button = Gtk.Button(label="▦  Applications")
        packages_button.add_css_class("uraam-nav-button")
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

    @staticmethod
    def _make_card(title: str, value: str, detail: str) -> Gtk.Frame:
        card = Gtk.Frame()
        card.add_css_class("uraam-card")
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        content.set_margin_top(16)
        content.set_margin_bottom(16)
        content.set_margin_start(18)
        content.set_margin_end(18)
        heading = Gtk.Label(label=title.upper(), xalign=0)
        heading.add_css_class("uraam-card-heading")
        content.append(heading)
        value_label = Gtk.Label(label=value, xalign=0)
        value_label.add_css_class("uraam-card-value")
        value_label.set_wrap(True)
        value_label.set_selectable(True)
        content.append(value_label)
        detail_label = Gtk.Label(label=detail, xalign=0)
        detail_label.add_css_class("dim-label")
        detail_label.set_wrap(True)
        content.append(detail_label)
        card.set_child(content)
        return card

    def _replace_card(self, card: Gtk.Frame, title: str, value: str, detail: str) -> None:
        content = card.get_child()
        if not isinstance(content, Gtk.Box):
            return
        heading = content.get_first_child()
        value_label = heading.get_next_sibling() if heading else None
        detail_label = value_label.get_next_sibling() if value_label else None
        if isinstance(heading, Gtk.Label):
            heading.set_text(title.upper())
        if isinstance(value_label, Gtk.Label):
            value_label.set_text(value)
        if isinstance(detail_label, Gtk.Label):
            detail_label.set_text(detail)

    def _build_dashboard(self) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        page.set_margin_top(28)
        page.set_margin_bottom(28)
        page.set_margin_start(30)
        page.set_margin_end(30)
        eyebrow = Gtk.Label(label="DEVICE MANAGEMENT / OVERVIEW", xalign=0)
        eyebrow.add_css_class("uraam-eyebrow")
        page.append(eyebrow)
        title = Gtk.Label(label="Command center", xalign=0)
        title.add_css_class("title-1")
        page.append(title)
        intro = Gtk.Label(label="Android device, connection and application inventory at a glance.", xalign=0)
        intro.add_css_class("dim-label")
        page.append(intro)

        grid = Gtk.Grid()
        grid.set_column_spacing(14)
        grid.set_row_spacing(14)
        grid.set_column_homogeneous(True)
        self.device_card = self._make_card("Device", "Waiting for device", "Android device identity")
        self.backend_card = self._make_card("Connection", "Not detected", "ADB · Root · Shizuku")
        self.rom_card = self._make_card("System", "—", "ROM and Android version")
        self.version_card = self._make_card("URAAM engine", "5.1.0", "Bash engine · GTK4 frontend")
        grid.attach(self.device_card, 0, 0, 1, 1)
        grid.attach(self.backend_card, 1, 0, 1, 1)
        grid.attach(self.rom_card, 0, 1, 1, 1)
        grid.attach(self.version_card, 1, 1, 1, 1)
        page.append(grid)

        inventory = Gtk.Frame()
        inventory.add_css_class("uraam-wide-card")
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        inner.set_margin_top(16)
        inner.set_margin_bottom(16)
        inner.set_margin_start(18)
        inner.set_margin_end(18)
        heading = Gtk.Label(label="APPLICATION INVENTORY", xalign=0)
        heading.add_css_class("uraam-card-heading")
        inner.append(heading)
        self.inventory_label = Gtk.Label(
            label="Connect an Android device to inspect installed applications.", xalign=0
        )
        self.inventory_label.set_wrap(True)
        inner.append(self.inventory_label)
        inventory.set_child(inner)
        page.append(inventory)

        note = Gtk.Label(
            label="Read-only desktop milestone. Debloating, APK installation and restoration remain protected by the existing Bash workflows.",
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
        page.set_margin_start(30)
        page.set_margin_end(30)
        eyebrow = Gtk.Label(label="DEVICE MANAGEMENT / APPLICATIONS", xalign=0)
        eyebrow.add_css_class("uraam-eyebrow")
        page.append(eyebrow)
        title = Gtk.Label(label="Installed applications", xalign=0)
        title.add_css_class("title-1")
        page.append(title)
        self.package_summary = Gtk.Label(label="Open this page to load the Android user-0 inventory.", xalign=0)
        self.package_summary.add_css_class("dim-label")
        page.append(self.package_summary)
        self.package_search = Gtk.SearchEntry()
        self.package_search.set_placeholder_text("Search package name…")
        self.package_search.connect("search-changed", self._filter_packages)
        page.append(self.package_search)
        self.package_filter = Gtk.DropDown.new_from_strings(
            ["All packages", "System apps", "User apps", "Unclassified"]
        )
        self.package_filter.set_selected(0)
        self.package_filter.connect("notify::selected", self._filter_packages)
        page.append(self.package_filter)
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
            self._replace_card(self.device_card, "Device", "Bridge unavailable", error)
            self._replace_card(self.backend_card, "Connection", "Unavailable", "Check ADB / Root / Shizuku")
            self._replace_card(self.rom_card, "System", "—", "No system information")
            return
        if payload.get("status") != "connected":
            self.status_label.set_text("No Android device connected")
            self._replace_card(self.device_card, "Device", "No device connected", "Connect via ADB, Root or Shizuku")
            self._replace_card(self.backend_card, "Connection", "Not detected", "ADB · Root · Shizuku")
            self._replace_card(self.rom_card, "System", "—", "Waiting for device information")
            return
        self.status_label.set_text("Android device connected")
        self._replace_card(
            self.device_card, "Device", payload.get("model") or "Unknown device",
            f"OEM: {payload.get('oem') or 'unknown'}"
        )
        self._replace_card(
            self.backend_card, "Connection", str(payload.get("backend", "unknown")).upper(),
            f"Serial: {payload.get('serial') or 'local'}"
        )
        rom = payload.get("rom") or {}
        self._replace_card(
            self.rom_card, "System", rom.get("name", "Unknown"),
            f"Version: {rom.get('version', 'unknown')}"
        )
        self._replace_card(
            self.version_card, "URAAM engine", payload.get("version", "5.1.0"),
            "Bash engine · GTK4 frontend"
        )

    def _on_refresh(self, _button: Gtk.Button) -> None:
        self._refresh_device()

    def _on_packages(self, _button: Gtk.Button) -> None:
        self.stack.set_visible_child_name("packages")
        self._run_async("list-packages", self._show_packages)

    def _show_packages(self, payload: Any, error: str | None) -> None:
        if error:
            self.status_label.set_text("Package inventory unavailable")
            self.package_summary.set_text(f"Inventory unavailable: {error}")
            self.inventory_label.set_text("The installed-package inventory could not be loaded.")
            self._packages = []
            self._package_types = {}
            while child := self.package_list.get_first_child():
                self.package_list.remove(child)
            return
        self._packages = sorted(set(payload.get("packages", [])), key=str.casefold)
        raw_types = payload.get("package_types", {})
        self._package_types = {
            name: raw_types.get(name, "unknown")
            for name in self._packages
        } if isinstance(raw_types, dict) else {name: "unknown" for name in self._packages}
        self.package_filter.set_selected(0)
        classification = (
            f"{payload.get('system_count', 0)} system · "
            f"{payload.get('user_count', 0)} user · "
            f"{payload.get('unclassified_count', len(self._packages))} unclassified"
        )
        self.package_summary.set_text(
            f"{len(self._packages)} installed package(s) · {classification} · Android user {payload.get('user', 0)} · read-only"
        )
        self.inventory_label.set_text(
            f"{len(self._packages)} package(s) detected on the connected Android device."
        )
        self._filter_packages()

    def _filter_packages(self, _entry: Gtk.SearchEntry | None = None) -> None:
        query = self.package_search.get_text().strip().casefold()
        while child := self.package_list.get_first_child():
            self.package_list.remove(child)
        selected = self.package_filter.get_selected()
        wanted = {1: "system", 2: "user", 3: "unknown"}.get(selected)
        visible = [
            name for name in self._packages
            if query in name.casefold()
            and (wanted is None or self._package_types.get(name, "unknown") == wanted)
        ]
        for package in visible:
            row = Gtk.ListBoxRow()
            row.add_css_class("uraam-package-row")
            line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            line.set_margin_top(10)
            line.set_margin_bottom(10)
            line.set_margin_start(14)
            line.set_margin_end(14)
            label = Gtk.Label(label=package, xalign=0)
            label.set_selectable(True)
            label.set_hexpand(True)
            line.append(label)
            kind = self._package_types.get(package, "unknown")
            kind_label = Gtk.Label(label=kind.upper())
            kind_label.add_css_class("dim-label")
            line.append(kind_label)
            row.set_child(line)
            self.package_list.append(row)
        filter_name = ["all", "system", "user", "unclassified"][selected]
        self.package_summary.set_text(
            f"{len(visible)} / {len(self._packages)} package(s) · {filter_name} · read-only"
        )


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
