#!/usr/bin/env bash
# Regression tests for bounded read-only API device output.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

cat > "$TMP_DIR/mock-engine.sh" <<'MOCK'
URAAM_VERSION="5.1.0"
EXEC_TYPE="ADB"
BACKEND_SERIAL="MOCK-SERIAL"
CURRENT_MODEL="Mock Android"
detect_backend_status() { :; }
backend_is_available() { return 0; }
device_brand() { :; }
device_rom_info() { printf 'Mock ROM|1\n'; }
device_oem_family() { printf 'mock\n'; }

run_device_bounded() {
    case "$*" in
        "pm path --user 0 com.example.demo")
            printf 'package:/data/app/com.example.demo/base.apk\n'
            ;;
        "dumpsys package com.example.demo")
            # Deliberately exceed the configured 4 KiB capture ceiling.
            head -c 8192 /dev/zero | base64 -w0
            ;;
        "pm list packages --user 0")
            # A syntactically valid but oversized inventory.
            for ((i=0; i<300; i++)); do
                printf 'package:com.example.generated.package%04d\n' "$i"
            done
            ;;
        "pm list packages -s --user 0"|"pm list packages -3 --user 0")
            printf '\n'
            ;;
        *)
            printf 'Unexpected mock device command: %s\n' "$*" >&2
            return 2
            ;;
    esac
}
MOCK

export URAAM_SCRIPT="$TMP_DIR/mock-engine.sh"
export URAAM_API_MAX_INVENTORY_BYTES=1024
export URAAM_API_MAX_DUMPSYS_BYTES=4096
export URAAM_API_MAX_PATHS_BYTES=4096

package_json="$(bash "$ROOT/uraam-api.sh" package-info:com.example.demo)"
jq -e '
    .status == "ok" and
    .paths == ["/data/app/com.example.demo/base.apk"] and
    .version_name == null and
    .version_code == null and
    .requested_permissions == null and
    .components.activities == null and
    .metadata_limited == true and
    .read_only == true
' <<< "$package_json" >/dev/null

if inventory_json="$(bash "$ROOT/uraam-api.sh" list-packages 2>/dev/null)"; then
    printf '%s\n' "FAIL: oversized inventory was accepted" >&2
    exit 1
fi
jq -e '
    .status == "error" and
    (.error | contains("exceeds the API size limit"))
' <<< "$inventory_json" >/dev/null

printf '%s\n' "PASS: oversized dumpsys metadata degrades to null without losing APK paths"
printf '%s\n' "PASS: oversized package inventory is rejected without returning partial data"
