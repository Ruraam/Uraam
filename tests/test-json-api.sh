#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/mockbin"

cat > "$TMP_DIR/mockbin/adb" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
    devices)
        printf 'List of devices attached\nTEST-SERIAL\tdevice\n'
        ;;
    '-s TEST-SERIAL get-state')
        printf 'device\n'
        ;;
    '-s TEST-SERIAL shell getprop ro.product.manufacturer')
        printf 'TestCo\n'
        ;;
    '-s TEST-SERIAL shell getprop ro.product.model')
        printf 'TestPhone\n'
        ;;
    '-s TEST-SERIAL shell getprop ro.build.version.release')
        printf '15\n'
        ;;
    '-s TEST-SERIAL shell pm list packages --user 0')
        printf 'package:com.example.alpha\npackage:com.example.beta\n'
        ;;
    '-s TEST-SERIAL shell getprop '*)
        printf '\n'
        ;;
    *)
        printf 'Unexpected mocked ADB call: %s\n' "$*" >&2
        exit 2
        ;;
esac
MOCK
chmod +x "$TMP_DIR/mockbin/adb"

export PATH="$TMP_DIR/mockbin:$PATH"
export ANDROID_SERIAL=TEST-SERIAL

device_json="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '
    .status == "connected" and
    .backend == "ADB" and
    .serial == "TEST-SERIAL" and
    (.model | contains("TestPhone")) and
    .oem == "unknown"
' <<< "$device_json" >/dev/null

packages_json="$(bash "$ROOT/uraam-api.sh" list-packages)"
jq -e '
    .status == "ok" and
    .user == 0 and
    .count == 2 and
    (.packages | index("com.example.alpha") != null) and
    (.packages | index("com.example.beta") != null)
' <<< "$packages_json" >/dev/null

if bash "$ROOT/uraam-api.sh" apply >/dev/null 2>&1; then
    printf '%s\n' "FAIL: unsupported destructive command was accepted" >&2
    exit 1
fi

help_output="$(bash "$ROOT/uraam-api.sh" --help)"
grep -Fq 'read-only' <<< "$help_output"

printf '%s\n' "PASS: JSON device information, package inventory and read-only command boundary"
