# Debloat profiles

This directory contains user-selectable JSON package profiles for URAAM. Profiles are inputs to a manual review workflow; they are not automatic uninstall instructions.

URAAM also supports compatible Canta-style package lists where they match the accepted schema.

## Profile format

Each profile must be a JSON object with the following fields:

```json
{
  "name": "Example profile",
  "description": "A short description of the target device and intent",
  "author": "Contributor",
  "version": "1.0",
  "apps": [
    {
      "packageName": "com.example.optionalapp"
    }
  ]
}
```

The `apps` array contains Android package IDs. Do not include display names in place of package IDs.

An example is available in [Docs/structure-example.json](../../Docs/structure-example.json).

## Using a profile

1. Place the JSON file in your user profile directory shown by URAAM. In a portable checkout this is `Configs/debloat/`.
2. Start URAAM and select **Debloat apps**.
3. Choose the profile and action.
4. Review every classification and description.
5. Select package numbers explicitly.
6. Use Dry-run before considering Apply.

The preview checks the live installed package inventory for Android user 0. Entries that are absent, protected, UAD-NG Unsafe or unknown/unlisted are not eligible for the UAD-NG manual selection flow.

## Profile naming

Use a descriptive name that identifies the device family and software context, for example:

`DeviceFamily-Model-AndroidVersion-ROMVersion.json`

Avoid names such as `Safe-All-Devices.json`. A profile tested on one model or firmware is not automatically suitable for another.

## OEM profiles

Curated `Safe-*.json` files are narrow, device-family-specific candidates. Their names do not mean that every entry is harmless on every firmware.

The runtime OEM/ROM detection and profile cross-check are informational only:
- a profile match does not authorize removal;
- absence from a matching profile is not an unsafe verdict;
- unknown OEM/ROM identity must not be guessed;
- users must review the actual installed packages and their dependencies.

Do not combine OEM profiles blindly.

## Risk and classification policy

The bundled [UAD-NG catalogue](../uad/README.md) provides pinned risk metadata.

- Recommended, Advanced and Expert entries may be presented for manual selection.
- Unsafe entries are blocked.
- Unknown or unlisted entries are blocked.
- URAAM's built-in safety whitelist takes precedence over UAD labels.
- The catalogue is not a substitute for device-specific testing.

The UAD-NG source is pinned in [source.json](../uad/source.json). The category review and limitations are documented in [Docs/UAD-NG-review-catalog.md](../../Docs/UAD-NG-review-catalog.md).

## Validate a profile

For local validation, use the repository's validator:

```bash
python3 scripts/validate-debloat-json.py Configs/debloat/your-profile.json
```

For a full changed-profile validation, CI runs the repository workflow. The validator checks JSON structure and package identifiers; for curated Safe profiles it also checks the pinned UAD-NG classification. This is a data validation gate, not a device safety certification.

## Contribute a profile

Before submitting a pull request:

1. State the exact model, Android release, ROM and firmware/build where it was tested.
2. Explain the purpose of each package in the profile.
3. Confirm which features were checked after applying the profile.
4. Include a restoration path and disclose any known side effects.
5. Keep the profile narrowly scoped.

Never submit a package list as universally safe based only on an upstream risk label.
