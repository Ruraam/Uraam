# Changelog

All notable changes to URAAM are documented in this file.

This project follows the principles of [Keep a Changelog](https://keepachangelog.com/en/1.1.0).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) where applicable.

## [Unreleased]

### Added
- Added a central documentation index at `Docs/README.md`.
- Added a quick-start guide covering installation, setup, and common workflows.
- Added architecture documentation describing URAAM's components and execution flow.
- Added safety and recovery guidance for destructive operations and uncertain device states.
- Added an UAD-NG review catalogue reference.
- Added wireless ADB and Shizuku setup documentation.
- Added contribution guidance in `Contributing.md`.
- Added documentation for the debloat configuration directory.
- Added an optional GTK4 desktop frontend foundation in `GUI/` with a source-checkout launcher.
- Added a read-only JSON bridge for device information and the Android user-0 package inventory.
- Added mocked JSON API regression coverage and a dedicated GUI foundation CI workflow.
- Added `Docs/GUI-Architecture.md` to document the frontend boundary and safety limitations.

### Changed
- Reworked the root `README.md` to provide a clearer project overview and navigation to the guides.
- Clarified the distinction between OEM detection, package recommendations, manual selection, preview, and apply operations.
- Clarified backup and restore limitations: restoring a package with `pm install-existing` does not constitute a full APK or application-data backup.
- Organized historical documentation as archived material.
- Kept `Docs/Safety-&-Auditing.md` as a compatibility pointer to `Docs/Safety-and-Recovery.md`.
- Documented that the first GUI milestone is read-only; all package-changing workflows remain in the Bash interface.

### Security
- Documented the safeguards surrounding destructive package operations, including explicit user selection, preview, confirmation, fresh inventory checks, and operation locking.
- Documented private operation journaling and manual reconciliation for uncertain outcomes.
- Clarified that catalogue categories and OEM profiles are informational inputs, not blanket authorization to remove packages.

### Validation
- Verified internal Markdown documentation links and their target paths.
- Existing shell-safety and debloat-configuration validation workflows passed for the documentation pull request.
- The GUI foundation does not change the existing `uraam.sh` runtime or user-data paths.
- The JSON bridge rejects unsupported and destructive command names; mocked ADB tests cover device information and package inventory responses.

## Release history

No versioned release entries have been published in this changelog yet.
