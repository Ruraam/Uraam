#!/usr/bin/env python3
"""Optional GTK4 frontend for URAAM's read-only JSON bridge.

The Bash engine remains authoritative. This first GUI milestone only displays
device information and the installed Android user-0 package inventory.
"""
from __future__ import annotations

import subprocess
import threading
from pathlib import Path
from typing import Any

from api_protocol import decode_api_response

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
        self._closing = False
        self._pending_request: tuple[str, Any] | None = None
        self._device_identity: tuple[str, str] | None = None
        self._selected_package: str | None = None
        self._packages: list[str] = []
        self._package_types: dict[str, str] = {}
        self._package_classification = "Inventory not loaded"

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

        self.connect("close-request", self._on_close_request)

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
        self.package_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.package_list.set_activate_on_single_click(True)
        self.package_list.connect("row-activated", self._on_package_activated)
        self.package_list.add_css_class("boxed-list")
        self._package_empty_label = Gtk.Label(
            label="No packages to display.", xalign=0.5
        )
        self._package_empty_label.set_wrap(True)
        self._package_empty_label.add_css_class("dim-label")
        self._package_empty_label.set_margin_top(24)
        self._package_empty_label.set_margin_bottom(24)
        self.package_list.set_placeholder(self._package_empty_label)
        scroller.set_child(self.package_list)
        page.append(scroller)
        self.stack.add_named(page, "packages")

        details = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        details.set_margin_top(28)
        details.set_margin_bottom(28)
        details.set_margin_start(30)
        details.set_margin_end(30)
        back = Gtk.Button(label="←  Back to applications")
        back.set_halign(Gtk.Align.START)
        back.connect("clicked", lambda _button: self.stack.set_visible_child_name("packages"))
        details.append(back)
        detail_title = Gtk.Label(label="Application inspector", xalign=0)
        detail_title.add_css_class("title-1")
        details.append(detail_title)
        self.package_detail_name = Gtk.Label(label="Select an application", xalign=0)
        self.package_detail_name.add_css_class("uraam-card-value")
        self.package_detail_name.set_selectable(True)
        details.append(self.package_detail_name)
        self.package_detail_status = Gtk.Label(label="Read-only Android package information", xalign=0)
        self.package_detail_status.add_css_class("dim-label")
        details.append(self.package_detail_status)
        self.package_detail_version = self._make_card("Version", "Not loaded", "Reported by Android Package Manager")
        self.package_detail_path = self._make_card("APK location", "Not loaded", "Installed APK path(s)")
        self.package_detail_permissions = self._make_card(
            "Requested permissions", "Not loaded",
            "Names requested by the package; grant status is not inferred"
        )
        self.package_detail_components = {
            "activities": self._make_card("Activities", "Not loaded", "Declared component entries"),
            "services": self._make_card("Services", "Not loaded", "Declared component entries"),
            "receivers": self._make_card("Receivers", "Not loaded", "Declared component entries"),
            "providers": self._make_card("Providers", "Not loaded", "Declared component entries"),
        }
        details.append(self.package_detail_version)
        details.append(self.package_detail_path)
        details.append(self.package_detail_permissions)
        for component_card in self.package_detail_components.values():
            details.append(component_card)
        safety_note = Gtk.Label(
            label="Information only. System/user classification is not a removal recommendation. No package changes are available in this inspector.",
            xalign=0,
        )
        safety_note.set_wrap(True)
        safety_note.add_css_class("dim-label")
        details.append(safety_note)
        self.stack.add_named(details, "package-detail")

    def _api_call(self, command: str) -> dict[str, Any]:
        if not API_PATH.is_file():
            raise RuntimeError(f"URAAM JSON bridge not found: {API_PATH}")
        result = subprocess.run(
            ["bash", str(API_PATH), command],
            cwd=str(ROOT_DIR),
            capture_output=True,
            text=True,
            errors="replace",
            timeout=45,
            check=False,
        )
        return decode_api_response(result.stdout, result.stderr, result.returncode)

    def _run_async(self, command: str, callback: Any) -> None:
        """Run one bridge request at a time, retaining the latest pending action."""
        if self._loading:
            # Device queries share the same ADB/Root/Shizuku transport. Keep them
            # serialized, but do not silently lose the user's most recent action.
            self._pending_request = (command, callback)
            self.status_label.set_text(f"Waiting to load {command}…")
            return
        self._start_async(command, callback)

    def _start_async(self, command: str, callback: Any) -> None:
        self._loading = True
        self.status_label.set_text(f"Loading {command}…")

        def worker() -> None:
            try:
                payload = self._api_call(command)
                error = None
            except Exception as exc:
                payload = None
                error = str(exc)
            GLib.idle_add(self._finish_async, callback, payload, error)

        threading.Thread(target=worker, daemon=True, name="uraam-api-request").start()

    def _finish_async(self, callback: Any, payload: Any, error: str | None) -> bool:
        if self._closing:
            self._loading = False
            self._pending_request = None
            return GLib.SOURCE_REMOVE

        pending = self._pending_request
        self._pending_request = None
        if pending is not None:
            # A newer action superseded this result. Start it before touching
            # widgets so an older response cannot overwrite the current view.
            self._loading = False
            self._start_async(*pending)
            return GLib.SOURCE_REMOVE

        self._loading = False
        callback(payload, error)
        return GLib.SOURCE_REMOVE

    def _on_close_request(self, _window: Gtk.ApplicationWindow) -> bool:
        """Prevent queued worker completions from touching a closing window."""
        self._closing = True
        self._pending_request = None
        return False

    def _reset_package_views(self, message: str) -> None:
        """Remove device-specific data when the bridge cannot confirm a device."""
        self._selected_package = None
        self._packages = []
        self._package_types = {}
        self._package_classification = message
        while child := self.package_list.get_first_child():
            self.package_list.remove(child)
        self.package_summary.set_text(message)
        self.inventory_label.set_text(message)
        self.package_detail_name.set_text("Select an application")
        self.package_detail_status.set_text(message)
        self._replace_card(self.package_detail_version, "Version", "Not loaded", message)
        self._replace_card(self.package_detail_path, "APK location", "Not loaded", message)
        self._replace_card(
            self.package_detail_permissions, "Requested permissions", "Not loaded", message
        )
        for component_name, component_card in self.package_detail_components.items():
            self._replace_card(component_card, component_name.title(), "Not loaded", message)

    def _refresh_device(self) -> None:
        self._run_async("device-info", self._show_device)

    def _show_device(self, payload: Any, error: str | None) -> None:
        if error:
            self._device_identity = None
            self.status_label.set_text("Bridge unavailable")
            self._replace_card(self.device_card, "Device", "Bridge unavailable", error)
            self._replace_card(self.backend_card, "Connection", "Unavailable", "Check ADB / Root / Shizuku")
            self._replace_card(self.rom_card, "System", "—", "No system information")
            self._replace_card(self.version_card, "URAAM engine", "Unavailable", "Bridge request failed")
            self._reset_package_views("Device information is unavailable; cached package data was cleared.")
            return
        if payload.get("status") != "connected":
            self._device_identity = None
            self.status_label.set_text("No Android device connected")
            self._replace_card(self.device_card, "Device", "No device connected", "Connect via ADB, Root or Shizuku")
            self._replace_card(self.backend_card, "Connection", "Not detected", "ADB · Root · Shizuku")
            self._replace_card(self.rom_card, "System", "—", "Waiting for device information")
            self._replace_card(self.version_card, "URAAM engine", "5.1.0", "Bash engine · GTK4 frontend")
            self._reset_package_views("No connected device; package data is not available.")
            return
        identity = (str(payload.get("backend") or "unknown"), str(payload.get("serial") or "local"))
        if identity != self._device_identity:
            self._reset_package_views("Device identity changed; reload the application inventory.")
            self._device_identity = identity
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
            self._reset_package_views(f"Inventory unavailable: {error}")
            self.inventory_label.set_text("The installed-package inventory could not be loaded.")
            return
        identity = (
            str(payload.get("backend") or "unknown"),
            str(payload.get("serial") or "local"),
        )
        if self._device_identity is not None and identity != self._device_identity:
            self._reset_package_views("Device changed while inventory was loading; refresh before continuing.")
            self.status_label.set_text("Device changed; inventory discarded")
            return
        if self._device_identity is None:
            self._device_identity = identity
        self._selected_package = None
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
        self._package_classification = (
            f"{classification} · Android user {payload.get('user', 0)} · read-only"
        )
        self.inventory_label.set_text(
            f"{len(self._packages)} package(s) detected on the connected Android device."
        )
        self._filter_packages()

    def _on_package_activated(self, _listbox: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        child = row.get_child()
        package_label = child.get_first_child() if isinstance(child, Gtk.Box) else None
        if not isinstance(package_label, Gtk.Label):
            return
        package = package_label.get_text()
        self._selected_package = package
        self.package_detail_name.set_text(package)
        self.package_detail_status.set_text("Querying Android using read-only commands…")
        self._replace_card(self.package_detail_version, "Version", "Loading…", "Reported by Android Package Manager")
        self._replace_card(self.package_detail_path, "APK location", "Loading…", "Installed APK path(s)")
        self._replace_card(
            self.package_detail_permissions, "Requested permissions", "Loading…",
            "Names requested by the package; grant status is not inferred"
        )
        for component_name, component_card in self.package_detail_components.items():
            self._replace_card(
                component_card, component_name.title(), "Loading…",
                "Declared component entries from Android Package Manager"
            )
        self.stack.set_visible_child_name("package-detail")
        self._run_async(
            f"package-info:{package}",
            lambda payload, error, expected=package: self._show_package_info(
                payload, error, expected
            ),
        )

    def _show_package_info(
        self, payload: Any, error: str | None, expected_package: str
    ) -> None:
        # A delayed response must never replace the details for a newer selection.
        if self._selected_package != expected_package:
            return
        if error:
            self.package_detail_status.set_text(f"Details unavailable: {error}")
            self._replace_card(self.package_detail_version, "Version", "Unavailable", "Android did not provide version metadata")
            self._replace_card(self.package_detail_path, "APK location", "Unavailable", "No verified APK path returned")
            self._replace_card(
                self.package_detail_permissions, "Requested permissions", "Unavailable",
                "No permission metadata returned"
            )
            for component_name, component_card in self.package_detail_components.items():
                self._replace_card(
                    component_card, component_name.title(), "Unavailable",
                    "No component metadata returned"
                )
            return
        if payload.get("package") != expected_package:
            self.package_detail_status.set_text(
                "Details discarded: Android returned metadata for a different package."
            )
            self._replace_card(
                self.package_detail_version, "Version", "Unavailable",
                "The bridge response did not match the selected package"
            )
            return
        version_name = payload.get("version_name") or "Not reported"
        version_code = payload.get("version_code") or "Not reported"
        self._replace_card(
            self.package_detail_version, "Version", str(version_name),
            f"Version code: {version_code}"
        )
        paths = payload.get("paths") if isinstance(payload.get("paths"), list) else []
        self._replace_card(
            self.package_detail_path, "APK location",
            f"{len(paths)} path(s) reported",
            "\n".join(str(path) for path in paths) if paths else "Android returned no APK paths"
        )
        requested = payload.get("requested_permissions")
        if isinstance(requested, list):
            permission_names = [str(item) for item in requested if isinstance(item, str)]
            permission_value = f"{len(permission_names)} requested"
            permission_detail = (
                "\n".join(permission_names)
                if permission_names else "No permission names parsed from the requested-permissions block"
            )
        else:
            permission_value = "Not reported"
            permission_detail = "This Android build did not expose a readable requested-permissions block"
        self._replace_card(
            self.package_detail_permissions, "Requested permissions",
            permission_value, permission_detail
        )
        components = payload.get("components")
        if isinstance(components, dict):
            for component_name, component_card in self.package_detail_components.items():
                entries = components.get(component_name)
                if isinstance(entries, list):
                    names = [str(item) for item in entries if isinstance(item, str)]
                    value = f"{len(names)} reported"
                    detail = "\n".join(names) if names else "No entries parsed in this section"
                else:
                    value = "Not reported"
                    detail = "This Android build did not expose this component section"
                self._replace_card(component_card, component_name.title(), value, detail)
        else:
            for component_name, component_card in self.package_detail_components.items():
                self._replace_card(
                    component_card, component_name.title(), "Not reported",
                    "This Android build did not expose component metadata"
                )
        self.package_detail_status.set_text(
            f"Backend: {str(payload.get('backend', 'unknown')).upper()} · Read-only inspection · Requested names only"
        )

    def _filter_packages(
        self, _entry: Gtk.SearchEntry | None = None, _pspec: Any = None
    ) -> None:
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
        filter_names = ["all", "system", "user", "unclassified"]
        filter_name = (
            filter_names[selected] if 0 <= selected < len(filter_names) else "all"
        )
        if visible:
            self._package_empty_label.set_text("")
        elif not self._packages:
            self._package_empty_label.set_text("No inventory loaded. Connect a device and refresh.")
        else:
            self._package_empty_label.set_text(
                "No packages match this search and filter. Try a different query."
            )
        self.package_summary.set_text(
            f"{len(visible)} / {len(self._packages)} package(s) · {filter_name} · "
            f"{self._package_classification}"
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
