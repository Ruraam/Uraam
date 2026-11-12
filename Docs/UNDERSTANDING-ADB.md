> **Archived reference — not current operational guidance.** This file belongs to an earlier device-specific Ruvomain Protocol workflow. URAAM's current implementation and safety behavior may differ. Do not apply package lists, tiers, tuning targets or replacement instructions from this page without independently validating them for your exact device and firmware. Start with the [current documentation index](README.md), [Quick Start](Quick-Start-Guide.md) and [Safety and Recovery](Safety-and-Recovery.md).

---

## What is ADB?

ADB (Android Debug Bridge) is the core command-line utility that creates a bridgebetween your computer and your phone’s operating system.

For the Ruvomain Protocol, ADB is our primary "privileged channel". It allows us to execute shell commands and surgically modify system packages—all **without root access**. This is critical for ourapproach: it lets us strip out bloatware and reclaim device sovereignty while keeping the system’s native security integrity and Samsung Knox completely intact.
