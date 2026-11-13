#!/usr/bin/env python3
"""Unit tests for the GTK-to-Bash JSON response contract."""

import unittest

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "GUI"))
from api_protocol import (
    decode_api_response,
    device_identity,
    inventory_matches_device,
    request_is_current,
)


class ApiProtocolTests(unittest.TestCase):
    def test_accepts_success_object(self):
        self.assertEqual(
            decode_api_response('{"status":"ok","count":2}', "", 0)["count"],
            2,
        )

    def test_accepts_disconnected_device(self):
        self.assertEqual(
            decode_api_response('{"status":"disconnected","backend":null}', "", 0)["status"],
            "disconnected",
        )

    def test_rejects_stdout_noise(self):
        with self.assertRaisesRegex(RuntimeError, "invalid JSON"):
            decode_api_response("debug line\\n{} ", "", 0)

    def test_rejects_non_object_json(self):
        with self.assertRaisesRegex(RuntimeError, "not an object"):
            decode_api_response("[]", "", 0)

    def test_rejects_missing_status(self):
        with self.assertRaisesRegex(RuntimeError, "status"):
            decode_api_response('{"packages":[]}', "", 0)

    def test_rejects_unknown_status(self):
        with self.assertRaisesRegex(RuntimeError, "status"):
            decode_api_response('{"status":"maybe"}', "", 0)

    def test_rejects_non_string_status(self):
        for status in ([], {}):
            with self.subTest(status=status):
                with self.assertRaisesRegex(RuntimeError, "status"):
                    decode_api_response(__import__("json").dumps({"status": status}), "", 0)

    def test_surfaces_json_error_payload(self):
        with self.assertRaisesRegex(RuntimeError, "No backend"):
            decode_api_response('{"status":"error","error":"No backend"}', "", 4)

    def test_nonzero_exit_without_error_uses_stderr(self):
        with self.assertRaisesRegex(RuntimeError, "permission denied"):
            decode_api_response('{"status":"ok"}', "permission denied", 5)

    def test_rejects_oversized_response(self):
        oversized = '{"status":"ok","padding":"' + ("x" * (8 * 1024 * 1024)) + '"}'
        with self.assertRaisesRegex(RuntimeError, "8 MiB"):
            decode_api_response(oversized, "", 0)

    def test_rejects_non_list_package_inventory(self):
        with self.assertRaisesRegex(RuntimeError, "package inventory"):
            decode_api_response('{"status":"ok","packages":"com.example.app"}', "", 0)

    def test_rejects_non_string_package_entries(self):
        with self.assertRaisesRegex(RuntimeError, "package inventory"):
            decode_api_response('{"status":"ok","packages":["com.example.app",7]}', "", 0)

    def test_rejects_unhashable_package_classification(self):
        for kind in ([], {}):
            with self.subTest(kind=kind):
                payload = __import__("json").dumps({"status": "ok", "package_types": {"com.example.app": kind}})
                with self.assertRaisesRegex(RuntimeError, "package classifications"):
                    decode_api_response(payload, "", 0)

    def test_rejects_invalid_rom_shape(self):
        with self.assertRaisesRegex(RuntimeError, "ROM metadata"):
            decode_api_response('{"status":"connected","rom":"Android 15"}', "", 0)

    def test_rejects_invalid_apk_paths(self):
        with self.assertRaisesRegex(RuntimeError, "APK path metadata"):
            decode_api_response('{"status":"ok","paths":["/data/app/base.apk",null]}', "", 0)

    def test_rejects_invalid_component_metadata(self):
        with self.assertRaisesRegex(RuntimeError, "component metadata"):
            decode_api_response('{"status":"ok","components":{"activities":"MainActivity"}}', "", 0)

    def test_error_without_message_is_safe(self):
        with self.assertRaisesRegex(RuntimeError, "URAAM request failed"):
            decode_api_response('{"status":"error","error":null}', "", 1)


class InventoryIdentityTests(unittest.TestCase):
    def setUp(self):
        self.device = {
            "status": "connected",
            "backend": "adb",
            "serial": "device-123",
        }
        self.inventory = {
            "status": "ok",
            "backend": "adb",
            "serial": "device-123",
            "packages": ["com.example.app"],
        }
        self.identity = ("adb", "device-123")

    def test_extracts_identity_only_for_connected_device(self):
        self.assertEqual(device_identity(self.device), self.identity)
        self.assertIsNone(device_identity({"status": "disconnected"}))
        self.assertIsNone(device_identity(None))

    def test_accepts_matching_inventory_for_current_generation(self):
        self.assertTrue(
            inventory_matches_device(
                self.inventory, self.device, 4, 4, self.identity
            )
        )

    def test_rejects_stale_generation_even_when_serial_is_unchanged(self):
        # A disconnect/reconnect can reuse the same backend and serial.
        # The generation token must still invalidate the earlier response.
        self.assertFalse(
            inventory_matches_device(
                self.inventory, self.device, 3, 4, self.identity
            )
        )

    def test_rejects_disconnected_device(self):
        self.assertFalse(
            inventory_matches_device(
                self.inventory,
                {"status": "disconnected"},
                4,
                4,
                self.identity,
            )
        )

    def test_rejects_changed_device_identity(self):
        replacement = {
            "status": "connected",
            "backend": "shizuku",
            "serial": "device-456",
        }
        self.assertFalse(
            inventory_matches_device(
                self.inventory, replacement, 4, 4, self.identity
            )
        )

    def test_rejects_inventory_from_another_device(self):
        wrong_inventory = {
            **self.inventory,
            "serial": "device-456",
        }
        self.assertFalse(
            inventory_matches_device(
                wrong_inventory, self.device, 4, 4, self.identity
            )
        )

    def test_rejects_missing_expected_identity_or_invalid_inventory(self):
        self.assertFalse(
            inventory_matches_device(
                self.inventory, self.device, 4, 4, None
            )
        )
        self.assertFalse(
            inventory_matches_device(
                None, self.device, 4, 4, self.identity
            )
        )


class ViewRequestFreshnessTests(unittest.TestCase):
    def test_accepts_request_for_current_view(self):
        self.assertTrue(request_is_current(7, 7, False))

    def test_rejects_request_after_navigation(self):
        self.assertFalse(request_is_current(7, 8, False))

    def test_rejects_request_when_window_is_closing(self):
        self.assertFalse(request_is_current(7, 7, True))

    def test_rejects_request_after_navigation_away_and_back(self):
        # Returning to the same named view must not revive an older callback.
        self.assertFalse(request_is_current(7, 9, False))


if __name__ == "__main__":
    unittest.main()
