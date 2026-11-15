#!/usr/bin/env python3
"""Optional GTK4 frontend for URAAM.

The Bash engine remains authoritative for package operations. The GUI combines
a read-only device/inventory bridge with a bounded wireless connection assistant.
"""
from __future__ import annotations

import ipaddress
import logging
import os
import re
import shutil
import signal
import subprocess
import threading
from pathlib import Path
from typing import Any

from bridge_process import (
    BridgeProcessCancelled,
    BridgeProcessTimeout,
    communicate_process,
    signal_process_group,
)
from api_protocol import (
    _bounded_error_message,
    coalesce_pending_request,
    decode_api_response,
    device_identity,
    device_matches_request,
    inventory_matches_device,
    package_detail_payload_matches,
    package_detail_request_is_current,
    request_is_current,
    take_pending_request,
)

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402


ROOT_DIR = Path(__file__).resolve().parent.parent
API_PATH = ROOT_DIR / "uraam-api.sh"
LOGGER = logging.getLogger(__name__)
SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
SHIZUKU_START_SCRIPT = "/sdcard/Android/data/moe.shizuku.privileged.api/start.sh"


def validate_adb_endpoint(value: str) -> str:
    """Validate an ADB host:port endpoint without accepting shell syntax."""
    endpoint = value.strip()
    if not endpoint or len(endpoint) > 255 or any(c.isspace() for c in endpoint):
        raise ValueError("Enter an IP address or hostname followed by :port.")
    if endpoint.startswith("["):
        match = re.fullmatch(r"\[([0-9A-Fa-f:.]+)\]:(\d{1,5})", endpoint)
        if match is None:
            raise ValueError("IPv6 endpoints must use [address]:port.")
        try:
            ipaddress.IPv6Address(match.group(1))
        except ipaddress.AddressValueError as exc:
            raise ValueError("The IPv6 address is invalid.") from exc
    else:
        match = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9.-]*):(\d{1,5})", endpoint)
        if match is None or ".." in match.group(1) or match.group(1).endswith("."):
            raise ValueError("Enter a valid IP address or hostname followed by :port.")
    if not 1 <= int(match.group(2)) <= 65535:
        raise ValueError("The port must be between 1 and 65535.")
    return endpoint


def parse_adb_devices_output(output: str) -> list[tuple[str, str]]:
    """Parse adb devices output, excluding daemon messages and its header."""
    devices = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[1] in {"device", "offline", "unauthorized"}:
            devices.append((fields[0], fields[1]))
    return devices


class UraamWindow(Gtk.ApplicationWindow):
    def __init__(self, application: Gtk.Application) -> None:
        super().__init__(application=application, title="URAAM Desktop")
        self.add_css_class("uraam-window")
        self._load_theme()
        self.set_default_size(1000, 680)
        self.set_size_request(760, 520)
        self._loading = False
        self._closing = False
        self._process_lock = threading.Lock()
        self._shutdown_event = threading.Event()
        self._active_process: subprocess.Popen[str] | None = None
        self._pending_request: tuple[str, Any] | None = None
        self._device_identity: tuple[str, str] | None = None
        self._device_generation = 0
        self._selected_package: str | None = None
        self._packages: list[str] = []
        self._package_types: dict[str, str] = {}
        self._package_classification = "Inventory not loaded"
        self._package_request_generation = 0
        self._view_generation = 0
        self._inventory_loaded = False
        self._connection_devices: list[tuple[str, str]] = []
        self.connection_mode = "adb"
        self._connection_serial: str | None = None
        self._connection_busy = False

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(outer)

        header = Gtk.HeaderBar()
        header.set_title_widget(Gtk.Label(label="URAAM Desktop"))
        self.refresh_button = Gtk.Button(label="Refresh")
        self.refresh_button.set_tooltip_text("Refresh device information")
        self._set_accessible_label(self.refresh_button, "Refresh device information")
        self._set_accessible_description(
            self.refresh_button,
            "Refreshes read-only device information without changing Android packages.",
        )
        self.refresh_button.connect("clicked", self._on_refresh)
        header.pack_end(self.refresh_button)
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
        self.dashboard_button = dashboard_button
        dashboard_button.add_css_class("uraam-nav-button")
        self._set_accessible_label(dashboard_button, "Open dashboard")
        dashboard_button.set_tooltip_text("Open dashboard · Ctrl+1")
        self._set_accessible_description(
            dashboard_button, "Keyboard shortcut: Ctrl+1. Current page is indicated visually."
        )
        dashboard_button.connect("clicked", lambda _button: self._show_view("dashboard"))
        sidebar.append(dashboard_button)
        packages_button = Gtk.Button(label="▦  Applications")
        self.packages_button = packages_button
        packages_button.add_css_class("uraam-nav-button")
        self._set_accessible_label(packages_button, "Open installed applications")
        packages_button.set_tooltip_text("Open installed applications · Ctrl+2")
        self._set_accessible_description(
            packages_button, "Keyboard shortcut: Ctrl+2. Current page is indicated visually."
        )
        packages_button.connect("clicked", self._on_packages)
        sidebar.append(packages_button)
        self.connections_button = Gtk.Button(label="⌁  Connections")
        self.connections_button.add_css_class("uraam-nav-button")
        self._set_accessible_label(self.connections_button, "Open connection assistant")
        self.connections_button.set_tooltip_text("Open connection assistant · Ctrl+3")
        self.connections_button.connect("clicked", lambda _b: self._show_view("connections"))
        sidebar.append(self.connections_button)

        shortcut_hint = Gtk.Label(
            label="SHORTCUTS\nCtrl+1  Dashboard\nCtrl+2  Applications\nEsc  Back from details",
            xalign=0,
        )
        shortcut_hint.set_wrap(True)
        shortcut_hint.add_css_class("uraam-shortcut-hint")
        sidebar.append(shortcut_hint)

        self.status_label = Gtk.Label(label="Checking device connection…", xalign=0)
        self.status_label.set_wrap(True)
        self.status_label.add_css_class("dim-label")
        sidebar.append(self.status_label)
        self.loading_spinner = Gtk.Spinner()
        self.loading_spinner.set_halign(Gtk.Align.START)
        self.loading_spinner.set_tooltip_text("A read-only bridge request is running")
        self._set_accessible_label(self.loading_spinner, "Read-only request in progress")
        self._set_accessible_description(
            self.loading_spinner,
            "Indicates that a read-only Android bridge request is in progress.",
        )
        sidebar.append(self.loading_spinner)

        self._install_keyboard_controller()

        self.connect("close-request", self._on_close_request)

        self._build_dashboard()
        self._build_packages()
        self._build_connections()
        self._show_view("dashboard")
        self._refresh_device()

    def _install_keyboard_controller(self) -> None:
        """Attach the keyboard controller to the window's GTK-managed lifecycle."""
        controller = Gtk.EventControllerKey()
        controller.connect("key-pressed", self._on_key_pressed)
        self.add_controller(controller)

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

    def _unload_theme(self) -> None:
        """Remove the display-wide CSS provider when this window closes."""
        provider = getattr(self, "_theme_provider", None)
        if provider is None:
            return
        display = Gdk.Display.get_default()
        if display is not None:
            Gtk.StyleContext.remove_provider_for_display(display, provider)
        self._theme_provider = None

    @staticmethod
    def _set_accessible_label(widget: Gtk.Widget, label: str) -> None:
        """Expose a concise accessible name for controls without visible labels."""
        widget.update_property(
            [Gtk.AccessibleProperty.LABEL],
            [label],
        )

    @staticmethod
    def _set_accessible_description(widget: Gtk.Widget, description: str) -> None:
        """Expose shortcut guidance and navigation state to assistive technology."""
        widget.update_property(
            [Gtk.AccessibleProperty.DESCRIPTION],
            [description],
        )

    @staticmethod
    def _make_card(
        title: str,
        value: str,
        detail: str,
        *,
        scrollable_detail: bool = False,
    ) -> Gtk.Frame:
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
        detail_label.set_selectable(True)
        if scrollable_detail:
            detail_scroller = Gtk.ScrolledWindow()
            detail_scroller.add_css_class("uraam-metadata-scroller")
            detail_scroller.set_policy(
                Gtk.PolicyType.NEVER,
                Gtk.PolicyType.AUTOMATIC,
            )
            detail_scroller.set_propagate_natural_height(True)
            detail_scroller.set_max_content_height(240)
            # Make the viewport the single Tab stop for long metadata. The
            # label remains selectable with the pointer, but does not create
            # a second, redundant keyboard stop inside the scrolling region.
            detail_scroller.set_focusable(True)
            UraamWindow._set_accessible_label(
                detail_scroller, f"{title} details"
            )
            detail_label.set_focusable(False)
            detail_scroller.set_child(detail_label)
            content.append(detail_scroller)
        else:
            content.append(detail_label)
        card.set_child(content)
        return card

    def _replace_card(self, card: Gtk.Frame, title: str, value: str, detail: str) -> None:
        content = card.get_child()
        if not isinstance(content, Gtk.Box):
            return
        heading = content.get_first_child()
        value_label = heading.get_next_sibling() if heading else None
        detail_container = value_label.get_next_sibling() if value_label else None
        detail_label = detail_container
        if isinstance(detail_container, Gtk.ScrolledWindow):
            detail_label = detail_container.get_child()
            # GTK may insert a Gtk.Viewport around a non-scrollable child.
            if isinstance(detail_label, Gtk.Viewport):
                detail_label = detail_label.get_child()
        if isinstance(heading, Gtk.Label):
            heading.set_text(title.upper())
        if isinstance(value_label, Gtk.Label):
            value_label.set_text(value)
        if isinstance(detail_label, Gtk.Label):
            detail_label.set_text(detail)

    def _add_scrollable_page(self, page: Gtk.Widget, name: str) -> None:
        """Keep long dashboard and inspector content reachable in short windows."""
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(
            Gtk.PolicyType.AUTOMATIC,
            Gtk.PolicyType.AUTOMATIC,
        )
        scroller.set_hexpand(True)
        scroller.set_vexpand(True)
        scroller.set_child(page)
        self.stack.add_named(scroller, name)

    @staticmethod
    def _make_expander(title: str, child: Gtk.Widget) -> Gtk.Expander:
        """Group verbose package metadata behind an accessible disclosure row."""
        expander = Gtk.Expander.new(title)
        expander.add_css_class("uraam-detail-expander")
        set_focusable = getattr(expander, "set_focusable", None)
        if callable(set_focusable):
            set_focusable(True)
        expander.set_expanded(False)
        expander.set_child(child)
        return expander

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
        self.version_card = self._make_card("URAAM engine", "5.2.0", "Bash engine · GTK4 frontend")
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
            label="Device and package information is read-only. Debloating, APK installation and restoration remain protected by the existing Bash workflows.",
            xalign=0,
        )
        note.set_wrap(True)
        note.add_css_class("dim-label")
        page.append(note)
        self._add_scrollable_page(page, "dashboard")

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
        self._set_accessible_label(self.package_search, "Search installed packages")
        self._set_accessible_description(
            self.package_search,
            "Type a package name to narrow the installed-applications list.",
        )
        self.package_search.connect("search-changed", self._filter_packages)
        page.append(self.package_search)
        self.package_filter = Gtk.DropDown.new_from_strings(
            ["All packages", "System apps", "User apps", "Unclassified"]
        )
        self.package_filter.set_selected(0)
        self._set_accessible_label(self.package_filter, "Filter packages by category")
        self._set_accessible_description(
            self.package_filter,
            "Choose all, system, user, or unclassified packages.",
        )
        self.package_filter.connect("notify::selected", self._filter_packages)
        page.append(self.package_filter)
        self.package_count_label = Gtk.Label(label="No inventory loaded.", xalign=0)
        self.package_count_label.add_css_class("dim-label")
        page.append(self.package_count_label)
        scroller = Gtk.ScrolledWindow()
        scroller.set_vexpand(True)
        scroller.set_hexpand(True)
        self.package_list = Gtk.ListBox()
        self.package_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._set_accessible_label(self.package_list, "Installed Android packages")
        self._set_accessible_description(
            self.package_list,
            "Select an application to inspect its read-only Android metadata.",
        )
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
        self.package_detail_back_button = back
        back.set_halign(Gtk.Align.START)
        self._set_accessible_label(back, "Back to installed applications")
        self._set_accessible_description(
            back,
            "Returns to the applications list. Keyboard shortcut: Escape.",
        )
        back.connect("clicked", lambda _button: self._return_to_packages())
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
        self.package_detail_path = self._make_card(
            "APK location", "Not loaded", "Installed APK path(s)",
            scrollable_detail=True,
        )
        self.package_detail_permissions = self._make_card(
            "Requested permissions", "Not loaded",
            "Names requested by the package; grant status is not inferred",
            scrollable_detail=True,
        )
        self.package_detail_components = {
            "activities": self._make_card(
                "Activities", "Not loaded", "Declared component entries",
                scrollable_detail=True,
            ),
            "services": self._make_card(
                "Services", "Not loaded", "Declared component entries",
                scrollable_detail=True,
            ),
            "receivers": self._make_card(
                "Receivers", "Not loaded", "Declared component entries",
                scrollable_detail=True,
            ),
            "providers": self._make_card(
                "Providers", "Not loaded", "Declared component entries",
                scrollable_detail=True,
            ),
        }
        permissions_expander = self._make_expander(
            "Requested permissions", self.package_detail_permissions
        )
        self.package_detail_permissions_expander = permissions_expander
        components_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL, spacing=10
        )
        for component_card in self.package_detail_components.values():
            components_box.append(component_card)
        components_expander = self._make_expander(
            "Declared components", components_box
        )
        self.package_detail_components_expander = components_expander
        details.append(self.package_detail_version)
        details.append(self.package_detail_path)
        details.append(permissions_expander)
        details.append(components_expander)
        safety_note = Gtk.Label(
            label="Information only. System/user classification is not a removal recommendation. No package changes are available in this inspector.",
            xalign=0,
        )
        safety_note.set_wrap(True)
        safety_note.add_css_class("dim-label")
        details.append(safety_note)
        self._add_scrollable_page(details, "package-detail")

    def _build_connections(self) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        for side in ("top", "bottom", "start", "end"):
            getattr(page, f"set_margin_{side}")(28 if side in ("top", "bottom") else 30)
        title = Gtk.Label(label="Connection assistant", xalign=0)
        title.add_css_class("title-1")
        page.append(title)
        intro = Gtk.Label(
            label="Guided wireless ADB pairing and Shizuku setup. Temporary pairing codes "
            "are never saved by URAAM.", xalign=0
        )
        intro.set_wrap(True)
        intro.add_css_class("dim-label")
        page.append(intro)
        self.connection_stack = Gtk.Stack()
        self.connection_stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.connection_stack.set_transition_duration(160)
        self.connection_stack.set_vexpand(True)
        page.append(self.connection_stack)

        home = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        home.append(self._connection_card(
            "WIRELESS ADB",
            "Android 11+: pair with the temporary six-digit code, then connect using the "
            "separate address and port shown on Wireless debugging."
        ))
        for label, mode in (("Set up wireless ADB  →", "adb"), ("Set up Shizuku  →", "shizuku")):
            button = Gtk.Button(label=label)
            button.add_css_class("suggested-action") if mode == "adb" else None
            button.connect("clicked", lambda _b, selected=mode: self._begin_connection(selected))
            home.append(button)
        existing = Gtk.Button(label="Use an already connected ADB device")
        existing.connect("clicked", self._use_existing_adb)
        home.append(existing)
        home.append(self._connection_note(
            "Android 10 and older have no pairing-code screen. Enable ADB TCP/IP over USB "
            "first, then connect to the device IP and port 5555. Use a trusted network."
        ))
        self.connection_stack.add_named(home, "home")

        pair = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        pair.append(self._connection_heading(
            "01 / PAIR THIS COMPUTER",
            "On Android open Developer options → Wireless debugging → Pair device with "
            "pairing code. Keep that screen open while entering its address and code."
        ))
        self.pair_endpoint = Gtk.Entry()
        self.pair_endpoint.set_placeholder_text("192.168.1.42:37123")
        self._set_accessible_label(self.pair_endpoint, "Pairing address and port")
        pair.append(self._connection_field("Pairing address : port", self.pair_endpoint))
        self.pair_code = Gtk.Entry()
        self.pair_code.set_visibility(False)
        self.pair_code.set_input_purpose(Gtk.InputPurpose.PASSWORD)
        self.pair_code.set_placeholder_text("Six-digit pairing code")
        self._set_accessible_label(self.pair_code, "Temporary pairing code")
        pair.append(self._connection_field("Temporary pairing code", self.pair_code))
        pair_button = Gtk.Button(label="Pair device")
        pair_button.add_css_class("suggested-action")
        pair_button.connect("clicked", self._pair_device)
        pair.append(pair_button)
        skip = Gtk.Button(label="Already paired · Skip")
        skip.connect("clicked", lambda _b: self._show_connection_step("connect"))
        pair.append(skip)
        pair.append(self._connection_note(
            "The code is passed directly to adb, cleared after success, and never written "
            "to URAAM logs or configuration."
        ))
        self.connection_stack.add_named(pair, "pair")

        connect = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        connect.append(self._connection_heading(
            "02 / CONNECT TO ANDROID",
            "Use the separate IP address and port on the main Wireless debugging screen. "
            "It is different from the temporary pairing port."
        ))
        self.connect_endpoint = Gtk.Entry()
        self.connect_endpoint.set_placeholder_text("192.168.1.42:39871")
        self._set_accessible_label(self.connect_endpoint, "Device address and port")
        connect.append(self._connection_field("Device address : port", self.connect_endpoint))
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        connect_button = Gtk.Button(label="Connect")
        connect_button.add_css_class("suggested-action")
        connect_button.connect("clicked", self._connect_device)
        actions.append(connect_button)
        refresh = Gtk.Button(label="Refresh devices")
        refresh.connect("clicked", self._refresh_devices_clicked)
        actions.append(refresh)
        connect.append(actions)
        self.device_dropdown = Gtk.DropDown.new_from_strings(["Refresh devices to list devices"])
        self._set_accessible_label(self.device_dropdown, "Connected ADB devices")
        connect.append(self._connection_field("ADB device", self.device_dropdown))
        use = Gtk.Button(label="Continue with selected device  →")
        use.add_css_class("suggested-action")
        use.connect("clicked", self._continue_connection)
        connect.append(use)
        self.connect_status = self._connection_note(
            "Only authorized devices in the 'device' state can be selected. Accept the "
            "RSA debugging prompt on Android if it appears."
        )
        connect.append(self.connect_status)
        back = Gtk.Button(label="← Back")
        back.set_halign(Gtk.Align.START)
        back.connect("clicked", self._back_from_connect)
        connect.append(back)
        self.connection_stack.add_named(connect, "connect")

        shizuku = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        shizuku.append(self._connection_heading(
            "03 / SHIZUKU",
            "Android 11+: start pairing inside the Shizuku app, enable Wireless debugging, "
            "then enter the pairing code in the Shizuku notification. Tap Start in Shizuku. "
            "This is separate from pairing this computer with ADB."
        ))
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        check = Gtk.Button(label="Check Shizuku")
        check.connect("clicked", self._check_shizuku)
        row.append(check)
        open_app = Gtk.Button(label="Open Shizuku on phone")
        open_app.add_css_class("suggested-action")
        open_app.connect("clicked", self._open_shizuku)
        row.append(open_app)
        shizuku.append(row)
        self.shizuku_status = self._connection_note(
            "Check installation, then open Shizuku and follow its Start instructions. "
            "Android may ask you to pair again inside the Shizuku app."
        )
        shizuku.append(self.shizuku_status)
        use_adb = Gtk.Button(label="Connect a computer with ADB to inspect this device")
        use_adb.connect("clicked", self._use_adb_for_shizuku)
        shizuku.append(use_adb)
        legacy = Gtk.Button(label="Start Shizuku · Android 10 or older")
        legacy.connect("clicked", self._start_legacy_shizuku)
        shizuku.append(legacy)
        shizuku.append(self._connection_note(
            "The legacy button runs the official computer-start script (Shizuku 11.2.0+) "
            "only when clicked, and only on Android 10 or older. Android 11+ must use "
            "Shizuku's in-app pairing. The desktop GUI uses ADB; rish remains available in Termux."
        ))
        back_home = Gtk.Button(label="← Back to connection methods")
        back_home.set_halign(Gtk.Align.START)
        back_home.connect("clicked", lambda _b: self._show_connection_step("home"))
        shizuku.append(back_home)
        finish_shizuku = Gtk.Button(label="Finish  →")
        finish_shizuku.add_css_class("suggested-action")
        finish_shizuku.connect("clicked", lambda _b: self._complete_connection())
        shizuku.append(finish_shizuku)
        self.connection_stack.add_named(shizuku, "shizuku")

        complete = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        complete.append(self._connection_heading("ALL SET", "The selected ADB device will be used by the dashboard."))
        self.complete_status = self._connection_note("No device selected.")
        complete.append(self.complete_status)
        done = Gtk.Button(label="Finish · Open dashboard")
        done.add_css_class("suggested-action")
        done.connect("clicked", lambda _b: self._finish_connection())
        complete.append(done)
        self.connection_stack.add_named(complete, "complete")

        self.connection_status = Gtk.Label(label="Ready to connect.", xalign=0)
        self.connection_status.set_wrap(True)
        self.connection_status.add_css_class("dim-label")
        page.append(self.connection_status)
        self._add_scrollable_page(page, "connections")

    @staticmethod
    def _connection_note(text: str) -> Gtk.Label:
        label = Gtk.Label(label=text, xalign=0)
        label.set_wrap(True)
        label.add_css_class("dim-label")
        return label

    @staticmethod
    def _connection_heading(title: str, description: str) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        heading = Gtk.Label(label=title, xalign=0)
        heading.add_css_class("uraam-card-heading")
        box.append(heading)
        body = Gtk.Label(label=description, xalign=0)
        body.set_wrap(True)
        box.append(body)
        return box

    @staticmethod
    def _connection_field(label_text: str, widget: Gtk.Widget) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
        label = Gtk.Label(label=label_text, xalign=0)
        label.add_css_class("uraam-card-heading")
        box.append(label)
        box.append(widget)
        return box

    @staticmethod
    def _connection_card(title: str, description: str) -> Gtk.Widget:
        frame = Gtk.Frame()
        frame.add_css_class("uraam-wide-card")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(16)
        box.set_margin_bottom(16)
        box.set_margin_start(16)
        box.set_margin_end(16)
        heading = Gtk.Label(label=title, xalign=0)
        heading.add_css_class("uraam-card-heading")
        box.append(heading)
        body = Gtk.Label(label=description, xalign=0)
        body.set_wrap(True)
        box.append(body)
        frame.set_child(box)
        return frame

    def _show_connection_step(self, step: str) -> None:
        self.connection_stack.set_visible_child_name(step)

    def _begin_connection(self, mode: str) -> None:
        self.connection_mode = mode
        if mode == "shizuku":
            self.connection_status.set_text(
                "Shizuku wireless pairing is performed in the Shizuku app on Android 11+."
            )
            self._show_connection_step("shizuku")
        else:
            self.connection_status.set_text("Wireless ADB pairing assistant.")
            self._show_connection_step("pair")

    def _use_existing_adb(self, _button: Gtk.Button) -> None:
        self.connection_mode = "adb"
        self._show_connection_step("connect")
        self._refresh_adb_devices()

    def _use_adb_for_shizuku(self, _button: Gtk.Button) -> None:
        self.connection_mode = "shizuku"
        self._show_connection_step("connect")
        self._refresh_adb_devices()

    def _back_from_connect(self, _button: Gtk.Button) -> None:
        self._show_connection_step("shizuku" if self.connection_mode == "shizuku" else "pair")

    def _run_adb(self, args: list[str], callback: Any, secret: str | None = None) -> None:
        if self._closing or self._connection_busy:
            return
        adb = shutil.which("adb")
        if adb is None:
            self.connection_status.set_text("ADB not found. Install Android platform-tools.")
            return
        self._connection_busy = True
        self.connection_status.set_text("Working…")

        def worker() -> None:
            try:
                proc = subprocess.run(
                    [adb, *args], capture_output=True, text=True, errors="replace",
                    timeout=20, check=False
                )
                out, err = (proc.stdout or "").strip(), (proc.stderr or "").strip()
                if secret:
                    out, err = out.replace(secret, "[redacted]"), err.replace(secret, "[redacted]")
                result = {"code": proc.returncode, "out": out[:2000], "err": err[:2000]}
            except subprocess.TimeoutExpired:
                result = {"code": 124, "out": "", "err": "ADB timed out after 20 seconds."}
            except OSError as exc:
                result = {"code": 127, "out": "", "err": str(exc)[:1000]}
            GLib.idle_add(self._finish_adb, callback, result)

        try:
            threading.Thread(target=worker, daemon=True, name="uraam-adb-assistant").start()
        except RuntimeError as exc:
            self._connection_busy = False
            self.connection_status.set_text(f"Unable to start ADB: {exc}")

    def _finish_adb(self, callback: Any, result: dict[str, Any]) -> bool:
        if self._closing:
            self._connection_busy = False
            return GLib.SOURCE_REMOVE
        self._connection_busy = False
        try:
            callback(result)
        except Exception:
            LOGGER.exception("Connection assistant callback failed")
            self.connection_status.set_text("Unable to update the connection assistant.")
        return GLib.SOURCE_REMOVE

    def _pair_device(self, _button: Gtk.Button) -> None:
        try:
            endpoint = validate_adb_endpoint(self.pair_endpoint.get_text())
        except ValueError as exc:
            self.connection_status.set_text(str(exc))
            return
        code = self.pair_code.get_text().strip()
        if not re.fullmatch(r"\d{6}", code):
            self.connection_status.set_text("The pairing code must contain six digits.")
            return

        def paired(result: dict[str, Any]) -> None:
            if result["code"] == 0:
                self.pair_code.set_text("")
                self.connection_status.set_text("Pairing successful. Continue to connect.")
                self._show_connection_step("connect")
            else:
                self.connection_status.set_text(result["err"] or result["out"] or "Pairing failed.")

        self._run_adb(["pair", endpoint, code], paired, secret=code)

    def _refresh_devices_clicked(self, _button: Gtk.Button) -> None:
        self._refresh_adb_devices()

    def _refresh_adb_devices(self, callback: Any | None = None) -> None:
        def refreshed(result: dict[str, Any]) -> None:
            if result["code"] != 0:
                self.connection_status.set_text(result["err"] or result["out"] or "ADB list failed.")
                return
            self._connection_devices = parse_adb_devices_output(result["out"])
            labels = [f"{serial} · {state}" for serial, state in self._connection_devices]
            self.device_dropdown.set_model(Gtk.StringList.new(labels or ["No ADB devices detected"]))
            self.device_dropdown.set_selected(0)
            ready = sum(state == "device" for _, state in self._connection_devices)
            self.connection_status.set_text(f"{ready} authorized ADB device(s) detected.")
            if callback:
                callback()

        self._run_adb(["devices", "-l"], refreshed)

    def _connect_device(self, _button: Gtk.Button) -> None:
        try:
            endpoint = validate_adb_endpoint(self.connect_endpoint.get_text())
        except ValueError as exc:
            self.connection_status.set_text(str(exc))
            return

        def connected(result: dict[str, Any]) -> None:
            response = result["out"].lower()
            if result["code"] != 0 or "failed to connect" in response or "cannot connect" in response:
                self.connection_status.set_text(
                    result["err"] or result["out"] or "ADB connect failed."
                )
                return
            self.connect_status.set_text(result["out"] or f"ADB connection requested for {endpoint}.")
            self._refresh_adb_devices(lambda: self._select_connected_endpoint(endpoint))

        self._run_adb(["connect", endpoint], connected)

    def _select_connected_endpoint(self, endpoint: str) -> None:
        for index, (serial, state) in enumerate(self._connection_devices):
            if serial == endpoint and state == "device":
                self.device_dropdown.set_selected(index)
                self._continue_connection(None)
                return
        self.connection_status.set_text("Accept the Android debugging prompt, then refresh devices.")

    def _continue_connection(self, _button: Gtk.Button | None) -> None:
        index = self.device_dropdown.get_selected()
        if index < 0 or index >= len(self._connection_devices):
            self.connection_status.set_text("Refresh ADB devices and select an authorized device.")
            return
        serial, state = self._connection_devices[index]
        if state != "device":
            self.connection_status.set_text("The selected device is not authorized yet.")
            return
        self._connection_serial = serial
        if self.connection_mode == "shizuku":
            self._show_connection_step("shizuku")
            self._check_shizuku(None)
        else:
            self._complete_connection()

    def _check_shizuku(self, _button: Gtk.Button | None) -> None:
        if not self._connection_serial:
            self.shizuku_status.set_text("Connect and select an ADB device first.")
            return

        def checked(result: dict[str, Any]) -> None:
            self.shizuku_status.set_text(
                "Shizuku is installed. Open it and follow its Start instructions."
                if result["code"] == 0 and "package:" in result["out"]
                else "Shizuku was not detected. Install the official app on Android first."
            )

        self._run_adb(["-s", self._connection_serial, "shell", "pm", "path", SHIZUKU_PACKAGE], checked)

    def _open_shizuku(self, _button: Gtk.Button) -> None:
        if not self._connection_serial:
            self.shizuku_status.set_text("Connect and select an ADB device first.")
            return

        def opened(result: dict[str, Any]) -> None:
            self.shizuku_status.set_text(
                "Shizuku opened. On Android 11+, start it in the app using Wireless debugging."
                if result["code"] == 0 else result["err"] or result["out"] or "Unable to open Shizuku."
            )

        self._run_adb(
            ["-s", self._connection_serial, "shell", "monkey", "-p", SHIZUKU_PACKAGE, "1"], opened
        )

    def _start_legacy_shizuku(self, _button: Gtk.Button) -> None:
        if not self._connection_serial:
            self.shizuku_status.set_text("Connect and select an ADB device first.")
            return

        def check_sdk(result: dict[str, Any]) -> None:
            if result["code"] != 0 or not result["out"].strip().isdigit():
                self.shizuku_status.set_text("Could not determine Android version; start was cancelled.")
                return
            if int(result["out"].strip()) > 29:
                self.shizuku_status.set_text(
                    "This device is Android 11 or newer. Start Shizuku from its app using "
                    "Wireless debugging; the legacy start script was not run."
                )
                return

            def started(start_result: dict[str, Any]) -> None:
                self.shizuku_status.set_text(
                    "Start command completed; check Shizuku's running status."
                    if start_result["code"] == 0
                    else start_result["err"] or start_result["out"] or "Shizuku start failed."
                )

            self._run_adb(
                ["-s", self._connection_serial, "shell", "sh", SHIZUKU_START_SCRIPT],
                started,
            )

        self._run_adb(
            ["-s", self._connection_serial, "shell", "getprop", "ro.build.version.sdk"],
            check_sdk,
        )

    def _complete_connection(self) -> None:
        self.complete_status.set_text(f"Selected ADB device: {self._connection_serial or 'none'}.")
        self._show_connection_step("complete")

    def _finish_connection(self) -> None:
        self._show_view("dashboard")
        self._refresh_device()

    def _api_call(self, command: str) -> dict[str, Any]:
        if not API_PATH.is_file():
            raise RuntimeError(f"URAAM JSON bridge not found: {API_PATH}")
        with self._process_lock:
            if self._closing:
                raise BridgeProcessCancelled("The read-only bridge is shutting down.")
        environment = os.environ.copy()
        selected_serial = getattr(self, "_connection_serial", None)
        if selected_serial:
            environment["ANDROID_SERIAL"] = selected_serial
        process = subprocess.Popen(
            ["bash", str(API_PATH), command],
            cwd=str(ROOT_DIR),
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        with self._process_lock:
            if self._closing:
                self._shutdown_event.set()
            else:
                self._active_process = process
        try:
            try:
                stdout, stderr = communicate_process(
                    process, self._shutdown_event, timeout_seconds=45
                )
            except BridgeProcessCancelled as exc:
                raise RuntimeError(str(exc)) from exc
            except BridgeProcessTimeout as exc:
                raise RuntimeError(
                    f"The read-only bridge request '{command}' timed out after 45 seconds."
                ) from exc
            return decode_api_response(stdout, stderr, process.returncode)
        finally:
            with self._process_lock:
                if self._active_process is process:
                    self._active_process = None

    def _run_async(self, command: str, callback: Any) -> None:
        """Run serialized bridge work; reject new work once shutdown begins."""
        if self._closing:
            return
        if self._loading:
            # Explicit latest-wins policy: replace, never queue unbounded work.
            self._pending_request = coalesce_pending_request(
                self._pending_request, (command, callback)
            )
            self.status_label.set_text(f"Waiting to load {command}…")
            return
        self._start_async(command, callback)

    def _start_async(self, command: str, callback: Any) -> None:
        """Start bridge work only while the window is still accepting requests."""
        if self._closing:
            return
        self._loading = True
        self.refresh_button.set_sensitive(False)
        self.loading_spinner.start()
        self.status_label.set_text(f"Loading {command}…")

        def worker() -> None:
            try:
                payload = self._api_call(command)
                error = None
            except Exception as exc:
                payload = None
                error = _bounded_error_message(
                    str(exc), "Unable to complete the read-only bridge request."
                )
            try:
                GLib.idle_add(self._finish_async, callback, payload, error)
            except Exception:
                # Keep GTK widget updates on the main context even if the
                # convenience idle_add wrapper cannot enqueue the completion.
                LOGGER.exception(
                    "GLib.idle_add failed; retrying with an explicit idle source"
                )
                try:
                    source = GLib.idle_source_new()
                    source.set_callback(
                        lambda: self._finish_async(callback, payload, error)
                    )
                    source.attach(GLib.MainContext.default())
                except Exception:
                    # There is no safe worker-thread fallback for GTK updates.
                    LOGGER.exception(
                        "Unable to enqueue the GTK completion on the main context"
                    )

        try:
            thread = threading.Thread(
                target=worker,
                daemon=True,
                name="uraam-api-request",
            )
            thread.start()
        except Exception as exc:
            # Restore the UI immediately if the runtime cannot create a worker.
            # This path runs on the GTK thread, so it is safe to update widgets
            # and deliver the normal callback contract directly.
            self._loading = False
            self.loading_spinner.stop()
            self.refresh_button.set_sensitive(True)
            self.status_label.set_text("Unable to start bridge request")
            callback(
                None,
                _bounded_error_message(
                    f"Unable to start the read-only bridge request '{command}': {exc}",
                    "Unable to start the read-only bridge request.",
                ),
            )

    def _finish_async(self, callback: Any, payload: Any, error: str | None) -> bool:
        if self._closing:
            self._loading = False
            self._pending_request = None
            return GLib.SOURCE_REMOVE

        pending = take_pending_request(self._pending_request, self._closing)
        self._pending_request = None
        if pending is not None:
            # A newer action superseded this result. Start it before touching
            # widgets so an older response cannot overwrite the current view.
            self._loading = False
            self._start_async(*pending)
            return GLib.SOURCE_REMOVE

        self._loading = False
        self.loading_spinner.stop()
        self.refresh_button.set_sensitive(True)
        try:
            callback(payload, error)
        except Exception:
            # A page callback must not escape through GLib's idle dispatcher
            # or leave the UI looking as though the request is still running.
            LOGGER.exception("Unable to update the GTK view after an async request")
            self.status_label.set_text("Unable to update interface")
        return GLib.SOURCE_REMOVE

    def _show_view(self, name: str) -> None:
        """Switch pages and keep sidebar navigation state synchronized."""
        if self.stack.get_visible_child_name() != name:
            self._view_generation += 1
        self.stack.set_visible_child_name(name)
        active_page = "packages" if name == "package-detail" else name
        for button_name, page in (
            ("dashboard_button", "dashboard"),
            ("packages_button", "packages"),
            ("connections_button", "connections"),
        ):
            button = getattr(self, button_name, None)
            if button is None:
                continue
            if page == active_page:
                button.add_css_class("active")
                state = "Current page"
            else:
                button.remove_css_class("active")
                state = "Open page"
            shortcut = {"dashboard": "Ctrl+1", "packages": "Ctrl+2", "connections": "Ctrl+3"}[page]
            self._set_accessible_description(
                button, f"{state}. Keyboard shortcut: {shortcut}."
            )

    def _on_key_pressed(
        self,
        _controller: Gtk.EventControllerKey,
        keyval: int,
        _keycode: int,
        state: Gdk.ModifierType,
    ) -> bool:
        """Provide predictable shortcuts without accepting extra modifiers."""
        if getattr(self, "_closing", False):
            return False
        modifiers = (
            Gdk.ModifierType.CONTROL_MASK
            | Gdk.ModifierType.SHIFT_MASK
            | Gdk.ModifierType.ALT_MASK
        )
        navigation_modifiers = state & modifiers
        if navigation_modifiers == Gdk.ModifierType.CONTROL_MASK:
            if keyval == Gdk.KEY_1:
                self._show_view("dashboard")
                return True
            if keyval == Gdk.KEY_2:
                self._on_packages(None)
                return True
            if keyval == getattr(Gdk, "KEY_3", None):
                self._show_view("connections")
                return True
        if navigation_modifiers == 0 and keyval == Gdk.KEY_Escape:
            if self.stack.get_visible_child_name() == "package-detail":
                return_to_packages = getattr(self, "_return_to_packages", None)
                if callable(return_to_packages):
                    return_to_packages()
                else:
                    # Keep lightweight WindowState test doubles compatible.
                    self._show_view("packages")
                return True
        return False

    def _return_to_packages(self) -> None:
        """Return to the inventory and restore focus when the widget exists."""
        self._show_view("packages")
        package_list = getattr(self, "package_list", None)
        if isinstance(package_list, Gtk.Widget):
            package_list.grab_focus()

    def _on_close_request(self, _window: Gtk.ApplicationWindow) -> bool:
        """Cancel the active read-only bridge process before the window closes."""
        with self._process_lock:
            if self._closing:
                return False
            self._closing = True
            self._pending_request = None
            self._shutdown_event.set()
            process = self._active_process
            if process is not None:
                signal_process_group(process, signal.SIGTERM)
        unload_theme = getattr(self, "_unload_theme", None)
        if callable(unload_theme):
            unload_theme()
        return False

    def _reset_package_views(self, message: str) -> None:
        """Remove device-specific data when the bridge cannot confirm a device."""
        self._selected_package = None
        self._package_request_generation += 1
        self._inventory_loaded = False
        self._packages = []
        self._package_types = {}
        self._package_classification = message
        self._package_empty_label.set_text(message)
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
            self._device_generation += 1
            self._device_identity = None
            self.status_label.set_text("Bridge unavailable")
            self._replace_card(self.device_card, "Device", "Bridge unavailable", error)
            self._replace_card(self.backend_card, "Connection", "Unavailable", "Check ADB / Root / Shizuku")
            self._replace_card(self.rom_card, "System", "—", "No system information")
            self._replace_card(self.version_card, "URAAM engine", "Unavailable", "Bridge request failed")
            self._reset_package_views("Device information is unavailable; cached package data was cleared.")
            return
        if payload.get("status") != "connected":
            self._device_generation += 1
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
            self._device_generation += 1
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
        self._show_view("packages")
        expected_view_generation = self._view_generation
        # Establish the current device identity immediately before inventory.
        # A prior dashboard connection state may already be stale.
        self._run_async(
            "device-info",
            lambda payload, error, view=expected_view_generation: self._begin_package_inventory(
                payload, error, view
            ),
        )

    def _begin_package_inventory(
        self, payload: Any, error: str | None, expected_view_generation: int
    ) -> None:
        if not request_is_current(
            expected_view_generation, self._view_generation, self._closing
        ):
            return
        self._show_device(payload, error)
        if error or not isinstance(payload, dict) or payload.get("status") != "connected":
            self.status_label.set_text("Connect an Android device before loading inventory")
            return
        expected_generation = self._device_generation
        expected_identity = self._device_identity
        self._run_async(
            "list-packages",
            lambda inventory, inventory_error, generation=expected_generation, identity=expected_identity, view=expected_view_generation: self._validate_package_inventory(
                inventory, inventory_error, generation, identity, view
            ),
        )

    def _validate_package_inventory(
        self,
        inventory: Any,
        inventory_error: str | None,
        expected_generation: int,
        expected_identity: tuple[str, str] | None,
        expected_view_generation: int,
    ) -> None:
        if not request_is_current(
            expected_view_generation, self._view_generation, self._closing
        ):
            return
        # Re-check the device after the potentially long package enumeration.
        # Only publish inventory if the same connected identity is still present.
        self._run_async(
            "device-info",
            lambda device, device_error, result=inventory, result_error=inventory_error, generation=expected_generation, identity=expected_identity, view=expected_view_generation: self._finish_package_inventory_validation(
                result, result_error, generation, identity, device, device_error, view
            ),
        )

    def _finish_package_inventory_validation(
        self,
        inventory: Any,
        inventory_error: str | None,
        expected_generation: int,
        expected_identity: tuple[str, str] | None,
        device: Any,
        device_error: str | None,
        expected_view_generation: int,
    ) -> None:
        if not request_is_current(
            expected_view_generation, self._view_generation, self._closing
        ):
            return
        if device_error or not isinstance(device, dict) or device.get("status") != "connected":
            self._show_device(device, device_error or "Device disconnected during inventory")
            self._reset_package_views("Device connection was lost during inventory; reload after reconnecting.")
            self.status_label.set_text("Device disconnected; inventory discarded")
            return

        if not device_matches_request(
            device,
            expected_generation,
            self._device_generation,
            expected_identity,
        ):
            if device_identity(device) is not None:
                self._show_device(device, None)
            self._reset_package_views(
                "Device identity changed during loading; reload the inventory."
            )
            self.status_label.set_text("Device changed; inventory discarded")
            return

        # A failed inventory is an operation error, not evidence of a device
        # identity mismatch. Surface the original bridge error after validating
        # that the same device is still connected.
        if inventory_error:
            self._show_packages(None, inventory_error, expected_generation)
            return

        if not inventory_matches_device(
            inventory,
            device,
            expected_generation,
            self._device_generation,
            expected_identity,
        ):
            self._reset_package_views(
                "Inventory identity did not match the connected device; reload the inventory."
            )
            self.status_label.set_text("Inventory discarded; device identity could not be verified")
            return
        self._show_packages(inventory, None, expected_generation)

    def _show_packages(
        self, payload: Any, error: str | None, expected_device_generation: int
    ) -> None:
        if expected_device_generation != self._device_generation:
            return
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
        self._inventory_loaded = True
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
        # Each activation is a distinct request, even when the user returns to
        # the same package (A → B → A) before an earlier response is delivered.
        self._package_request_generation += 1
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
        self._show_view("package-detail")
        back_button = getattr(self, "package_detail_back_button", None)
        if isinstance(back_button, Gtk.Widget):
            back_button.grab_focus()
        generation = self._package_request_generation
        device_generation = self._device_generation
        view_generation = self._view_generation
        self._run_async(
            f"package-info:{package}",
            lambda payload, error, expected=package, expected_generation=generation, expected_device=device_generation, expected_view=view_generation: self._show_package_info(
                payload, error, expected, expected_generation, expected_device, expected_view
            ),
        )

    def _show_package_info(
        self,
        payload: Any,
        error: str | None,
        expected_package: str,
        expected_generation: int,
        expected_device_generation: int,
        expected_view_generation: int,
    ) -> None:
        # A delayed response must never replace details after a reset or device change.
        if not package_detail_request_is_current(
            self._inventory_loaded,
            expected_generation,
            self._package_request_generation,
            expected_device_generation,
            self._device_generation,
            expected_package,
            self._selected_package,
            expected_view_generation,
            self._view_generation,
            self.stack.get_visible_child_name(),
            self._closing,
        ):
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
        if not package_detail_payload_matches(payload, expected_package):
            message = "Details discarded: Android returned metadata for a different package."
            self.package_detail_status.set_text(message)
            self._replace_card(
                self.package_detail_version, "Version", "Unavailable",
                "The bridge response did not match the selected package"
            )
            self._replace_card(
                self.package_detail_path, "APK location", "Unavailable", message
            )
            self._replace_card(
                self.package_detail_permissions, "Requested permissions",
                "Unavailable", message
            )
            for component_name, component_card in self.package_detail_components.items():
                self._replace_card(
                    component_card, component_name.title(), "Unavailable", message
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
            row.set_focusable(True)
            self._set_accessible_label(row, package)
            self._set_accessible_description(
                row, f"{self._package_types.get(package, 'unknown').title()} application. "
                "Activate to inspect read-only package metadata."
            )
            line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            line.set_margin_top(10)
            line.set_margin_bottom(10)
            line.set_margin_start(14)
            line.set_margin_end(14)
            label = Gtk.Label(label=package, xalign=0)
            # Keep the row as the single keyboard stop; selecting a child
            # label would add a redundant focus target inside every result.
            label.set_selectable(False)
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
        self.package_count_label.set_text(
            f"Showing {len(visible)} of {len(self._packages)} package(s)"
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
