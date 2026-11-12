# Bundled UAD-NG metadata

URAAM vendors a pinned snapshot of the UAD-NG package catalogue for offline risk labels and descriptions.

- Upstream: https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation
- Source file: `resources/assets/uad_lists.json`
- Pinned revision: `9fcad87bf78c52c4270504bc8880139d95a27a29`
- Snapshot: 2026-11-12
- Records: 5,399
- Data licence: GPL-3.0 (see the upstream repository's LICENSE)

The catalogue is metadata, not a debloat profile. URAAM never selects packages because they are present in this file.

## URAAM selection policy

- **Recommended**, **Advanced**, and **Expert** entries may be displayed as candidates, but the user must select each package by its displayed number.
- **Unsafe** entries are always blocked by the debloat selection flow.
- Entries absent from the catalogue or carrying an unknown risk value are blocked.
- Whitelist-protected packages remain blocked regardless of UAD classification.
- A destructive apply requires a fresh installed-package inventory and an exact `APPLY N` confirmation.
- Before confirmation, URAAM displays UAD-listed `dependencies` (packages required by the selected package) and `neededBy` reverse dependencies (packages that may rely on the selected package).
- Installed reverse dependencies produce an explicit impact warning; dependency presence is checked against Android user 0's live package inventory.
- Relationship data is advisory and non-exhaustive. An empty field does not prove that no runtime or OEM dependency exists; URAAM does not automatically add, remove, or select related packages.

The snapshot is intentionally pinned so an offline URAAM run has stable metadata. Updating it requires changing the revision in `source.json`, refreshing the data from that exact upstream revision, and running the UAD metadata validation tests.
