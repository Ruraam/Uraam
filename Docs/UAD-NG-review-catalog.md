# UAD-NG metadata and review policy

URAAM bundles a pinned snapshot of the Universal Debloater Alliance – Next Generation (UAD-NG) package catalogue. The catalogue provides offline package descriptions, categories, risk labels and relationship metadata for the manual debloat preview.

**The catalogue is reference metadata, not a debloat profile.** The presence of a package in the JSON file never selects it for removal.

## Source and provenance

| Field | Value |
|---|---|
| Upstream project | [Universal Debloater Alliance – Next Generation](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation) |
| Upstream file | `resources/assets/uad_lists.json` |
| Pinned revision | `9fcad87bf78c52c4270504bc8880139d95a27a29` |
| Snapshot date | 2026-11-12 |
| Records | 5,399 |
| Data licence | GPL-3.0; see `Configs/uad/LICENSE` |

The local manifest is [source.json](../Configs/uad/source.json). The catalogue is stored at [uad_lists.json](../Configs/uad/uad_lists.json).

## Snapshot counts

| Risk level | Records |
|---|---:|
| Recommended | 3,018 |
| Advanced | 1,160 |
| Expert | 923 |
| Unsafe | 298 |
| **Total** | **5,399** |

These are counts in the pinned upstream snapshot, not counts of packages installed on a particular phone and not instructions to remove a category or risk level in bulk.

## Selection policy

- Recommended, Advanced and Expert entries can be shown as candidates when they are installed for Android user 0 and are not protected by URAAM.
- The user must select every package explicitly by its displayed number.
- Unsafe entries are blocked.
- Packages missing from the catalogue or carrying an unknown risk classification are blocked.
- URAAM's built-in safety whitelist takes precedence over UAD-NG labels.
- Apply requires a valid local catalogue, a fresh inventory, exact `APPLY N` confirmation and revalidation under the exclusive apply lock.
- No catalogue entry is automatically selected.

A Recommended label means UAD-NG classifies the package as a candidate; it does not guarantee that removal is harmless on every device, Android version, region, carrier or firmware.

## Dependencies and reverse dependencies

UAD-NG may provide:

- `dependencies`: packages that the listed package depends on;
- `neededBy`: packages that may depend on the listed package.

URAAM checks listed relationships against the live Android user-0 package inventory and warns when a listed reverse dependent is installed.

Relationship data is advisory and non-exhaustive. An empty list does not prove that no dependency exists. Android runtime behavior, OEM integration, overlays, carrier requirements and app-specific assumptions may not be represented. URAAM never automatically adds, removes or selects related packages.

## OEM profiles are separate

Curated `Safe-*.json` files under `Configs/debloat/` are distinct from the full UAD-NG catalogue. Their presence in a matching OEM profile is displayed as an advisory cross-check only. A profile match is not a guarantee of compatibility, and a package absent from a profile is not automatically unsafe.

Do not combine OEM profiles blindly or apply a profile to a different device family without reviewing every package.

## Updating the snapshot

To update the bundled metadata:

1. Select and record an exact upstream Git commit.
2. Fetch `resources/assets/uad_lists.json` from that commit.
3. Update `Configs/uad/source.json` with the revision, URL, date and record count.
4. Update the validator's pinned-revision expectation intentionally.
5. Run `python3 tests/validate_uad_metadata.py`.
6. Review any changed risk labels and OEM profiles; do not silently reclassify packages.
7. Include the upstream licence and attribution.

The metadata validator checks the manifest, record count, package keys, supported risk levels/categories and required field types. Passing validation confirms data structure and provenance consistency, not real-device safety.
