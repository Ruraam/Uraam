> **Archived reference — not current operational guidance.** This file belongs to an earlier device-specific Ruvomain Protocol workflow. URAAM's current implementation and safety behavior may differ. Do not apply package lists, tiers, tuning targets or replacement instructions from this page without independently validating them for your exact device and firmware. Start with the [current documentation index](README.md), [Quick Start](Quick-Start-Guide.md) and [Safety and Recovery](Safety-and-Recovery.md).

---

### Network & Resource Confinement Layers

The Ruvomain Protocol extends beyond basic package removal.
To achieve true hardware sovereignty and operational efficiency, we implement a multi-layered confinement strategy to minimize the device's external footprint:

**- NextDNS** (System-wide DNS Filtering):
Configured directly within Android’s Private DNS settings. This acts as the firstline of defense, neutralizing GAFAM telemetry, ISP-level tracking, and ad-infrastructure requests before they even exit the device.

**- AdGuard Nightly** (Granular Firewall):
Deployed for strict network enforcement. This layer restricts connectivity forapplications that do not require network access, prevents "phoning home" during standby (screen-off), and effectively isolates telemetry-heavy processes to minimize energy footprint and unauthorized background communication.

**- AppOps** (Privilege & Wakelock Management):
Enforces the Principle of Least Privilege. Beyond standard permission stripping, this layer targets system-level wakelocks and hardware sensors to ensure processes remain dormant unless explicitly required by the user. This is critical for preventing unauthorized data access (Clipboard, Sensors, Location, Biometrics) and ensuring maximum hardware idle efficiency.

*By layering these tools, the terminal is transformed from a data-leaking device into a hardened, localized system that obeys only the user's intent.*
