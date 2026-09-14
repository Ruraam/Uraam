## ⚙️ Quick Start

**Disconnect Samsung account before using tier 2 and 3 in script and for more privacy and toavoid account sync loops.**

### Universal Ruvomain ADB App-Manager (URAAM)

**1-USB option** ***Enable USB Debugging on your device:***

* Settings > About phone > Tap "Build Number" 7 times

* Settings > Developer Options > Enable "USB Debugging"

* Connect your device to your PC via USB

or

**2-Wireless option** ***Use wireless ADB setup assistant option in Dashboard.***
* Execute script and choose option ***[w] Wireless ADB Setup***
* In "Wireless ADB Mode", you have 2 choice:

* Wireless ADB + Shizuku:  One-Click Wireless ADB auto-connection with Shizuku
     * [More information & Quick Start Guide](/Docs/Shizuku_wireless.md)

or

* Wireless ADB: Standard wireless ADB debugging connection.

or

**3-Shizuku option** ***(For Termux via Shizuku & Rish):***
* Start [Shizuku](https://shizuku.rikka.app/).
* Export the Shizuku shell (`rish`) into Termux environment.
* URAAM will execute elevated package commands directly on-device.

*Note:*
* *- If adb connection fails, ensure your PC and Android device are on the same Wi-Fi network.*
* *- If the pairing code is rejected, turn off Wireless Debugging and turn it back on to refresh the token.*

---
## ⚡ Quick & Direct Installation

### 📦 Universal 1-Line Installer (Recommended)
The installer will automatically detect your platform and guide you through:
- **Debian / Ubuntu**: Native `.deb` package(recommended) or standalone binary.
- **Android (Termux)**: Automatic setup with storage and environment checks.
- **Other Linux distros**: Direct standalone installation.

Run the universal installer directly in your terminal (**Linux PC** or **Android Termux**) :
```bash
bash<(curl -fsSL https://raw.githubusercontent.com/Uraam/Uraam/main/installer.sh)
```

### 📦 Updating / Uninstalling

To **update** to the latest release: In URAAM dashboard, Select "[u] Update URAAM" and will update automatically on all platform. 

For **uninstall** URAAM, simply re-run the same command and choose the corresponding option from the menu:

**You can also downlaod latest DEB files from [Releases Page](https://github.com/Ruvyrom/Uraam/releases)**

> * **Note :**
>> * *The installer auto-install GIT after confirm and takes care of cloning the repository.*
>> * *URAAM auto-install ADB and JQ if necessary.*
>> * *DEB package install dependencies*
### Usage Anywhere

Once installed, simply run the global command from any directory:
```bash
uraam
```

### 📁 File Layout (`~/.Uraam/`)
| Folder | Purpose|| On Debian with DEB version |
| :--- | :--- | :--- | :--- |
| Configs | `Configs/debloat/` | Place debloat lists here (*Canta/UAD, raw JSON supported*) | $HOME/.local/share/uraam/Configs
| Apps | `Apps/` | Place APKs to batch-install | $HOME/.local/share/uraam/Apps
| backup-restore | `Configs/backup-restore/` | Exported application lists & restore points | $HOME/.local/share/uraam/backup-restore

## Other installation method
<details>
<sumary>Prerequisites:</sumary>

- `git` for clone repo

Git installation:

>>Termux
```bash
pkg install git
```
>>Debian, Ubuntu, WSL
```bash
sudo apt install git -y
```
>>Arch based
```bash
sudo pacman -S --no-confirm git
```
>>Fedora based
```bash
sudo dnf install -y git
```

</details>

***Note:** `adb` and `jq` (The script will attempt an android-tools/jq auto-installation if missing).*


<details>
<summary><b></b>Execution:</b></summary>

- **Clone the repo:**
  
```bash
git clone https://github.com/Ruvyrom/Uraam.git
```

Folder layout:
* Place debloat configurations in `./Configs/debloat/` *(Canta JSON supported)*.
* Place APKs to install in `./Apps/`.
* Backups and restoration targets reside in `./Configs/backup-restore/`.

```bash
make -C ./Uraam
```
Or run directly in **Bash**:
```bash
cd ./Uraam
```

```bash
chmod +x uraam.sh && ./uraam.sh
```
</details>
</details>

***Note :***

*- Make sure you run these commands from the directory where you cloned the repository. If you are in your Termux home folder, the command above is correct.*

*- If `adb` fails, run `adb kill-server && adb start-server` and ensure your device appears in `adb devices`.*

</details>

### 🍎 For MacOS users:

Install [Homebrew](https://brew.sh/) if you haven't already.

**Prerequisites:**
```bash
brew install git android-tools jq
```
**Follow the same quick start than [Linux, Termux...](https://github.com/Ruvyrom/Ruvomain-Protocol/blob/main/Docs/Quick-Start-Guide.md#for-linux-termux-wsl)**
