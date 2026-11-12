The lists above are compatible with Ruvomain App-Manager & Canta.

### Contributing - JSON files importation

You have a specific device? Create your JSON list or Canta restoration JSON list, fork this repo, place it in `/Configs/debloat`, and submit a Pull Request. Your configuration will then be available to the entire community.

- You **must** create your JSON file list with **THIS STRUCTURE**:

```json
{
  "name": "NAME OF YOUR FILE HERE",
  "description": "YOUR DESCRIPTION HERE",
  "author": "USERNAME",
  "version": "NUMBER VERSION",
  "apps": [
    {
      "packageName": "your.package.name"
    },
    {
      "packageName": "your.package.name"
    }
  ]
}
```

For using your liste with URAAM ruvomain-debloat script:
- **Copy** your personal or Canta .json restoration files in `/Configs/debloat` folder

- **Execute** script and select your json file

**Feel free to share your files with Pull Request in `./Configs`, to help grow the community!**

**Please ensure:**

- The JSON syntax is [valid](https://github.com/Ruvyrom/Ruvomain-Protocole/blob/main/Docs/structure-example.json).

- You have tested the debloat/restore list on your own device.

- You keep the minimalist philosophy of the project.

You can contribute with Pull Request.

**Naming Convention for Imports:**
`[Philosophy]-[DeviceName]-[OSVersion].json`
*Example:*

*Baremetal-Pixel6-LOS232.json*

*Degoogle-OP15-OxyOS15.json*

Need help with your first contribution? [Consult this guide](https://github.com/firstcontributions/first-contributions) to learn the basics of pull requests.

---

### Protocol Hierarchy (Tiers lists 1,2,3 for S24+ Exynos)
The protocol is modular, allowing users to choose their level of optimization. *Tierslists are provided as standardized defaults, but the architecture is designed for you to edit `tier*.json` files to fit your specific operational requirements.*

You can modify .json files if you want keep a fonctionality in /Configs

| Tier | Strategy| Recommended For |
|:---|:---|:---|
| **Tier 1 (Stable/Conservative)** | Redundancy & Telemetry | All users seeking immediate gains. |
| **Tier 2 (Advanced/Balanced)** | AI Telemetry & Cloud Bloat | Users prioritizing privacy & efficiency. |
| **Tier 3 (Surgical/Extreme)** | Ghost Mode (System Core) | Advanced users building a bare-metal experience. |

The protocol keeps `Samsung Camera` and `gallery`, `Dolby Atmos`, `Samsung Screenshot`, `OneUI launcher`.
For privacy, you can block internet connection (via firewall) for these apps without problem.

**For view packages list and descriptions see the /docs/[package-list.md](https://github.com/Ruvyrom/Ruvomain-Protocole/blob/main/Docs/package-list.md)**

**⚠️ Before use Tier3, you must read /docs/[REMPLACEMENT.md](https://github.com/Ruvyrom/Ruvomain-Protocole/blob/main/Docs/REMPLACEMENT.md)**

### Safe OEM profiles (UAD-NG)

Conservative manufacturer-specific profiles added to this directory:

- `Safe-ASUS-ZenUI.json`
- `Safe-Huawei-EMUI-HarmonyOS.json`
- `Safe-HONOR-MagicOS.json`
- `Safe-Motorola-MyUX.json`
- `Safe-LG-UX.json`
- `Safe-OnePlus-OxygenOS.json`
- `Safe-OPPO-Realme-ColorOS.json`
- `Safe-Lenovo-ZUI.json`
- `Safe-NothingOS.json`
- `Safe-Nubia-RedMagic.json`
- `Safe-TECNO-Infinix-Transsion.json`
- `Safe-Blackview-DokeOS.json`
- `Safe-Meizu-FlymeOS.json`
- `Safe-Wiko-Android.json`

**Safety policy:** each package ID was checked against the UAD-NG package database and is classified `list: Oem` and `removal: Recommended` at the source revision below. UAD defines *Recommended* as removable but still advises users to review their own needs. This does not guarantee that every package exists on every firmware or that optional features remain available. These are curated subsets, not universal guarantees. Check the packages present on your device, make a backup, and review the selected list before applying it. Do not combine OEM profiles blindly.

Source: [UAD-NG package database](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/blob/9fcad87bf78c52c4270504bc8880139d95a27a29/resources/assets/uad_lists.json) (revision `9fcad87bf78c52c4270504bc8880139d95a27a29`).


### Automated validation

Pull requests that modify debloat JSON profiles run
`python3 scripts/validate-debloat-json.py` through GitHub Actions.
The validator checks the shared JSON structure, non-empty required fields,
duplicate package IDs, and every `Safe-*.json` package against the pinned
UAD-NG database revision above. A Safe profile is rejected unless each package
exists in that database and has `removal: Recommended`.

The UAD source is pinned to a commit so results do not silently change when
the upstream database is updated. This check is a data-classification gate,
not a guarantee that removal is harmless on every device or firmware.


### Other UAD-NG categories

Google, AOSP, Carrier and Misc categories were audited, but are not imported as
bulk-uninstall JSON profiles. They contain system dependencies, overlays,
carrier-specific services and device-specific components. See
[Docs/UAD-NG-review-catalog.md](../../Docs/UAD-NG-review-catalog.md) for the
pinned category counts and the rationale for requiring per-package review.


### Runtime OEM and ROM identification

During the manual UAD-NG preview, URAAM reads Android build properties to identify
the manufacturer family and, when an explicit vendor property is available,
the ROM family/version (for example One UI, MIUI/HyperOS, OxygenOS, ColorOS,
EMUI/HarmonyOS, MagicOS, ZenUI, My UX, Funtouch OS/OriginOS, Pixel Android,
Nothing OS, or LineageOS). This identification is informational only:
unknown or missing properties are reported conservatively and do not change
package risk classifications or automatically select packages. The detected
device model, OEM family and ROM/version are checked again immediately before
applying a preview. A model change invalidates the preview.


### Backend interruption safety

During a confirmed multi-package apply, URAAM checks the selected ADB, root or
Shizuku transport before each package operation. If the transport is no longer
available, it stops the batch and reports the unattempted packages as skipped.
If a package command fails while the transport remains available, the failure
is counted and the next selected package may still be attempted. A real device
can still change state between checks; inspect the final summary and device
state after any interrupted operation.

Package inventory parsing is fail-closed: URAAM rejects command failures,
empty output, and responses containing malformed/error lines even if some
valid package rows were returned. It will not treat a partial list as a safe
basis for a destructive preview or apply.
