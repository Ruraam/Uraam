#!/usr/bin/env bash
# ==============================================================================
# URAAM - Universal URAAM Android ADB Manager
# Remote Installer & Updater Script
# ==============================================================================

set -eo pipefail

show_logo() {
clear
echo -e "${PURPLE}"
cat << 'EOF'
::| ::|::::::\ ::::\  ::::\ ::::::|
::|_::|::|,::|::|,::|::|,::|:::"::|
`:::::|::| ::\::| ::|::| ::|::| ::|
EOF
echo -e "${NC}"
}

BLUE='\033[0;34m'
BOLD='\033[1m'
CYAN='\033[0;36m'
PURPLE='\e[0;35m'
GREEN='\033[0;32m'
RED='\033[1;31m'
WHITE='\033[0;37m'
YELLOW='\033[0;33m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-$HOME/Uraam}"
REPO_URL="https://github.com/Uraam/Uraam"
BRANCH="${BRANCH:-main}"

tem_set_storage() {
if [ -n "$PREFIX" ] && [[ "$PREFIX" == *com.termux* ]]; then
if [ ! -d "$HOME/storage" ]; then
echo "Storage permission required for backups..."
termux-setup-storage
fi
fi
}

is_installed_via_deb() {
local package_name="${1:-uraam-debian}"
if [ -n "$PREFIX" ] && [[ "$PREFIX" == *com.termux* ]]; then
return 1
fi
if command -v dpkg-query >/dev/null 2>&1; then
local package_status
package_status=$(dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null)
if [[ "$package_status" == *"install ok installed"* ]]; then
return 0
fi
fi
return 1
}

ensure_git() {
if ! command -v git >/dev/null 2>&1; then
printf "${YELLOW}[!] Git is missing. Attempting automatic installation...${NC}\n"
if command -v pkg >/dev/null 2>&1; then
pkg update -y && pkg install git -y
elif command -v apt >/dev/null 2>&1; then
sudo apt update && sudo apt install -y git
elif command -v pacman >/dev/null 2>&1; then
sudo pacman -Sy --noconfirm git
elif command -v dnf >/dev/null 2>&1; then
sudo dnf install -y git
elif command -v brew >/dev/null 2>&1; then
brew install git
else
printf "%b\n" "${RED}[X] Package manager not found. Please install git manually.${NC}"
read -rp "Press [Enter] to exit..."
exit 1
fi
fi
printf "%b\n" "${GREEN}[✓] Git is ready.${NC}"
sleep 3
}

ensure_jq() {
if command -v jq >/dev/null; then
printf "${GREEN}[✓] JQ is already installed and ready to use.${NC}\n"
return 0
fi

printf "${RED}[!] JQ is not detected on your system.${NC}\n"
read -p "Do you want to install JQ now? (y/n) : " choice

case "$choice" in
y|Y)
printf "%b\n" "${GREEN}[+] Attempting automatic installation...${NC}"

if [ -n "$PREFIX" ] && [[ "$PREFIX" == *com.termux* ]] && command -v pkg >/dev/null; then
pkg install -y jq
elif is_installed_via_deb; then
sudo apt install -y jq
elif command -v apt-get >/dev/null; then
sudo apt-get update && sudo apt-get install -y jq
elif command -v pacman >/dev/null; then
sudo pacman -S --noconfirm jq
elif command -v dnf >/dev/null; then
sudo dnf install -y jq
elif command -v brew >/dev/null; then
brew install jq
else
printf "%b\n" "${RED}[!] Package manager not supported. Please install JQ manually.${NC}" >&2
read -rp "Press [Enter] to return to main menu..."
return 1
fi
;;
*)
printf "%b\n" "${YELLOW}[-] Installation cancelled. JQ is required for the project to work properly.${NC}"
return 1
;;
esac
}

direct_install() {
show_logo
printf "%b\n" "${BLUE}------------------------------------------${NC}"
printf "%b\n" "${CYAN}=== URAAM v4.4.1 Direct Installer ===${NC}"
printf "%b\n" "${BLUE}------------------------------------------${NC}"
printf "%b\n" "${CYAN}This installer will:${NC}"
printf "%b\n" "${WHITE} • Download URAAM from official repo${NC}"
printf "%b\n" "${WHITE} • Auto-install git if missing${NC}"
printf "%b\n" "${WHITE} • Setup files into ~/Uraam${NC}"
printf "%b\n" "${WHITE} • Expose 'uraam' command in PATH${NC}"
printf "%b\n" "${BLUE}------------------------------------------${NC}"

read -p "Do you want to start the installation of URAAM? (y/n) : " choice

case "$choice" in
y|Y)
show_logo

printf "%b\n" "${BLUE}--------------------------------------------${NC}"
if [ -d "$INSTALL_DIR/.git" ]; then
printf "%b\n" "${CYAN}[*] Updating existing installation...${NC}"
cd "$INSTALL_DIR" || exit 1
git fetch --all --prune >/dev/null 2>&1
if git reset --hard "origin/$BRANCH" >/dev/null 2>&1; then
printf "%b\n" "${GREEN}[✓] Core repository updated successfully.${NC}"
else
printf "%b\n" "${BLUE}--------------------------------------------${NC}"
printf "%b\n" "${RED}[X] Git reset failed. Check repository branch status.${NC}"
read -rp "Press [Enter] to exit..."
exit 1
fi
else
printf "%b\n" "${CYAN}[*] Performing initial clone to: ${INSTALL_DIR}...${NC}"
mkdir -p "$(dirname "$INSTALL_DIR")"

git clone --depth 1 -b "$BRANCH" --progress "$REPO_URL" "$INSTALL_DIR" 2>&1 | while IFS= read -r line; do
if [[ "$line" =~ Receiving\ objects:[[:space:]]*([0-9]+)% ]]; then
percent="${BASH_REMATCH[1]}"
completed=$(( percent / 5 ))
remaining=$(( 20 - completed ))
bar_done=$(printf "%${completed}s" | tr ' ' '#')
bar_empty=$(printf "%${remaining}s" | tr ' ' '-')
printf "\r${CYAN}[${bar_done}${bar_empty}] ${percent}%%${NC}"
fi
done

if [ -d "$INSTALL_DIR/.git" ]; then
printf "%b\n" "\r${GREEN}[####################] 100%%${NC}"
printf "%b\n" "${GREEN}[✓] Repository cloned successfully.${NC}"
cd "$INSTALL_DIR" || exit 1
else
printf "%b\n" "${BLUE}--------------------------------------------${NC}"
printf "%b\n" "\n${RED}[X] Failed to clone repository. Check your connection.${NC}"
read -rp "Press [Enter] to exit..."
exit 1
fi
fi

if [ -f "$INSTALL_DIR/uraam.sh" ]; then
chmod +x "$INSTALL_DIR/uraam.sh"
find "$INSTALL_DIR" -type f -name "*.sh" -exec chmod +x {} +
else
printf "%b\n" "${BLUE}--------------------------------------------${NC}"
printf "%b\n" "${RED}[X] Critical error: uraam.sh was not found in ${INSTALL_DIR}.${NC}"
read -rp "Press [Enter] to exit..."
exit 1
fi

BIN_DIR=""
if [ -n "$PREFIX" ] && [ -d "$PREFIX/bin" ]; then
BIN_DIR="$PREFIX/bin"
elif [ -w "/usr/local/bin" ]; then
BIN_DIR="/usr/local/bin"
else
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
fi

ln -sf "$INSTALL_DIR/uraam.sh" "$BIN_DIR/uraam"
chmod +x "$BIN_DIR/uraam"
printf "%b\n" "${BLUE}--------------------------------------------${NC}"
printf "%b\n" "${GREEN}[✓] Command 'uraam' linked to %s${NC}" "$BIN_DIR"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
SHELL_NAME="$(basename "${SHELL:-bash}")"
RC_FILE=""

case "$SHELL_NAME" in
zsh)  RC_FILE="$HOME/.zshrc" ;;
bash) RC_FILE="$HOME/.bashrc" ;;
*)
if [ -f "$HOME/.bashrc" ]; then
RC_FILE="$HOME/.bashrc"
elif [ -f "$HOME/.profile" ]; then
RC_FILE="$HOME/.profile"
fi
;;
esac

EXPORT_LINE="export PATH=\"\$PATH:$BIN_DIR\""

if [ -n "$RC_FILE" ]; then
if ! grep -qsF "$EXPORT_LINE" "$RC_FILE" 2>/dev/null; then
printf "%b\n"  "\n# URAAM ADB Manager\n%s\n" "$EXPORT_LINE" >> "$RC_FILE"
printf "%b\n"  "${GREEN}[✓] Added %s to PATH in%s${NC}" "$BIN_DIR" "$RC_FILE"
printf "%b\n"  "${YELLOW}[i] Run 'source %s' or restart your terminal to apply changes.${NC}" "$RC_FILE"
fi
else
printf "%b\n" "${YELLOW}[!] Could not detect shell RC file. Please add manually:${NC}\n"
printf "%b\n" "${YELLOW}    %s${NC}\n" "$EXPORT_LINE"
fi
}

cleanup
printf "%b\n" "${BLUE}============================================${NC}"
printf "%b\n" "${CYAN}URAAM has been successfully installed!${NC}"
printf "%b\n" "${CYAN}Run '${WHITE}uraam${NC}' to start.${NC}"
printf "%b\n" "${BLUE}============================================${NC}"
;;

n|N)
printf "%b\n" "${YELLOW}[-] Installation aborted by user.${NC}\n"
exit 0
;;

*)
printf "%b\n" "${RED}[!] Invalid choice. Installation canceled.${NC}\n"
exit 1
;;
esac
}

debian_deb_installer() {
show_logo
printf "%b\n" "${BLUE}------------------------------------------${NC}"
printf "%b\n" "${CYAN}=== URAAM v4.4.2 Direct DEB installer ===${NC}"
printf "%b\n" "${BLUE}------------------------------------------${NC}"
printf "%b\n" "${CYAN}This installer will:${NC}"
printf "%b\n" "${WHITE} • Download UTAAM DEB from official repo${NC}"
printf "%b\n" "${WHITE} • Auto-install git if missing${NC}"
printf "%b\n" "${WHITE} • Setup files into HOMR/.local/share/uraam${NC}"
printf "%b\n" "${WHITE} • Add URAAM in system menu by .desktop file${NC}"
printf "%b\n" "${BLUE}------------------------------------------${NC}"

read -p "Do you want to start the installation of URAAM? (y/n) : " choice

case "$choice" in
y|Y)
show_logo
printf "%b\n" "${BLUE}------------------------------------------${NC}"

printf "%b\n" "${CYAN}[*] Debian detected.${NC}"
printf "%b\n" "${CYAN}[*] Checking for Latest DEB Release on GitHub...${NC}"

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
error_message=$(echo "$release_json" | jq -r '.message // empty' 2>/dev/null)

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
local_ver=$(dpkg-query -W -f='${Version}' uraam 2>/dev/null | tr -d '\r')
if [ -z "$local_ver" ]; then
local_ver=$(dpkg-query -W -f='${Version}' uraam-debian 2>/dev/null | tr -d '\r')
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
printf "\n%b\n" "${RED}[!] New version found (${latest_tag}), but no .deb asset is available.${NC}"
read -rp "Press [Enter] to return to menu..."
return 1
fi

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

if [[ ! "$confirm" =~ ^[yY]$]]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${RED}[X] ${action_label} canceled.${NC}"
read -rp "PressEnter to return to main menu..."
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
printf "\n%b\n" "${GREEN}[✓] URAAM successfully updated to ${latest_tag}!${NC}"
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

cleanup() {
printf "%b\n" "${BLUE}------------------------------------------${NC}"
printf "%b\n" "${CYAN}[*] Cleaning up...${NC}"
rm -rf "$INSTALL_DIR/assets" "$INSTALL_DIR/installer.sh"
}

show_main_menu() {
show_logo
printf "%b\n" "${BLUE}------------------------------------------${NC}"
printf "%b\n" "${CYAN}=== URAAM v4.4.1 Installer ===${NC}"
printf "%b\n" "${BLUE}------------------------------------------${NC}"
printf "%b\n" "${CYAN}Welcome to URAAM installer!${NC}"
printf "%b\n" "${BLUE}------------------------------------------${NC}"
echo -e "   [d] ${CYAN}Direct Installation${NC} ${YELLOW}(For all system)${NC}"
echo -e "   [i] ${CYAN}Deb Package Installation${NC}" 
echo -e "           ${YELLOW}(Download and install .deb for Debian only))${NC}"
echo -e "${BLUE}--------------------${NC} [e] Exit" ${BLUE}------${NC}
} 

handle_menu_choice() {
local choice="$1"
case "$choice" in
d|D)
clear
printf "%b\n" "${CYAN}[*] Checking prerequisites...${NC}"
ensure_git || return 1
direct_install
;;
i|I)
clear
printf "%b\n" "${CYAN}[*] Checking prerequisites...${NC}"
ensure_git || return 1
ensure_jq || return 1
debian_deb_installer
;;
e|E)
printf "%b\n" "${GREEN}Goodbye!${NC}"
exit 0
;;
*)
printf "%b\n" "${RED}[X] Invalid option!${NC}"
sleep 1
;;
esac
}

main() {
while true; do
term_set_storage
show_main_menu
read -rp "Enter choice: " user_choice
handle_menu_choice "$user_choice"
done
}

main
