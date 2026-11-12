# Quick Start

This guide takes you from installation to a first, non-destructive device check. For destructive package changes, read [Safety and Recovery](Safety-and-Recovery.md) first.

## 1. Host requirements

URAAM is a Bash application. The current runtime uses these tools:

| Tool | Purpose |
|---|---|
| Bash | Run the application |
| `adb` | Android Debug Bridge backend |
| `jq` | JSON configuration, metadata and journal handling |
| `curl` | Installer and updater network access |
| GNU `timeout` or `gtimeout` | Bound device command execution |
| `flock` | Exclusive lock for destructive debloat apply |
| `sync`, `mktemp`, `mv` | Durable operation journal handling |

The installer can resolve some dependencies on supported package managers. If installing manually, install the tools appropriate to your platform.

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install bash curl jq adb coreutils util-linux
```

### Termux

```bash
pkg update
pkg install bash curl jq android-tools coreutils util-linux
```

Termux may ask for shared-storage access. Grant it only if you want URAAM to access shared files.

### macOS

Install Android platform-tools and GNU coreutils:

```bash
brew install android-platform-tools coreutils jq curl
```

Homebrew's GNU timeout is normally named `gtimeout`. The exclusive `flock` requirement applies to destructive debloat apply; if it is unavailable, URAAM refuses to proceed with that operation.

### Other Linux / WSL

Install Bash, ADB platform-tools, jq, GNU coreutils and util-linux using your distribution's package manager. WSL users must separately configure a reachable ADB transport (for example, Windows ADB or USB/IP); URAAM cannot configure USB passthrough for every WSL setup.

## 2. Install URAAM

### Universal installer

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Ruraam/Uraam/main/installer.sh)
```

Review the installer source first if you prefer not to execute a downloaded script directly. You can also download it and run it locally.

### Debian package

Download the current `uraam-debian_..._all.deb` asset from [Releases](https://github.com/Ruraam/Uraam/releases), then:

```bash
sudo apt install ./uraam-debian_VERSION_all.deb
```

Use the exact filename from the release.

### Run from source

```bash
git clone https://github.com/Ruraam/Uraam.git
cd Uraam
bash ./uraam.sh
```

## 3. Connect the Android device

### USB ADB

1. On Android, open **Settings → About phone** and tap **Build number** until Developer options are enabled.
2. Open **Developer options** and enable **USB debugging**.
3. Connect the device to the host with a data-capable USB cable.
4. Unlock the device and accept the RSA authorization prompt.
5. On the host, run:

```bash
adb devices
```

The device should appear with state `device`. If it appears as `unauthorized`, accept the prompt on Android. If no device appears, check the cable, USB mode, platform-tools and host permissions.

### Wireless debugging

Use Android's **Wireless debugging** developer option and the pairing code/port shown by Android, or use the wireless helper in URAAM. The host and phone must be on the same trusted network. Pairing and connection ports can change; do not assume a fixed port.

See [Shizuku and Wireless ADB](Shizuku_wireless.md).

### Shizuku (Termux)

1. Install and start [Shizuku](https://shizuku.rikka.app/).
2. Follow Shizuku's official instructions for your Android version to start the service.
3. Make the Shizuku shell command `rish` available in the Termux session.
4. Confirm that `rish -c id` succeeds before selecting the Shizuku backend in URAAM.

URAAM does not install or grant Shizuku permissions on your behalf.

### Local root

On a rooted Android environment, URAAM can use the local `su` command when available and authorized. Root access is not required for the ADB workflow.

## 4. First launch

Start URAAM:

```bash
uraam
```

For a source checkout, run `bash ./uraam.sh` from the repository directory.

The dashboard displays the detected backend and active data paths. Confirm that the selected backend points to the intended device before running an operation.

## 5. First safe workflow

For a first run, do not start by uninstalling packages.

1. Open **Debloat apps**.
2. Select a profile and choose the requested action.
3. Review the inventory and UAD-NG risk information.
4. Select only packages you understand.
5. Choose **Dry-run**.
6. Confirm that the displayed package list and operation count match your expectations.

Dry-run does not issue uninstall or disable operations. If you later choose Apply, URAAM requires the exact `APPLY N` confirmation and performs fresh identity/inventory checks.

## 6. Useful dashboard actions

| Key | Action |
|---|---|
| `d` | Debloat apps |
| `i` | Install APK(s) from the Apps directory |
| `b` | Create a restoration list |
| `r` | Restore packages from a selected list |
| `w` | Wireless connection menu |
| `l` | View operation logs |
| `u` | Update URAAM |
| `e` | Exit |

Menu labels are shown by the running version; follow the on-screen prompt if it differs.

## 7. Where files are stored

For a portable checkout, the repository contains `Apps/`, `Configs/` and `Logs/`. For an installed build, user data normally lives under `$XDG_DATA_HOME/uraam` (or `~/.local/share/uraam`) and user profiles under `$XDG_CONFIG_HOME/uraam` (or `~/.config/uraam`).

The dashboard prints the resolved paths. See [Architecture](Architecture.md#data-and-configuration-paths).

## 8. Troubleshooting

- **ADB says unauthorized:** unlock Android and accept the authorization prompt; then rerun `adb devices`.
- **ADB shows no device:** check platform-tools, cable/data mode, USB permissions and the selected serial.
- **Wireless connection fails:** re-enable Wireless debugging, pair again using the current code and port, and check that both devices share a trusted network.
- **Shizuku backend unavailable:** start Shizuku and verify `rish -c id` in the same Termux environment.
- **Timeout utility unavailable:** install GNU coreutils. On macOS, try `gtimeout`; URAAM probes compatibility before sending a device command.
- **Apply refuses because flock is missing:** install util-linux (or provide a compatible `flock`). Do not bypass the lock.
- **An interrupted operation is reported:** read [Safety and Recovery](Safety-and-Recovery.md#interrupted-operation-recovery). Do not delete the journal blindly.
- **Inventory is rejected:** reconnect the backend and retry. URAAM deliberately refuses empty, malformed or partial package inventories.

## Further reading

- [Safety and Recovery](Safety-and-Recovery.md)
- [Architecture](Architecture.md)
- [UAD-NG review catalogue](UAD-NG-review-catalog.md)
