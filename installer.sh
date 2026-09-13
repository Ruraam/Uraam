#!/usr/bin/env bash
# ==============================================================================
# URAAM - Universal URAAM Android ADB Manager
# Remote Installer & Updater Script
# ==============================================================================

set -eo pipefail

show_logo() {
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

if [ -n "$PREFIX" ] && [[ "$PREFIX" == *com.termux* ]]; then
if [ ! -d "$HOME/storage" ]; then
echo "Storage permission required for backups..."
termux-setup-storage
fi
fi

cleanup() {
printf "%b\n" "${BLUE}------------------------------------------${NC}"
printf "%b\n" "${CYAN}[*] Cleaning up...${NC}"
rm -rf "$INSTALL_DIR/assets" "$INSTALL_DIR/installer.sh"
}

clear
show_logo
echo -e "${BLUE}==========================================${NC}"
echo -e "${CYAN}URAAM RUVOMAIN ADB APP-MANAGER | INSTALLER${NC}"
echo -e "${BLUE}==========================================${NC}"
printf "%b\n" "${CYAN}WELCOME TO URAAM INSTALLER!${NC}"
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
clear
show_logo
printf "%b\n" "${BLUE}------------------------------------------${NC}"
printf "%b\n" "${CYAN}[*] Checking prerequisites...${NC}"

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
fi

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
