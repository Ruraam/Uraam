# UAD-NG category audit

This audit is based on the pinned UAD-NG database revision
`9fcad87bf78c52c4270504bc8880139d95a27a29`.

Source:
[UAD-NG package database](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/blob/9fcad87bf78c52c4270504bc8880139d95a27a29/resources/assets/uad_lists.json)

## Category totals

| UAD category | Packages | Recommended | Advanced | Expert | Unsafe |
|---|---:|---:|---:|---:|---:|
| Google | 184 | 119 | 45 | 18 | 2 |
| Aosp | 273 | 42 | 72 | 89 | 70 |
| Carrier | 254 | 228 | 14 | 11 | 1 |
| Misc | 433 | 330 | 46 | 40 | 17 |

The counts are source classifications, not a recommendation to uninstall all
packages in a category. UAD's `Recommended` label is not a guarantee that a
package is safe to remove on every device, Android version, carrier, or
firmware. Package descriptions and dependencies must be reviewed individually.

## Why these categories are not bulk-imported as profiles

- **Google:** includes optional Google apps, but also services tied to system
  intelligence, security, setup, and Google Mobile Services. Removing a
  dependency can break features even when the package is marked Recommended.
- **Aosp:** includes Android overlays and framework-adjacent components. The
  source contains 70 Unsafe and 89 Expert entries; it must never be treated as
  a generic debloat list.
- **Carrier:** entries are operator- and region-specific. Removing a package
  that is required by the active SIM/operator can affect provisioning,
  voicemail, carrier services, device unlock, or emergency-related features.
- **Misc:** is heterogeneous and includes chipset-specific overlays,
  diagnostics, preinstalled third-party apps, and device-specific services.
  A category-wide uninstall list is not meaningful.

## URAAM policy

1. Keep OEM profiles separate and device-family-specific.
2. Do not turn an entire UAD category into a one-click JSON uninstall profile.
3. Keep Advanced, Expert, and Unsafe packages out of profiles labelled Safe.
4. Before creating importable Google/AOSP/Carrier/Misc profiles, URAAM should
   present per-package descriptions, UAD removal level, dependencies, and an
   explicit user selection. A source label alone is insufficient.
5. Keep the UAD source revision pinned so audits are reproducible.

The current CI validates the 14 new OEM JSON profiles changed in this pull
request against the pinned source. It does not certify that removal is harmless
on every device.
