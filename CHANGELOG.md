# Changelog

All notable URAAM changes are documented here.

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
