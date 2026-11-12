#!/usr/bin/env python3
"""Validate bundled URAAM debloat JSON presets without touching a device."""

import json
import re
import sys
from pathlib import Path

CONFIG_DIR = Path("Configs/debloat")
PACKAGE_ID = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$")

# Keep aligned with SAFETY_WHITELIST in uraam.sh.
PROTECTED_PACKAGES = {
    "android",
    "com.android.systemui",
    "com.android.settings",
    "com.android.settings.intelligence",
    "com.android.keyguard",
    "com.android.wallpaper.livepicker",
    "com.android.packageinstaller",
    "com.android.permissioncontroller",
    "com.google.android.permissioncontroller",
    "com.google.android.packageinstaller",
    "com.android.phone",
    "com.android.server.telecom",
    "com.android.providers.telephony",
    "com.android.emergency",
    "com.android.providers.settings",
    "com.android.providers.media",
    "com.android.providers.downloads",
    "com.android.providers.contacts",
    "com.android.keychain",
    "com.android.certinstaller",
    "com.android.inputdevices",
    "com.google.android.gms",
    "com.google.android.gsf",
    "com.android.vending",
    "com.android.dialer",
    "com.android.nfc",
    "com.android.setupwizard",
    "com.google.android.setupwizard",
    "org.lineageos.setupwizard",
    "com.sec.android.app.SecSetupWizard",
    "com.android.emergency.auto_generated_rro_product__",
    "com.android.providers.settings.auto_generated_rro_product__",
    "com.android.providers.settings.overlay.product.gs101",
    "com.android.providers.telephony.overlay.product.gs101",
    "com.android.server.telecom.overlay.product.gs101",
    "org.lineageos.setupwizard.auto_generated_rro_product__",
    "com.android.imsserviceentitlement",
    "com.google.android.grilservice",
    "com.samsung.slsi.telephony.oemril",
    "com.samsung.slsi.telephony.oem.oemrilhookservice",
    "com.shannon.imsservice",
    "com.google.RilConfigService",
    "com.sec.android.app.bluetoothagent",
    "com.sec.android.app.setupwizardlegalprovider",
    "com.samsung.android.knox.attestation",
    "com.telstra.telephony.exttelephony",
}


def main() -> int:
    files = sorted(CONFIG_DIR.glob("*.json"))
    if not files:
        print(f"ERROR: no JSON presets found in {CONFIG_DIR}", file=sys.stderr)
        return 1

    errors = []
    package_count = 0

    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            errors.append(f"{path}: invalid JSON: {exc}")
            continue

        if not isinstance(data, dict):
            errors.append(f"{path}: root must be a JSON object")
            continue

        for field in ("name", "description", "author", "version"):
            if not isinstance(data.get(field), str) or not data[field].strip():
                errors.append(f"{path}: missing or invalid '{field}' metadata")

        apps = data.get("apps")
        if not isinstance(apps, list) or not apps:
            errors.append(f"{path}: 'apps' must be a non-empty array")
            continue

        seen = set()
        for index, app in enumerate(apps):
            if not isinstance(app, dict):
                errors.append(f"{path}: apps[{index}] must be an object")
                continue
            package = app.get("packageName")
            if not isinstance(package, str) or not PACKAGE_ID.fullmatch(package):
                errors.append(f"{path}: apps[{index}] has an invalid packageName")
                continue
            package_count += 1
            if package in seen:
                errors.append(f"{path}: duplicate package '{package}'")
            seen.add(package)
            if package in PROTECTED_PACKAGES:
                errors.append(f"{path}: protected Android package '{package}' must not be listed")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"Validated {len(files)} JSON presets ({package_count} package entries).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
