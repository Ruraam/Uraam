"""Strict decoder for responses from uraam-api.sh."""

from __future__ import annotations

import json
from typing import Any


MAX_API_RESPONSE_BYTES = 8 * 1024 * 1024
VALID_STATUSES = {"ok", "connected", "disconnected"}
STRING_FIELDS = {"backend", "serial", "model", "oem", "version", "package"}
COUNT_FIELDS = {"count", "user", "system_count", "user_count", "unclassified_count"}
COMPONENT_FIELDS = {"activities", "services", "receivers", "providers"}


def _validate_payload_shape(payload: dict[str, Any]) -> None:
    """Reject malformed known fields before the GTK callbacks consume them."""
    for field in STRING_FIELDS:
        if field in payload and payload[field] is not None and not isinstance(payload[field], str):
            raise RuntimeError(f"The bridge returned an invalid '{field}' field.")

    for field in COUNT_FIELDS:
        value = payload.get(field)
        if field in payload and (
            isinstance(value, bool) or not isinstance(value, int) or value < 0
        ):
            raise RuntimeError(f"The bridge returned an invalid '{field}' count.")

    if "rom" in payload and payload["rom"] is not None:
        rom = payload["rom"]
        if not isinstance(rom, dict) or any(
            key in rom and rom[key] is not None and not isinstance(rom[key], str)
            for key in ("name", "version")
        ):
            raise RuntimeError("The bridge returned invalid ROM metadata.")

    if "packages" in payload:
        packages = payload["packages"]
        if not isinstance(packages, list) or any(not isinstance(item, str) for item in packages):
            raise RuntimeError("The bridge returned an invalid package inventory.")

    if "package_types" in payload:
        package_types = payload["package_types"]
        if not isinstance(package_types, dict) or any(
            not isinstance(name, str)
            or not isinstance(kind, str)
            or kind not in {"system", "user", "unknown"}
            for name, kind in package_types.items()
        ):
            raise RuntimeError("The bridge returned invalid package classifications.")

    if "paths" in payload:
        paths = payload["paths"]
        if not isinstance(paths, list) or any(not isinstance(item, str) for item in paths):
            raise RuntimeError("The bridge returned invalid APK path metadata.")

    if "requested_permissions" in payload:
        permissions = payload["requested_permissions"]
        if permissions is not None and (
            not isinstance(permissions, list)
            or any(not isinstance(item, str) for item in permissions)
        ):
            raise RuntimeError("The bridge returned invalid requested-permission metadata.")

    if "components" in payload:
        components = payload["components"]
        if not isinstance(components, dict) or any(
            key not in COMPONENT_FIELDS
            or (
                value is not None
                and (
                    not isinstance(value, list)
                    or any(not isinstance(item, str) for item in value)
                )
            )
            for key, value in components.items()
        ):
            raise RuntimeError("The bridge returned invalid component metadata.")


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

    if not isinstance(status, str) or status not in VALID_STATUSES:
        raise RuntimeError("The bridge returned an unexpected or missing response status.")

    _validate_payload_shape(payload)
    return payload

def device_identity(payload: Any) -> tuple[str, str] | None:
    """Return the stable bridge identity only for a confirmed connected device."""
    if not isinstance(payload, dict) or payload.get("status") != "connected":
        return None
    return (
        str(payload.get("backend") or "unknown"),
        str(payload.get("serial") or "local"),
    )



def device_matches_request(
    device: Any,
    expected_generation: int,
    current_generation: int,
    expected_identity: tuple[str, str] | None,
) -> bool:
    """Confirm the same connected device without requiring a successful inventory payload."""
    return (
        expected_generation == current_generation
        and expected_identity is not None
        and device_identity(device) == expected_identity
    )

def inventory_matches_device(
    inventory: Any,
    device: Any,
    expected_generation: int,
    current_generation: int,
    expected_identity: tuple[str, str] | None,
) -> bool:
    """Accept inventory only when generation and both reported identities agree."""
    if not device_matches_request(
        device, expected_generation, current_generation, expected_identity
    ) or not isinstance(inventory, dict):
        return False
    inventory_identity = (
        str(inventory.get("backend") or "unknown"),
        str(inventory.get("serial") or "local"),
    )
    return inventory_identity == expected_identity

def request_is_current(
    expected_view_generation: int,
    current_view_generation: int,
    closing: bool,
) -> bool:
    """Allow a view-bound callback only while its originating view is active."""
    return not closing and expected_view_generation == current_view_generation

def coalesce_pending_request(
    _current: tuple[str, Any] | None,
    incoming: tuple[str, Any],
) -> tuple[str, Any]:
    """Keep only the newest queued action while a bridge request is running."""
    return incoming


def take_pending_request(
    pending: tuple[str, Any] | None,
    closing: bool,
) -> tuple[str, Any] | None:
    """Drop queued work on shutdown; otherwise return the latest queued action."""
    return None if closing else pending

def package_detail_request_is_current(
    inventory_loaded: bool,
    expected_request_generation: int,
    current_request_generation: int,
    expected_device_generation: int,
    current_device_generation: int,
    expected_package: str,
    selected_package: str | None,
    expected_view_generation: int,
    current_view_generation: int,
    visible_view: str | None,
    closing: bool,
) -> bool:
    """Reject package metadata callbacks after selection, device, view, or shutdown changes."""
    return (
        not closing
        and inventory_loaded
        and expected_request_generation == current_request_generation
        and expected_device_generation == current_device_generation
        and expected_package == selected_package
        and expected_view_generation == current_view_generation
        and visible_view == "package-detail"
    )

