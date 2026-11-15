# Changelog

All notable URAAM changes are documented here.

## [5.2.0] - 2026-11-15

### Added
- Complete the optional GTK4 desktop foundation with a branded Cyberpunk Glass interface.
- Add a read-only desktop dashboard for device status and Android user-0 package inventory.
- Package the GTK frontend, API protocol adapter, bridge process, stylesheet, desktop launcher and SVG icon in the Debian package.
- Add desktop database and icon-cache refresh handling to the Debian package lifecycle.
- Validate Debian package installation, upgrade, removal and preservation of user configuration, backups and logs in CI.
- Build and validate Debian and Termux packages automatically for published releases.

### Safety and compatibility
- Keep the GTK frontend read-only; package-changing Android operations remain in the Bash CLI.
- Preserve the existing Bash engine, command-line workflows and user-data paths.
- Keep GTK4 dependencies optional and Termux CLI-only.
- Validate the read-only JSON bridge and enforce its documented command boundary.

### Validation
- GTK4 frontend smoke test and Python syntax/bindings checks.
- Bash syntax, ShellCheck and shell-safety regression tests.
- Debian package layout, desktop-file validation, install/uninstall lifecycle and upgrade preservation tests.
- Debian and Termux package metadata and payload validation.

## [5.1.0] - 2026-11-12

### Added
- Optional GTK4 desktop frontend installation from the universal Linux installer.
- Desktop application-menu entry and official SVG icon for Linux desktop environments.
- Debian package support for the GUI payload while keeping GTK4 dependencies optional.
- Read-only desktop integration for device information and Android user-0 package inventory.

### Compatibility and safety
- Bash remains the complete interface for package-changing operations.
- Termux remains CLI-only.
- Existing user configuration, backups, and logs are preserved by the GUI installation lifecycle.
