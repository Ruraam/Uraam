# URAAM Desktop foundation

URAAM Desktop is an optional GTK4 frontend. It does not replace the Bash CLI and does not contain a second implementation of Android package-management logic. The CLI remains a first-class, independently usable entry point: it must work without Python, PyGObject, GTK4, a graphical session, or the desktop launcher. Installing or launching the GUI is always optional; Termux remains CLI-only.

## Current scope

The first foundation milestone is deliberately read-only:

- `uraam-api.sh device-info` reports the selected backend and device identity.
- `uraam-api.sh list-packages` returns the installed package inventory for Android user 0, plus best-effort system / third-party classification from Android Package Manager.
- The GUI provides All / System / User / Unclassified filters. Classification is informational only; it does not imply that an app is safe to remove.
- `uraam-gui` launches the optional Python / GTK4 desktop interface.
- The GUI can display connection information and the package inventory.

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

The GUI invokes the adapter with `subprocess.run([...])`; it does not use a shell to interpolate user-controlled values. The adapter only accepts exactly one documented read-only command. Extra arguments and unknown commands, including destructive command names, are rejected. The adapter sources the engine only in `URAAM_TESTING=1` mode, so the interactive CLI entry point is not started as a side effect.

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

## Safety boundary

This milestone does not expose debloat preview, Apply, package disable/uninstall, APK installation, restoration, wireless pairing or journal reconciliation through the GUI. Continue to use the existing Bash interface for those workflows.

A future mutating API must call the existing engine's validated operation paths. It must not duplicate safety checks, bypass the apply lock, skip fresh device/inventory validation, omit the private operation journal, or weaken exact user confirmation. No GUI action may directly construct an arbitrary Android shell command.

## Tests

`tests/test-json-api.sh` uses a mocked ADB executable to verify device information and the user-0 inventory. It also verifies that unsupported destructive command names are rejected.

The GUI foundation workflow validates Bash syntax for the engine, CLI launcher and adapter, ShellCheck, Python syntax, GTK4 bindings, Debian desktop package layout and the mocked JSON API. The shell-safety workflow continues to validate the existing CLI safety and dry-run/recovery suites independently of GTK. These tests do not replace testing with real Android devices and each supported backend.
