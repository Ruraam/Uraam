> **Archived reference — not current operational guidance.** This file belongs to an earlier device-specific Ruvomain Protocol workflow. URAAM's current implementation and safety behavior may differ. Do not apply package lists, tiers, tuning targets or replacement instructions from this page without independently validating them for your exact device and firmware. Start with the [current documentation index](README.md), [Quick Start](Quick-Start-Guide.md) and [Safety and Recovery](Safety-and-Recovery.md).

---

### Uraam Hierarchy
(These three files are compatible with the Samsung Galaxy S24+ (you can use them on this model) and serve as an example to demonstrate how the protocol works.

URAAM script is modular, allowing users to choose their level of optimization. *Tiers lists are provided as standardized defaults, but the architecture is designed for you to edit `tier*.json` files to fit your specific operational requirements.*

You can modify these list in .json files for keep fonctionnality you want or [import](Configs/debloat/README.md) your personnal `.json` files list in `/Configs/debloat`.

| Tier | Strategy| Recommended For |
|:---|:---|:---|
| **Tier 1 (Stable/Conservative)** | Redundancy & Telemetry | All users seeking immediate gains. |
| **Tier 2 (Advanced/Balanced)** | AI Telemetry & Cloud Bloat | Users prioritizing privacy & efficiency. |
| **Tier 3 (Surgical/Extreme)** | Ghost Mode (System Core) | Advanced users building a bare-metal experience. |

URAAM keeps `Samsung Camera` and `gallery`, `Dolby Atmos`, `Samsung Screenshot`, `OneUI launcher`.
For privacy, you can block internet connexion (with firewall) for these apps without problem.

**For view packages list and descriptions see the /docs/[package-list.md](https://github.com/Ruvyrom/Ruvomain-Protocole/blob/main/Docs/uraam_list.md)**

**⚠️ Before use Tier3, you must read /docs/[REMPLACEMENT.md](https://github.com/Ruvyrom/Ruvomain-Protocole/blob/main/Docs/uraam_remplace.md)**
