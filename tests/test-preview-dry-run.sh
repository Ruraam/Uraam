#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export URAAM_TESTING=1
# shellcheck source=../uraam.sh
source "$ROOT/uraam.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Exercise the real inventory parser and ensure preview queries installed-only packages.
run_device() {
    printf '%s' "$*" > "$TMP_DIR/last-command"
    printf 'package:com.example.app\npackage:com.android.systemui\n'
}
device_package_list active > "$TMP_DIR/inventory.out" || fail "valid package inventory rejected"
inventory="$(cat "$TMP_DIR/inventory.out")"
[[ "$(cat "$TMP_DIR/last-command")" == 'pm list packages --user 0' ]] ||
    fail "preview inventory must exclude packages uninstalled for user 0"
grep -Fxq 'com.example.app' <<< "$inventory" || fail "package inventory parsing lost a package"
run_device() { printf 'device offline\n'; }
# shellcheck disable=SC2218 # Defined in the sourced URAAM script.
if device_package_list all >/dev/null 2>&1; then
    fail "empty/unrecognized package inventory must be rejected"
fi
pass "package inventory parsing fails closed and uses installed-only mode"

is_whitelisted com.android.systemui || fail "exact whitelist not enforced"
is_whitelisted com.samsung.android.bluetooth || fail "Bluetooth family pattern not enforced"
is_whitelisted com.samsung.android.knox.kpecore || fail "Knox family pattern not enforced"
pass "critical package protections"

# Mock OEM properties to verify normalization and advisory profile matching.
device_getprop() {
    case "$1" in
        ro.product.manufacturer) printf '%s\n' Xiaomi ;;
        ro.product.brand) printf '%s\n' Redmi ;;
        *) printf '\n' ;;
    esac
}
[[ "$(device_oem_family)" == "xiaomi" ]] || fail "Xiaomi/Redmi OEM detection failed"
[[ "$(oem_profile_status_for_package com.miui.analytics xiaomi)" == "MATCH" ]] ||
    fail "package present in Xiaomi Safe profile was not recognized"
[[ "$(oem_profile_status_for_package com.example.app xiaomi)" == "NOT_LISTED" ]] ||
    fail "package absent from Xiaomi Safe profile was not marked advisory NOT_LISTED"
[[ "$(oem_profile_status_for_package com.example.app unknown)" == "UNKNOWN" ]] ||
    fail "unknown OEM should remain UNKNOWN"
pass "OEM identity normalization and advisory profile matching"

# ROM/version detection uses vendor build properties and stays conservative.
device_getprop() {
    case "$1" in
        ro.product.manufacturer) printf '%s\n' Samsung ;;
        ro.product.brand) printf '%s\n' samsung ;;
        ro.build.version.oneui) printf '%s\n' 8.5 ;;
        ro.build.version.release) printf '%s\n' 16 ;;
        *) printf '\n' ;;
    esac
}
[[ "$(device_rom_info)" == "One UI|8.5" ]] ||
    fail "One UI version detection returned: $(device_rom_info)"

device_getprop() {
    case "$1" in
        ro.product.manufacturer) printf '%s\n' Xiaomi ;;
        ro.product.brand) printf '%s\n' POCO ;;
        ro.mi.os.version.name) printf '%s\n' 2.0.1 ;;
        ro.build.version.release) printf '%s\n' 15 ;;
        *) printf '\n' ;;
    esac
}
[[ "$(device_rom_info)" == "HyperOS|2.0.1" ]] ||
    fail "HyperOS version detection returned: $(device_rom_info)"

device_getprop() {
    case "$1" in
        ro.product.manufacturer) printf '%s\n' Google ;;
        ro.product.brand) printf '%s\n' Pixel ;;
        ro.lineage.version) printf '%s\n' 22.2 ;;
        ro.build.version.release) printf '%s\n' 15 ;;
        *) printf '\n' ;;
    esac
}
[[ "$(device_rom_info)" == "LineageOS|22.2" ]] ||
    fail "custom ROM should take precedence over OEM default: $(device_rom_info)"

device_getprop() {
    case "$1" in
        ro.product.manufacturer) printf '%s\n' OnePlus ;;
        ro.product.brand) printf '%s\n' OnePlus ;;
        ro.build.version.release) printf '%s\n' 16 ;;
        *) printf '\n' ;;
    esac
}
[[ "$(device_rom_info)" == "Unknown ROM|16" ]] ||
    fail "unknown vendor ROM must not be guessed: $(device_rom_info)"
pass "ROM family/version detection and conservative fallback"

TEST_CONFIG="$TMP_DIR/profile.json"
UAD_METADATA_FILE="$TMP_DIR/uad_lists.json"
cat > "$UAD_METADATA_FILE" <<'JSON'
{
  "com.example.app": {
    "list": "Oem",
    "description": "A recommended test application.",
    "removal": "Recommended",
    "dependencies": ["com.example.framework"],
    "neededBy": ["com.example.consumer"]
  },
  "com.example.expert": {
    "list": "Google",
    "description": "An expert-only test application.",
    "removal": "Expert"
  },
  "com.example.unsafe": {
    "list": "Aosp",
    "description": "Never remove this critical test package.",
    "removal": "Unsafe"
  }
}
JSON
cat > "$TEST_CONFIG" <<'JSON'
{
  "name": "Preview test",
  "apps": [
    {"packageName": "com.example.app"},
    {"packageName": "com.example.expert"},
    {"packageName": "com.example.unsafe"},
    {"packageName": "com.example.unknown"},
    {"packageName": "com.example.missing"},
    {"packageName": "com.android.systemui"},
    {"packageName": "com.samsung.android.bluetooth"}
  ]
}
JSON

mapfile -t direct_dependencies < <(uad_relationships_for_package "com.example.app" dependencies)
[[ "${direct_dependencies[0]:-}" == "com.example.framework" ]] ||
    fail "UAD dependency parser returned: ${direct_dependencies[*]:-<empty>}"
mapfile -t direct_needed_by < <(uad_relationships_for_package "com.example.app" neededBy)
[[ "${direct_needed_by[0]:-}" == "com.example.consumer" ]] ||
    fail "UAD reverse-dependency parser returned: ${direct_needed_by[*]:-<empty>}"

require_backend() {
    EXEC_TYPE="ADB"
    BACKEND_SERIAL="TEST-SERIAL"
    CURRENT_MODEL="Mock Android device"
}
select_json_file() { SELECTED_FILE="$TEST_CONFIG"; }
device_package_list() {
    printf '%s\n' \
        'com.example.app' \
        'com.example.expert' \
        'com.example.unsafe' \
        'com.example.unknown' \
        'com.example.framework' \
        'com.example.consumer' \
        'com.android.systemui' \
        'com.samsung.android.bluetooth'
}
show_logo() { :; }
pause() { :; }
start_log() { LOGFILE="$TMP_DIR/test.log"; return 0; }
DEVICE_MUTATIONS=()
run_device() {
    DEVICE_MUTATIONS+=("$*")
    return 0
}

uraam_debloat > "$TMP_DIR/dry-run.out" 2>&1 <<'INPUT'
u
1
d
INPUT
grep -Fq '[1] [Recommended] [Oem] com.example.app' "$TMP_DIR/dry-run.out" ||
    fail "UAD Recommended metadata was not displayed"
grep -Fq '[2] [Expert] [Google] com.example.expert' "$TMP_DIR/dry-run.out" ||
    fail "UAD Expert metadata was not displayed"
grep -Fq '[BLOCKED] [UNSAFE] [Aosp] com.example.unsafe' "$TMP_DIR/dry-run.out" ||
    fail "Unsafe package was not blocked"
grep -Fq '[BLOCKED] [UNKNOWN] [Unlisted] com.example.unknown' "$TMP_DIR/dry-run.out" ||
    fail "Unknown UAD package was not blocked"
grep -Fq '[NOT SELECTED] [Expert] com.example.expert' "$TMP_DIR/dry-run.out" ||
    fail "unselected Expert package was not explicitly excluded"
grep -Fq '[WILL UNINSTALL] [Recommended] com.example.app' "$TMP_DIR/dry-run.out" ||
    fail "preview did not list the eligible package"
grep -Fq '[PROTECTED BY URAAM] com.android.systemui' "$TMP_DIR/dry-run.out" ||
    fail "preview did not identify exact-whitelist package"
grep -Fq '[PROTECTED BY URAAM] com.samsung.android.bluetooth' "$TMP_DIR/dry-run.out" ||
    fail "preview did not identify OEM-pattern protected package"
grep -Fq '[NOT INSTALLED] com.example.missing' "$TMP_DIR/dry-run.out" ||
    fail "preview did not identify absent package"
grep -Fq '[DEPENDENCY INSTALLED] com.example.framework' "$TMP_DIR/dry-run.out" || {
    cat "$TMP_DIR/dry-run.out" >&2
    fail "selected package dependency was not shown as installed"
}
grep -Fq 'Installed dependent may be affected: com.example.consumer relies on com.example.app' "$TMP_DIR/dry-run.out" ||
    fail "installed reverse dependency warning was not displayed"
grep -Fq 'Dependency metadata is advisory and non-exhaustive' "$TMP_DIR/dry-run.out" ||
    fail "non-exhaustive dependency caveat was not displayed"
grep -Fq 'DRY RUN complete: 1 manually selected package(s)' "$TMP_DIR/dry-run.out" ||
    fail "dry-run summary incorrect"
(( ${#DEVICE_MUTATIONS[@]} == 0 )) || fail "dry-run executed a device mutation"
pass "dry-run previews exact actions and performs no mutation"

uraam_debloat > "$TMP_DIR/apply.out" 2>&1 <<'INPUT'
u
1
a
APPLY 1
INPUT
(( ${#DEVICE_MUTATIONS[@]} == 1 )) || fail "expected exactly one uninstall command"
[[ "${DEVICE_MUTATIONS[0]}" == 'pm uninstall -k --user 0 com.example.app' ]] ||
    fail "unexpected command executed: ${DEVICE_MUTATIONS[0]}"
pass "apply requires exact count and executes only eligible packages"

DEVICE_MUTATIONS=()
uraam_debloat > "$TMP_DIR/reject.out" 2>&1 <<'INPUT'
u
1
a
APPLY 4
INPUT
(( ${#DEVICE_MUTATIONS[@]} == 0 )) || fail "incorrect confirmation executed a mutation"
pass "incorrect operation count is rejected"

DEVICE_MUTATIONS=()
uraam_debloat > "$TMP_DIR/disable.out" 2>&1 <<'INPUT'
d
1
a
APPLY 1
INPUT
(( ${#DEVICE_MUTATIONS[@]} == 1 )) || fail "expected exactly one disable command"
[[ "${DEVICE_MUTATIONS[0]}" == 'pm disable-user --user 0 com.example.app' ]] ||
    fail "unexpected disable command: ${DEVICE_MUTATIONS[0]}"
pass "disable preview and apply path"

DEVICE_MUTATIONS=()
device_package_list() {
    if [[ ! -e "$TMP_DIR/first-inventory" ]]; then
        : > "$TMP_DIR/first-inventory"
        printf '%s\n' 'com.example.app' 'com.android.systemui' 'com.samsung.android.bluetooth'
    else
        printf '%s\n' 'com.android.systemui' 'com.samsung.android.bluetooth'
    fi
}
if uraam_debloat > "$TMP_DIR/stale.out" 2>&1 <<'INPUT'
u
1
a
APPLY 1
INPUT
then
    fail "stale preview should abort with a non-zero status"
fi
grep -Fq 'Device or UAD safety state changed after preview' "$TMP_DIR/stale.out" ||
    fail "stale preview was not rejected"
(( ${#DEVICE_MUTATIONS[@]} == 0 )) || fail "stale preview executed a mutation"
pass "stale preview is rejected before execution"
