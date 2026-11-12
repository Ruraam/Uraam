# Shizuku and Wireless ADB

This guide explains the connection options available to URAAM. Shizuku and ADB are separate Android mechanisms; using one does not automatically configure the other.

## Prerequisites

- A supported Android device with Developer options available.
- A trusted host/device connection (USB or a trusted local Wi-Fi network).
- URAAM installed and its host dependencies available.
- For the Shizuku backend: Shizuku running and the `rish` command available in the same Termux environment.

Official project: [Shizuku](https://shizuku.rikka.app/).

## Option A: Android Wireless debugging (pairing flow)

1. Connect the host and Android device to the same trusted Wi-Fi network.
2. On Android, open **Developer options → Wireless debugging** and enable it.
3. Choose **Pair device with pairing code**.
4. Use the IP address, pairing port and code displayed by Android with the ADB pairing flow.
5. After pairing, connect using the separate connection endpoint shown by Android.
6. Verify the device:

```bash
adb devices
```

The pairing port and connection port are not necessarily the same. Android may change them after reconnecting or rebooting. Use the current values shown on the device; do not assume a fixed port.

URAAM also provides a wireless helper from the dashboard (**[w] Wireless menu**). Follow the exact prompts displayed by the installed version.

## Option B: Shizuku from Termux

1. Install Shizuku from its [official project page](https://shizuku.rikka.app/).
2. Start the Shizuku service using the official instructions for your Android version. On recent Android versions, this commonly uses Wireless debugging; some devices can use a temporary ADB connection.
3. Follow Shizuku's instructions to install or expose its shell command `rish` in Termux.
4. In the same Termux session, verify:

```bash
command -v rish
rish -c id
```

5. Launch URAAM and choose the Shizuku backend when prompted.

URAAM does not start Shizuku, grant its permissions, or install `rish` automatically. Shizuku's service lifecycle and permission model are controlled by Shizuku and Android.

## Option C: USB ADB, then wireless connection

A USB connection can be used as an initial transport when the device's wireless setup requires it:

1. Enable Developer options and USB debugging.
2. Connect by USB and authorize the host.
3. Confirm the device appears as `device` in `adb devices`.
4. Use Android's Wireless debugging pairing workflow or URAAM's helper.
5. Verify the wireless endpoint before unplugging USB.

Do not assume that enabling legacy ADB TCP/IP on port 5555 is equivalent to Android's modern Wireless debugging pairing flow.

## Reconnection

- **After a reboot:** Android may disable wireless debugging or invalidate temporary pairing state. Re-enable it and pair/connect again as needed.
- **After a Wi-Fi change:** confirm both devices are on the same trusted network and use the current IP/port.
- **After a lost ADB session:** inspect `adb devices`, reconnect using the current endpoint and re-authorize if Android asks.
- **After Shizuku stops:** start its service again using the official Shizuku instructions, then re-check `rish -c id`.

## Troubleshooting

| Symptom | Checks |
|---|---|
| Device is `unauthorized` | Unlock Android and accept the RSA authorization prompt |
| `adb devices` is empty | Check cable/data mode, platform-tools, USB permissions or wireless endpoint |
| Pairing fails | Re-open Wireless debugging and use the currently displayed pairing code and port |
| Pairing succeeds but connection fails | Use the separate connection port/address displayed by Android |
| `rish` not found | Revisit Shizuku's Termux integration instructions and check PATH |
| `rish -c id` fails | Check that Shizuku is running and the shell integration is correctly installed |
| URAAM reports backend unavailable | Verify the selected backend independently before attempting any package operation |

Use only networks you trust. Wireless debugging exposes a powerful development interface to the local network while enabled.
