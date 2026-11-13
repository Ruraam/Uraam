#!/usr/bin/env python3
"""Unit tests for the GTK-to-Bash JSON response contract."""

import unittest

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "GUI"))
from api_protocol import decode_api_response


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

    def test_error_without_message_is_safe(self):
        with self.assertRaisesRegex(RuntimeError, "URAAM request failed"):
            decode_api_response('{"status":"error","error":null}', "", 1)


if __name__ == "__main__":
    unittest.main()
