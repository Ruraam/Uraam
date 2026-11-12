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

TEST_CONFIG="$TMP_DIR/profile.json"
cat > "$TEST_CONFIG" <<'JSON'
{
  "name": "Preview test",
  "apps": [
    {"packageName": "com.example.app"},
    {"packageName": "com.example.missing"},
    {"packageName": "com.android.systemui"},
    {"packageName": "com.samsung.android.bluetooth"}
  ]
}
JSON

require_backend() {
    EXEC_TYPE="ADB"
    BACKEND_SERIAL="TEST-SERIAL"
    CURRENT_MODEL="Mock Android device"
}
select_json_file() { SELECTED_FILE="$TEST_CONFIG"; }
device_package_list() {
    printf '%s\n' \
        'com.example.app' \
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
d
INPUT
grep -Fq '[WILL UNINSTALL] com.example.app' "$TMP_DIR/dry-run.out" ||
    fail "preview did not list the eligible package"
grep -Fq '[PROTECTED] com.android.systemui' "$TMP_DIR/dry-run.out" ||
    fail "preview did not identify exact-whitelist package"
grep -Fq '[PROTECTED] com.samsung.android.bluetooth' "$TMP_DIR/dry-run.out" ||
    fail "preview did not identify OEM-pattern protected package"
grep -Fq '[NOT INSTALLED] com.example.missing' "$TMP_DIR/dry-run.out" ||
    fail "preview did not identify absent package"
grep -Fq 'DRY RUN complete: 1 package(s)' "$TMP_DIR/dry-run.out" ||
    fail "dry-run summary incorrect"
(( ${#DEVICE_MUTATIONS[@]} == 0 )) || fail "dry-run executed a device mutation"
pass "dry-run previews exact actions and performs no mutation"

uraam_debloat > "$TMP_DIR/apply.out" 2>&1 <<'INPUT'
u
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
a
APPLY 4
INPUT
(( ${#DEVICE_MUTATIONS[@]} == 0 )) || fail "incorrect confirmation executed a mutation"
pass "incorrect operation count is rejected"

DEVICE_MUTATIONS=()
uraam_debloat > "$TMP_DIR/disable.out" 2>&1 <<'INPUT'
d
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
uraam_debloat > "$TMP_DIR/stale.out" 2>&1 <<'INPUT'
u
a
APPLY 1
INPUT
grep -Fq 'Device package state changed after preview' "$TMP_DIR/stale.out" ||
    fail "stale preview was not rejected"
(( ${#DEVICE_MUTATIONS[@]} == 0 )) || fail "stale preview executed a mutation"
pass "stale preview is rejected before execution"
