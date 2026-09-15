#!/usr/bin/env bash
# ==============================================================================
# Installer Script for URAAM
# Project: URAAM (Universal Ruvomain Android App-Manager)
# Author:Ruvyrom
# License: GPL-3.0
# Description: Automated installer for PC (Debian/Ubuntu/Arch/Fedora) & Android (Termux)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

CURRENT_VERSION="4.4.2"

REPO_URL="https://github.com/Uraam/Uraam"
BRANCH="main"
REPO_OWNER="Uraam"
REPO_NAME="Uraam"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

is_debian_like() {
if [ -f /etc/os-release ]; then
. /etc/os-release
case "$ID" in
debian|ubuntu|linuxmint|pop) return 0 ;;
esac
case "$ID_LIKE" in
*debian*|*ubuntu*) return 0 ;;
esac
fi
return 1
}

is_installed_via_deb() {
local package_name="${1:-uraam-debian}"
if [ -n "$PREFIX" ] && [[ "$PREFIX" == *com.termux* ]]; then
return 1
fi
if command -v dpkg-query >/dev/null 2>&1; then
local package_status
package_status=$(dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null || true)
if [[ "$package_status" == *"install ok installed"* ]]; then
return 0
fi
fi
return 1
}

device_brand() {
local tbrand tmodel tandroid_ver
local ver_suffix=""

tbrand=$(getprop ro.product.manufacturer 2>/dev/null || true)
tmodel=$(getprop ro.product.model 2>/dev/null || true)
tandroid_ver=$(getprop ro.build.version.release 2>/dev/null || true)

if [ -n "$tbrand" ]; then
[ -n "$tandroid_ver" ] && ver_suffix=" (Android ${tandroid_ver})"
CURRENT_MODEL="${tbrand^} ${tmodel}${ver_suffix}"
elif is_installed_via_deb; then
CURRENT_MODEL="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null) $(cat/sys/devices/virtual/dmi/id/product_name 2>/dev/null) $(uname-s) $(uname -m)"
else
CURRENT_MODEL=""
fi
}

show_logo() {
clear
echo -e "${PURPLE}"
cat << 'EOF'
::| ::|::::::\ ::::\  ::::\ ::::::|
::|_::|::|,::|::|,::|::|,::|:::"::|
`:::::|::| ::\::| ::|::| ::|::| ::|
EOF
echo -e "${NC}"
printf "%b\n" "${BLUE}====================================================${NC}"
printf "%b\n" "     Automated Installer & Manager for URAAM CLI"
[ -n "$CURRENT_MODEL" ] && printf "%b\n" "Target: ${CYAN}${CURRENT_MODEL}${NC}"
printf "%b\n" "${BLUE}====================================================${NC}"
echo ""
}

term_set_storage() {
if [ -d "/data/data/com.termux" ] || { [ -n "$PREFIX" ] && [[ "$PREFIX" == *com.termux* ]]; };then
IS_TERMUX=true
[ -z "$PREFIX" ] && PREFIX="/data/data/com.termux/files/usr"
if [ ! -d "$HOME/storage" ] && command -v termux-setup-storage >/dev/null 2>&1; then
echo -e "${YELLOW}[!] Storage access is required for backups, please grant permission...${NC}"
termux-setup-storage
fi
else
IS_TERMUX=false
fi
}

check_dependencies() {
term_set_storage

local deps=("git" "curl" "jq" "adb")
local missing_deps=()

for dep in "${deps[@]}"; do
if ! command -v "$dep" >/dev/null 2>&1; then
missing_deps+=("$dep")
fi
done

if [ "${#missing_deps[@]}" -gt 0 ]; then
printf "%b\n" "${YELLOW}[!] Installing required core tools: ${missing_deps[*]}${NC}"
if [ "$IS_TERMUX" = true ]; then
pkg update -y

for dep in "${missing_deps[@]}"; do
if [ "$dep" = "adb" ]; then
pkg install -y android-tools
else
pkg install -y "$dep"
fi
done
elif command -v apt >/dev/null 2>&1; then
sudo apt update && sudo apt install -y "${missing_deps[@]}"
elif command -v apt-get >/dev/null 2>&1; then
sudo apt-get update -y && sudo apt-get install -y "${missing_deps[@]}"
elif command -v pacman >/dev/null 2>&1; then
sudo pacman -Sy --noconfirm "${missing_deps[@]}"
elif command -v dnf >/dev/null 2>&1; then
sudo dnf install -y "${missing_deps[@]}"
else
printf "%b\n" "${RED}[X] Could not auto-install dependencies. Please install ${missing_deps[*]} manually.${NC}"
exit 1
fi
fi
}

standalone_uraam() {
show_logo
printf "%b\n" "${BLUE}--------------------------------------------${NC}"
printf "%b\n" "   ${CYAN}=== URAAM | Standalone Installer ===${NC}"
printf "%b\n" "${BLUE}--------------------------------------------${NC}"
printf "\n%b" "${YELLOW}[?] You are about to update URAAM. Do you want to download and install it? [y/N]: ${NC}"
read -r confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
printf "%b\n" "${BLUE}--------------------------------------------${NC}"
printf "%b\n" "[X] Update canceled."
return 0
fi

printf "${YELLOW}[*] Updating existing installation...${NC}\n"

local target_bin
if [ -n "$PREFIX" ]; then
target_bin="$PREFIX/bin/uraam"
else
target_bin="/usr/local/bin/uraam"
fi

local raw_url="https://raw.githubusercontent.com/Uraam/Uraam/main/uraam.sh"
local tmp_file
tmp_file=$(mktemp)

if curl -fsSL "$raw_url" -o "$tmp_file"; then
if [ -w "$(dirname "$target_bin")" ] || [ -w "$target_bin" ]; then
cp "$tmp_file" "$target_bin"
chmod +x "$target_bin"
else
sudo cp "$tmp_file" "$target_bin"
sudo chmod +x "$target_bin"
fi
rm -f "$tmp_file"
printf "%b\n" "${GREEN}[✓] URAAM updated successfully.${NC}"
printf "%b\n" "${CYAN}--------------------------------------------${NC}"

if [ -n "$PREFIX" ] && [ ! -f "$HOME/.shortcuts/URAAM" ]; then
echo ""
read -rp"  Create a Termux:Widget home screen shortcut? (y/N): " create_widget
if [[ "$create_widget" =~ ^[yY]([eE][sS])?$ ]]; then
mkdir -p "$HOME/.shortcuts"
cat << 'EOF' > "$HOME/.shortcuts/URAAM"
#!/data/data/com.termux/files/usr/bin/bash
uraam
EOF
chmod +x "$HOME/.shortcuts/URAAM"
printf "%b\n" "${GREEN}[✓]${NC} Shortcut created in ~/.shortcuts/URAAM!"
printf "%b\n" "    (Available via Termux:Widget or Shortcut Maker)\n"
printf "%b\n" "${CYAN}--------------------------------------------${NC}"
fi
fi

read -rp "Press Enter to restart URAAM..."
clear
exec "$target_bin" "$@"
else
rm -f "$tmp_file"
printf "%b\n" "${CYAN}--------------------------------------------${NC}"
printf "%b\n" "${RED}[X] Download failed. Check your internet connection.${NC}"
sleep 1
read -rp "Press Enter to return to main menu"
return 0
fi
}

deb_uraam() {
show_logo

if ! is_debian_like; then
standalone_uraam
return $?
else
printf "%b\n" "${BLUE}--------------------------------------------${NC}"
printf "%b\n" "       ${CYAN}=== URAAM | DEB Installer ===${NC}"
printf "%b\n" "${BLUE}--------------------------------------------${NC}"

printf "%b\n" "${CYAN}[*] Debian .deb installation detected.${NC}"
printf "%b\n" "${CYAN}[*] Checking for updates on GitHub...${NC}"
fi

local api_url
if [[ "$REPO_URL" == *"api.github.com"* ]]; then
api_url="${REPO_URL%/}/releases/latest"
else
local repo_path
repo_path=$(echo "$REPO_URL" | sed -E 's#^https?://github.com/##; s#/$##; s#\.git$##')
api_url="https://api.github.com/repos/${repo_path}/releases/latest"
fi

local release_json
release_json=$(curl -sSL \
-H "Accept: application/vnd.github+json" \
-H "User-Agent: URAAM-Updater" \
"$api_url")

local latest_tag
latest_tag=$(echo "$release_json" | jq -r '.tag_name // empty' 2>/dev/null | tr -d '\r')

if [ -z "$latest_tag" ]; then
local error_message
error_message=$(echo "$release_json" | jq-r '.message // empty' 2>/dev/null)

printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${RED}[X] Error: Unable to fetch release info from GitHub.${NC}"

if [ -n "$error_message" ]; then
printf "%b\n" "${RED}[X] GitHub API response: ${error_message}${NC}"
fi

read -rp "Press Enter to return to main menu"
return 1
fi

local remote_ver="${latest_tag#v}"

local local_ver
local_ver=$(dpkg-query -W -f='${Version}' uraam 2>/dev/null |tr -d '\r')
if [ -z "$local_ver" ]; then
local_ver=$(dpkg-query -W -f='${Version}' uraam-debian 2>/dev/null |tr -d '\r')
fi
local_ver="${local_ver#v}"

printf "%b\n" "${YELLOW}Current version:${NC} ${local_ver}"
printf "%b\n" "${GREEN}Latest version:${NC} ${remote_ver}"

if [ "$local_ver" = "$remote_ver" ]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "\n%b\n" "${GREEN}[✓] URAAM is already up to date!${NC}"
read -rp "Press [Enter] to return to menu..."
return 0
fi

local deb_url
deb_url=$(echo "$release_json" | jq -r '.assets[] | select(.name | test("uraam-debian*\\.deb$")) | .browser_download_url' | head -n1)

if [ -z "$deb_url" ] || [ "$deb_url" = "null" ]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf"\n%b\n" "${RED}[!] New version found (${latest_tag}), but no .deb assetis available.${NC}"
read -rp "Press [Enter] to return to menu..."
return 1
fi

printf "\n%b" "${YELLOW}[?] A new update is available. Do you want to download and install it? [y/N]: ${NC}"
read -r confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${RED}[X] Update canceled.${NC}"
read -rp "Press Enter to return to main menu"
return 0
fi

local tmp_deb="/tmp/uraam-debian_${remote_ver}_all.deb"

printf "\n%b\n" "${CYAN}[*] Downloading: ${deb_url}${NC}"
if ! curl -L --progress-bar -o "$tmp_deb" "$deb_url"; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${RED}[X] Download failed.${NC}"
rm -f "$tmp_deb"
read -rp "Press Enter to return to main menu"
return 1
fi

printf "\n%b\n" "${CYAN}[*] Installing package (sudo required)...${NC}"
if sudo apt-get install -y "$tmp_deb"; then
rm -f "$tmp_deb"
printf "\n%b\n" "${GREEN}[✓]URAAM successfully updated to ${latest_tag}!${NC}"
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${YELLOW}[!] Please restart URAAM to apply changes.${NC}"
exit 0
else
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "\n%b\n" "${RED}[X] Installation failed.${NC}"
rm -f "$tmp_deb"
read -rp "Press Enter to return to main menu"
return 1
fi
}

uninstall_uraam() {
show_logo
printf "\n%b" "${RED}[?] Are you sure you want to uninstall URAAM? [y/N]: ${NC}"
read -r confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
printf "%b\n" "${YELLOW}[*] Uninstallation aborted.${NC}"
read -rp "Press Enter to return to menu..."
return 0
fi

if [ "$IS_TERMUX" = true ]; then
dpkg -r uraam-termux 2>/dev/null || rm -f "$PREFIX/bin/uraam"
else
if is_debian_like && is_installed_via_deb; then
sudo dpkg -r uraam-debian 2>/dev/null || true
fi
sudo rm -f "/usr/local/bin/uraam"
fi

printf "%b\n" "${GREEN}[✓] URAAM has been uninstalled.${NC}"
read -rp "Press Enter to return to menu..."
}

show_menu() {
while true; do
show_logo
local install_label="1) Install / Update URAAM"
if is_installed_via_deb; then
install_label="1) Update/ Reinstall URAAM deb"
elif command -v uraam >/dev/null 2>&1; then
install_label="1) Update / Reinstall URAAM"
fi

echo -e "${YELLOW}Please choose an option:${NC}"
echo -e "  ${CYAN}${install_label}${NC}"
echo -e "  ${CYAN}2) Uninstall URAAM${NC}"
echo -e "  ${CYAN}0) Exit${NC}"
echo -e "${BLUE}---------------------------------------${NC}""
read -rp "Enter choice[0-2]: " choice

case "$choice" in
1)
deb_uraam
;;
2)
uninstall_uraam
;;
0)
clear
printf "%b\n" "${GREEN}Goodbye!${NC}"
exit 0
;;
*)
printf "%b\n" "${RED}[!] Invalid choice.${NC}"
sleep 1
;;
esac
done
}

main() {
check_dependencies
show_menu
}

main "$@"
