#!/usr/bin/env python3
"""Unit tests for the GTK-to-Bash JSON response contract."""

import unittest

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "GUI"))
from api_protocol import (
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


class ApiProtocolTests(unittest.TestCase):
    def test_accepts_success_inventory_object(self):
        payload = (
            '{"status":"ok","backend":"adb","serial":"device-123","user":0,'
            '"count":2,"packages":["com.example.one","com.example.two"],'
            '"package_types":{"com.example.one":"system","com.example.two":"user"},'
            '"system_count":1,"user_count":1,"unclassified_count":0,'
            '"classification_available":true}'
        )
        self.assertEqual(decode_api_response(payload, "", 0)["count"], 2)

    def test_accepts_connected_device_contract(self):
        payload = (
            '{"status":"connected","version":"4.4.3","backend":"adb",'
            '"serial":"device-123","model":"Pixel","oem":"google",'
            '"rom":{"name":"Android","version":"15"}}'
        )
        self.assertEqual(decode_api_response(payload, "", 0)["status"], "connected")

    def test_accepts_disconnected_device_contract(self):
        payload = (
            '{"status":"disconnected","version":"4.4.3","backend":null,'
            '"serial":null,"model":null,"oem":"unknown","rom":null}'
        )
        self.assertEqual(decode_api_response(payload, "", 0)["status"], "disconnected")

    def test_rejects_incomplete_connected_device_contract(self):
        with self.assertRaisesRegex(RuntimeError, "backend"):
            decode_api_response(
                '{"status":"connected","version":"4.4.3","model":"Pixel",'
                '"oem":"google","serial":"device-123","rom":null}',
                "", 0
            )

    def test_rejects_connected_identity_in_disconnected_contract(self):
        with self.assertRaisesRegex(RuntimeError, "identity"):
            decode_api_response(
                '{"status":"disconnected","version":"4.4.3","backend":"adb",'
                '"serial":null,"model":null,"oem":"unknown","rom":null}',
                "", 0
            )

    def test_rejects_inventory_with_inconsistent_counts(self):
        payload = (
            '{"status":"ok","backend":"adb","serial":"device-123","user":0,'
            '"count":2,"packages":["com.example.one"],'
            '"package_types":{"com.example.one":"user"},'
            '"system_count":0,"user_count":1,"unclassified_count":0,'
            '"classification_available":true}'
        )
        with self.assertRaisesRegex(RuntimeError, "count"):
            decode_api_response(payload, "", 0)

    def test_rejects_inventory_with_incomplete_classification(self):
        payload = (
            '{"status":"ok","backend":"adb","serial":"device-123","user":0,'
            '"count":1,"packages":["com.example.one"],"package_types":{},'
            '"system_count":0,"user_count":0,"unclassified_count":1,'
            '"classification_available":false}'
        )
        with self.assertRaisesRegex(RuntimeError, "classifications"):
            decode_api_response(payload, "", 0)

    def test_rejects_unrecognized_ok_payload(self):
        with self.assertRaisesRegex(RuntimeError, "recognized payload"):
            decode_api_response('{"status":"ok","count":2}', "", 0)

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

    def test_rejects_non_string_package_version_metadata(self):
        for field in ("version_name", "version_code"):
            with self.subTest(field=field):
                payload = __import__("json").dumps(
                    {"status": "ok", "package": "com.example.app", field: 42}
                )
                with self.assertRaisesRegex(RuntimeError, field):
                    decode_api_response(payload, "", 0)

    def test_rejects_non_string_package_semantics_metadata(self):
        for field in ("permissions_semantics", "components_semantics", "metadata_source"):
            with self.subTest(field=field):
                payload = __import__("json").dumps(
                    {"status": "ok", "package": "com.example.app", field: []}
                )
                with self.assertRaisesRegex(RuntimeError, field):
                    decode_api_response(payload, "", 0)

    def test_rejects_non_boolean_metadata_flags(self):
        for field in ("metadata_limited", "read_only", "classification_available"):
            with self.subTest(field=field):
                payload = __import__("json").dumps(
                    {"status": "ok", "package": "com.example.app", field: "false"}
                )
                with self.assertRaisesRegex(RuntimeError, field):
                    decode_api_response(payload, "", 0)

    def test_accepts_nullable_package_versions_and_valid_metadata_flags(self):
        payload = (
            '{"status":"ok","package":"com.example.app","backend":"adb",'
            '"paths":["/data/app/com.example.app/base.apk"],'
            '"version_name":null,"version_code":null,'
            '"requested_permissions":null,"components":{'
            '"activities":null,"services":null,"receivers":null,"providers":null},'
            '"metadata_limited":false,"read_only":true,'
            '"permissions_semantics":"requested_only_not_grant_status"}'
        )
        self.assertTrue(decode_api_response(payload, "", 0)["read_only"])

    def test_rejects_package_details_without_explicit_read_only_flag(self):
        payload = (
            '{"status":"ok","package":"com.example.app","backend":"adb",'
            '"paths":["/data/app/base.apk"],"version_name":null,"version_code":null,'
            '"requested_permissions":null,"components":{},"metadata_limited":false,'
            '"read_only":false}'
        )
        with self.assertRaisesRegex(RuntimeError, "not explicitly read-only"):
            decode_api_response(payload, "", 0)

    def test_rejects_ok_response_with_missing_package_detail_fields(self):
        with self.assertRaisesRegex(RuntimeError, "missing required fields"):
            decode_api_response(
                '{"status":"ok","package":"com.example.app","backend":"adb"}',
                "", 0
            )

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


class DeviceRequestFreshnessTests(unittest.TestCase):
    def setUp(self):
        self.device = {
            "status": "connected",
            "backend": "adb",
            "serial": "device-123",
        }
        self.identity = ("adb", "device-123")

    def test_accepts_same_connected_device_without_inventory_payload(self):
        self.assertTrue(
            device_matches_request(self.device, 4, 4, self.identity)
        )

    def test_rejects_changed_generation(self):
        self.assertFalse(
            device_matches_request(self.device, 3, 4, self.identity)
        )

    def test_rejects_replaced_device(self):
        replacement = {
            "status": "connected",
            "backend": "shizuku",
            "serial": "device-456",
        }
        self.assertFalse(
            device_matches_request(replacement, 4, 4, self.identity)
        )

    def test_rejects_disconnected_device(self):
        self.assertFalse(
            device_matches_request(
                {"status": "disconnected"}, 4, 4, self.identity
            )
        )

    def test_rejects_missing_expected_identity(self):
        self.assertFalse(
            device_matches_request(self.device, 4, 4, None)
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


class PendingRequestPolicyTests(unittest.TestCase):
    def test_new_action_replaces_existing_pending_action(self):
        first = ("device-info", object())
        latest = ("list-packages", object())
        self.assertIs(coalesce_pending_request(first, latest), latest)

    def test_first_pending_action_is_retained_when_slot_is_empty(self):
        latest = ("device-info", object())
        self.assertIs(coalesce_pending_request(None, latest), latest)

    def test_completion_takes_latest_pending_action(self):
        latest = ("device-info", object())
        self.assertIs(take_pending_request(latest, False), latest)

    def test_shutdown_discards_pending_action(self):
        pending = ("list-packages", object())
        self.assertIsNone(take_pending_request(pending, True))

    def test_empty_pending_slot_stays_empty(self):
        self.assertIsNone(take_pending_request(None, False))


class PackageDetailPayloadIdentityTests(unittest.TestCase):
    def test_accepts_metadata_for_requested_package(self):
        self.assertTrue(
            package_detail_payload_matches(
                {"package": "com.example.app"}, "com.example.app"
            )
        )

    def test_rejects_metadata_for_another_package(self):
        self.assertFalse(
            package_detail_payload_matches(
                {"package": "com.example.other"}, "com.example.app"
            )
        )

    def test_rejects_missing_package_identity(self):
        self.assertFalse(package_detail_payload_matches({}, "com.example.app"))

    def test_rejects_non_object_payload(self):
        self.assertFalse(package_detail_payload_matches([], "com.example.app"))

    def test_rejects_empty_expected_package(self):
        self.assertFalse(package_detail_payload_matches({"package": ""}, ""))


class PackageDetailFreshnessTests(unittest.TestCase):
    def _is_current(self, **overrides):
        values = {
            "inventory_loaded": True,
            "expected_request_generation": 5,
            "current_request_generation": 5,
            "expected_device_generation": 3,
            "current_device_generation": 3,
            "expected_package": "com.example.app",
            "selected_package": "com.example.app",
            "expected_view_generation": 8,
            "current_view_generation": 8,
            "visible_view": "package-detail",
            "closing": False,
        }
        values.update(overrides)
        return package_detail_request_is_current(**values)

    def test_accepts_current_package_detail_response(self):
        self.assertTrue(self._is_current())

    def test_rejects_response_after_another_package_is_selected(self):
        self.assertFalse(self._is_current(selected_package="com.example.other"))

    def test_rejects_response_after_selection_generation_changes(self):
        self.assertFalse(self._is_current(current_request_generation=6))

    def test_rejects_response_after_device_generation_changes(self):
        self.assertFalse(self._is_current(current_device_generation=4))

    def test_rejects_response_after_navigation(self):
        self.assertFalse(self._is_current(current_view_generation=9))

    def test_rejects_response_when_detail_view_is_not_visible(self):
        self.assertFalse(self._is_current(visible_view="packages"))

    def test_rejects_response_after_inventory_reset(self):
        self.assertFalse(self._is_current(inventory_loaded=False))

    def test_rejects_response_during_shutdown(self):
        self.assertFalse(self._is_current(closing=True))


if __name__ == "__main__":
    unittest.main()
