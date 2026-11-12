# URAAM architecture

This document describes the current Bash implementation. It is a practical map of the repository, not a promise that every host has identical Android capabilities.

## Runtime overview

URAAM is a menu-driven Bash application. Its main entry point is `uraam.sh`; it resolves its own location, determines user-data paths, initializes required directories and enters the dashboard.

```text
uraam.sh
 ├─ Environment and path detection
 ├─ Backend selection / health checks
 │   ├─ ADB
 │   ├─ local ROOT (su)
 │   └─ SHIZUKU (rish)
 ├─ Dashboard
 │   ├─ Debloat preview and apply
 │   ├─ APK installation
 │   ├─ Restoration-list backup
 │   ├─ Package restoration
 │   ├─ Wireless ADB helpers
 │   ├─ Logs
 │   └─ Update check
 └─ Safety primitives
     ├─ Package inventory validation
     ├─ UAD-NG metadata lookup
     ├─ Device identity checks
     ├─ Bounded device commands
     ├─ Apply lock
     └─ Pending-operation journal
```

## Device backends

The device command dispatcher selects one of three backends:

- **ADB:** runs commands through the selected ADB serial.
- **ROOT:** runs the Android shell command through `su -c`.
- **SHIZUKU:** runs the command through `rish -c`.

The selected backend is checked independently of the result of a package operation. A package command failure is not automatically treated as proof that the transport disconnected.

ADB shell permissions are not equivalent to root. The ADB path relies on Android's package manager permissions for the requested operation and applies package changes for user 0.

## Debloat data flow

1. A user chooses a JSON configuration.
2. URAAM validates and loads package identifiers.
3. It obtains a validated inventory of packages installed for Android user 0.
4. It classifies each profile entry as protected, absent, blocked Unsafe/Unknown, or a selectable UAD-NG candidate.
5. The user manually selects package numbers.
6. URAAM prints the exact proposed operations and available dependency/reverse-dependency context.
7. The user chooses Dry-run, Apply or Cancel.
8. Apply requires the exact operation-count confirmation.
9. URAAM refreshes device identity and inventory, acquires the exclusive lock, and revalidates again.
10. Each destructive command is journaled before dispatch. A batch stops on transport loss, timeout or uncertain command failure.

The bundled UAD-NG file is a pinned metadata catalogue. It is not itself an executable debloat profile and does not cause automatic package selection.

## Data and configuration paths

The implementation distinguishes portable and installed layouts.

| Purpose | Portable checkout | Installed layout |
|---|---|---|
| Script/repository | Checkout directory | Package or standalone installation path |
| User profiles | `Configs/debloat/` | `$XDG_CONFIG_HOME/uraam/debloat` or `~/.config/uraam/debloat` |
| APK staging | `Apps/` | `$XDG_DATA_HOME/uraam/Apps` or `~/.local/share/uraam/Apps` |
| Restoration lists | `Configs/backup-restore/` | `$XDG_DATA_HOME/uraam/Configs/backup-restore` |
| Debloat logs | `Logs/debloat/` | `$XDG_DATA_HOME/uraam/Logs/debloat` |
| Backup logs | `Logs/backup/` | `$XDG_DATA_HOME/uraam/Logs/backup` |
| Restore logs | `Logs/restore/` | `$XDG_DATA_HOME/uraam/Logs/restore` |

When an installed user profile directory is empty, bundled JSON profiles may be copied into it. Existing user files are not overwritten by this seeding step.

## Repository map

| Path | Responsibility |
|---|---|
| `uraam.sh` | Main runtime, backend dispatch, menu and operation logic |
| `installer.sh` | Interactive installer and lifecycle handling |
| `Configs/debloat/` | Importable JSON package profiles and profile guidance |
| `Configs/uad/` | Pinned UAD-NG metadata, source manifest and attribution |
| `Apps/` | APK staging directory |
| `Logs/` | Runtime log location for portable installs |
| `Docs/` | User and technical documentation |
| `tests/` | Mocked regression tests and metadata validator |
| `.github/workflows/` | Automated shell and configuration validation |

## Operational boundaries

- URAAM's package-management actions target Android user 0.
- A restoration list is not a full device backup.
- OEM and ROM detection is informational; it is not a compatibility certification.
- UAD-NG dependency data is advisory and non-exhaustive.
- Mocked tests validate code paths, not every Android OEM implementation.
- A successful command response does not certify that the resulting device behavior is desirable. Inspect the device after changes.
