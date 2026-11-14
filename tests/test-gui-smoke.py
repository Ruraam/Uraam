#!/usr/bin/env python3
"""Headless GTK4 construction and navigation smoke test for URAAM."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "GUI"))

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

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

        window.close()
        drain_main_context()
        print("PASS: GTK4 window construction, package filtering and navigation")
        return 0
    finally:
        UraamWindow._refresh_device = original_refresh


if __name__ == "__main__":
    raise SystemExit(main())
