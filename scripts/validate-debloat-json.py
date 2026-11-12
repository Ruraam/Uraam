#!/usr/bin/env python3
"""Validate URAAM debloat JSON files and conservative profiles against pinned UAD-NG data."""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = ROOT / "Configs" / "debloat"
UAD_REVISION = "9fcad87bf78c52c4270504bc8880139d95a27a29"
UAD_URL = (
    "https://raw.githubusercontent.com/Universal-Debloater-Alliance/"
    "universal-android-debloater-next-generation/"
    f"{UAD_REVISION}/resources/assets/uad_lists.json"
)


def load_uad() -> Any:
    request = urllib.request.Request(
        UAD_URL, headers={"User-Agent": "URAAM-config-validator"}
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.loads(response.read().decode("utf-8"))


def package_records(data: Any) -> dict[str, dict[str, Any]]:
    """Normalize known UAD JSON layouts to package -> metadata."""
    records: dict[str, dict[str, Any]] = {}

    def visit(node: Any, key_hint: str | None = None) -> None:
        if isinstance(node, dict):
            package = (
                node.get("packageName")
                or node.get("package_name")
                or node.get("id")
                or node.get("package")
                or key_hint
            )
            if isinstance(package, str) and (
                "removal" in node or "list" in node
            ):
                records[package] = node
            else:
                for key, value in node.items():
                    visit(value, key if isinstance(key, str) else None)
        elif isinstance(node, list):
            for value in node:
                visit(value)

    visit(data)
    return records


def main() -> int:
    if not CONFIG_DIR.is_dir():
        print(f"ERROR: configuration directory not found: {CONFIG_DIR}", file=sys.stderr)
        return 1

    try:
        uad = package_records(load_uad())
    except Exception as exc:  # network, HTTP, or malformed source
        print(f"ERROR: cannot load pinned UAD-NG database: {exc}", file=sys.stderr)
        return 1

    if not uad:
        print("ERROR: no package records recognized in UAD-NG database", file=sys.stderr)
        return 1

    errors: list[str] = []
    requested = [Path(arg) for arg in sys.argv[1:]]
    if requested:
        json_files = []
        for item in requested:
            path = item if item.is_absolute() else ROOT / item
            try:
                path.resolve().relative_to(CONFIG_DIR.resolve())
            except ValueError:
                errors.append(f"{item}: path is outside {CONFIG_DIR}")
                continue
            if path.suffix.lower() == ".json" and path.is_file():
                json_files.append(path)
            else:
                errors.append(f"{item}: JSON file does not exist")
        json_files = sorted(set(json_files))
    else:
        json_files = sorted(CONFIG_DIR.glob("*.json"))

    if not json_files:
        if errors:
            print("URAAM debloat configuration validation FAILED:")
            for error in errors:
                print(f" - {error}")
            return 1
        print("No changed JSON profiles to validate.")
        return 0

    for path in json_files:
        try:
            config = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"{path.name}: invalid JSON: {exc}")
            continue

        if not isinstance(config, dict):
            errors.append(f"{path.name}: top-level JSON value must be an object")
            continue

        for field in ("name", "description", "author", "version"):
            if not isinstance(config.get(field), str) or not config[field].strip():
                errors.append(f"{path.name}: '{field}' must be a non-empty string")

        apps = config.get("apps")
        if not isinstance(apps, list):
            errors.append(f"{path.name}: 'apps' must be an array")
            continue

        seen: set[str] = set()
        for index, app in enumerate(apps):
            where = f"{path.name}: apps[{index}]"
            if not isinstance(app, dict):
                errors.append(f"{where} must be an object")
                continue
            package = app.get("packageName")
            if not isinstance(package, str) or not package.strip():
                errors.append(f"{where}.packageName must be a non-empty string")
                continue
            if package in seen:
                errors.append(f"{path.name}: duplicate package ID '{package}'")
            seen.add(package)

            # Only files explicitly named Safe-* are constrained by UAD.
            if path.name.startswith("Safe-"):
                metadata = uad.get(package)
                if metadata is None:
                    errors.append(
                        f"{path.name}: '{package}' is absent from pinned UAD-NG data"
                    )
                elif metadata.get("removal") != "Recommended":
                    errors.append(
                        f"{path.name}: '{package}' has UAD removal="
                        f"{metadata.get('removal')!r}, expected 'Recommended'"
                    )

    if errors:
        print("URAAM debloat configuration validation FAILED:")
        for error in errors:
            print(f" - {error}")
        return 1

    print(
        f"Validated {len(json_files)} selected JSON profiles; "
        f"{sum(1 for p in json_files if p.name.startswith('Safe-'))} Safe profiles "
        f"checked against UAD-NG revision {UAD_REVISION}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
