"""Strict decoder for responses from uraam-api.sh."""

from __future__ import annotations

import json
from typing import Any


MAX_API_RESPONSE_BYTES = 8 * 1024 * 1024
MAX_JSON_NESTING = 100
MAX_JSON_CONTAINER_ENTRIES = 100_000
VALID_STATUSES = {"ok", "connected", "disconnected"}
STRING_FIELDS = {
    "backend", "serial", "model", "oem", "version", "package",
    "version_name", "version_code", "permissions_semantics",
    "components_semantics", "metadata_source",
}
COUNT_FIELDS = {"count", "user", "system_count", "user_count", "unclassified_count"}
COMPONENT_FIELDS = {"activities", "services", "receivers", "providers"}
BIDI_CONTROL_CODEPOINTS = frozenset({
    0x061C,  # Arabic Letter Mark
    0x200E, 0x200F,  # Left-to-Right / Right-to-Left Mark
    0x202A, 0x202B, 0x202C, 0x202D, 0x202E,  # Embedding / override controls
    0x2066, 0x2067, 0x2068, 0x2069,  # Directional isolates
})



def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    """Prevent ambiguous JSON objects from silently overriding earlier fields."""
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"The bridge returned a duplicate JSON key: '{key}'.")
        result[key] = value
    return result


def _reject_non_json_constant(value: str) -> None:
    """Reject NaN and Infinity, which are not valid JSON values."""
    raise ValueError(f"The bridge returned a non-standard JSON constant: {value}.")


def _validate_json_nesting(value: Any) -> None:
    """Bound JSON nesting and total container entries without recursive traversal."""
    pending = [(value, 0)]
    total_entries = 0
    while pending:
        current, depth = pending.pop()
        if isinstance(current, dict):
            total_entries += len(current)
            for key in current:
                _validate_display_string(key, "JSON object key")
            children = current.values()
        elif isinstance(current, list):
            total_entries += len(current)
            children = current
        else:
            continue
        if total_entries > MAX_JSON_CONTAINER_ENTRIES:
            raise RuntimeError(
                "The bridge JSON contains too many container entries "
                "for the decoder safety limit."
            )
        next_depth = depth + 1
        if next_depth > MAX_JSON_NESTING:
            raise RuntimeError(
                "The bridge JSON nesting exceeds the decoder safety limit."
            )
        pending.extend(
            (child, next_depth)
            for child in children
            if isinstance(child, (dict, list))
        )


def _validate_display_string(value: str, field: str) -> None:
    """Reject controls, bidi overrides and invalid Unicode in GTK text."""
    if any(
        ord(character) < 32
        or 0x7F <= ord(character) <= 0x9F
        or 0xD800 <= ord(character) <= 0xDFFF
        or ord(character) in BIDI_CONTROL_CODEPOINTS
        for character in value
    ):
        raise RuntimeError(
            f"The bridge returned unsafe control characters or unsafe Unicode in '{field}'."
        )


def _validate_display_strings(values: list[str], field: str) -> None:
    for value in values:
        _validate_display_string(value, field)


def _validate_payload_shape(payload: dict[str, Any]) -> None:
    """Reject malformed known fields before the GTK callbacks consume them."""
    for field in STRING_FIELDS:
        value = payload.get(field)
        if field in payload and value is not None:
            if not isinstance(value, str):
                raise RuntimeError(f"The bridge returned an invalid '{field}' field.")
            _validate_display_string(value, field)

    for field in COUNT_FIELDS:
        value = payload.get(field)
        if field in payload and (
            isinstance(value, bool) or not isinstance(value, int) or value < 0
        ):
            raise RuntimeError(f"The bridge returned an invalid '{field}' count.")

    for field in ("metadata_limited", "read_only", "classification_available"):
        if field in payload and not isinstance(payload[field], bool):
            raise RuntimeError(f"The bridge returned an invalid '{field}' flag.")

    if "rom" in payload and payload["rom"] is not None:
        rom = payload["rom"]
        if not isinstance(rom, dict) or any(
            key in rom and rom[key] is not None and not isinstance(rom[key], str)
            for key in ("name", "version")
        ):
            raise RuntimeError("The bridge returned invalid ROM metadata.")
        for field in ("name", "version"):
            if isinstance(rom.get(field), str):
                _validate_display_string(rom[field], f"rom.{field}")

    if "packages" in payload:
        packages = payload["packages"]
        if not isinstance(packages, list) or any(not isinstance(item, str) for item in packages):
            raise RuntimeError("The bridge returned an invalid package inventory.")
        _validate_display_strings(packages, "packages")
        if len(packages) != len(set(packages)):
            raise RuntimeError("The bridge returned duplicate package entries.")

    if "package_types" in payload:
        package_types = payload["package_types"]
        if not isinstance(package_types, dict) or any(
            not isinstance(name, str)
            or not isinstance(kind, str)
            or kind not in {"system", "user", "unknown"}
            for name, kind in package_types.items()
        ):
            raise RuntimeError("The bridge returned invalid package classifications.")
        _validate_display_strings(list(package_types), "package_types")

    if "paths" in payload:
        paths = payload["paths"]
        if not isinstance(paths, list) or any(not isinstance(item, str) for item in paths):
            raise RuntimeError("The bridge returned invalid APK path metadata.")
        _validate_display_strings(paths, "paths")

    if "requested_permissions" in payload:
        permissions = payload["requested_permissions"]
        if permissions is not None and (
            not isinstance(permissions, list)
            or any(not isinstance(item, str) for item in permissions)
        ):
            raise RuntimeError("The bridge returned invalid requested-permission metadata.")
        if permissions is not None:
            _validate_display_strings(permissions, "requested_permissions")

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
        for entries in components.values():
            if entries is not None:
                _validate_display_strings(entries, "components")



def _validate_status_contract(payload: dict[str, Any]) -> None:
    """Require the fields that make each successful bridge response meaningful."""
    status = payload["status"]

    if status == "connected":
        if not isinstance(payload.get("version"), str) or not payload["version"]:
            raise RuntimeError("The connected-device response is missing its URAAM version.")
        if not isinstance(payload.get("backend"), str) or not payload["backend"]:
            raise RuntimeError("The connected-device response is missing its backend.")
        if not isinstance(payload.get("model"), str) or not isinstance(payload.get("oem"), str):
            raise RuntimeError("The connected-device response is missing device metadata.")
        if "serial" not in payload or "rom" not in payload:
            raise RuntimeError("The connected-device response is missing identity or ROM fields.")
        if payload["rom"] is not None and not isinstance(payload["rom"], dict):
            raise RuntimeError("The connected-device response contains invalid ROM metadata.")
        return

    if status == "disconnected":
        if not isinstance(payload.get("version"), str) or not payload["version"]:
            raise RuntimeError("The disconnected-device response is missing its URAAM version.")
        if any(payload.get(field) is not None for field in ("backend", "serial", "model", "rom")):
            raise RuntimeError("The disconnected-device response contains a connected-device identity.")
        if not isinstance(payload.get("oem"), str):
            raise RuntimeError("The disconnected-device response is missing its OEM state.")
        return

    if status != "ok":
        return

    if "packages" in payload:
        required = ("backend", "serial", "user", "count", "packages", "package_types")
        if any(field not in payload for field in required):
            raise RuntimeError("The package-inventory response is missing required fields.")
        packages = payload["packages"]
        if payload["count"] != len(packages) or payload["user"] != 0:
            raise RuntimeError("The package-inventory response has inconsistent count or user data.")
        if set(payload["package_types"]) != set(packages):
            raise RuntimeError("The package-inventory classifications do not match the inventory.")
        for field in ("system_count", "user_count", "unclassified_count"):
            if field not in payload:
                raise RuntimeError(f"The package-inventory response is missing '{field}'.")
        if sum(payload[field] for field in ("system_count", "user_count", "unclassified_count")) != len(packages):
            raise RuntimeError("The package-inventory classification counts are inconsistent.")
        actual_counts = {
            kind: sum(value == kind for value in payload["package_types"].values())
            for kind in ("system", "user", "unknown")
        }
        declared_counts = {
            "system": payload["system_count"],
            "user": payload["user_count"],
            "unknown": payload["unclassified_count"],
        }
        if actual_counts != declared_counts:
            raise RuntimeError("The package-inventory classification counts do not match package types.")
        if "classification_available" not in payload:
            raise RuntimeError("The package-inventory response is missing classification availability.")
        if payload["classification_available"] != (actual_counts["unknown"] == 0):
            raise RuntimeError("The package-inventory classification availability flag is inconsistent.")
        return

    if any(field in payload for field in ("package", "paths", "components", "read_only")):
        required = (
            "backend", "paths", "version_name", "version_code",
            "requested_permissions", "components", "metadata_limited", "read_only",
        )
        if any(field not in payload for field in required):
            raise RuntimeError("The package-detail response is missing required fields.")
        if not isinstance(payload.get("package"), str) or not payload["package"]:
            raise RuntimeError("The package-detail response is missing a valid package identity.")
        if not isinstance(payload.get("backend"), str) or not payload["backend"]:
            raise RuntimeError("The package-detail response is missing its backend.")
        if not payload["paths"]:
            raise RuntimeError("The package-detail response contains no APK paths.")
        if payload["read_only"] is not True:
            raise RuntimeError("The package-detail response is not explicitly read-only.")
        if not isinstance(payload["components"], dict):
            raise RuntimeError("The package-detail response is missing component metadata.")
        return

    raise RuntimeError("The bridge returned an 'ok' response with no recognized payload type.")

MAX_ERROR_MESSAGE_CHARS = 2048


def _bounded_error_message(value: Any, fallback: str) -> str:
    """Normalize untrusted bridge diagnostics before exposing them to the UI."""
    if not isinstance(value, str):
        value = ""
    normalized = value
    for escaped_control in (r"\x00", r"\n", r"\r", r"\t"):
        normalized = normalized.replace(escaped_control, " ")
    normalized = "".join(
        character
        if (
            ord(character) >= 32
            and not 0x7F <= ord(character) <= 0x9F
            and not 0xD800 <= ord(character) <= 0xDFFF
            and ord(character) not in BIDI_CONTROL_CODEPOINTS
        )
        else " "
        for character in normalized
    )
    message = " ".join(normalized.split()).strip() or fallback
    if len(message) > MAX_ERROR_MESSAGE_CHARS:
        message = message[:MAX_ERROR_MESSAGE_CHARS - 3].rstrip() + "..."
    return message


def decode_api_response(stdout: str, stderr: str, returncode: int) -> dict[str, Any]:
    """Decode one JSON object and reject malformed or inconsistent responses."""
    if len(stdout.encode("utf-8")) > MAX_API_RESPONSE_BYTES:
        raise RuntimeError("The bridge response exceeds the 8 MiB safety limit.")

    try:
        payload = json.loads(
            stdout,
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=_reject_non_json_constant,
        )
    except json.JSONDecodeError as exc:
        fallback = (
            "The bridge returned truncated JSON."
            if exc.pos >= len(stdout.rstrip())
            else "The bridge returned invalid JSON."
        )
        detail = _bounded_error_message(stderr, fallback)
        raise RuntimeError(detail) from exc
    except RecursionError as exc:
        raise RuntimeError(
            "The bridge JSON nesting exceeds the decoder safety limit."
        ) from exc
    except ValueError as exc:
        detail = _bounded_error_message(str(exc), "The bridge returned invalid JSON.")
        raise RuntimeError(detail) from exc

    if not isinstance(payload, dict):
        raise RuntimeError("The bridge returned a JSON value that is not an object.")

    _validate_json_nesting(payload)

    status = payload.get("status")
    if returncode != 0 or status == "error":
        message = _bounded_error_message(
            payload.get("error"),
            _bounded_error_message(stderr, "URAAM request failed."),
        )
        raise RuntimeError(message)

    if not isinstance(status, str) or status not in VALID_STATUSES:
        raise RuntimeError("The bridge returned an unexpected or missing response status.")

    _validate_payload_shape(payload)
    _validate_status_contract(payload)
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


def package_detail_payload_matches(payload: Any, expected_package: str) -> bool:
    """Accept package metadata only when it names the requested package."""
    return (
        isinstance(payload, dict)
        and isinstance(expected_package, str)
        and bool(expected_package)
        and payload.get("package") == expected_package
    )

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

