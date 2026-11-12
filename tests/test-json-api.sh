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
        printf 'package:com.example.alpha\npackage:com.example.beta\npackage:com.example.system\n'
        ;;
    '-s TEST-SERIAL shell pm list packages -s --user 0')
        printf 'package:com.example.system\n'
        ;;
    '-s TEST-SERIAL shell pm list packages -3 --user 0')
        printf 'package:com.example.alpha\npackage:com.example.beta\n'
        ;;
    '-s TEST-SERIAL shell pm path --user 0 com.example.alpha')
        printf 'package:/data/app/~~abc/com.example.alpha/base.apk\n'
        ;;
    '-s TEST-SERIAL shell dumpsys package com.example.alpha')
        printf 'Package [com.example.alpha] (123):\n    versionCode=42 minSdk=23 targetSdk=35\n    versionName=1.2.3\n    requested permissions:\n      android.permission.INTERNET\n      android.permission.CAMERA\n    install permissions:\n      android.permission.INTERNET: granted=true\n    Activities:\n      com.example.alpha/.MainActivity filter abc\n      com.example.alpha/com.example.alpha.SettingsActivity filter def\n    Services:\n      com.example.alpha/.SyncService\n    Receivers:\n      com.example.alpha/.BootReceiver\n    Providers:\n      com.example.alpha/.DataProvider\n'
        ;;
    '-s TEST-SERIAL shell pm path --user 0 com.example.legacy')
        printf 'package:/data/app/com.example.legacy/base.apk\n'
        ;;
    '-s TEST-SERIAL shell dumpsys package com.example.legacy')
        printf 'Package [com.example.legacy] (456):\n    versionName=2.0\n    Providers:\n      com.example.legacy/.StoreProvider\n    Activities:\n      com.example.legacy/.HomeActivity filter xyz\n      com.other.app/.ForeignActivity filter xyz\n      ResolverTableEntry com.example.legacy/.NotAComponent\n    Services:\n    Receivers:\n      com.example.legacy/com.example.legacy.BootReceiver\n'
        ;;
    '-s TEST-SERIAL shell pm path --user 0 com.example.nosections')
        printf 'package:/data/app/com.example.nosections/base.apk\n'
        ;;
    '-s TEST-SERIAL shell dumpsys package com.example.nosections')
        printf 'Package [com.example.nosections] (789):\n    versionName=3.0\n    requested permissions:\n      android.permission.INTERNET\n'
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

package_info="$(bash "$ROOT/uraam-api.sh" package-info:com.example.alpha)"
jq -e '
    .status == "ok" and
    .package == "com.example.alpha" and
    .backend == "ADB" and
    .version_name == "1.2.3" and
    .version_code == "42" and
    .requested_permissions == ["android.permission.INTERNET", "android.permission.CAMERA"] and
    .permissions_semantics == "requested_only_not_grant_status" and
    .components.activities == ["com.example.alpha/.MainActivity", "com.example.alpha/com.example.alpha.SettingsActivity"] and
    .components.services == ["com.example.alpha/.SyncService"] and
    .components.receivers == ["com.example.alpha/.BootReceiver"] and
    .components.providers == ["com.example.alpha/.DataProvider"] and
    .components_semantics == "entries_from_matching_dumpsys_sections_only" and
    .paths == ["/data/app/~~abc/com.example.alpha/base.apk"] and
    .read_only == true
' <<< "$package_info" >/dev/null

legacy_info="$(bash "$ROOT/uraam-api.sh" package-info:com.example.legacy)"
jq -e '
    .status == "ok" and
    .components.activities == ["com.example.legacy/.HomeActivity"] and
    .components.services == [] and
    .components.receivers == ["com.example.legacy/com.example.legacy.BootReceiver"] and
    .components.providers == ["com.example.legacy/.StoreProvider"]
' <<< "$legacy_info" >/dev/null

missing_info="$(bash "$ROOT/uraam-api.sh" package-info:com.example.nosections)"
jq -e '
    .status == "ok" and
    .components.activities == null and
    .components.services == null and
    .components.receivers == null and
    .components.providers == null and
    .requested_permissions == ["android.permission.INTERNET"]
' <<< "$missing_info" >/dev/null

if bash "$ROOT/uraam-api.sh" 'package-info:com.example.alpha;id' >/dev/null 2>&1; then
    printf '%s\\n' "FAIL: malformed package identifier was accepted" >&2
    exit 1
fi

packages_json="$(bash "$ROOT/uraam-api.sh" list-packages)"
jq -e '
    .status == "ok" and
    .user == 0 and
    .count == 3 and
    .classification_available == true and
    .system_count == 1 and
    .user_count == 2 and
    .unclassified_count == 0 and
    .package_types["com.example.system"] == "system" and
    .package_types["com.example.alpha"] == "user" and
    .package_types["com.example.beta"] == "user" and
    (.packages | index("com.example.alpha") != null) and
    (.packages | index("com.example.beta") != null)
' <<< "$packages_json" >/dev/null

if bash "$ROOT/uraam-api.sh" apply >/dev/null 2>&1; then
    printf '%s\n' "FAIL: unsupported destructive command was accepted" >&2
    exit 1
fi

if bash "$ROOT/uraam-api.sh" device-info extra-argument >/dev/null 2>&1; then
    printf '%s\n' "FAIL: unexpected extra API arguments were accepted" >&2
    exit 1
fi

help_output="$(bash "$ROOT/uraam-api.sh" --help)"
grep -Fq 'read-only' <<< "$help_output"

printf '%s\n' "PASS: JSON device information, package inventory, package inspector and strict read-only command boundary"
