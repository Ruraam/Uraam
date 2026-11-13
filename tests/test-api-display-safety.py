#!/usr/bin/env python3
"""Reject unsafe control characters in bridge strings consumed by GTK."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "GUI"))
from api_protocol import decode_api_response


class BridgeDisplayStringSafetyTests(unittest.TestCase):
    def _decode(self, payload):
        return decode_api_response(json.dumps(payload), "", 0)

    def test_rejects_control_characters_in_device_metadata(self):
        payload = {
            "status": "connected",
            "version": "5.1.0",
            "backend": "adb",
            "serial": "device-123",
            "model": "Pixel\u0000spoofed",
            "oem": "google",
            "rom": {"name": "Android", "version": "15"},
        }
        with self.assertRaisesRegex(RuntimeError, "unsafe control characters.*model"):
            self._decode(payload)

    def test_rejects_bidirectional_override_in_device_metadata(self):
        payload = {
            "status": "connected",
            "version": "5.1.0",
            "backend": "adb",
            "serial": "device-123",
            "model": "Pixel\u202eexe",
            "oem": "google",
            "rom": {"name": "Android", "version": "15"},
        }
        with self.assertRaisesRegex(RuntimeError, "unsafe control characters.*model"):
            self._decode(payload)

    def test_accepts_rtl_text_without_directional_control_characters(self):
        payload = {
            "status": "connected",
            "version": "5.1.0",
            "backend": "adb",
            "serial": "device-123",
            "model": "هاتف بيكسل",
            "oem": "google",
            "rom": {"name": "אנדרואיד", "version": "15"},
        }
        self.assertEqual(self._decode(payload)["model"], "هاتف بيكسل")

    def test_rejects_control_characters_in_rom_metadata(self):
        payload = {
            "status": "connected",
            "version": "5.1.0",
            "backend": "adb",
            "serial": "device-123",
            "model": "Pixel",
            "oem": "google",
            "rom": {"name": "Android\nInjected line", "version": "15"},
        }
        with self.assertRaisesRegex(RuntimeError, "unsafe control characters.*rom.name"):
            self._decode(payload)

    def test_rejects_control_characters_in_package_inventory_names(self):
        package = "com.example.app\tspoofed"
        payload = {
            "status": "ok",
            "backend": "adb",
            "serial": "device-123",
            "user": 0,
            "count": 1,
            "packages": [package],
            "package_types": {"com.example.classified": "user"},
            "system_count": 0,
            "user_count": 1,
            "unclassified_count": 0,
            "classification_available": True,
        }
        with self.assertRaisesRegex(RuntimeError, "unsafe control characters.*packages"):
            self._decode(payload)

    def _package_detail(self):
        return {
            "status": "ok",
            "package": "com.example.app",
            "backend": "adb",
            "paths": ["/data/app/com.example.app/base.apk"],
            "version_name": None,
            "version_code": None,
            "requested_permissions": [],
            "components": {},
            "metadata_limited": False,
            "read_only": True,
        }

    def test_rejects_control_characters_in_apk_paths(self):
        payload = self._package_detail()
        payload["paths"] = ["/data/app/base.apk\u0000spoofed"]
        with self.assertRaisesRegex(RuntimeError, "unsafe control characters.*paths"):
            self._decode(payload)

    def test_rejects_control_characters_in_requested_permissions(self):
        payload = self._package_detail()
        payload["requested_permissions"] = ["android.permission.CAMERA\nspoofed"]
        with self.assertRaisesRegex(
            RuntimeError, "unsafe control characters.*requested_permissions"
        ):
            self._decode(payload)

    def test_rejects_control_characters_in_component_names(self):
        payload = self._package_detail()
        payload["components"] = {"activities": ["com.example.Main\rInjected"]}
        with self.assertRaisesRegex(RuntimeError, "unsafe control characters.*components"):
            self._decode(payload)

    def test_rejects_invisible_format_characters_in_apk_paths(self):
        for character in ("\u200b", "\u2060", "\ufeff", "\u00ad"):
            with self.subTest(codepoint=hex(ord(character))):
                payload = self._package_detail()
                payload["paths"] = ["/data/app/base" + character + ".apk"]
                with self.assertRaisesRegex(
                    RuntimeError, "invisible Unicode format characters.*paths"
                ):
                    self._decode(payload)

    def test_rejects_invisible_format_characters_in_requested_permissions(self):
        for character in ("\u200b", "\u2060", "\ufeff", "\u00ad"):
            with self.subTest(codepoint=hex(ord(character))):
                payload = self._package_detail()
                payload["requested_permissions"] = [
                    "android.permission.CAMERA" + character
                ]
                with self.assertRaisesRegex(
                    RuntimeError,
                    "invisible Unicode format characters.*requested_permissions",
                ):
                    self._decode(payload)

    def test_rejects_invisible_format_characters_in_component_names(self):
        for character in ("\u200b", "\u2060", "\ufeff", "\u00ad"):
            with self.subTest(codepoint=hex(ord(character))):
                payload = self._package_detail()
                payload["components"] = {
                    "activities": ["com.example.Main" + character]
                }
                with self.assertRaisesRegex(
                    RuntimeError, "invisible Unicode format characters.*components"
                ):
                    self._decode(payload)

    def test_accepts_normal_unicode_apk_paths(self):
        payload = self._package_detail()
        payload["paths"] = ["/data/app/édition/base.apk"]
        self.assertEqual(
            self._decode(payload)["paths"], ["/data/app/édition/base.apk"]
        )

    def test_sanitizes_bidi_override_in_bridge_error_message(self):
        payload = {"status": "error", "error": "Permission" + chr(0x202E) + "Denied"}
        with self.assertRaisesRegex(RuntimeError, "^Permission Denied$"):
            self._decode(payload)

    def test_sanitizes_bidi_controls_in_stderr_fallback(self):
        stderr = "Device" + chr(0x202E) + " unavailable"
        with self.assertRaisesRegex(RuntimeError, "^Device unavailable$"):
            decode_api_response("not-json", stderr, 1)

    def test_accepts_normal_unicode_device_and_package_metadata(self):
        payload = {
            "status": "connected",
            "version": "5.1.0",
            "backend": "adb",
            "serial": "device-123",
            "model": "Téléphone Édition",
            "oem": "Constructeur",
            "rom": {"name": "Android", "version": "15"},
        }
        self.assertEqual(self._decode(payload)["model"], "Téléphone Édition")


if __name__ == "__main__":
    unittest.main()
