# Safety and Recovery

URAAM performs operations that can disable or uninstall Android applications for user 0. A package may provide a visible app, a background service, an OEM feature, or a dependency used by other components. Treat every package change as a device-specific decision.

## Safety model

URAAM uses multiple independent checks. None of them can prove that a package is harmless to remove on every Android device.

### Preview classifications

The debloat preview separates profile entries into these groups:

| Classification | Meaning | Apply eligibility |
|---|---|---|
| Selectable | Installed for user 0, not protected, and classified by UAD-NG as Recommended, Advanced or Expert | User must select it manually |
| Unsafe | UAD-NG marks the package Unsafe | Blocked |
| Unknown | Package is absent from the catalogue or has an unsupported/missing risk classification | Blocked |
| Protected | Matches URAAM's built-in safety whitelist or package patterns | Blocked |
| Not installed | Not present in the current installed-only user-0 inventory | Not applicable |

A missing catalogue or invalid catalogue prevents Apply. Do not remove the metadata file to bypass classification.

### Risk labels

- **Recommended:** UAD-NG considers the package a candidate for removal; review it for your device.
- **Advanced:** requires closer review of the package's purpose and dependencies.
- **Expert:** intended for users who can assess system-level consequences.
- **Unsafe:** blocked by URAAM's UAD-NG selection flow.
- **Unknown / unlisted:** blocked by default.

These labels originate from community-maintained metadata. They are not device-specific test results, warranties or safety certifications.

### OEM and ROM detection

URAAM reads available Android build properties to identify a manufacturer family, ROM family and version. It may display a cross-check against a curated Safe OEM profile:

- **MATCH:** the package appears in a matching curated profile.
- **NOT LISTED:** it does not appear in that profile; this is not an unsafe verdict.
- **UNKNOWN:** the OEM/profile match could not be established.

Detection is informational only. It does not automatically select packages or change UAD-NG risk classification. Missing vendor properties are reported conservatively rather than guessed.

### Dependency information

The preview can show UAD-NG `dependencies` and `neededBy` relationships and whether listed related packages are installed for user 0.

This information is advisory and non-exhaustive. Empty relationship fields do not prove that no runtime, OEM, carrier or application dependency exists. URAAM does not automatically select or remove related packages.

## Dry-run and Apply

The debloat flow requires explicit user input at each stage:

1. Choose the uninstall or disable action.
2. Review the complete package inventory classification.
3. Select package numbers individually. Empty input cancels; malformed, duplicate or out-of-range selections are rejected.
4. Review the final selected package list and relationship warnings.
5. Choose Dry-run, Apply or Cancel.
6. Dry-run reports what would happen and returns without issuing uninstall or disable commands.
7. Apply requires typing the exact confirmation string shown by URAAM, in the form `APPLY N`.

Before Apply, URAAM refreshes the package inventory and compares device model, OEM family and ROM information with the original preview. It then acquires an exclusive `flock` lock and repeats the inventory, identity and package-eligibility checks while holding that lock. A changed or incomplete state aborts the operation.

The lock prevents concurrent URAAM apply sessions from modifying the device through this workflow. It cannot prevent Android, another tool or the user from changing package state independently.

## Bounded device commands

Package inventory, uninstall and disable commands run through a host-side timeout.

- Default: 30 seconds.
- Override: `URAAM_DEVICE_TIMEOUT`.
- Accepted range: integer from 1 to 300 seconds.
- Required implementation: GNU coreutils `timeout` or compatible `gtimeout`.

URAAM probes the required GNU timeout options before sending a device command. It tries `timeout` and then `gtimeout`. If neither is compatible, the command is refused.

A timed-out uninstall or disable has an **unknown outcome**. Android may have applied the operation even though the host did not receive a response. URAAM marks the operation uncertain, stops the batch and does not retry it automatically. Refresh the inventory and inspect the device before deciding what to do next.

## Interrupted-operation journal

Before each uninstall or disable command, URAAM writes a private JSON journal containing the operation state, package, backend, ADB serial when applicable, device model, batch position and UTC timestamp.

The journal is written through a temporary file in the same directory, restricted to mode `0600`, and synchronized before the device command is sent. The journal path is:

- Portable checkout: `Logs/debloat/active-operation.json`.
- Installed layout: `$XDG_DATA_HOME/uraam/Logs/debloat/active-operation.json` or `~/.local/share/uraam/Logs/debloat/active-operation.json`.

A successful package command clears its journal before the next package is attempted. A failed, timed-out or interrupted operation is retained as uncertain. This includes a crash after Android applied a command but before URAAM could clear the journal.

### Recovery procedure

When a pending journal is found:

1. URAAM blocks a new destructive apply.
2. It validates the journal structure and compares the recorded backend/device identity with the current session.
3. It checks the backend and refreshes the relevant package inventory when possible.
4. It displays the observed state but does not treat inventory alone as proof of success or failure.
5. The operator must inspect the Android device and decide what happened.
6. Only then may the operator enter the exact acknowledgement `RECONCILE package.name` requested by the program.

URAAM never resumes or replays the interrupted uninstall/disable command. Do not delete a pending or corrupt journal blindly. If its contents are invalid or the recorded device does not match, stop and investigate manually.

## Batch stop conditions

A multi-package batch stops when:

- the selected backend becomes unavailable;
- a device command times out;
- a package command fails and its outcome may be uncertain;
- the journal cannot be safely persisted or cleared;
- device identity or package eligibility changes during validation.

Remaining operations are reported as skipped. URAAM does not automatically retry an uncertain operation.

## Backups and restoration limits

The backup feature creates a JSON restoration list of package records present in the device package database but not currently installed for user 0. Restore calls Android's `pm install-existing --user 0`.

It does not back up app data, APK files, account state, settings, photos or firmware. A package that has been completely removed from the device may not be restorable with `install-existing`.

## After any operation

- Check the final success / failed / skipped summary.
- Inspect the device's launcher, connectivity, telephony, notifications and features you rely on.
- Refresh the package inventory.
- Keep the logs and restoration JSON until you are satisfied with the result.
- If an operation was interrupted or timed out, reconcile it before starting another destructive batch.

## Test coverage and limitations

CI covers Bash syntax, ShellCheck errors, pinned UAD-NG metadata validation, mocked preview/Dry-run behavior and mocked abrupt-process recovery. These tests do not replace physical-device testing across ADB, root and Shizuku, Android versions, OEM firmware, host operating systems or unusual transport failures.
