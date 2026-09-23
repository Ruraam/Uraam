<p align="center">
<img src="https://img.shields.io/badge/Status | Stable-000000?logo=github&logoColor=white&style=for-the-badge&color=151B22" alt="Status"height="25"> &nbsp; <img src="https://img.shields.io/badge/Clones | 4406 (14 last days)-%23121011.svg?logo=github&logoColor=white&style=for-the-badge&color=151B22" alt="Total clones"height="25">
</p>

<div align="center" style="background-color: #151B22; display: inline-block">
<img src="assets/uraam_logo.jpg" width="200">
</div>

&nbsp;
<p align="center">
<img src="https://img.shields.io/badge/| Bash-4EAA25?logo=gnubash&logoColor=4EAA25&style=for-the-badge&color=151B22"height="25"> &nbsp;
<img src="https://img.shields.io/badge/| JSON-000?logo=json&logoColor=fff&style=for-the-badge&color=151B22"height="25"> &nbsp;
<img src="https://img.shields.io/badge/| ADB-3DDC84?logo=android&logoColor=3DDC84&style=for-the-badge&color=151B22"height="25">
<img src="https://img.shields.io/badge/| Linux-yellow?&logo=linux&logoColor=yellow&style=for-the-badge&color=151B22"height="25"> &nbsp; 
<img src="https://img.shields.io/badge/| Termux | Shizuku | Root-000000?logo=iterm2&logoColor=fff&style=for-the-badge&color=151B22"height="25" > &nbsp; 
<img src="https://img.shields.io/badge/| MacOS-magenta?&logo=Apple&logoColor=magenta&style=for-the-badge&color=151B22"height="25" >
<img src="https://custom-icon-badges.demolab.com/badge/ | WSL-0078D6?logo=windows11&logoColor=blue&style=for-the-badge&color=151B22"height="25">  &nbsp;
<img src="https://img.shields.io/badge/| Android-3DDC88?logo=android&logoColor=3DDC84&style=for-the-badge&color=151B22"height="25">  &nbsp;
<img src="https://img.shields.io/badge/| Debloater-003087?logo=android&logoColor=3DDC84&style=for-the-badge&color=151B22"height="25"> &nbsp;
<img src="https://img.shields.io/badge/| Restore-FFC517?logo=android&logoColor=3DDC84&style=for-the-badge&color=151B22"height="25"> &nbsp;
<img src="https://img.shields.io/badge/| App Manager-764ABC?logo=android&logoColor=3DDC84&style=for-the-badge&color=151B22" alt="Device"height="25"> &nbsp;
<img src="https://img.shields.io/badge/No Root-FE7A16?&style=for-the-badge&color=151B22"height="25"> &nbsp;
<img src="https://img.shields.io/badge/Canta compatible-FFB3C7?&style=for-the-badge&color=151B22"height="25"> &nbsp;
<img src="https://img.shields.io/badge/Privacy Focused-%23FF0000.svg?&style=for-the-badge&color=151B22"height="25"> &nbsp;
<img src="https://img.shields.io/badge/ License GPLv3-black?style=for-the-badge&color=151B22" alt="License"height="25">
</p>

# URAAM - Universal Ruvomain ADB App Manager</p>

URAAM is a lightweight, fully open-source Bash toolkit that lets you safely **debloat**, **disable**, **backup** and **restore** Android applications.

- Works on **Termux** (Wireless ADB / Shizuku / Root)
- Works on **Linux, macOS and WSL** via ADB
- Compatible with **Canta** and **UAD** JSON lists
- Minimal dependencies (`adb`, `jq`, `git`)
- Transparent and auditable (pure Bash)

Designed to be simple, fast, and respectful of your device integrity.

---

***[📦 Universal 1-Line Installer](https://github.com/Uraam/Uraam/blob/main/README.md#-universal-1-line-installer)***

***[📱 Android 15/16 Native Linux Terminal (AVF)](https://github.com/Uraam/Uraam/blob/main/README.md#-android-1516-native-linux-terminal-avf)***

| <div align="center">Termux</div> <div align="center"><img src="/assets/Termux-Icon.webp"></div> | <img src="assets/uraam-termux.jpg" width="200"> | <img src="assets/uraam-wireless.jpg" width="200"> || <div align="center">Debian</div> <div align="center"><img src="/assets/debian_logo.png" width="150"></div> | <div align="center"><img src="assets/debupdate.png" width="400"></div> |
| :--- | :--- | :--- | :--- | :--- | :--- |
|| <div align="center">Dashboard</div> | <div align="center">Wireless ADB</div> || | Uraam DEB Update |

> **🚀 Latest Updates:**
> *[changelog on Releases Page](https://github.com/Uraam/Uraam/releases)*
>
>---

## ⚡ Core Features

* 🗑️ **Debloat (JSON-Powered):** Safely remove or disable bloatware using community-driven Canta & UAD JSON lists.
* 📦 **Batch APK Installer:** Drop your APKs into `./Apps/` and install them all in one click with automatic handling.
* 💾 **Smart Backup (JSON):** Export your current device state and package configuration to a portable JSON file.
* 🔄 **Restore (JSON-Driven):** Revert uninstalled apps or reinstall packages seamlessly from previous backups.
* 📶 **Wireless ADB Assistant:** Built-in pairing & connection helper for seamless PC-free or cable-free setup.
* 🚀 **Self-Updater:** Keep URAAM up to date directly fromthe official repository with a single keypress.
* 📜 **Integrated Logs Viewer:** Inspect terminal history and debug operations instantly without leaving the dashboard.

## 🚀 Ready to deploy?

**UNIVERSAL RUVOMAIN ADB APP-MANAGER (URAAM):**

## 1-USB option: Enable USB Debugging on your device:

* Settings > About phone > Tap "Build Number" 7 times

* Settings > Developer Options > Enable "USB Debugging"

* Connect your device to your PC via USB

or

## 2-Wireless option: Use wireless ADB setup assistant option in Dashboard.
* Execute script and choose option ***[w] Wireless ADB Setup***
* In "Wireless ADB Mode", you have 2 choice:

* Wireless ADB + Shizuku:  One-Click Wireless ADB auto-connection with Shizuku
     * [More information & Shizuku auto-connection Quick Start Guide](/Docs/Shizuku_wireless.md)

or

* Wireless ADB: Standard wireless ADB debugging connection.

## 3-Shizuku option (For Termux via Shizuku & Rish):
* Start [Shizuku](https://shizuku.rikka.app/).
* Export the Shizuku shell (`rish`) into Termux environment.
* URAAM will execute elevated package commands directly on-device.

## 📁 File Layout (`~/.Uraam/`)

| Folder | Purpose|| On Debian/Ubuntu with DEB version |
| :--- | :--- | :--- | :--- |
| Configs | `Configs/debloat/` | Place debloat lists here (*Canta/UAD, raw JSON supported*) | $HOME/.local/share/uraam/Configs
| Apps | `Apps/` | Place APKs to batch-install | $HOME/.local/share/uraam/Apps
| backup-restore | `Configs/backup-restore/` | Exported application lists & restore points | $HOME/.local/share/uraam/backup-restore

# ⚡ Quick & Direct Installation

## 📦 Universal 1-Line Installer

**The installer will automatically detectyour platform and guide you through:**

- **Debian / Ubuntu / WSL**: Native `.deb` package (recommended) or standalone binary.
- **Android (Termux)**: Automatic setup with storage and environment checks.
-**macOS & other Linux distros**: Direct standalone installation.

#####For Debian/Ubunu-bzsed distributions

**Install debup with [APT repository](https://github.com/Ruraam/debup/tree/main#option-1-apt-repository-recommended).**

or

Run the universal installer directly in your terminal (**Linux, Mac, Termux or Proot debian/ubuntu**):
*installer download standlone or .deb. 
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Ruraam/Uraam/main/installer.sh || wget -qO- https://raw.githubusercontent.com/Uraam/Uraam/main/installer.sh)
```

## 📦 Recommended for Debian/Ubuntu/WSL/Android Linux Terminal (AVF) [![debup](https://img.shields.io/badge/Install_with-debup-blue)](https://github.com/Ruraam/debup) 
debub - The AUR-like CLI package manager for Debian/Ubuntu-based distributions, WSL, Android Linux Terminal. Search, track, install, and upgrade.deb packages directly from GitHub Releases on all architectures via APT.)


Keep Uraam automatically updated directly from GitHub Releases using **[debup](https://github.com/Ruraam/debup/blob/main/README.md)**:

1. **Install debup:**
```bash
curl -fsSL https://github.com/Ruraam/debup/releases/latest/download/debup_2.0.0_all.deb -o /tmp/debup.deb && sudoapt install -y /tmp/debup.deb && rm -f /tmp/debup.deb
```
2. **Search and track Uraam:**
```bash
dbp search uraam
```
Type 1 & Enter, type 1 when prompted and debup installs URAAM via apt and add it to debup's sources.list for future update.

or
```bash
dbp add Ruraam/Uraam
```
Press enter and debup installs Uraam via apt and add it to debup's sources.list for future update.

### 🔄 Upgrading via debup

Upgrade **Uraam**
Or upgrade all tracked GitHub packages at once:
```bash
dbp upgrade
```

### 🚀 Usage Anywhere
Once installed, simply run the global command from any directory:
```bash
uraam
```
💡 **Desktop Integration:** If installed via the `.deb` package (Debian, Ubuntu, etc.), a desktop entryis automatically created. You can launch URAAM directly from your system applications menu under the **Accessories / Utility** category.

### 📦 Updating / Uninstalling

**To update to the latest release:**
- Use [debup](https://github.com/Uraam/debup/tree/main) (Debian/Ubuntu)
```bash
dbp upgrade
```
- In the URAAM dashboard, select `[u] Update URAAM` to update automatically on all platforms.

- **To uninstall** URAAM: Simply re-run the universal command above and select the uninstall option from the menu.

*(You can also download the latest `.deb` packages directly from the [Releases Page](https://github.com/Uraam/Uraam/releases))*

---

## 📱 Android 15/16 Native Linux Terminal (AVF)

Running the new native Linux VM on Android? You can install URAAM directly with a single command:
```bash
curl -L -O https://github.com/Ruraam/Uraam/releases/download/v4.4.3/uraam-debian_v4.4.3_all.deb && sudo apt install -y ./uraam-debian_v4.4.3_all.deb
```
Launch URAAM with this command:
```bash
uraam
```
> **Note:** On first run (`uraam`), accept the ADB prompt that appears on your phone screen to allowlocal device control.


---

> **Note:**
> -The installer auto-installs **Git** (after confirmation) and handles repository cloning.
> - URAAMauto-installs **ADB** and **JQ** if missing.
> - The `.deb` package automatically handles system dependencies.

📖 *For platform-specific documentation (Termux standalone, macOS, WSL2, Linux udev rules), refer to the URAAM - [Quick Start Guide](/Docs/Quick-Start-Guide.md).*

---
## Dictionary: Technical Context
<details>
<summary><b>⚙️ What is ADB? (Forbeginners)</b></summary>

ADB (Android Debug Bridge) is the core command-line utility that creates a bridge between your computer and your phone’s operating system.

For URAAM, ADB is our primary "privileged channel." It allows us to execute shell commands and surgically modify system packages—all <b>without root access</b>. This is critical for our approach: it lets us strip out bloatware and reclaim device sovereignty while keeping the system’s native security integrity and Samsung Knox completely intact.
</details>

<details>
<summary><b>🐚 What is Bash? (Why we use it)</b></summary>

Bash is the scripting language that powers URAAM. We chose it for one reason: <b>transparency</b>. Unlike closed-source tools that hide their logic in a "blackbox," our Bash scripts are written in plain, readable text. This means you can personally audit, verify, and understand every single command before it touches your device. It is the foundation of a truly trust-based and auditable system.
</details>

<details>
<summary><b>📄 What is JSON? (Our configuration layer)</b></summary>

JSON acts as our "configuration layer." It is a simple, human-readable format that holds the data for the protocol, essentially acting as a map that tells the scripts exactly which packages to target. By separating our data (the JSON files) from our logic (the Bashscripts), we keep the protocol modular and incredibly easy to customize. You don't need to be a coder to manage these lists; you just need to edit the map.
</details>

<details>
<summary><b>🔄 What is Git? (Why it matters)</b></summary>

Git is our "version control" system. Think of it as a time machine for URAAM. Every change, improvement, or optimization we make is recorded in the project's history. This allows us to track exactly how the protocol evolves, roll back to previous versions if needed, and ensures that the project remains a transparent, collaborative, and living system—not just a static file.
</details>

---
## ⚖️ Comparison Matrix

| Feature | Standard Approach (Canta/Shizuku)| **URAAM** |
| :--- | :--- | :--- |
| **Dependencies** | Java, Shizuku, Canta | **jq** |
| **Memory Footprint** | Permanent (Active service) | **None (One-time execution)** |
| **Auditability** | Limited (Black-box) | **Total (Native Bash)** |
| **Complexity** | High (Multi-layered) | **Minimalist (Surgical)** |

---
## 👥 Contributing

**You have a specific device? Create your JSON file list or import Canta/UAD and raw packages list!**

Fork this repo, place it in `/Configs/debloat`, and submit a Pull Request. Your configuration will then be available to the entire community.
To create your JSON list file or import Canta backup [following the contributing guide](Configs/debloat/README.md).

>**Need help with your first contribution?** *[Consult this guide](https://github.com/firstcontributions/first-contributions) to learn the basics of pull requests.*

---
## 📖 Documentation
To gain a deeper understanding of the technical and operational aspects of the protocol, please refer to the following files located in the `/Docs` directory:

<details>
<summary><b>Click to view documentation</b></summary>

>[URAAM Hierarchy](/Docs/Uraam-Hierarchy.md) (3 tiers packages list exemple for S24+)

>>An overview of the Uraam's global architecture.

>[JSON files importation](/Docs/structure-example.json)

>>How to import your personnal .json list files for using with URAAM script.

>[Network & Resource Confinement](/Docs/Network-&-Resource-Confinement-Layers.md)

>>Technical details on system hardening and resource management.

>[Package List](Docs/Tiers-list.md) (S24+)

>>A detailed list of components targeted by the protocol.

>[Replacement](/Docs/Remplacement.md)

>>Documentation regarding software substitution processes and procedures.Users on different hardware or firmware versions should exercise caution and verify package dependencies before execution.

>[Interface Setup](/Docs/Interface-Setup.md)

>A guide to achieving an AOSP-like aestheticand maximum operational efficiency while retaining native Samsung system optimizations.

>>[Monitoring Strategy](/Docs/Monitoring-Strategy.md)

>Methodologies for analyzing system behavior, battery drain, and network telemetry to maintain long-term stability.

>[Safety & Auditing](Docs/Safety-&-Auditing.md)

>>Information regarding code transparency, audit processes, and system integrity maintenance.
</details>

---
### 👥 Credits

*   Package definitions and safe removal classifications adapted from **[Universal Android Debloater Next Generation (UAD-NG)](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation).**
*   Thanks to [Dyokism](https://github.com/dyokism) for code contribution.
*   Big thanks to **[Dyokism](https://github.com/dyokism)**, **[Willie_169](https://github.com/Willie169)**, and for **community** testing and JSON presets.

---
## ✅ Current Status:
Stable environment. No critical system crashes or UI stutters detected in daily driving.

## ⚠️ Disclaimer
*I am not responsible for any issues resulting from system modifications. Always perform a data backup before deployment.*

---
*My other project on github for [Google Pixel6, LineageOS Vanilla 23.2](https://github.com/Ruvyrom/Ruvyrom/tree/main)*



