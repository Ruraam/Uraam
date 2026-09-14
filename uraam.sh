#!/usr/bin/env bash
#
# URAAM - Universal Ruvomain ADB App-Manager v4.4.2
#
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
SOURCE="$(readlink "$SOURCE")"
[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

if [[ "$SCRIPT_DIR" == */bin* ]] || [[ "$SCRIPT_DIR" == /usr/* ]]; then
USER_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/uraam"
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/uraam"
else
USER_CONFIG_DIR="$SCRIPT_DIR/Configs"
fi

REPO_DIR="$SCRIPT_DIR"
APP_DIR="$USER_DATA_DIR/Apps"
USER_DEBLOAT_DIR="$USER_CONFIG_DIR/debloat"
CONFIGS_DIR="$USER_DEBLOAT_DIR"
USER_BACKUPS_DIR="$USER_DATA_DIR/Configs/backup-restore"
BACKUPS_DIR="$USER_BACKUPS_DIR"

LOGD_DIR="$USER_DATA_DIR/Logs/debloat"
LOGB_DIR="$USER_DATA_DIR/Logs/backup"
LOGR_DIR="$USER_DATA_DIR/Logs/restore"

REPO_URL="https://github.com/Uraam/Uraam"
BRANCH="main"

if [ -z "$INSTALL_DIR" ]; then
if [ -n "$PREFIX" ] &&[ -f "$PREFIX/bin/uraam" ]; then
INSTALL_DIR="$PREFIX/bin"
elif [ -f "/usr/local/bin/uraam" ];then
INSTALL_DIR="/usr/local/bin"
elif [ -d "$HOME/Uraam" ]; then
INSTALL_DIR="$HOME/Uraam"
else
INSTALL_DIR="$SCRIPT_DIR"
fi
fi

mkdir -p "$USER_DEBLOAT_DIR" "$BACKUPS_DIR" "$APP_DIR" "$LOGD_DIR" "$LOGB_DIR" "$LOGR_DIR"

BLUE='\033[0;34m'
BOLD='\033[1m'
CYAN='\033[0;36m'
PURPLE='\e[0;35m'
GREEN='\033[0;32m'
RED='\033[1;31m'
WHITE='\033[0;37m'
YELLOW='\033[0;33m'
NC='\033[0m'

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

init_debloat_configs() {
if ! compgen -G "$USER_DEBLOAT_DIR/*.json" >/dev/null; then
if [ -d "/usr/share/uraam/Configs/debloat" ]; then
cp -n /usr/share/uraam/Configs/debloat/*.json "$USER_DEBLOAT_DIR/" 2>/dev/null || true
elif command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
echo -e "${CYAN}[*] Initializing default debloat lists...${NC}"
local api_files
api_files=$(curl -s "https://api.github.com/repos/Uraam/Uraam/contents/Configs/debloat?ref=${BRANCH}" | jq -r '.[] | select(.name | endswith(".json")) | .download_url' 2>/dev/null)
for url in $api_files; do
[ -n "$url" ] && curl -sL "$url" -o "$USER_DEBLOAT_DIR/$(basename "$url")"
done
fi
fi
}

term_set_storage() {
if {[ -d "/data/data/com.termux" ] || [[ "$PREFIX" == *com.termux* ]]; } && [ ! -d "$HOME/storage" ]; then
if command -v termux-setup-storage >/dev/null 2>&1; then
echo -e "${YELLOW}[!] Storage permission required for backups...${NC}"
termux-setup-storage
sleep 2
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

ensure_adb() {
if command -v adb >/dev/null; then
printf "${GREEN}[✓] ADB is already installed and ready to use.${NC}\n"
return 0
fi

printf "${RED}[!] ADB is not detected on your system.${NC}\n"
read -p "Do you want to install ADB now? (y/n) : " choice

case "$choice" in
y|Y)
printf "${GREEN}[+] Attempting automatic installation...${NC}\n"
if [ -n "$PREFIX" ] && [[ "$PREFIX" == *com.termux* ]] && command -v pkg >/dev/null; then
pkg install -y android-tools
elif is_installed_via_deb; then
sudo apt install -y adb
elif command -v apt-get >/dev/null; then
sudo apt-get update && sudo apt-get install -y adb
elif command -v pacman >/dev/null; then
sudo pacman -S --noconfirm android-tools
elif command -v dnf >/dev/null; then
sudo dnf install -y android-tools
elif command -v brew >/dev/null; then
brew install android-platform-tools
else
printf "${RED}[!] Package manager not supported. Please install ADB manually.${NC}\n" >&2
sleep 1
read -rp "Press [Enter] to return to main menu..."
return 1
fi
;;
*)
printf "${YELLOW}[-] Installation cancelled. ADB is required for the project to work properly.${NC}\n"
return 1
;;
esac
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

device_brand() {
local brand model android_ver
local tbrand tmodel tandroid_ver
local ver_suffix=""

brand=$("$EXEC" getprop ro.product.manufacturer 2>/dev/null|| echo "")
model=$("$EXEC" getprop ro.product.model 2>/dev/null ||echo "")
android_ver=$("$EXEC" getprop ro.build.version.release 2>/dev/null || echo "")

tbrand=$(getprop ro.product.manufacturer 2>/dev/null || echo "")
tmodel=$(getprop ro.product.model 2>/dev/null || echo "")
tandroid_ver=$(getprop ro.build.version.release 2>/dev/null || echo "")

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

detect_backend_status() {
EXEC=""
EXEC_TYPE=""

if is_installed_via_deb; then
if command -v adb >/dev/null 2>&1; then
local connected
connected=$(adb devices 2>/dev/null | grep -v "List of devices" | grep "device$" | head -n 1)
if [ -n "$connected" ]; then
EXEC="adb shell"
EXEC_TYPE="ADB"
device_brand
printf "%b\n" "${PURPLE}[Host]${NC} $CURRENT_MODEL"
printf "%b\n" "${PURPLE}[Target]${NC} $CURRENT_MODEL"
printf "%b\n" "${GREEN}[✓] Execution backend: ADB (Debian)${NC}"
return 0
fi
fi
device_brand
printf "%b\n" "${PURPLE}[Host]${NC} $CURRENT_MODEL"
printf "%b\n" "${RED}[!] No target device connected via ADB.${NC}"
return 1
fi

if [ "$(id -u)" -eq 0 ] || { command -v su >/dev/null 2>&1 && su -c "id" >/dev/null 2>&1; }; then
EXEC="su -c"
EXEC_TYPE="ROOT"
device_brand
printf "%b\n" "${PURPLE}[Host]${NC} $CURRENT_MODEL"
printf "%b\n" "${GREEN}[✓] Execution backend: ROOT (su)${NC}"
return0
fi

if command -v rish >/dev/null 2>&1 && echo "exit" | rish >/dev/null 2>&1; then
EXEC="rish -c"
EXEC_TYPE="SHIZUKU"
device_brand
printf "%b\n" "${PURPLE}[Host]${NC} $CURRENT_MODEL"
printf "%b\n" "${GREEN}[✓] Execution backend: SHIZUKU (Rish)${NC}"
return 0
fi

if command -v adb >/dev/null 2>&1; then
local connected
connected=$(adb devices 2>/dev/null |grep -v "List of devices" | grep "device$" | head -n 1)
if [ -n "$connected" ]; then
EXEC="adb shell"
EXEC_TYPE="ADB"
device_brand
printf "%b\n" "${PURPLE}[Host]${NC} $CURRENT_MODEL"
printf "%b\n" "${PURPLE}[Target]${NC} $CURRENT_MODEL"
printf "%b\n" "${GREEN}[✓] Execution backend: ADB (Connected)${NC}"
return 0
fi
fi

device_brand
printf "%b\n" "${PURPLE}[Host]${NC} $CURRENT_MODEL"
printf "%b\n" "${RED}[!] No execution backend detected.${NC}"
return 1
}

require_backend() {
show_logo
ensure_adb || 1
ensure_jq || return 1

if ! detect_backend_status; then
printf "%b\n" "${BLUE}--------------------------------------------------------${NC}"
printf "%b\n" "${RED}[ERROR] Action aborted: no active backend detected!${NC}"
printf "%b\n""${YELLOW}[!] Make sure:${NC}"
printf "%b\n" "  ${CYAN}1.USB/Wireless debugging is enabled and authorized.${NC}"
printf "%b\n" "  ${CYAN}2.The device is visible via 'adb devices' (or rish/root active).${NC}"
printf "%b\n" "${BLUE}--------------------------------------------------------${NC}"
read -rp "Press [Enter] to return to main menu..."
return 1
fi
return 0
}

init_logs() {
mkdir -p "$LOGD_DIR"

find "$LOGD_DIR" -name "uraam-debloat-*.log" -type f -mtime +30 -delete 2>/dev/null

LOGFILE="$LOGD_DIR/uraam-debloat-$(date +%Y%m%d_%H%M%S).log"

exec> >(tee -a "$LOGFILE") 2>&1
}

init_logs_backup() {
mkdir -p "$LOGB_DIR"

find "$LOGB_DIR" -name "uraam-backup-*.log" -type f -mtime +30 -delete 2>/dev/null

LOGFILE="$LOGB_DIR/uraam-backup-$(date +%Y%m%d_%H%M%S).log"

exec> >(tee -a "$LOGFILE") 2>&1
}

init_logs_restore() {
mkdir -p "$LOGR_DIR"

find "$LOGR_DIR" -name "uraam-restore-*.log" -type f -mtime +30 -delete 2>/dev/null

LOGFILE="$LOGR_DIR/uraam-restore-$(date +%Y%m%d_%H%M%S).log"

exec> >(tee -a "$LOGFILE") 2>&1
}

wireless_adb() {
show_logo
printf "%b\n" "${BLUE}===================================================${NC}"
printf "%b\n" "${CYAN}URAAM RUVOMAIN ADB APP-MANAGER | WIRELESS ADB SETUP${NC}"
printf "%b\n" "${BLUE}===================================================${NC}"
printf "%b\n" "${CYAN}CRITICAL STEP: Wireless Debugging.${NC}"
printf "%b\n" "${CYAN} 1. Go to Settings > Developer Options.${NC}"
printf "%b\n" "${CYAN} 2. Tap on 'Wireless debugging' (the text itself).${NC}"
printf "%b\n" "${CYAN} 3. Select 'Pair device with pairing code'.${NC}"
printf "%b\n" "${BLUE}---------------------------------------------------${NC}"
ensure_adb || return 1
check_adb_menu
printf "%b\n" "\n${BLUE}-------------------------------------------------${NC}"

printf "%b\n" "Do you need to PAIR first (y/N)" 
read -rp " " need_pair

case "$need_pair" in
y|Y)
printf "%b\n" "\n--- STEP 1: PAIRING ---"
printf "%b\n" "\n${CYAN}Check the pairing popup dialog${NC}"
printf "%b\n" "${CYAN}for IP:Port and the 6-digit code.${NC}"
read -rp "Enter PAIRING host:port or just PORT: " pair_input
if [[ "$pair_input" =~ ^[0-9]+$ ]]; then
pair_host="127.0.0.1:$pair_input"
else
pair_host="$pair_input"
fi

read -rp "Enter 6-digit PAIRING CODE: " pair_code

if [ "$need_pair" = "y" ] || [ "$need_pair" = "Y" ]; then
if [ -z "$pair_host" ] || [ -z "$pair_code" ]; then
printf "%b\n" "\n${RED}[!] Pairing aborted: host or code cannot be empty.${NC}"
printf "%b\n" "\n${BLUE}----------------------------------------------------${NC}"
printf "%b\n" "Press Enter to return to main menu..."
read -rp ""
return 1
fi
adb pair "$pair_host" "$pair_code"
else
printf "%b\n" "\n${RED}[!] Pairing aborted: host or code cannot be empty.${NC}"
fi
;;
esac

printf "%b\n" "\n--- STEP 2: CONNECTION ---"
printf "%b\n" "\n${CYAN}Look at the main Wireless Debugging screen${NC}" 
printf "%b\n" "${CYAN}for the CONNECTION port.${NC}"

read -rp "Enter CONNECTION host:port or just PORT: " conn_host
if [[ "$conn_input" =~ ^[0-9]+$ ]]; then
conn_host="127.0.0.1:$conn_input"
else
conn_host="$conn_host"
fi

if [ -n "$conn_host" ]; then
printf "%b\n" "\n${YELLOW}[*] Connecting to $conn_host...${NC}"
adb connect "$conn_host"

sleep 1
if adb devices | grep -q "$conn_host.*device"; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "\n${GREEN}[✓] Successfully connected via Wireless ADB!${NC}"
else
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "\n${RED}[!] Connection failed.${NC}"
printf "%b\n" "Check IP/Port and make sure screen is on."
fi
else
printf "%b\n" "${BLUE}---------------------------------------${NC}"
echo -e "\n${RED}[!] Connection aborted: host empty.${NC}"
fi

printf "%b\n" "\n${BLUE}--------------------------------------------------------${NC}"
printf "%b\n" "Press Enter to return to main menu..."
read -rp ""
return 1
}

wireless_shizuku() {
show_logo
printf "%b\n" "${BLUE}==================================================${NC}"
printf "%b\n" "${CYAN}URAAM RUVOMAIN ADB APP-MANAGER | WIRELESS SHIZUKU${NC}"
printf "%b\n" "${BLUE}==================================================${NC}"
printf "%b\n" "${CYAN}WIRELESS ADB & SHIZUKU SETUP${NC}"
printf "%b\n" " ${CYAN}1.Starts Shizuku and enables Wireless ADB in a single step.${NC}"
printf "%b\n" " ${CYAN}2.Unplug your USB cable:no need to plug it in again!${NC}"
printf "%b\n" "\n${BLUE}------------------------------------------------${NC}"
ensure_adb || exit 1
check_adb_menu
printf "%b\n" "\n${BLUE}------------------------------------------------${NC}"
if ! $EXEC pm path moe.shizuku.privileged.api >/dev/null 2>&1; then
wireless_adb
return 0 2>/dev/null || exit 0
fi

if [[ "$EXEC" =~ "rish" ]]; then
printf "%b\n" "${GREEN}[✓] Shizuku is already active (running under rish context).${NC}"
else
SHIZUKU_CHECK=$($EXEC pidof rish 2>/dev/null || $EXEC ps-A 2>/dev/null | grep -i shizuku)

if [ -z "$SHIZUKU_CHECK" ]; then
printf "%b\n" "${YELLOW}[!] Starting Shizuku service...${NC}"
$EXEC sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh 2>/dev/null || \
$EXEC sh /data/user_de/0/moe.shizuku.privileged.api/bin/start.sh 2>/dev/null
sleep 3
else
printf "%b\n" "${YELLOW}[!] Shizuku is already running.${NC}"
fi
fi

printf "%b\n" "${YELLOW}[!] Enabling wireless ADB on port 5555...${NC}"
adb tcpip 5555
sleep 2

IP=$(adb shell ip -finet addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)

if [ -z "$IP" ]; then
IP=$(adb shell ip route 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i}' | head -n1)
fi

if [ -z "$IP" ]; then
printf "%b\n" "\n${BLUE}--------------------------------------------------${NC}"
printf "%b\n" "${RED}[X] Could not automatically determine device IP. Please ensure Wi-Fi is connected.${NC}"
printf "%b\n" "${YELLOW}[*] You can manually connect using: adb connect${NC} <device-ip>:5555"
else
printf "%b\n" "${GREEN}[✓] Device IP detected:${NC} $IP"
printf "%b\n" "${YELLOW}[!] Connecting to wireless ADB...${NC}"
adb connect "$IP:5555"
printf "%b\n" "\n${BLUE}--------------------------------------------------${NC}"
printf "%b\n" "${GREEN}[✓] Wireless ADB setup complete!${NC} You can now unplug your cable."
printf "%b\n" "${YELLOW}[*] To reconnect later: adb connect $IP:5555${NC}"
read -rp "Press Enter to return to main menu"
return 0
fi
}

uraam_debloat() {
show_logo
printf "%b\n" "${BLUE}==========================================${NC}"
printf "%b\n" "        ${CYAN}=== URAAM | Debloater ===${NC}"
printf "%b\n" "${BLUE}==========================================${NC}"
printf "%b\n" "${CYAN}Place debloat configurations in ./Configs/debloat/${NC}"
printf "%b\n" "${CYAN}(Canta JSON, UAD lists & raw packages supported).${NC}"
printf "%b\n" "\n${CYAN}You have the choice to ${WHITE}[D]${NC}isable or ${WITHE}[U]${NC}ninstall packages.${NC}"
echo -e "${BLUE}------------------------------------------${NC}"
init_debloat_configs
printf "%b\n" "${YELLOW}[*] Fetching installed packages...${NC}"
local installed_packages
installed_packages=$($EXEC pm list packages 2>/dev/null | sed 's/^package://' | tr -d '\r')

if [ -z "$installed_packages" ]; then
printf "%b\n" "${RED}[ERROR] Failed to fetch packages from device.${NC}"
read -rp "Press [Enter] to return..."
return 1
fi

local files=()

shopt -s nullglob
files+=("$CONFIGS_DIR"/*.json)
if [ "$USER_DEBLOAT_DIR" != "$CONFIGS_DIR" ]; then
files+=("$USER_DEBLOAT_DIR"/*.json)
fi
shopt -u nullglob

if [ "$USER_DEBLOAT_DIR" != "$CONFIGS_DIR" ]; then
for f in "$USER_DEBLOAT_DIR"/*.json; do
[ -e "$f" ] && files+=("$f")
done
fi

if [ ${#files[@]} -eq 0 ]; then
printf "%b\n" "\n${RED}[X] No .json files found in $CONFIGS_DIR${NC}"
read -rp "Press Enter to return to main menu..."
return 1
fi

printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${GREEN}[✓] Configuration files found:${NC}"
printf "%b\n" "${BLUE}---------------------------------------${NC}"

local display_names=()
for f in "${files[@]}"; do
display_names+=("$(basename "$f")")
done

PS3="Select the file number (1-${#files[@]}): "
select short_name in "${display_names[@]}"; do
if [ -n "$short_name" ]; then
file="${files[$((REPLY-1))]}"
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${YELLOW}[!] Selected file:${NC} ${GREEN}${short_name}${NC}"
break
else
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "\n${RED}[X] Invalid selection, please try again.${NC}"
sleep 4
fi
done

mapfile -t PACKAGES < <(jq -r '
  def extract:
    if type == "string" and test("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+$") then
      .
    elif type == "object" then
      (.packageName // .package // empty)
    elif type == "array" then
      .[] | extract
    else
      empty
    end;

 if .apps then .apps[] | extract
 elif .packages then .packages[] | extract
 elif type == "array" then .[] | extract
 else extract
 end
 ' "$file" 2>/dev/null | sort -u)

 if [ ${#PACKAGES[@]} -eq 0 ]; then
 printf "%b\n" "${BLUE}---------------------------------------${NC}"
 printf "%b\n" "${RED}[X] No packages found. Verify the JSON format.${NC}"
 sleep 1
 read -rp "Press Enter to return to main menu"
 return 1
 fi

echo -e "${YELLOW}[?] Choose action: [U]ninstall  /  [D]isable  /  [C]ancel: ${NC}"
read -r action

case "$action" in
[Uu])
ACTION="uninstall"
ACTION_LABEL="removed"
;;
[Dd])
ACTION="disable"
ACTION_LABEL="disabled"
;;
*)
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${YELLOW}[X] Operation cancelled.${NC}"
sleep 1
read -rp "Press Enter to return to main menu"
return 0
;;
esac

printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "\n%b" "${YELLOW}[?] You are about to $ACTION packages... continue? [y/N]: ${NC}"
read -r confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${YELLOW}[X] Operation canceled.${NC}"
return 0
fi

printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${YELLOW}[!] Fetching installed packages from device...${NC}"
local INSTALLED_PKGS
INSTALLED_PKGS=$($EXEC pm list packages -u 2>/dev/null | tr -d '\r' | cut -d: -f2)

printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${YELLOW}[!] Starting $ACTION of ${#PACKAGES[@]} packages...${NC}"

local SUCCESS=0
local SKIPPED=0
local FAILED=0

for pkg in "${PACKAGES[@]}"; do
[ -z "$pkg" ] && continue
echo -n "${YELLOW}Checking${NC} $pkg: "

if ! echo "$INSTALLED_PKGS" | grep -qx "$pkg"; then
printf "%b\n" "${YELLOW}[*] Skipped (not installed)${NC}"
((SKIPPED++))
continue
fi

if [ "$ACTION" = "uninstall" ]; then
if $EXEC pm uninstall -k --user 0 "$pkg" >/dev/null 2>&1; then
echo -e "\n${GREEN}[✓] Success ($ACTION_LABEL)${NC}"
((SUCCESS++))
else
echo -e "\n${RED}[X] Failed${NC}"
((FAILED++))
fi
else

if $EXEC pm disable-user --user 0 "$pkg" >/dev/null 2>&1 || $EXEC pm disable --user 0 "$pkg" >/dev/null 2>&1; then
echo -e "\n${GREEN}[✓] Success ($ACTION_LABEL)${NC}"
((SUCCESS++))
else
echo -e "\n${RED}[X] Failed${NC}"
((FAILED++))
fi
fi
done

echo -e "\n${BLUE}----------------------------------------${NC}"
echo -e "Summary: ${GREEN}$SUCCESS [✓] $ACTION_LABEL${NC}, ${YELLOW}$SKIPPED[*] skipped${NC}, ${RED}$FAILED [X] failed${NC}."
echo -e "\n${BLUE}----------------------------------------${NC}"
sleep 1
read -rp "Press Enter to return to main menu"
return 0
}

ubackup() {
local output_dir="$BACKUPS_DIR"
mkdir -p "$output_dir"

local date_str
date_str="$(date +%Y%m%d_%H%M%S)"
local output_file="$output_dir/Uraam_Restoration_List_${date_str}.json"

printf "\n%b\n" "${BLUE}----------------------------------------${NC}"
printf "%b\n" "${YELLOW}Generating restoration list...${NC}"
printf "%b\n" "${BLUE}----------------------------------------${NC}"

local all_pkgs active_pkgs
all_pkgs=$($EXEC pm list packages -u --user 0 2>/dev/null | sed 's/^package://' | tr -d '\r' | sort)
active_pkgs=$($EXEC pm list packages --user 0 2>/dev/null | sed 's/^package://' | tr -d '\r' | sort)

if [ -z "$all_pkgs" ]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "\n%b\n" "${RED}[!] Unable to communicate with package manager.${NC}"
read -rp "Press [Enter] to return to main menu"
return 1
fi

comm -23 <(echo "$all_pkgs") <(echo "$active_pkgs") | jq -R -s --arg date "$date_str" '
  [ split("\n")[] 
    | select(test("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z0-9_]+)+$")) 
    | {packageName: .} 
  ] as $apps
  | {
      name: ("Uraam_Restore_List_" + $date),
      description: "List of debloated packages pending restoration",
      author: "URAAM",
      version: "4.4.0",
      apps: $apps
      }
' > "$output_file"

local count
count=$(jq '.apps | length' "$output_file" 2>/dev/null || echo 0)

if [ "$count" -eq 0 ]; then
rm -f "$output_file"
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "\n%b\n" "${YELLOW}[X] No debloated packages found on this device.${NC}"
else
printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "\n%b\n" "${GREEN}[✓] Successfully identified $count debloated packages!${NC}"
printf "%b\n" "${BLUE}[!] File saved to: ${output_file}${NC}"
fi

read -rp "Press [Enter] to return to main menu"
}

uraam_backup() {
show_logo
echo -e "${BLUE}===============================================${NC}"
echo -e "${CYAN}URAAM RUVOMAIN ADB APP-MANAGER | BACKUP CREATOR${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${CYAN}Backups targets reside in ./Configs/backup-restore/"
echo -e "${BLUE}-----------------------------------------------${NC}"

printf "%b\n" "\n${RED}--- Warning ---${NC}"
echo -e "${CYAN}[?] You are about to create backup.*json in /Configs/backuo-restore.${NC}"
read -p "Are you sure you want to proceed? (y/N): " confirm

if [[ ! "$confirm" =~ ^[yY]$ ]]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
echo "${RED}[X] Operation cancelled.${NC}"
sleep 1
read -rp "Press Enter to return to main menu"
return 1
else
ubackup
fi
}

uraam_installer() {
clear
show_logo
printf "%b\n" "${BLUE}==========================================${NC}"
printf "%b\n" "${CYAN}URAAM RUVOMAIN ADB APP-MANAGER | INSTALLER${NC}"
printf "%b\n" "${BLUE}==========================================${NC}"
printf "%b\n" "${CYAN}Place APKs to install in ./Apps/ before starting.${NC}"
printf "%b\n" "${BLUE}----------------------------------------${NC}"

require_backend || return 1

if [ ! -d "$APP_DIR" ]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
echo -e "\n${RED}[ERROR]${NC}Directory $APP_DIR not found."
sleep 1
read -rp "Press Enter to return to main menu"
return 1
fi

shopt -s nullglob
local apks=("$APP_DIR"/*.apk)
shopt -u nullglob

if [ ${#apks[@]} -eq 0 ]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
echo -e "\n${RED}[ERROR]${NC}[X] No APK files found in $APP_DIR."
sleep 1
read -rp "Press Enter to return to main menu"
return 1
fi

echo -e "\n${PURPLE}[INFO]${NC} ${YELLOW}[!] Deploying${NC} ${#apks[@]} ${YELLOW}package(s)...${NC}"

local ok=0
local fail=0
for apk in "${apks[@]}"; do
echo -n "${YELLOW}Installing:${NC} $(basename "$apk") ... "
if $EXEC pm install -r -g "$apk" >/dev/null 2>&1; then
echo -e "${GREEN}[✓] Success${NC}"
((ok++))
else
echo -e "${RED}[X] Failed${NC}"
((fail++))
fi
done

echo -e "\n${BLUE}----------------------------------------${NC}"
echo -e "Summary: ${GREEN}$ok [✓] Installed${NC}, ${RED}$fail [X] Failed${NC}."
echo -e "${BLUE}----------------------------------------${NC}\n"
sleep 1
read -rp "Press Enter to return to main menu"
return 0
}

uraam_restore() {
show_logo
echo -e "${BLUE}=========================================${NC}"
echo -e "${CYAN}URAAM RUVOMAIN ADB APP-MANAGER | RESTORER${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "\n${CYAN}Restoration targets reside in ./Configs/backup-restore/${NC}"
echo -e "\n${BLUE}---------------------------------------${NC}"

require_backend || return 1

shopt -s nullglob
local files=("$BACKUPS_DIR"/*.json)
shopt -u nullglob

local display_names=()
for f in "${files[@]}"; do
display_names+=("$(basename "$f")")
done

printf "%b\n" "${BLUE}---------------------------------------${NC}"
printf "%b\n" "${GREEN}[✓] Configuration files found:${NC}"
printf "%b\n" "${BLUE}---------------------------------------${NC}"

PS3="Select the file number (1-${#files[@]}): "
select short_name in "${display_names[@]}"; do
if [ -n "$short_name" ]; then
file="${files[$((REPLY-1))]}"
echo -e "\n${YELLOW}[!] Selected file:${NC} ${GREEN}${short_name}${NC}"
break
else
printf "%b\n" "${BLUE}--------------------------------------------${NC}"
echo -e "\n${RED}[X] Invalid selection, please try again.${NC}"
read -rp "Press Enter to return to main menu"
return 1
fi
done

mapfile -t PACKAGES < <(jq -r '
  def extract:
    if type == "string" and test("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+$") then
      .
    elif type == "object" then
      (.packageName // .package // empty)
    elif type == "array" then
      .[] | extract
    else
      empty
    end;

  if .apps then .apps[] | extract
  elif .packages then .packages[] | extract
  elif type == "array" then .[] | extract
  else extract
  end
' "$file" 2>/dev/null | sort -u)

if [ ${#PACKAGES[@]} -eq 0 ]; then
printf "%b\n" "${CYAN}--------------------------------------------${NC}"
echo -e "\n${RED}[X] No packages found. Verify the JSON format.${NC}"
sleep 1
read -rp "Press Enter to return to main menu"
return 1
fi

printf "%b\n" "${BLUE}--------------------------------------------${NC}"
printf "%b\n" "${BLUE}[!] Starting restoration of ${#PACKAGES[@]} packages...${NC}"

local SUCCESS=0
local FAILED=0

for pkg in "${PACKAGES[@]}"; do
[ -z "$pkg" ] && continue
echo -n "${YELLOW}[!] Restoring${NC} $pkg: "

if $EXEC pm install-existing --user 0 "$pkg" >/dev/null 2>&1; then
echo -e "\n${GREEN}[✓] Success${NC}"
((SUCCESS++))
else
echo -e "\n${RED}[X] Failed (already present or not found)${NC}"
((FAILED++))
fi
done

printf "%b\n" "\n${BLUE}----------------------------------------${NC}"
printf "%b\n" "\nSummary: ${GREEN}$SUCCESS [✓] restored${NC}, ${RED}$FAILED [X] failed/skipped${NC}."
echo -e "\n${BLUE}----------------------------------------${NC}"
sleep 1
read -rp "Press Enter to return to main menu"
return 0
}

view_dlogs() {
clear
if compgen -G "$LOGD_DIR/*.log" >/dev/null; then
if command -v less >/dev/null 2>&1; then
echo -e "${GREEN}[*] Viewing logs (Press 'q' to quit, ':n' for next file)...${NC}"
sleep 1
less -R "$LOGD_DIR"/*.log
elif command -v nano >/dev/null 2>&1; then
echo-e "${YELLOW}[!] 'less' not found. Opening with nano in view-mode...${NC}"
sleep 1
nano -v "$LOGD_DIR"/*.log
else
echo -e "\n${YELLOW}[!] Displaying raw logs:${NC}\n"
cat "$LOGD_DIR"/*.log
echo -e "\n${CYAN}Press [Enter] to return to the menu...${NC}"
read -r
fi
else
echo -e "\n${RED}[X] No log files found in $LOGD_DIR${NC}"
sleep 2
fi
}

view_blogs() {
clear
if compgen -G "$LOGB_DIR/*.log" >/dev/null; then
if command -v less >/dev/null 2>&1; then
echo -e "${GREEN}[*] Viewing logs (Press 'q' to quit, ':n' for next file)...${NC}"
sleep 1
less -R "$LOGB_DIR"/*.log
elif command -v nano >/dev/null 2>&1; then
echo -e "${YELLOW}[!] 'less' not found. Opening with nano in view-mode...${NC}"
sleep1
nano -v "$LOGB_DIR"/*.log
else
echo -e "\n${YELLOW}[!] Displaying raw logs:${NC}\n"
cat "$LOGB_DIR"/*.log
echo -e "Press Enter to return to the menu..."
read -r
fi
else
echo -e "\n${RED}[X] No log files found in $LOGB_DIR${NC}"
sleep 2
fi
}

view_rlogs() {
clear
if compgen -G "$LOGR_DIR/*.log" >/dev/null; then
if command -v less >/dev/null 2>&1; then
echo -e "${GREEN}[*] Viewing logs (Press 'q' to quit, ':n' for next file)...${NC}"
sleep 1
less -R "$LOGR_DIR"/*.log
elif command -v nano >/dev/null 2>&1; then
echo -e "${YELLOW}[!] 'less' not found. Opening with nano in view-mode...${NC}"
sleep1
nano -v "$LOGR_DIR"/*.log
else
echo -e "\n${YELLOW}[!] Displaying raw logs:${NC}\n"
cat "$LOGR_DIR"/*.log
echo -e "Press [Enter] to return to the menu... "
read -r
fi
else
echo -e "${RED}[X] No log files found in $LOGR_DIR${NC}"
sleep 2
fi
}

vl_menu() {
show_logo
echo -e "${BLUE}==========================================${NC}"
echo -e "${CYAN}URAAM RUVOMAIN ADB APP-MANAGER | VIEW LOGS${NC}"
echo -e "${BLUE}==========================================${NC}"

echo -e "\n [1] View Debloat Logs"
echo -e " [2] View Restore Logs"
echo -e " [3] View Backup Logs"
echo -e " [4] Return to Dashboard"
echo -e " [5] Exit\n"
read -rp "Enter choice: " choice
case "$choice" in

1) view_dlogs;;
2) view_rlogs ;;
3) view_blogs ;;
4) return 0 ;;
5)
echo -e "\nGoodbye!"
clear
exit 0
;;
*)
echo -e "${RED}[X] Invalid option.${NC} Please try again."
;;
esac
}

update_uraam() {
show_logo
echo -e "${BLUE}========================================${NC}"
echo -e "        ${CYAN}=== URAAM | UPDATER ===${NC}"
echo -e "${BLUE}========================================${NC}"
printf "\n%b" "${YELLOW}[?] You areabout to update URAAM. Do you want to download and install it? [y/N]: ${NC}"
read -r confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
printf "%b\n" "${CYAN}--------------------------------------------${NC}"
printf "%b\n" "[X] Update canceled."
return 0
fi

printf "${YELLOW}[*] Updating existing installation...${NC}\n"

local target_bin="$0"
if [ -n "$PREFIX" ] &&[ -f "$PREFIX/bin/uraam" ]; then
target_bin="$PREFIX/bin/uraam"
elif [ -f "/usr/local/bin/uraam" ]; then
target_bin="/usr/local/bin/uraam"
fi

local raw_url="https://raw.githubusercontent.com/Uraam/Uraam/main/uraam.sh"
local tmp_file
tmp_file=$(mktemp)

if curl -fsSL"$raw_url" -o "$tmp_file"; then
if [ -w "$target_bin" ]; then
cp "$tmp_file" "$target_bin"
chmod +x "$target_bin"
else
sudo cp "$tmp_file" "$target_bin"
sudo chmod +x "$target_bin"
fi
rm -f "$tmp_file"
printf "${GREEN}[✓] URAAM updated successfully.${NC}\n"
printf "%b\n" "${CYAN}--------------------------------------------${NC}"
sleep1
read -rp "Press Enter to restart URAAM with new changes..."
clear
exec "$target_bin" "$@"
else
rm -f "$tmp_file"
printf "${RED}[X] Downloadfailed. Check your internet connection.${NC}\n"
sleep 1
read -rp "Press Enter to return to main menu"
return 0
fi
}

check_and_update() {
show_logo

if ! is_installed_via_deb; then
update_uraam
return $?
fi

printf "%b\n" "${CYAN}[*] Debian .deb installation detected.${NC}"
printf "%b\n" "${CYAN}[*] Checking for updates on GitHub...${NC}"

ensure_jq || return 1

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

if [ -d "/data/data/com.termux" ] && command -v termux-setup-storage >/dev/null 2>&1; then
if [ ! -d "$HOME/storage/shared" ]; then
printf "%b\n" "${BLUE}---------------------------------------${NC}"
echo -e "\n${CYAN}[*] Requesting storage access (please confirm the popup)...${NC}"
termux-setup-storage
sleep 1
fi
fi

wireless_menu() {
show_logo
printf "%b\n" "${BLUE}==================================================${NC}"
printf "%b\n" ".       ${CYAN}=== URAAM | WIRELESS ADB MODE ===${NC}"
printf "%b\n" "${BLUE}==================================================${NC}"
ensure_adb || return 1
printf "%b\n" "${BLUE}------------------------------------------------${NC}"
printf "%b\n" "Choose your wireless ADB connection mode"

echo -e "   [a] ${CYAN}Standard Wireless ADB${NC}"

if ! is_installed_via_deb; then
echo -e "   [s] ${CYAN}Starts Shizuku and enables Wireless ADB${NC} ${YELLOW}(Recommended)${NC}"
fi

echo -e "   [r] ${CYAN}Return to Dashboard${NC}"
echo -e "   [e] ${CYAN}Exit${NC}"

printf "%b\n" "${BLUE}--------------------------------------------------${NC}"
printf "%b\n" "Select an option:"

read -rp " " choice
case "$choice" in
a|A)
wireless_adb
;;
s|S)
if is_installed_via_deb; then
printf "%b\n" "${YELLOW}[!] Shizuku is only available on Android/Termux.${NC}"
printf "%b\n" "${BLUE}--------------------------------------------------${NC}"
read -rp "Press [Enter] to continue..."
else
wireless_shizuku
fi
;;
r|R)
return 0
;;
e|E)
echo -e "Goodbye!"
clear
exit 0
;;
*)
echo -e "\n${RED}[!] Invalid option.${NC} Please try again."
sleep 1
;;
esac
}

show_main_menu() {
show_logo
printf "%b\n" "${CYAN}=== URAAM v4.4.1 Dashboard ===${NC}"
detect_backend_status
printf "%b\n" "${BLUE}--------------------------------------------------------${NC}"
echo -e "${CYAN}Folder layout instructions before starting:${NC}"
echo -e "${CYAN}Place debloat configurations in ./Configs/debloat/ (Canta JSON supported).${NC}"
echo -e "${CYAN}Place APKs to install in ./Apps/.${NC}"
echo -e "${CYAN}Backups and restoration targets reside in ./Configs/backup-restore/${NC}"
printf "%b\n" "${BLUE}--------------------------------------------------------${NC}"
echo -e "   [d] ${CYAN}Debloat apps${NC} ${YELLOW}(Remove Bloatware)${NC}"
echo -e "   [i] ${CYAN}Install APK(s)${NC} ${YELLOW}(Batch APK Install)${NC}"
echo -e "   [b] ${CYAN}Backup${NC} ${YELLOW}(Export Apps List)${NC}"
echo -e "   [r] ${CYAN}Restore${NC} ${YELLOW}(Revert/Reinstall Apps)${NC}"
echo -e "   [w] ${CYAN}Wireless Menu${NC} ${YELLOW}(Pair & Connect)${NC}" 
echo -e "   [u] ${CYAN}Update URAAM${NC} ${YELLOW}(Search/install update from Github)${NC}"
echo -e "${BLUE}------------------------------------------${NC} [e] Exit ${BLUE}-----${NC}"
}

handle_menu_choice() {
local choice="$1"
case "$choice" in
d|D)
require_backend || return 1
uraam_debloat
;;
i|I)
require_backend || return 1
uraam_installer
;;
b|B)
require_backend || return 1
uraam_backup
;;
r|R)
require_backend || return 1
uraam_restore
;;
w|W)
wireless_menu
;;
u|U)
update_uraam
;;
e)
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
