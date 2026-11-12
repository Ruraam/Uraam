#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export URAAM_TESTING=1
# shellcheck source=../uraam.sh
source "$ROOT/uraam.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || fail "jq is required"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT
LOGD_DIR="$TMP_DIR/logs"
URAAM_OPERATION_JOURNAL="$LOGD_DIR/active-operation.json"
URAAM_APPLY_LOCK="$LOGD_DIR/apply.lock"
mkdir -p -- "$LOGD_DIR"

EXEC_TYPE="ADB"
BACKEND_SERIAL="TEST-SERIAL"
CURRENT_MODEL="Test device"
COMMAND_STARTED="$TMP_DIR/command-started"

# Run the real journal writer in a child, then block inside the mocked device
# command. SIGKILL cannot run shell traps or cleanup, matching abrupt death.
(
    run_device_bounded() {
        : > "$COMMAND_STARTED"
        while :; do :; done
    }
    write_operation_journal started uninstall com.example.crash 1 1 ||
        exit 20
    run_device_bounded pm uninstall -k --user 0 com.example.crash
) &
child_pid=$!

for _ in $(seq 1 200); do
    [[ -e "$COMMAND_STARTED" ]] && break
    kill -0 "$child_pid" 2>/dev/null || fail "child exited before entering the mocked device command"
    sleep 0.05
done
[[ -e "$COMMAND_STARTED" ]] || fail "child never entered the mocked device command"
[[ -f "$URAAM_OPERATION_JOURNAL" ]] || fail "journal was not persisted before the command started"
[[ "$(jq -r '.state' "$URAAM_OPERATION_JOURNAL")" == "started" ]] ||
    fail "journal did not retain the in-flight started state"

kill -KILL "$child_pid" 2>/dev/null || fail "could not SIGKILL the child process"
wait "$child_pid" 2>/dev/null || true

[[ -f "$URAAM_OPERATION_JOURNAL" ]] || fail "journal disappeared after SIGKILL"
[[ "$(jq -r '.package' "$URAAM_OPERATION_JOURNAL")" == "com.example.crash" ]] ||
    fail "journal package was not preserved after SIGKILL"
pass "SIGKILL during a mocked device operation leaves the pre-operation journal intact"

# Restart-side recovery must inspect inventory and require explicit human
# acknowledgement. It must never call the destructive device command again.
# The test has no physical Android device. Model a connected ADB
# transport so recovery can exercise inventory and explicit acknowledgement.
backend_is_available() { return 0; }
device_package_list() {
    [[ "$1" == active ]] || return 2
    printf '%s\n' com.example.crash
}
recover_pending_operation <<< "NO" >/dev/null 2>&1 &&
    fail "recovery accepted an unconfirmed operation"
[[ -f "$URAAM_OPERATION_JOURNAL" ]] || fail "unconfirmed recovery removed the journal"

recover_pending_operation <<< "RECONCILE com.example.crash" ||
    fail "manual reconciliation failed"
[[ ! -e "$URAAM_OPERATION_JOURNAL" ]] || fail "manual reconciliation did not clear the journal"
[[ -e "$COMMAND_STARTED" ]] || fail "command-start marker unexpectedly disappeared"
pass "restart recovery requires inventory review and explicit acknowledgement"
pass "recovery does not replay the interrupted destructive command"
