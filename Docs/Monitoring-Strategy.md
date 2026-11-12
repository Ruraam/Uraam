> **Archived reference — not current operational guidance.** This file belongs to an earlier device-specific Ruvomain Protocol workflow. URAAM's current implementation and safety behavior may differ. Do not apply package lists, tiers, tuning targets or replacement instructions from this page without independently validating them for your exact device and firmware. Start with the [current documentation index](README.md), [Quick Start](Quick-Start-Guide.md) and [Safety and Recovery](Safety-and-Recovery.md).

---

## Monitoring Strategy


**1. Baseline Consumption (The Point of Origin)**

**Before any modification, you must establish your idle drain.**

>**Action:** Charge your device to 100%. Leave it in deep idle (screenoff, Wi-Fi on, SIM active) for 8 hours (overnight).

>**Measure:** Use AccuBattery.

>**Ruvomain Goal:** Target a drain rate between 0.0% and 0.2% per hour. If you exceed 0.5%, your system is polluted by active telemetry services.

**2. Wakelock Audit (Hunting the Intruders)**

**The primary enemy of battery efficiency is not activeusage; it is the CPU's inability to enter "Deep Sleep."**

>**Tool:** [AppOps](https://appops.rikka.app/) (via [Shizuku](https://shizuku.rikka.app/)).

**Procedure:**

>**1.Identify** system apps requesting the WAKE_LOCK permission.
>
>**2. Monitor** processes preventing the device from sleeping.
>
>**3.Audit:** If anon-essential system app holds active wakelocks in the background, it must be confined or neutralized according to the Protocol tiers.

**3. Network Traffic Analysis (Data Flow)**

**A sovereign system communicates only when the Architect authorizes it.**

>**Tool:** AdGuard (Filtering Log).

**Procedure:**

>**1.** Enable local filtering.
>
>**2.** Run for 1 hour under normal usage.
>
>**3. Audit:** Observe domains contacted by system apps (Samsung, Google, Facebook services).
>
>**4. Action:** If telemetry domains are detected, apply block rules via theintegrated firewall.

**4. Framework Stability (The Guardrail)**

**Never delete blindly. Verify the health ofthe system_server.**

>**Action:** After applying your configuration (Tier 1/2/3), monitor for spontaneous reboots or UI lag.
>
>**Technical Note:** If the Samsung keyboard reinstalls itself, you have compromised framework dependencies.
>
>**Remember:** Never use brute-force deletion.
Apply the "Confinement Strategy"(revoke permissions + restrict execution) rather than deletion.

**🛡️ Protocol Reminder**

**Your audit success is measured by these indicators:**

>**Thermals:** The device remains at ambient temperature during mixed usage.
>
>**SOT (Screen On Time):** A steady progression toward 11h+ (for an S24+).

>Share your results in the comments:
>
>**Model:** (e.g., S24+ S926B)
>
>**Tier applied:** (Tier 1, 2, or 3)
>
>**Idle drain(mAh/h):**
>
>**System observations:** Audit is repetition. The more you clean, the moretransparent the system becomes.
