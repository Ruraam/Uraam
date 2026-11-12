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
LOGD_DIR="$TMP_DIR/logs"
URAAM_OPERATION_JOURNAL="$LOGD_DIR/active-operation.json"
URAAM_APPLY_LOCK="$LOGD_DIR/apply.lock"
mkdir -p "$LOGD_DIR"

# Exercise the production timeout wrapper with mocked host executables.
eval "$(declare -f run_device_bounded | sed '1s/run_device_bounded/run_device_bounded_real/')"
mkdir -p "$TMP_DIR/mockbin"
cat > "$TMP_DIR/mockbin/timeout" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "--signal=TERM" ]] || exit 2
shift
case "$1" in
    --kill-after=1)
        shift
        [[ "$1" == "1s" && "$2 $3" == "sh -c" ]] || exit 2
        exit 0
        ;;
    --kill-after=5)
        shift
        [[ "$1" == "30s" ]] || exit 2
        shift
        [[ "${MOCK_TIMEOUT_MODE:-success}" != "expire" ]] || exit 124
        exec "$@"
        ;;
    *) exit 2 ;;
esac
MOCK
cat > "$TMP_DIR/mockbin/adb" <<'MOCK'
#!/usr/bin/env bash
printf invoked > "$TMP_DIR/adb-called"
[[ "$*" == "-s TEST-SERIAL shell pm list packages --user 0" ]] || exit 2
printf "package:com.example.app\\n"
MOCK
chmod +x "$TMP_DIR/mockbin/timeout" "$TMP_DIR/mockbin/adb"
PATH="$TMP_DIR/mockbin:$PATH"
export PATH
EXEC_TYPE="ADB"
BACKEND_SERIAL="TEST-SERIAL"
MOCK_TIMEOUT_MODE=success
export MOCK_TIMEOUT_MODE
run_device_bounded_real pm list packages --user 0 >/dev/null || fail "a command completing within its timeout was rejected"
(( DEVICE_COMMAND_TIMED_OUT == 0 )) || fail "successful bounded command was marked timed out"
MOCK_TIMEOUT_MODE=expire
export MOCK_TIMEOUT_MODE
if run_device_bounded_real pm list packages --user 0 >/dev/null 2>&1; then
    fail "a command exceeding its timeout should fail"
fi
(( DEVICE_COMMAND_TIMED_OUT == 1 )) || fail "timeout outcome was not recorded"
if device_package_list active >/dev/null 2>&1; then
    fail "a timed-out package inventory must be rejected"
fi
MOCK_TIMEOUT_MODE=success
export MOCK_TIMEOUT_MODE
pass "bounded commands accept timely responses and identify timeouts"
# Prefer a compatible gtimeout when the first timeout command is BusyBox-like.
cat > "$TMP_DIR/mockbin/timeout" <<'MOCK'
#!/usr/bin/env bash
exit 2
MOCK
cat > "$TMP_DIR/mockbin/gtimeout" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "--signal=TERM" ]] || exit 2
shift
[[ "$1" == "--kill-after=1" ]] && { shift; [[ "$1" == "1s" ]] && exit 0; }
[[ "$1" == "--kill-after=5" ]] || exit 2
shift 2
exec "$@"
MOCK
chmod +x "$TMP_DIR/mockbin/timeout" "$TMP_DIR/mockbin/gtimeout"
rm -f "$TMP_DIR/adb-called"
run_device_bounded_real pm list packages --user 0 >/dev/null || fail "compatible gtimeout fallback was not selected"

# If neither implementation supports the required options, fail before ADB.
cat > "$TMP_DIR/mockbin/gtimeout" <<'MOCK'
#!/usr/bin/env bash
exit 2
MOCK
chmod +x "$TMP_DIR/mockbin/gtimeout"
rm -f "$TMP_DIR/adb-called"
if run_device_bounded_real pm list packages --user 0 >/dev/null 2>&1; then
    fail "unsupported timeout implementations must be rejected"
fi
[[ ! -e "$TMP_DIR/adb-called" ]] || fail "ADB was invoked without a compatible timeout utility"
pass "unsupported timeout implementations fail closed and gtimeout fallback works"
# The rest of the suite mocks the device backend while keeping the production
# debloat preview/apply orchestration under test.
run_device_bounded() { DEVICE_COMMAND_TIMED_OUT=0; run_device "$@"; }


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

# A partial response containing valid package rows plus an error must fail closed.
run_device() {
    printf 'package:com.example.app\nError: device disconnected\n'
    return 0
}
if device_package_list active >/dev/null 2>&1; then
    fail "partial package inventory mixed with an error must be rejected"
fi
run_device() {
    printf 'package:com.example.app\n'
    return 1
}
if device_package_list active >/dev/null 2>&1; then
    fail "a failed Android package-list command must be rejected"
fi
pass "partial and failed Android package inventories are rejected"

# Exercise the real backend transport probe for ADB and Shizuku.
MOCK_ADB_STATE="device"
adb() {
    [[ "$1 $2 $3" == "-s TEST-SERIAL get-state" ]] || return 2
    printf '%s\n' "$MOCK_ADB_STATE"
}
EXEC_TYPE="ADB"
BACKEND_SERIAL="TEST-SERIAL"
backend_is_available || fail "ADB device state 'device' should be available"
MOCK_ADB_STATE="offline"
if backend_is_available; then fail "offline ADB transport must be unavailable"; fi

MOCK_RISH_AVAILABLE=1
rish() {
    [[ "$1 $2" == "-c id" ]] && (( MOCK_RISH_AVAILABLE ))
}
EXEC_TYPE="SHIZUKU"
backend_is_available || fail "active Shizuku transport should be available"
MOCK_RISH_AVAILABLE=0
if backend_is_available; then fail "inactive Shizuku transport must be unavailable"; fi
EXEC_TYPE="ADB"
BACKEND_SERIAL="TEST-SERIAL"
pass "ADB and Shizuku transport health checks"

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
DEVICE_BRAND_CALLS=0
CHANGE_DEVICE_ON_RECHECK=0
device_brand() {
    ((DEVICE_BRAND_CALLS+=1))
    if (( CHANGE_DEVICE_ON_RECHECK && DEVICE_BRAND_CALLS >= 2 )); then
        CURRENT_MODEL="Different Android device"
    else
        CURRENT_MODEL="Mock Android device"
    fi
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
SIMULATE_DISCONNECT_ON_MUTATION=0
backend_is_available() {
    if (( SIMULATE_DISCONNECT_ON_MUTATION )) &&
        (( ${#DEVICE_MUTATIONS[@]} >= 1 )); then
        return 1
    fi
    return 0
}
run_device() {
    DEVICE_MUTATIONS+=("$*")
    if (( SIMULATE_DISCONNECT_ON_MUTATION )) &&
        (( ${#DEVICE_MUTATIONS[@]} == 1 )); then
        return 1
    fi
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

# A different model on the same ADB transport must invalidate the preview.
# Restore the normal inventory mock after the preceding stale-inventory case.
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
DEVICE_MUTATIONS=()
DEVICE_BRAND_CALLS=0
CHANGE_DEVICE_ON_RECHECK=1
if uraam_debloat > "$TMP_DIR/device-swap.out" 2>&1 <<'INPUT'
u
1
a
APPLY 1
INPUT
then
    fail "device model change should abort the preview"
fi
grep -Fq 'Device model, OEM or ROM identity changed after preview' "$TMP_DIR/device-swap.out" ||
    fail "device model change was not reported"
(( ${#DEVICE_MUTATIONS[@]} == 0 )) || fail "device swap executed a mutation"
CHANGE_DEVICE_ON_RECHECK=0
pass "device model changes invalidate stale previews"

# A transport loss during the first operation must stop the rest of the batch.
DEVICE_MUTATIONS=()
SIMULATE_DISCONNECT_ON_MUTATION=1
if uraam_debloat > "$TMP_DIR/disconnect.out" 2>&1 <<'INPUT'
u
1,2
a
APPLY 2
INPUT
then
    : # Partial batch is reported in the summary; transport loss is fail-safe.
fi
(( ${#DEVICE_MUTATIONS[@]} == 1 )) ||
    fail "a disconnected backend must not receive later package operations"
grep -Fq 'Backend disconnected during operation; stopping the batch.' "$TMP_DIR/disconnect.out" ||
    fail "mid-operation backend loss was not reported"
grep -Fq '1 succeeded' "$TMP_DIR/disconnect.out" && fail "failed first operation was incorrectly counted as success"
grep -Fq '1 failed' "$TMP_DIR/disconnect.out" ||
    fail "failed operation was not counted"
grep -Fq '1 skipped' "$TMP_DIR/disconnect.out" ||
    fail "remaining package was not counted as skipped"
SIMULATE_DISCONNECT_ON_MUTATION=0
pass "backend loss during an operation stops the remaining batch"
# The previous failed transport operation is uncertain; explicitly reconcile it
# before starting a separate test batch, just as a user must do after a failure.
recover_pending_operation <<< "RECONCILE com.example.app" ||
    fail "pending disconnect operation could not be reconciled"
[[ ! -e "$URAAM_OPERATION_JOURNAL" ]] ||
    fail "disconnect recovery did not clear the journal"

# A timed-out destructive command has an unknown outcome: never retry it or
# send subsequent mutations in the same batch.
DEVICE_MUTATIONS=()
SIMULATE_DISCONNECT_ON_MUTATION=0
run_device_bounded() {
    if [[ "$*" == "pm uninstall -k --user 0 com.example.app" ]]; then
        DEVICE_MUTATIONS+=("$*")
        DEVICE_COMMAND_TIMED_OUT=1
        return 124
    fi
    run_device "$@"
}
uraam_debloat > "$TMP_DIR/timeout.out" 2>&1 <<'INPUT'
u
1,2
a
APPLY 2
INPUT
(( ${#DEVICE_MUTATIONS[@]} == 1 )) || fail "a timed-out destructive command must not be retried or followed by another mutation"
grep -Fq "Uninstall timed out; its outcome is unknown" "$TMP_DIR/timeout.out" ||
    fail "unknown outcome after uninstall timeout was not reported"
grep -Fq "1 failed" "$TMP_DIR/timeout.out" || fail "timed-out package was not counted as failed"
grep -Fq "1 skipped" "$TMP_DIR/timeout.out" || fail "remaining package was not skipped after timeout"
pass "destructive timeout stops batch without retrying an uncertain operation"

# The timeout path must leave a durable, private journal that survives process exit.
[[ -f "$URAAM_OPERATION_JOURNAL" ]] || fail "uncertain operation journal was not persisted"
[[ "$(jq -r '.state' "$URAAM_OPERATION_JOURNAL")" == "uncertain" ]] ||
    fail "timed-out operation journal was not marked uncertain"
[[ "$(stat -c '%a' "$URAAM_OPERATION_JOURNAL")" == "600" ]] ||
    fail "operation journal permissions are not 0600"
pass "uncertain operations persist a private recovery journal"

# Simulate a process crash after the pre-command journal write.
write_operation_journal started uninstall com.example.crash 1 1 ||
    fail "could not create simulated crash journal"
[[ "$(jq -r '.state' "$URAAM_OPERATION_JOURNAL")" == "started" ]] ||
    fail "pre-command journal state was not persisted"
device_package_list() { printf '%s\n' com.example.other; }
if recover_pending_operation <<< "NO"; then
    fail "recovery must require explicit acknowledgement"
fi
[[ -f "$URAAM_OPERATION_JOURNAL" ]] || fail "unconfirmed recovery removed the journal"
recover_pending_operation <<< "RECONCILE com.example.crash" ||
    fail "explicit recovery acknowledgement was rejected"
[[ ! -e "$URAAM_OPERATION_JOURNAL" ]] || fail "reconciled journal was not cleared"
(( ${#DEVICE_MUTATIONS[@]} == 1 )) || fail "recovery replayed a destructive command"
pass "crash journal requires inventory review and explicit reconciliation without replay"

# A reused ADB serial must not allow recovery on a different physical model.
write_operation_journal started uninstall com.example.swap 1 1 ||
    fail "could not create device-identity recovery journal"
RECOVERY_INVENTORY_CALLS=0
device_package_list() {
    ((RECOVERY_INVENTORY_CALLS+=1))
    printf '%s\n' com.example.swap
}
CURRENT_MODEL="Different Android device"
if recover_pending_operation <<< "RECONCILE com.example.swap" >/dev/null 2>&1; then
    fail "recovery accepted a different model on a reused ADB serial"
fi
(( RECOVERY_INVENTORY_CALLS == 0 )) ||
    fail "inventory was queried before device identity was validated"
[[ -f "$URAAM_OPERATION_JOURNAL" ]] ||
    fail "device-identity mismatch removed the pending journal"
CURRENT_MODEL="Mock Android device"
recover_pending_operation <<< "RECONCILE com.example.swap" >/dev/null ||
    fail "recovery on the original device identity was rejected"
pass "recovery rejects a changed device model even when the ADB serial is reused"

# Reconciliation must fail closed if ADB is offline before inventory retrieval.
write_operation_journal started uninstall com.example.reconnect 1 1 ||
    fail "could not create reconnect recovery journal"
RECOVERY_INVENTORY_CALLS=0
RECOVERY_TRANSPORT_AVAILABLE=0
RECOVERY_INVENTORY_FAIL=0
backend_is_available() { (( RECOVERY_TRANSPORT_AVAILABLE )); }
device_package_list() {
    ((RECOVERY_INVENTORY_CALLS+=1))
    (( RECOVERY_INVENTORY_FAIL == 0 )) || return 1
    printf '%s\n' com.example.reconnect
}
if recover_pending_operation <<< "RECONCILE com.example.reconnect" >/dev/null 2>&1; then
    fail "recovery proceeded while ADB was offline"
fi
[[ -f "$URAAM_OPERATION_JOURNAL" ]] ||
    fail "offline transport removed the pending journal"
(( RECOVERY_INVENTORY_CALLS == 0 )) ||
    fail "offline transport triggered an inventory query"

# Simulate ADB dropping after preflight but during the inventory request.
RECOVERY_TRANSPORT_AVAILABLE=1
RECOVERY_INVENTORY_FAIL=1
if recover_pending_operation <<< "RECONCILE com.example.reconnect" >/dev/null 2>&1; then
    fail "recovery accepted an incomplete inventory after transport loss"
fi
[[ -f "$URAAM_OPERATION_JOURNAL" ]] ||
    fail "inventory transport failure removed the pending journal"

# Reconnect the original device and reconcile explicitly; no command is replayed.
RECOVERY_INVENTORY_FAIL=0
recover_pending_operation <<< "RECONCILE com.example.reconnect" >/dev/null ||
    fail "recovery did not resume after the original device reconnected"
[[ ! -e "$URAAM_OPERATION_JOURNAL" ]] ||
    fail "successful reconnect reconciliation did not clear the journal"
(( RECOVERY_INVENTORY_CALLS == 2 )) ||
    fail "unexpected number of inventory attempts across disconnect/reconnect"
pass "recovery retains the journal across ADB loss and succeeds after reconnect"

# Corrupt journals must fail closed.
printf '{invalid json' > "$URAAM_OPERATION_JOURNAL"
if recover_pending_operation >/dev/null 2>&1; then
    fail "corrupt operation journal must block recovery"
fi
pass "corrupt recovery journal fails closed"

# flock must exclude a second independent apply lock holder.
acquire_apply_lock || fail "first apply lock acquisition failed"
if flock -n "$URAAM_APPLY_LOCK" -c true >/dev/null 2>&1; then
    release_apply_lock
    fail "a concurrent process acquired an already-held apply lock"
fi
release_apply_lock
pass "concurrent apply sessions are excluded by the device lock"
