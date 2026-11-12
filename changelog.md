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

### Changed
- Reworked the root `README.md` to provide a clearer project overview and navigation to the guides.
- Clarified the distinction between OEM detection, package recommendations, manual selection, preview, and apply operations.
- Clarified backup and restore limitations: restoring a package with `pm install-existing` does not constitute a full APK or application-data backup.
- Organized historical documentation as archived material.
- Kept `Docs/Safety-&-Auditing.md` as a compatibility pointer to `Docs/Safety-and-Recovery.md`.

### Security
- Documented the safeguards surrounding destructive package operations, including explicit user selection, preview, confirmation, fresh inventory checks, and operation locking.
- Documented private operation journaling and manual reconciliation for uncertain outcomes.
- Clarified that catalogue categories and OEM profiles are informational inputs, not blanket authorization to remove packages.

### Validation
- Verified internal Markdown documentation links and their target paths.
- Existing shell-safety and debloat-configuration validation workflows passed for the documentation pull request.
- No URAAM runtime code or user-data paths were changed by this documentation refresh.

## Release history

No versioned release entries have been published in this changelog yet.
