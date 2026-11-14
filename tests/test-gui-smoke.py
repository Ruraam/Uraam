#!/usr/bin/env python3
"""Headless GTK4 construction and navigation smoke test for URAAM."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "GUI"))

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib  # noqa: E402

from main import UraamApplication, UraamWindow  # noqa: E402


def drain_main_context() -> None:
    context = GLib.MainContext.default()
    while context.pending():
        context.iteration(False)


def main() -> int:
    # Keep this smoke test isolated from ADB, Root, Shizuku and the device API.
    original_refresh = UraamWindow._refresh_device
    UraamWindow._refresh_device = lambda self: None
    application = UraamApplication()
    try:
        if not application.register(None):
            raise RuntimeError("Unable to register the GTK application")

        window = UraamWindow(application)
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
        detail_label = metadata_scroller.get_child()
        if detail_label.get_text() != stress_metadata:
            raise AssertionError("The GTK metadata card truncated a large value")
        if not detail_label.get_selectable():
            raise AssertionError("Large metadata is not selectable for copying")
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
        if window.package_count_label.get_text() != "Showing 1 of 2 package(s)":
            raise AssertionError("The GTK package count is inconsistent")

        window._show_view("packages")
        if window.stack.get_visible_child_name() != "packages":
            raise AssertionError("Applications navigation failed")
        window._show_view("package-detail")
        if window.stack.get_visible_child_name() != "package-detail":
            raise AssertionError("Package inspector navigation failed")

        window.close()
        drain_main_context()
        print("PASS: GTK4 window construction, package filtering and navigation")
        return 0
    finally:
        UraamWindow._refresh_device = original_refresh


if __name__ == "__main__":
    raise SystemExit(main())
