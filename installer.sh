#!/usr/bin/env bash
# ==============================================================================
# Installer Script for URAAM
# Project: URAAM (Universal Ruvomain Android App-Manager)
# Author: Ruvyrom
# License: GPL-3.0
# Description: Automated installer for PC (Debian/Ubuntu/Arch/Fedora) & Android (Termux)
#==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

CURRENT_VERSION="4.4.2"

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
if command -v dpkg-query >/dev/null2>&1; then
local package_status
package_status=$(dpkg-query -W-f='${Status}' "$package_name" 2>/dev/null || true)
if[[ "$package_status" == *"install ok installed"* ]]; then
return 0
fi
fi
return 1
}

device_brand() {
local brand model android_ver
local tbrand tmodel tandroid_ver
local ver_suffix=""

brand=$("$EXEC" getprop ro.product.manufacturer 2>/dev/null || true)
model=$("$EXEC" getprop ro.product.model 2>/dev/null || true)
android_ver=$("$EXEC" getprop ro.build.version.release 2>/dev/null || true)

tbrand=$(getprop ro.product.manufacturer 2>/dev/null || true)
tmodel=$(getprop ro.product.model 2>/dev/null || true)
tandroid_ver=$(getprop ro.build.version.release 2>/dev/null || true)

if [ -n "$brand" ]; then
[ -n "$android_ver" ] && ver_suffix=" (Android ${android_ver})"
CURRENT_MODEL="${brand^} ${model}${ver_suffix}"
elif [ -n "$tbrand" ]; then
[ -n "$tandroid_ver" ] && ver_suffix=" (Android ${tandroid_ver})"
CURRENT_MODEL="${tbrand^} ${tmodel}${ver_suffix}"
elif is_installed_via_deb; then
CURRENT_MODEL="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null) $(uname -s) $(uname -m)"
else
CURRENT_MODEL=""
fi
}

banner() {
clear
device_brand
echo -e "${PURPLE}"
cat << 'EOF'
::| ::|::::::\ ::::\  ::::\ ::::::|
::|_::|::|,::|::|,::|::|,::|:::"::|
`:::::|::| ::\::| ::|::| ::|::| ::|
EOF
echo -e "${NC}"
printf "%b\n" "${BLUE}====================================================${NC}"
printf "%b\n" "     Automated Installer & Manager for URAAM CLI"
[ -n "$CURRENT_MODEL" ] && printf "%b\n" "     Target: ${CYAN}${CURRENT_MODEL}${NC}"
printf "%b\n" "${BLUE}====================================================${NC}"
echo ""
}

check_dependencies() {
if [ -d "/data/data/com.termux" ] || [ -n "$PREFIX" ] && [[ "$PREFIX" == *com.termux* ]]; }; then
IS_TERMUX=true
[ -z "$PREFIX" ] && PREFIX="/data/data/com.termux/files/usr"
if [ ! -d "$HOME/storage" ] && command -v termux-setup-storage >/dev/null2>&1; then
echo -e "${YELLOW}[!] Storage access is required for backups, please grant permission...${NC}"
termux-setup-storage
fi
else
IS_TERMUX=false
fi

local deps=("git" "curl" "jq" "adb")
local missing_deps=()

for dep in "${deps[@]}"; do
if !command -v "$dep" >/dev/null 2>&1; then
missing_deps+=("$dep")
fi
done

if [ "${#missing_deps[@]}" -gt 0 ];then
printf "%b\n" "${YELLOW}[!] Installing required core tools: ${missing_deps[*]}${NC}"
if [ "$IS_TERMUX" = true ]; then
pkg update -y

for dep in "${missing_deps[@]}";do
if [ "$dep" = "adb" ]; then
pkg install -y android-tools
else
pkg install -y "$dep"
fi
done
elif command -v apt>/dev/null 2>&1; then
sudo apt update && sudo apt install -y "${missing_deps[@]}"
elif command -v apt-get >/dev/null 2>&1; then
sudo apt-get update -y && sudo apt-get install -y "${missing_deps[@]}"
elif command -v pacman >/dev/null 2>&1; then
sudo pacman -Sy --noconfirm "${missing_deps[@]}"
elif command -v dnf >/dev/null 2>&1; then
sudo dnfinstall -y "${missing_deps[@]}"
else
printf "%b\n" "${RED}[X] Could not auto-install dependencies. Please install ${missing_deps[*]} manually.${NC}"
exit1
fi
fi
}

fetch_release() {
printf "%b\n" "${CYAN}[*] Fetching latest release info from GitHub...${NC}"
RELEASE_DATA=$(curl -sL "$API_URL")
LATEST_TAG=$(echo "$RELEASE_DATA" | jq -r '.tag_name // empty')

if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "null" ]; then
printf "%b\n" "${RED}[X] Failed to fetch release information.${NC}"
return 1
fi

printf "%b\n" "${GREEN}[+] Online version: ${YELLOW}${LATEST_TAG}${NC} | Current: ${YELLOW}${CURRENT_VERSION}${NC}"
return 0
}

install_process() {
fetch_release || return 1

local action_label prompt_msg
if is_installed_via_deb; then
action_label="Update"
prompt_msg="A new update is available. Do you want to download and install it? [y/N]: "
else
action_label="Installation"
prompt_msg="Latest release found. Do you want to download and install it? [y/N]: "
fi

printf "\n%b" "${YELLOW}[?] ${prompt_msg}${NC}"
read -r confirm

if [[ ! "$confirm" =~ ^[yY]$ ]]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${RED}[X] ${action_label} canceled.${NC}"
read -rp "Press Enter to return to menu..."
return 0
fi

local tmp_dir
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

if [ "$IS_TERMUX" = true ]; then
printf "%b\n" "${CYAN}[*] Searching Termux package or standalone script in release...${NC}"

[ -z "$PREFIX" ] && PREFIX="/data/data/com.termux/files/usr"
mkdir -p "$PREFIX/bin"

TERMUX_DEB_URL=$(echo "$RELEASE_DATA" | jq -r '[.assets[] | select(.name |endswith(".deb")) | select(.name | contains("termux")) | .browser_download_url][0] // empty')

if [ -n "$TERMUX_DEB_URL" ] && [ "$TERMUX_DEB_URL" != "null" ]; then
printf "%b\n" "${GREEN}[+] Found Termux package: $(basename "$TERMUX_DEB_URL")${NC}"
curl -L -o "$tmp_dir/uraam-termux.deb" "$TERMUX_DEB_URL"
dpkg -i "$tmp_dir/uraam-termux.deb" || apt-get install -f -y
else
printf "%b\n" "${YELLOW}[!] Installing standalone script...${NC}"
SCRIPT_URL=$(echo "$RELEASE_DATA" | jq -r '[.assets[] | select(.name == "uraam.sh" or .name == "uraam") | .browser_download_url][0] // empty')
if [ -z "$SCRIPT_URL" ] || [ "$SCRIPT_URL" = "null" ]; then
SCRIPT_URL="https:raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/uraam.sh"
fi
curl -fsSL -o "$PREFIX/bin/uraam" "$SCRIPT_URL"
chmod +x "$PREFIX/bin/uraam"
fi
else

local debian_choice="2"
if is_debian_like; then
printf "\n%b\n" "${YELLOW}[?] Debian/Ubuntu environment detected. Choose installation method:${NC}"
echo -e "  ${CYAN}1) .deb packageinstallation (System package manager)${NC}"
echo -e "  ${CYAN}2) Direct script installation (/usr/local/bin/uraam)${NC}"
read -rp "Select method[1-2, default: 1]: " debian_choice
[ -z "$debian_choice" ] && debian_choice="1"
fi

if [ "$debian_choice" = "1" ]; then
printf "%b\n" "${CYAN}[*] Searching .deb package in release...${NC}"
PC_DEB_URL=$(echo "$RELEASE_DATA" | jq -r '[.assets[] | select(.name | endswith(".deb")) | select((.name | contains("termux")) == false) | .browser_download_url][0] // empty')

if [ -n "$PC_DEB_URL" ] && [ "$PC_DEB_URL" != "null" ]; then
printf "%b\n" "${GREEN}[+] Found Debian package: $(basename "$PC_DEB_URL")${NC}"
curl -L -o "$tmp_dir/uraam-pc.deb" "$PC_DEB_URL"
sudo dpkg -i "$tmp_dir/uraam-pc.deb" || sudo apt install -f -y
else
printf "%b\n" "${YELLOW}[!] No .deb found in release. Falling back to direct script installation...${NC}"
SCRIPT_URL=$(echo "$RELEASE_DATA" | jq -r '[.assets[] | select(.name =="uraam.sh" or .name == "uraam") | .browser_download_url][0] // empty')
if [ -z "$SCRIPT_URL" ] || [ "$SCRIPT_URL" = "null" ]; then
SCRIPT_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/uraam.sh"
fi
sudo curl -fsSL -o "/usr/local/bin/uraam" "$SCRIPT_URL"
sudo chmod +x "/usr/local/bin/uraam"
fi
else
printf "%b\n" "${CYAN}[*] Installing standalone script to /usr/local/bin...${NC}"
SCRIPT_URL=$(echo "$RELEASE_DATA" | jq -r '[.assets[] | select(.name == "uraam.sh" or .name == "uraam") | .browser_download_url][0] // empty')
if [ -z "$SCRIPT_URL" ] || [ "$SCRIPT_URL" = "null" ]; then
SCRIPT_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/uraam.sh"
fi
sudo curl -fsSL -o "/usr/local/bin/uraam" "$SCRIPT_URL"
sudo chmod +x "/usr/local/bin/uraam"
fi
fi
echo ""
printf "%b\n" "${GREEN}[✓] ${action_label} completed successfully!${NC}"
printf "%b\n" "${GREEN}[i] You can now run the app by simply typing: uraam${NC}"
read -rp "Press Enter to return to menu..."
}

uninstall_process(){
printf "\n%b" "${RED}[?] Are you sure you want to uninstall URAAM?[y/N]: ${NC}"
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
banner
local install_label="1) Install / Update URAAM"
if is_installed_via_deb || command -v uraam>/dev/null 2>&1; then
install_label="1) Update / Reinstall URAAM"
fi

echo -e "${YELLOW}Please choose an option:${NC}"
echo -e "  ${CYAN}${install_label}${NC}"
echo -e "  ${CYAN}2) Uninstall URAAM${NC}"
echo -e "  ${CYAN}0) Exit${NC}"
echo ""
read -rp "Enter choice [0-2]: " choice

case "$choice" in
1)
install_process
;;
2)
uninstall_process
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
