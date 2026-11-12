# URAAM documentation

This directory contains the operational and technical documentation for URAAM. Start with the Quick Start if you are installing URAAM for the first time.

## User guides

| Document | What it covers |
|---|---|
| [Quick Start](Quick-Start-Guide.md) | Host requirements, installation, USB ADB, wireless ADB and first launch |
| [Shizuku and Wireless ADB](Shizuku_wireless.md) | Shizuku prerequisites, pairing, connection and troubleshooting |
| [Safety and Recovery](Safety-and-Recovery.md) | Package preview, manual selection, Dry-run, Apply, timeouts, journal and recovery |
| [UAD-NG review catalogue](UAD-NG-review-catalog.md) | Pinned UAD-NG metadata, risk categories and dependency caveats |
| [URAAM Desktop architecture](GUI-Architecture.md) | Optional GTK4 frontend, read-only JSON bridge and safety boundaries |

## Technical reference

| Document | What it covers |
|---|---|
| [Architecture](Architecture.md) | Runtime components, data paths, backends and operational boundaries |
| [Configuration format](../Configs/debloat/README.md) | JSON profile schema, OEM profile policy and validation |
| [Repository hierarchy](Uraam-Hierarchy.md) | Historical overview of the configuration hierarchy |

## Contributing

- [Contributor guide](../Contributing.md)
- [Example JSON profile](structure-example.json)
- [UAD metadata manifest](../Configs/uad/source.json)

## Documentation policy

- The code and tests are authoritative when behavior changes.
- Do not describe a feature as guaranteed safe. Explain its limits and failure modes.
- Distinguish mocked CI coverage from real-device testing.
- Keep commands, paths, filenames and menu labels synchronized with the current source.
- Pin external classification data to an exact upstream revision when reproducibility matters.

Some older reference documents in this directory describe historical device-specific tuning plans. They are not universal Android removal instructions. Verify every package against the target device and firmware before use.
