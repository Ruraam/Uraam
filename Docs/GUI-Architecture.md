# URAAM Desktop foundation

URAAM Desktop is an optional GTK4 frontend. It does not replace the Bash CLI and does not contain a second implementation of Android package-management logic. The CLI remains a first-class, independently usable entry point: it must work without Python, PyGObject, GTK4, a graphical session, or the desktop launcher. Installing or launching the GUI is always optional; Termux remains CLI-only.

## Current scope

The first foundation milestone is deliberately read-only:

- `uraam-api.sh device-info` reports the selected backend and device identity.
- `uraam-api.sh list-packages` returns the installed package inventory for Android user 0, plus best-effort system / third-party classification from Android Package Manager.
- `uraam-api.sh package-info:<package.id>` returns the APK path(s) and version metadata reported by Android for one validated package identifier.
- The GUI provides All / System / User / Unclassified filters and a read-only package inspector. Classification is informational only; it does not imply that an app is safe to remove.
- `uraam-gui` launches the optional Python / GTK4 desktop interface.
- The GUI can display connection information, the package inventory and per-package details.

The API emits one JSON object on standard output. Diagnostic messages from the existing terminal-oriented engine are suppressed by the adapter. Errors are returned as JSON and a non-zero exit status.

## Architecture

```text
GTK4 frontend (GUI/main.py)
        |
        | subprocess argument vector; JSON only
        v
Read-only adapter (uraam-api.sh)
        |
        | sources functions; URAAM_TESTING=1 prevents main()
        v
Existing Bash engine (uraam.sh)
        |
        +-- ADB
        +-- local ROOT
        +-- Shizuku (rish)
```

The GUI invokes the adapter with `subprocess.run([...])`; it does not use a shell to interpolate user-controlled values. The adapter only accepts exactly one documented read-only command. Package inspection uses a single `package-info:<package.id>` argument; the package identifier is validated against a strict Android package-name pattern before any device command is sent. Extra arguments and unknown commands, including destructive command names, are rejected. The adapter sources the engine only in `URAAM_TESTING=1` mode, so the interactive CLI entry point is not started as a side effect.

## JSON response examples

Connected device:

```json
{
  "status": "connected",
  "version": "5.1.0",
  "backend": "ADB",
  "serial": "DEVICE-SERIAL",
  "model": "Manufacturer Model (Android 15)",
  "oem": "unknown",
  "rom": {
    "name": "Unknown ROM",
    "version": "15"
  }
}
```

Package inventory:

```json
{
  "status": "ok",
  "backend": "ADB",
  "serial": "DEVICE-SERIAL",
  "user": 0,
  "count": 2,
  "packages": [
    "com.example.first",
    "com.example.second"
  ],
  "package_types": {
    "com.example.first": "user",
    "com.example.second": "system"
  },
  "classification_available": true,
  "system_count": 1,
  "user_count": 1,
  "unclassified_count": 0
}
```

When no backend is connected, `device-info` returns `status: disconnected`. The package inventory command fails closed and returns a JSON error instead of presenting an empty inventory as valid. If Android cannot provide reliable system / third-party subsets, the package names remain visible and are marked unclassified rather than guessed.

## Run from a source checkout

Install the host dependencies on Debian / Ubuntu:

```bash
sudo apt install python3 python3-gi gir1.2-gtk-4.0 jq adb
```

Then launch:

```bash
bash ./uraam-gui
```

For a source checkout, the launcher and API remain beside `uraam.sh`. Debian packages install the frontend under `/usr/share/uraam`, the command at `/usr/bin/uraam-gui`, and the official SVG icon under the hicolor icon theme. The application-menu entry is registered only when GTK4 bindings are available. The universal Linux installer offers the same optional frontend installation under `/usr/local`; Termux remains CLI-only.

## Package inspector

The package inspector uses bounded, read-only `pm path --user 0` and `dumpsys package` queries through the existing Bash device-execution layer. APK paths are accepted only from valid `package:/absolute/path` responses. Version name and version code are displayed only when the device output contains the expected fields; otherwise the GUI reports that the metadata was not provided. Requested permission names are parsed only from the dedicated `requested permissions:` section. They are explicitly not presented as granted permissions: install/runtime grant sections are not used to infer access. If the section is absent, the API returns null and the GUI says the metadata was not reported. Activities, services, receivers and providers are read only from their matching explicit `dumpsys package` sections. Each component category is returned as an array when its section is present (including an empty array when no entries are parsed), or `null` when the Android build does not expose that section. Entries are restricted to component names prefixed by the inspected package ID; unrelated resolver-table references are ignored. This is a best-effort view of the Package Manager dump, not a guarantee of runtime reachability or launchability. Signing-certificate identity and safety verdicts are not inferred. The inspector offers no install, disable, uninstall, or restore controls.

## Safety boundary

This milestone does not expose debloat preview, Apply, package disable/uninstall, APK installation, restoration, wireless pairing or journal reconciliation through the GUI. Continue to use the existing Bash interface for those workflows.

A future mutating API must call the existing engine's validated operation paths. It must not duplicate safety checks, bypass the apply lock, skip fresh device/inventory validation, omit the private operation journal, or weaken exact user confirmation. No GUI action may directly construct an arbitrary Android shell command.

## Tests

`tests/test-json-api.sh` uses mocked ADB, `su` and `rish` executables to verify the three backend paths independently. It checks device identity, the user-0 inventory and package inspection (APK paths, version metadata and read-only status) through ADB, local ROOT and Shizuku transports; the ROOT and Shizuku fixtures simulate the Termux detection environment and never invoke real privilege escalation or a Shizuku service. The Android/OEM compatibility matrix additionally covers Google Pixel (Android 14), Xiaomi/Redmi with HyperOS, OPPO with ColorOS, Motorola with My UX, and Samsung with One UI. Package fixtures deliberately vary metadata presence, component-section order and content, and missing sections. Additional scenarios cover missing `dumpsys` metadata, ADB `unauthorized` and offline states, denied Root/Shizuku access, and malformed package-inventory output. These are deterministic command mocks, not claims of real Android/OEM certification. It also verifies package metadata, APK-path parsing, requested-permission section parsing (without treating requested permissions as grants), and component extraction from all four explicit component sections. Component fixtures cover reordered sections, present-but-empty sections, missing sections, unrelated package names, malformed component class names and non-component resolver text; missing sections must remain `null`, while present empty sections must be `[]`. It rejects malformed package identifiers and unsupported destructive command names, and checks that extra API arguments are rejected.

The GUI foundation workflow validates Bash syntax for the engine, CLI launcher and adapter, ShellCheck, Python syntax, GTK4 bindings, Debian desktop package layout and the mocked JSON API. The shell-safety workflow continues to validate the existing CLI safety and dry-run/recovery suites independently of GTK. These tests do not replace testing with real Android devices and each supported backend.
