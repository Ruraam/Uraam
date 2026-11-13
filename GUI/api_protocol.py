"""Strict decoder for responses from uraam-api.sh."""

from __future__ import annotations

import json
from typing import Any


MAX_API_RESPONSE_BYTES = 8 * 1024 * 1024
VALID_STATUSES = {"ok", "connected", "disconnected"}


def decode_api_response(stdout: str, stderr: str, returncode: int) -> dict[str, Any]:
    """Decode one JSON object and reject malformed or inconsistent responses."""
    if len(stdout.encode("utf-8")) > MAX_API_RESPONSE_BYTES:
        raise RuntimeError("The bridge response exceeds the 8 MiB safety limit.")

    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as exc:
        detail = stderr.strip() or "The bridge returned invalid JSON."
        raise RuntimeError(detail) from exc

    if not isinstance(payload, dict):
        raise RuntimeError("The bridge returned a JSON value that is not an object.")

    status = payload.get("status")
    if returncode != 0 or status == "error":
        message = payload.get("error")
        if not isinstance(message, str) or not message.strip():
            message = stderr.strip() or "URAAM request failed."
        raise RuntimeError(message)

    if status not in VALID_STATUSES:
        raise RuntimeError("The bridge returned an unexpected or missing response status.")

    return payload
