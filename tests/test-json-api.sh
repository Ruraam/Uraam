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
        case "${MOCK_ADB_STATE:-device}" in
            unauthorized) printf 'List of devices attached\nTEST-SERIAL\tunauthorized\n' ;;
            offline) printf 'List of devices attached\n' ;;
            *) printf 'List of devices attached\nTEST-SERIAL\tdevice\n' ;;
        esac
        ;;
    '-s TEST-SERIAL get-state')
        [[ "${MOCK_ADB_STATE:-device}" == "device" ]] || exit 1
        printf 'device\n'
        ;;
    '-s TEST-SERIAL shell getprop ro.product.manufacturer')
        printf '%s\n' "${MOCK_MANUFACTURER:-TestCo}"
        ;;
    '-s TEST-SERIAL shell getprop ro.product.brand')
        printf '%s\n' "${MOCK_BRAND:-TestCo}"
        ;;
    '-s TEST-SERIAL shell getprop ro.product.model')
        printf 'TestPhone\n'
        ;;
    '-s TEST-SERIAL shell getprop ro.build.version.release')
        printf '%s\n' "${MOCK_ANDROID_RELEASE:-15}"
        ;;
    '-s TEST-SERIAL shell getprop ro.build.version.oneui')
        printf '%s\n' "${MOCK_ONEUI_VERSION:-}"
        ;;
    '-s TEST-SERIAL shell getprop ro.mi.os.version.name')
        printf '%s\\n' "${MOCK_HYPEROS_VERSION:-}"
        ;;
    '-s TEST-SERIAL shell getprop ro.miui.ui.version.name')
        printf '%s\\n' "${MOCK_MIUI_VERSION:-}"
        ;;
    '-s TEST-SERIAL shell getprop ro.build.version.opporom')
        printf '%s\\n' "${MOCK_COLOROS_VERSION:-}"
        ;;
    '-s TEST-SERIAL shell getprop ro.build.version.myux')
        printf '%s\\n' "${MOCK_MYUX_VERSION:-}"
        ;;
    '-s TEST-SERIAL shell pm list packages --user 0')
        if [[ "${MOCK_ADB_INVENTORY:-valid}" == "malformed" ]]; then
            printf 'package:com.example.alpha\nunexpected truncated output\n'
        else
            printf 'package:com.example.alpha\npackage:com.example.beta\npackage:com.example.system\n'
        fi
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
        printf 'Package [com.example.legacy] (456):\n    versionName=2.0\n    Providers:\n      com.example.legacy/.StoreProvider\n    Activities:\n      com.example.legacy/.HomeActivity filter xyz\n      com.other.app/.ForeignActivity filter xyz\n      com.example.legacy/.Bad-Class filter malformed\n      com.example.legacy/9InvalidClass filter malformed\n      ResolverTableEntry com.example.legacy/.NotAComponent\n    Services:\n    Receivers:\n      com.example.legacy/com.example.legacy.BootReceiver\n'
        ;;
    '-s TEST-SERIAL shell pm path --user 0 com.example.nosections')
        printf 'package:/data/app/com.example.nosections/base.apk\n'
        ;;
    '-s TEST-SERIAL shell pm path --user 0 com.example.old')
        printf 'package:/data/app/com.example.old/base.apk\n'
        ;;
    '-s TEST-SERIAL shell pm path --user 0 com.lab.pixel')
        printf 'package:/data/app/com.lab.pixel/base.apk\n'
        ;;
    '-s TEST-SERIAL shell pm path --user 0 com.lab.xiaomi')
        printf 'package:/data/app/com.lab.xiaomi/base.apk\n'
        ;;
    '-s TEST-SERIAL shell pm path --user 0 com.lab.oppo')
        printf 'package:/data/app/com.lab.oppo/base.apk\n'
        ;;
    '-s TEST-SERIAL shell pm path --user 0 com.lab.motorola')
        printf 'package:/data/app/com.lab.motorola/base.apk\n'
        ;;
    '-s TEST-SERIAL shell dumpsys package com.example.nosections')
        printf 'Package [com.example.nosections] (789):\n    versionName=3.0\n    requested permissions:\n      android.permission.INTERNET\n'
        ;;
    '-s TEST-SERIAL shell dumpsys package com.example.old')
        printf 'Package [com.example.old] (101):\n    codePath=/data/app/com.example.old\n'
        ;;
    '-s TEST-SERIAL shell dumpsys package com.lab.pixel')
        printf 'Package [com.lab.pixel] (202):\n    versionCode=7\n    versionName=PixelFixture\n    Activities:\n      com.lab.pixel/com.lab.pixel.MainActivity filter\n    Services:\n      com.lab.pixel/.SyncService\n'
        ;;
    '-s TEST-SERIAL shell dumpsys package com.lab.xiaomi')
        printf 'Package [com.lab.xiaomi] (303):\n    requested permissions:\n      android.permission.INTERNET\n    Receivers:\n      com.lab.xiaomi/.BootReceiver\n    Providers:\n      com.lab.xiaomi/com.lab.xiaomi.StoreProvider\n'
        ;;
    '-s TEST-SERIAL shell dumpsys package com.lab.oppo')
        printf 'Package [com.lab.oppo] (404):\n    versionName=OppoFixture\n    Services:\n      com.lab.oppo/.PushService\n    Activities:\n      com.lab.oppo/.HomeActivity\n'
        ;;
    '-s TEST-SERIAL shell dumpsys package com.lab.motorola')
        printf 'Package [com.lab.motorola] (505):\n    versionName=MotoFixture\n    Activities:\n      com.lab.motorola/com.lab.motorola.LauncherActivity filter\n    Receivers:\n      com.lab.motorola/.UpdateReceiver\n    Providers:\n      com.lab.motorola/.DataProvider\n'
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
cat > "$TMP_DIR/mockbin/su" <<'MOCK'
#!/usr/bin/env bash
[[ "${MOCK_SU_DENY:-0}" == "1" ]] && exit 1
[[ "${1:-}" == "-c" && -n "${2:-}" ]] || exit 2
exec bash -c "$2"
MOCK

cat > "$TMP_DIR/mockbin/rish" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "-c" && -n "${2:-}" ]]; then
    exec bash -c "$2"
fi
if [[ "${MOCK_RISH_DENY:-0}" == "1" ]]; then exit 1; fi
if (($# == 0)); then
    IFS= read -r handshake || exit 1
    [[ "$handshake" == "exit" ]] && exit 0
fi
exit 2
MOCK

cat > "$TMP_DIR/mockbin/dumpsys" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" == "package com.example.alpha" ]] || {
    printf 'Unexpected mocked dumpsys call: %s\n' "$*" >&2
    exit 2
}
printf 'Package [com.example.alpha] (123):\n    versionCode=42 minSdk=23 targetSdk=35\n    versionName=1.2.3\n    requested permissions:\n      android.permission.INTERNET\n    Activities:\n      com.example.alpha/.MainActivity filter abc\n'
MOCK

cat > "$TMP_DIR/mockbin/pm" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
    'list packages --user 0')
        printf 'package:com.example.alpha\npackage:com.example.beta\npackage:com.example.system\n'
        ;;
    'list packages -s --user 0')
        printf 'package:com.example.system\n'
        ;;
    'list packages -3 --user 0')
        printf 'package:com.example.alpha\npackage:com.example.beta\n'
        ;;
    'path --user 0 com.example.alpha')
        printf 'package:/data/app/~~abc/com.example.alpha/base.apk\n'
        ;;
    'dumpsys package com.example.alpha')
        printf 'Package [com.example.alpha] (123):\n    versionCode=42 minSdk=23 targetSdk=35\n    versionName=1.2.3\n    requested permissions:\n      android.permission.INTERNET\n    Activities:\n      com.example.alpha/.MainActivity filter abc\n'
        ;;
    *)
        printf 'Unexpected mocked Package Manager call: %s\n' "$*" >&2
        exit 2
        ;;
esac
MOCK

chmod +x "$TMP_DIR/mockbin/adb" "$TMP_DIR/mockbin/su" "$TMP_DIR/mockbin/rish" "$TMP_DIR/mockbin/pm" "$TMP_DIR/mockbin/dumpsys"

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


# Legacy Android-shaped dump: absent metadata stays unknown, never guessed.
old_info="$(bash "$ROOT/uraam-api.sh" package-info:com.example.old)"
jq -e '.status == "ok" and .version_name == null and .version_code == null and .components.activities == null and .components.providers == null' <<< "$old_info" >/dev/null

# OEM/ROM profile fixture (Samsung One UI, Android 8.1).
export MOCK_MANUFACTURER=Samsung MOCK_BRAND=samsung MOCK_ONEUI_VERSION=6.1 MOCK_ANDROID_RELEASE=8.1
legacy_device="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.status == "connected" and .oem == "samsung" and .rom.name == "One UI" and .rom.version == "6.1"' <<< "$legacy_device" >/dev/null
unset MOCK_MANUFACTURER MOCK_BRAND MOCK_ONEUI_VERSION MOCK_ANDROID_RELEASE


# Android/OEM compatibility matrix: property detection and dumpsys section
# parsing are exercised independently of physical hardware.
export MOCK_MANUFACTURER=Google MOCK_BRAND=google MOCK_ANDROID_RELEASE=14
pixel_device="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.oem == "google" and .rom.name == "Pixel Android" and .rom.version == "14"' <<< "$pixel_device" >/dev/null
pixel_info="$(bash "$ROOT/uraam-api.sh" package-info:com.lab.pixel)"
jq -e '.version_name == "PixelFixture" and .version_code == "7" and .components.activities == ["com.lab.pixel/com.lab.pixel.MainActivity"] and .components.services == ["com.lab.pixel/.SyncService"]' <<< "$pixel_info" >/dev/null

export MOCK_MANUFACTURER=Xiaomi MOCK_BRAND=Redmi MOCK_HYPEROS_VERSION=1.0
xiaomi_device="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.oem == "xiaomi" and .rom.name == "HyperOS" and .rom.version == "1.0"' <<< "$xiaomi_device" >/dev/null
xiaomi_info="$(bash "$ROOT/uraam-api.sh" package-info:com.lab.xiaomi)"
jq -e '.components.receivers == ["com.lab.xiaomi/.BootReceiver"] and .components.providers == ["com.lab.xiaomi/com.lab.xiaomi.StoreProvider"] and .components.activities == null' <<< "$xiaomi_info" >/dev/null

export MOCK_MANUFACTURER=OPPO MOCK_BRAND=OPPO MOCK_HYPEROS_VERSION= MOCK_COLOROS_VERSION=14
oppo_device="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.oem == "oppo" and .rom.name == "ColorOS" and .rom.version == "14"' <<< "$oppo_device" >/dev/null
oppo_info="$(bash "$ROOT/uraam-api.sh" package-info:com.lab.oppo)"
jq -e '.version_name == "OppoFixture" and .components.services == ["com.lab.oppo/.PushService"] and .components.activities == ["com.lab.oppo/.HomeActivity"]' <<< "$oppo_info" >/dev/null

export MOCK_MANUFACTURER=Motorola MOCK_BRAND=motorola MOCK_MYUX_VERSION=5
moto_device="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.oem == "motorola" and .rom.name == "My UX" and .rom.version == "5"' <<< "$moto_device" >/dev/null
moto_info="$(bash "$ROOT/uraam-api.sh" package-info:com.lab.motorola)"
jq -e '.version_name == "MotoFixture" and .components.activities == ["com.lab.motorola/com.lab.motorola.LauncherActivity"] and .components.receivers == ["com.lab.motorola/.UpdateReceiver"] and .components.providers == ["com.lab.motorola/.DataProvider"]' <<< "$moto_info" >/dev/null
unset MOCK_MANUFACTURER MOCK_BRAND MOCK_ANDROID_RELEASE MOCK_HYPEROS_VERSION MOCK_MIUI_VERSION MOCK_COLOROS_VERSION MOCK_MYUX_VERSION

# Unauthorized and offline ADB devices are not usable backends.
export MOCK_ADB_STATE=unauthorized
unauthorized_info="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.status == "disconnected" and .backend == null' <<< "$unauthorized_info" >/dev/null
export MOCK_ADB_STATE=offline
offline_info="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.status == "disconnected" and .backend == null' <<< "$offline_info" >/dev/null
unset MOCK_ADB_STATE

# Malformed package output must fail closed, not return a partial inventory.
export MOCK_ADB_INVENTORY=malformed
if bash "$ROOT/uraam-api.sh" list-packages >/dev/null 2>&1; then
    printf '%s\\n' "FAIL: malformed package inventory was accepted" >&2
    exit 1
fi
unset MOCK_ADB_INVENTORY
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


# Exercise each transport independently. These are host-side command mocks:
# no physical device, privilege escalation or Shizuku service is contacted.
export PREFIX="$TMP_DIR/com.termux/files/usr"
export MOCK_ADB_STATE=offline
unset ANDROID_SERIAL

export MOCK_SU_DENY=0
root_info="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.status == "connected" and .backend == "ROOT" and .serial == null' <<< "$root_info" >/dev/null
root_packages="$(bash "$ROOT/uraam-api.sh" list-packages)"
jq -e '.status == "ok" and .backend == "ROOT" and .count == 3' <<< "$root_packages" >/dev/null
root_package="$(bash "$ROOT/uraam-api.sh" package-info:com.example.alpha)"
jq -e '.status == "ok" and .backend == "ROOT" and .paths == ["/data/app/~~abc/com.example.alpha/base.apk"] and .version_name == "1.2.3" and .read_only == true' <<< "$root_package" >/dev/null

export MOCK_SU_DENY=1
export MOCK_RISH_DENY=1
no_backend_info="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.status == "disconnected" and .backend == null' <<< "$no_backend_info" >/dev/null
unset MOCK_RISH_DENY

shizuku_info="$(bash "$ROOT/uraam-api.sh" device-info)"
jq -e '.status == "connected" and .backend == "SHIZUKU" and .serial == null' <<< "$shizuku_info" >/dev/null
shizuku_packages="$(bash "$ROOT/uraam-api.sh" list-packages)"
jq -e '.status == "ok" and .backend == "SHIZUKU" and .count == 3' <<< "$shizuku_packages" >/dev/null
shizuku_package="$(bash "$ROOT/uraam-api.sh" package-info:com.example.alpha)"
jq -e '.status == "ok" and .backend == "SHIZUKU" and .paths == ["/data/app/~~abc/com.example.alpha/base.apk"] and .version_name == "1.2.3" and .read_only == true' <<< "$shizuku_package" >/dev/null

unset MOCK_ADB_STATE
printf '%s\n' "PASS: mocked ADB, ROOT and SHIZUKU read-only backend paths"

printf '%s\n' "PASS: JSON device information, package inventory, package inspector and strict read-only command boundary"
