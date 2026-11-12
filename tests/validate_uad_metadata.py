#!/usr/bin/env python3
"""Validate the pinned UAD-NG metadata bundled with URAAM."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Configs" / "uad" / "uad_lists.json"
MANIFEST = ROOT / "Configs" / "uad" / "source.json"
RISKS = {"Recommended", "Advanced", "Expert", "Unsafe"}
CATEGORIES = {"Aosp", "Google", "Carrier", "Oem", "Misc"}


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


try:
    data = json.loads(DATA.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    fail(f"cannot read UAD metadata or manifest: {exc}")

if not isinstance(data, dict) or not data:
    fail("UAD metadata must be a non-empty JSON object")
if manifest.get("provider") != "Universal Debloater Alliance - Next Generation (UAD-NG)":
    fail("unexpected UAD metadata provider")
if manifest.get("source_revision") != "9fcad87bf78c52c4270504bc8880139d95a27a29":
    fail("UAD source revision changed without an explicit validator update")
if manifest.get("package_count") != len(data):
    fail("UAD package count does not match source manifest")
if manifest.get("policy", {}).get("auto_select") is not False:
    fail("UAD metadata must never enable automatic selection")

for package, entry in data.items():
    if not isinstance(package, str) or not package or any(ch.isspace() for ch in package):
        fail(f"invalid package key: {package!r}")
    if not isinstance(entry, dict):
        fail(f"{package}: metadata entry must be an object")
    if entry.get("removal") not in RISKS:
        fail(f"{package}: unsupported risk level {entry.get('removal')!r}")
    if entry.get("list") not in CATEGORIES:
        fail(f"{package}: unsupported UAD category {entry.get('list')!r}")
    if not isinstance(entry.get("description"), str):
        fail(f"{package}: description must be a string")
    for field in ("dependencies", "neededBy", "labels"):
        if not isinstance(entry.get(field), list):
            fail(f"{package}: {field} must be an array")

print(f"PASS: validated {len(data)} UAD-NG package records")
