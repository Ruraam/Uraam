#!/usr/bin/env bash
#
# URAAM - Universal Ruvomain ADB App-Manager
# Hardened maintenance release based on v4.4.7
#
# Compatible with: Debian/Linux, Android Termux
# Backends: ADB, local ROOT, Shizuku (rish)
#
# Existing data layout is preserved:
#   portable: <script-dir>/Apps, Configs, Logs
#   installed: ~/.local/share/uraam and ~/.config/uraam
#
# NOTE: Package operations are destructive. Review each selected list before
# applying it. Android system-package removal is performed for user 0 only.

set -o pipefail
umask 077

URAAM_VERSION="4.4.7"
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    LINK="$(readlink "$SOURCE")"
    [[ "$LINK" != /* ]] && LINK="$DIR/$LINK"
    SOURCE="$LINK"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# Resolve install/data locations without changing the legacy portable layout.
if [[ "$SCRIPT_DIR" == */bin || "$SCRIPT_DIR" == */bin/* || "$SCRIPT_DIR" == /usr/* ]]; then
    USER_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/uraam"
    USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/uraam"
else
    USER_DATA_DIR="$SCRIPT_DIR"
    USER_CONFIG_DIR="$SCRIPT_DIR/Configs"
fi

REPO_DIR="$SCRIPT_DIR"
APP_DIR="$USER_DATA_DIR/Apps"
USER_DEBLOAT_DIR="$USER_CONFIG_DIR/debloat"
CONFIGS_DIR="$USER_DEBLOAT_DIR"
USER_BACKUPS_DIR="$USER_DATA_DIR/Configs/backup-restore"
BACKUPS_DIR="$USER_BACKUPS_DIR"
SYSTEM_DEBLOAT_DIR="${PREFIX:-/usr}/share/uraam/debloat"
UAD_METADATA_FILE="$SCRIPT_DIR/Configs/uad/uad_lists.json"
[[ -r "$UAD_METADATA_FILE" ]] || UAD_METADATA_FILE="${PREFIX:-/usr}/share/uraam/Configs/uad/uad_lists.json"

LOGD_DIR="$USER_DATA_DIR/Logs/debloat"
LOGB_DIR="$USER_DATA_DIR/Logs/backup"
LOGR_DIR="$USER_DATA_DIR/Logs/restore"

REPO_URL="https://github.com/Ruraam/Uraam"
BRANCH="main"
EXEC_TYPE=""
CURRENT_MODEL=""
LOGFILE=""
BACKEND_SERIAL="${ANDROID_SERIAL:-}"

# ---------------------------------------------------------------------------
# Strict Safety Whitelist (Anti-Bootloop & Critical Framework Guard)
# ---------------------------------------------------------------------------
SAFETY_WHITELIST=(
    # Core Android Framework & System UI
    "android"
    "com.android.systemui"
    "com.android.settings"
    "com.android.settings.intelligence"
    "com.android.keyguard"
    "com.android.wallpaper.livepicker"

    # Package & Permission Managers (Critical to install/manage anything)
    "com.android.packageinstaller"
    "com.android.permissioncontroller"
    "com.google.android.permissioncontroller"
    "com.google.android.packageinstaller"

    # Core Telecom & Emergency Layer
    "com.android.phone"
    "com.android.server.telecom"
    "com.android.providers.telephony"
    "com.android.emergency"

    # Core Data Providers & Cryptographic Store
    "com.android.providers.settings"
    "com.android.providers.media"
    "com.android.providers.downloads"
    "com.android.providers.contacts"
    "com.android.keychain"
    "com.android.certinstaller"
    "com.android.inputdevices"

    # Google Play Core Architecture
    "com.google.android.gms"
    "com.google.android.gsf"
    "com.android.vending"
)

# Terminal colors (disabled automatically when output is not a terminal).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; CYAN=$'\033[0;36m'
    PURPLE=$'\033[0;35m'; GREEN=$'\033[0;32m'; RED=$'\033[1;31m'
    WHITE=$'\033[0;37m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'
else
    BLUE=""; BOLD=""; CYAN=""; PURPLE=""; GREEN=""; RED=""
    WHITE=""; YELLOW=""; NC=""
fi

# ---------------------------------------------------------------------------
# Common helpers
# ---------------------------------------------------------------------------

msg()  { printf '%b\n' "$*"; }
info() { msg "${CYAN}[*]${NC} $*"; }
ok()   { msg "${GREEN}[✓]${NC} $*"; }
warn() { msg "${YELLOW}[!]${NC} $*" >&2; }
err()  { msg "${RED}[X]${NC} $*" >&2; }

pause() {
    read -r -p "Press Enter to continue..." _ || true
}

SAFETY_PACKAGE_PATTERNS=(
    '^com\.android\.providers\.(settings|telephony|media|downloads|contacts)(\.|$)'
    '(^|\.)(telephony[^.]*|telecom|ims|imsservice|ril)(\.|$)'
    '(^|\.)(setupwizard|permissioncontroller|packageinstaller|systemui|keyguard|emergency)(\.|$)'
    '(^|\.)(bluetooth|bluetoothagent|bluetoothservice|nfc)(\.|$)'
    '^com\.android\.(providers\.(settings|telephony)|server\.telecom|emergency|systemui|permissioncontroller).*overlay'
    '^com\.samsung\.android\.knox\.(attestation|containercore|kpecore)(\.|$)'
)

is_whitelisted() {
    local target="$1"
    local safe_pkg pattern
    for safe_pkg in "${SAFETY_WHITELIST[@]}"; do
        [[ "$safe_pkg" == "$target" ]] && return 0
    done
    for pattern in "${SAFETY_PACKAGE_PATTERNS[@]}"; do
        [[ "$target" =~ $pattern ]] && return 0
    done
    return 1
}

show_logo() {
    [[ -t 1 ]] && clear
    msg "${PURPLE}"
    cat <<'EOF'
         _    _  _____   ___    ___   _   _
        |:|  |:||:::::\ /:::\  /:::\ |:\ /:|
        |:|\_|:||:|,|:||:|,|:||:|,|:||:|"|:|
         \:::::||:| |:\|:| |:||:| |:||:| |:|
EOF
    msg "${NC}"
}

is_termux() {
    [[ -d /data/data/com.termux ]] || [[ "${PREFIX:-}" == *com.termux* ]]
}

is_installed_via_deb() {
    local package_name="${1:-uraam-debian}" status
    is_termux && return 1
    command -v dpkg-query >/dev/null 2>&1 || return 1
    status="$(dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null || true)"
    [[ "$status" == *"install ok installed"* ]]
}

init_directories() {
    local dir
    for dir in "$USER_DEBLOAT_DIR" "$BACKUPS_DIR" "$APP_DIR" \
        "$LOGD_DIR" "$LOGB_DIR" "$LOGR_DIR"; do
        if ! mkdir -p -- "$dir"; then
            err "Cannot create directory: $dir"
            return 1
        fi
    done

    # Seed bundled configurations only when the user's directory is empty.
    if [[ -d "$SYSTEM_DEBLOAT_DIR" ]] &&
        ! find "$USER_DEBLOAT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
        find "$SYSTEM_DEBLOAT_DIR" -maxdepth 1 -type f -name '*.json' \
            -exec cp -n -- '{}' "$USER_DEBLOAT_DIR/" \; 2>/dev/null || true
    fi
}

term_set_storage() {
    is_termux || return 0
    [[ -n "${PREFIX:-}" ]] || PREFIX="/data/data/com.termux/files/usr"

    if [[ ! -d "$HOME/storage" ]] && command -v termux-setup-storage >/dev/null 2>&1; then
        msg "${BLUE}---------------------------------------${NC}"
        info "Requesting Termux storage access. Confirm the Android permission dialog."
        termux-setup-storage || warn "Storage permission was not granted."
    fi
}

start_log() {
    local kind="$1" dir="$2" prefix="$3"
    mkdir -p -- "$dir" || return 1
    find "$dir" -maxdepth 1 -type f -name "${prefix}-*.log" -mtime +30 -delete 2>/dev/null || true
    LOGFILE="$dir/${prefix}-$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee -a "$LOGFILE") 2>&1
}

# ---------------------------------------------------------------------------
# Dependency handling
# ---------------------------------------------------------------------------

install_package() {
    local package="$1"
    if is_termux; then
        command -v pkg >/dev/null 2>&1 || { err "Termux pkg is unavailable."; return 1; }
        pkg install -y "$package"
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y "$package"
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm "$package"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$package"
    elif command -v brew >/dev/null 2>&1; then
        brew install "$package"
    else
        err "No supported package manager found. Install $package manually."
        return 1
    fi
}

ensure_command() {
    local command_name="$1" package_name="$2" answer
    if command -v "$command_name" >/dev/null 2>&1; then
        ok "$command_name is installed."
        return 0
    fi

    warn "$command_name is not installed."
    read -r -p "Install $package_name now? [y/N]: " answer
    [[ "$answer" =~ ^[yY]$ ]] || return 1
    install_package "$package_name" || return 1
    command -v "$command_name" >/dev/null 2>&1 || {
        err "$command_name is still unavailable after installation."
        return 1
    }
    ok "$command_name installed successfully."
}

ensure_adb() {
    ensure_command adb android-tools
}

ensure_jq() {
    ensure_command jq jq
}

# ---------------------------------------------------------------------------
# Device execution layer
# ---------------------------------------------------------------------------

shell_quote_args() {
    local arg
    printf -v _QUOTED_ARGS '%q ' "$@"
    printf '%s' "${_QUOTED_ARGS% }"
}

run_adb() {
    local -a cmd=(adb)
    [[ -n "$BACKEND_SERIAL" ]] && cmd+=(-s "$BACKEND_SERIAL")
    cmd+=(shell "$@")
    "${cmd[@]}"
}

run_root() {
    local command_string
    command_string="$(shell_quote_args "$@")"
    su -c "$command_string"
}

run_shizuku() {
    local command_string
    command_string="$(shell_quote_args "$@")"
    rish -c "$command_string"
}

run_device() {
    case "$EXEC_TYPE" in
        ADB)     run_adb "$@" ;;
        ROOT)    run_root "$@" ;;
        SHIZUKU) run_shizuku "$@" ;;
        *)       err "No valid device backend selected."; return 1 ;;
    esac
}

device_getprop() {
    local property="$1"
    case "$EXEC_TYPE" in
        ADB)     run_adb getprop "$property" 2>/dev/null ;;
        ROOT)    run_root getprop "$property" 2>/dev/null ;;
        SHIZUKU) run_shizuku getprop "$property" 2>/dev/null ;;
        *)       getprop "$property" 2>/dev/null ;;
    esac
}

device_brand() {
    local brand model android_ver
    brand="$(device_getprop ro.product.manufacturer || true)"
    model="$(device_getprop ro.product.model || true)"
    android_ver="$(device_getprop ro.build.version.release || true)"

    if [[ -n "$brand$model" ]]; then
        CURRENT_MODEL="${brand^} $model"
        [[ -n "$android_ver" ]] && CURRENT_MODEL+=" (Android $android_ver)"
    elif is_installed_via_deb; then
        CURRENT_MODEL="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null) $(uname -s) $(uname -m)"
    else
        CURRENT_MODEL="Unknown device"
    fi
}

detect_backend_status() {
    EXEC_TYPE=""
    BACKEND_SERIAL="${ANDROID_SERIAL:-}"

    if command -v adb >/dev/null 2>&1; then
        local devices serial
        devices="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}')"
        if [[ -n "$BACKEND_SERIAL" ]]; then
            if printf '%s\n' "$devices" | grep -Fxq "$BACKEND_SERIAL"; then
                EXEC_TYPE="ADB"
            fi
        else
            serial="$(printf '%s\n' "$devices" | head -n1)"
            if [[ -n "$serial" ]]; then
                BACKEND_SERIAL="$serial"
                EXEC_TYPE="ADB"
            fi
        fi
    fi

    if [[ -z "$EXEC_TYPE" ]] && is_termux; then
        if [[ "$(id -u)" -eq 0 ]]; then
            EXEC_TYPE="ROOT"
        elif command -v su >/dev/null 2>&1 && su -c id >/dev/null 2>&1; then
            EXEC_TYPE="ROOT"
        elif [[ -z "${BACKEND:-}" ]] && command -v rish >/dev/null 2>&1 &&
            printf 'exit\n' | rish >/dev/null 2>&1; then
            EXEC_TYPE="SHIZUKU"
        fi
    fi

    if [[ -n "$EXEC_TYPE" ]]; then
        device_brand
        msg "${PURPLE}[Target]${NC} $CURRENT_MODEL"
        ok "Execution backend: $EXEC_TYPE"
        return 0
    fi

    if is_installed_via_deb; then
        CURRENT_MODEL="$(uname -s) $(uname -m)"
        msg "${PURPLE}[Host]${NC} $CURRENT_MODEL"
    fi
    warn "No execution backend detected."
    return 1
}

require_backend() {
    show_logo
    ensure_adb || return 1
    ensure_jq || return 1

    if ! detect_backend_status; then
        msg "${BLUE}--------------------------------------------------------${NC}"
        err "Action aborted: no active backend detected."
        msg "  1. Enable and authorize USB/Wireless debugging."
        msg "  2. Check 'adb devices'."
        msg "  3. On Termux, start ROOT or Shizuku (rish)."
        msg "${BLUE}--------------------------------------------------------${NC}"
        pause
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Wireless ADB / Shizuku
# ---------------------------------------------------------------------------

check_adb_menu() {
    adb devices -l
}

wireless_adb() {
    show_logo
    msg "${BLUE}---------------------------------------------------${NC}"
    msg "         ${CYAN}=== URAAM | WIRELESS ADB SETUP ===${NC}"
    msg "${BLUE}---------------------------------------------------${NC}"
    msg "1. Open Developer Options > Wireless debugging."
    msg "2. Choose 'Pair device with pairing code' if not paired."
    ensure_adb || return 1
    check_adb_menu

    local need_pair pair_host pair_code conn_input conn_host
    read -r -p "Do you need to pair first? [y/N]: " need_pair

    if [[ "$need_pair" =~ ^[yY]$ ]]; then
        read -r -p "Pairing host:port (or port only): " pair_host
        [[ "$pair_host" =~ ^[0-9]+$ ]] && pair_host="127.0.0.1:$pair_host"
        read -r -s -p "6-digit pairing code: " pair_code
        printf '\n'
        if [[ -z "$pair_host" || -z "$pair_code" ]]; then
            err "Pairing host and code are required."
            pause
            return 1
        fi
        adb pair "$pair_host" "$pair_code" || {
            err "ADB pairing failed."
            pause
            return 1
        }
        ok "Pairing completed."
    fi

    read -r -p "Connection host:port (or port only): " conn_input
    conn_host="$conn_input"
    [[ "$conn_input" =~ ^[0-9]+$ ]] && conn_host="127.0.0.1:$conn_input"
    [[ -n "$conn_host" ]] || { err "Connection host is empty."; pause; return 1; }

    info "Connecting to $conn_host..."
    if adb connect "$conn_host" && adb devices | awk -v h="$conn_host" '$1==h && $2=="device" {found=1} END {exit !found}'; then
        ok "Wireless ADB connected: $conn_host"
        BACKEND_SERIAL="$conn_host"
        pause
        return 0
    fi

    err "Connection failed. Check the IP address, port and debugging state."
    pause
    return 1
}

wireless_shizuku() {
    show_logo
    msg "${BLUE}------------------------------------------------${NC}"
    msg "       ${CYAN}=== URAAM | SHIZUKU SETUP ===${NC}"
    msg "${BLUE}------------------------------------------------${NC}"

    if ! is_termux; then
        warn "Shizuku local mode is intended for Android/Termux."
        pause
        return 1
    fi
    if ! command -v rish >/dev/null 2>&1; then
        err "rish was not found. Install/configure the Shizuku shell integration first."
        pause
        return 1
    fi

    if ! rish -c id >/dev/null 2>&1; then
        err "Shizuku is not active. Start it from the Shizuku app first."
        pause
        return 1
    fi

    ok "Shizuku is active."
    info "Shizuku already provides the local privileged shell; no legacy ADB TCP port is forced."
    pause
    return 0
}

wireless_menu() {
    show_logo
    msg "${BLUE}==================================================${NC}"
    msg "       ${CYAN}=== URAAM | WIRELESS CONNECTION ===${NC}"
    msg "${BLUE}==================================================${NC}"
    ensure_adb || return 1
    printf ' [a] Standard Wireless ADB\n'
    is_termux && printf ' [s] Check Shizuku (rish)\n'
    printf ' [r] Return\n [e] Exit\n'
    read -r -p "Select: " choice
    case "$choice" in
        a|A) wireless_adb ;;
        s|S) wireless_shizuku ;;
        r|R) return 0 ;;
        e|E) exit 0 ;;
        *) warn "Invalid option."; sleep 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# JSON configuration parsing
# ---------------------------------------------------------------------------

validate_json_file() {
    local file="$1"
    [[ -f "$file" ]] || { err "File not found: $file"; return 1; }
    jq empty "$file" >/dev/null 2>&1 || { err "Invalid JSON: $file"; return 1; }
}

load_packages_from_json() {
    local file="$1" parsed
    validate_json_file "$file" || return 1
    parsed="$(jq -r '
        def extract:
            if type == "string" then
                select(test("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$"))
            elif type == "object" then
                (.packageName // .package // .id // empty) |
                select(type == "string" and test("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$"))
            elif type == "array" then
                .[] | extract
            else empty end;
        if type == "object" and (.apps | type) == "array" then
            .apps[] | extract
        elif type == "object" and (.packages | type) == "array" then
            .packages[] | extract
        elif type == "array" then .[] | extract
        else extract end
    ' "$file" 2>/dev/null | sort -u)" || {
        err "Could not parse package IDs from $file."
        return 1
    }
    [[ -n "$parsed" ]] || { err "No valid Android package IDs found in $file."; return 1; }
    mapfile -t PACKAGES <<< "$parsed"
}

select_json_file() {
    local directory="$1" prompt="$2" file
    local -a files=()
    shopt -s nullglob
    files=("$directory"/*.json)
    shopt -u nullglob

    ((${#files[@]} > 0)) || { err "No JSON files found in $directory."; return 1; }

    printf '%s\n' "$prompt"
    local i
    for i in "${!files[@]}"; do
        printf '  [%d] %s\n' "$((i+1))" "$(basename "${files[$i]}")"
    done
    local selection
    read -r -p "Select file number (1-${#files[@]}): " selection
    [[ "$selection" =~ ^[0-9]+$ ]] || { err "Invalid selection."; return 1; }
    (( selection >= 1 && selection <= ${#files[@]} )) || { err "Selection out of range."; return 1; }
    SELECTED_FILE="${files[$((selection-1))]}"
}

# ---------------------------------------------------------------------------
# Device package operations
# ---------------------------------------------------------------------------

device_package_list() {
    local mode="${1:-active}" raw
    case "$mode" in
        all)    raw="$(run_device pm list packages -u --user 0)" || return 1 ;;
        active) raw="$(run_device pm list packages --user 0)" || return 1 ;;
        *) return 2 ;;
    esac
    [[ "$raw" == *"package:"* ]] || {
        err "Android returned no package records; refusing to continue."
        return 1
    }
    printf '%s\n' "$raw" | sed -n 's/^package://p' | tr -d '\r' | sort -u
}

package_is_installed() {
    local package="$1" installed="$2"
    grep -Fxq -- "$package" <<< "$installed"
}

uad_metadata_for_package() {
    local package="$1"
    if [[ -r "$UAD_METADATA_FILE" ]] && command -v jq >/dev/null 2>&1; then
        jq -r --arg package "$package" '
            if has($package) then
                .[$package] |
                [
                    (.removal // "Unknown"),
                    (.list // "Unlisted"),
                    ((.description // "No UAD description available.") | gsub("[\r\n\t]+"; " "))
                ] | @tsv
            else
                ["Unknown", "Unlisted", "Not present in the bundled UAD-NG catalogue."] | @tsv
            end
        ' "$UAD_METADATA_FILE" 2>/dev/null
    else
        printf '%s\t%s\t%s\n' "Unknown" "Unlisted" \
            "UAD metadata unavailable; review this package manually."
    fi
}

uraam_debloat() {
    show_logo
    msg "${BLUE}------------------------------------------${NC}"
    msg "        ${CYAN}=== URAAM | DEBLOATER ===${NC}"
    msg "Configurations: $USER_DEBLOAT_DIR"
    msg "${BLUE}------------------------------------------${NC}"
    require_backend || return 1
    select_json_file "$CONFIGS_DIR" "Available debloat configurations:" || return 1
    local file="$SELECTED_FILE"
    info "Selected: $(basename "$file")"
    load_packages_from_json "$file" || { pause; return 1; }

    local action mode confirm installed pkg operation_count ready_count
    local selection token risk category description metadata index
    local success=0 skipped=0 failed=0
    local -a PREVIEW_PRESENT=() PREVIEW_PROTECTED=() PREVIEW_MISSING=()
    local -a PREVIEW_UNSAFE=() PREVIEW_UNKNOWN=() CANDIDATE_PACKAGES=() CANDIDATE_RISKS=()
    local -a CANDIDATE_CATEGORIES=() CANDIDATE_DESCRIPTIONS=()
    local -a SELECTED_PACKAGES=() requested_indices=()
    local -A selected_indices=()

    printf 'Choose action: [u] Uninstall for user 0 / [d] Disable / [c] Cancel: '
    read -r action
    case "$action" in
        u|U) action="uninstall" ;;
        d|D) action="disable" ;;
        *) warn "Operation cancelled."; return 0 ;;
    esac

    installed="$(device_package_list active)" || {
        err "Cannot obtain a reliable package inventory; no changes made."
        return 1
    }
    for pkg in "${PACKAGES[@]}"; do
        if is_whitelisted "$pkg"; then
            PREVIEW_PROTECTED+=("$pkg")
        elif package_is_installed "$pkg" "$installed"; then
            metadata="$(uad_metadata_for_package "$pkg")" || return 1
            IFS=$'\t' read -r risk category description <<< "$metadata"
            case "$risk" in
                Unsafe) PREVIEW_UNSAFE+=("$pkg") ;;
                Recommended|Advanced|Expert)
                    CANDIDATE_PACKAGES+=("$pkg")
                    CANDIDATE_RISKS+=("$risk")
                    CANDIDATE_CATEGORIES+=("${category:-Unlisted}")
                    CANDIDATE_DESCRIPTIONS+=("${description:-No description available.}")
                    ;;
                *) PREVIEW_UNKNOWN+=("$pkg") ;;
            esac
        else
            PREVIEW_MISSING+=("$pkg")
        fi
    done

    msg ""
    msg "${BOLD}=== URAAM | UAD RISK REVIEW ===${NC}"
    printf 'Device: %s' "${CURRENT_MODEL:-Unknown device}"
    [[ -n "$BACKEND_SERIAL" ]] && printf ' (%s)' "$BACKEND_SERIAL"
    printf '\nBackend: %s | Android user: 0\n' "${EXEC_TYPE:-unknown}"
    printf 'Action requested: %s\n\n' "$action"
    if [[ -r "$UAD_METADATA_FILE" ]]; then
        printf 'UAD-NG metadata: bundled catalogue available\n'
    else
        warn "UAD-NG catalogue missing; packages will be marked Unknown."
    fi

    for index in "${!CANDIDATE_PACKAGES[@]}"; do
        printf '\n  [%d] [%s] [%s] %s\n' \
            "$((index+1))" "${CANDIDATE_RISKS[$index]}" \
            "${CANDIDATE_CATEGORIES[$index]}" "${CANDIDATE_PACKAGES[$index]}"
        printf '      %s\n' "${CANDIDATE_DESCRIPTIONS[$index]}"
    done
    for pkg in "${PREVIEW_UNSAFE[@]}"; do
        metadata="$(uad_metadata_for_package "$pkg")"
        IFS=
    for pkg in "${PREVIEW_PROTECTED[@]}"; do
        printf '\n  [PROTECTED BY URAAM] %s\n' "$pkg"
    done
    for pkg in "${PREVIEW_MISSING[@]}"; do
        printf '\n  [NOT INSTALLED] %s\n' "$pkg"
    done

    msg ""
    printf 'Catalogue: %d selectable, %d Unsafe blocked, %d unknown blocked, %d protected, %d absent.\n' \
        "${#CANDIDATE_PACKAGES[@]}" "${#PREVIEW_UNSAFE[@]}" "${#PREVIEW_UNKNOWN[@]}" \
        "${#PREVIEW_PROTECTED[@]}" "${#PREVIEW_MISSING[@]}"
    (( ${#CANDIDATE_PACKAGES[@]} > 0 )) || {
        warn "No selectable installed packages. Nothing can be changed."
        return 0
    }

    printf '\nSelect package numbers separated by commas (example: 1,3). Empty/C cancels: '
    read -r selection
    [[ -n "$selection" ]] || {
        warn "No packages selected. Nothing changed."
        return 0
    }
    [[ "$selection" != "c" && "$selection" != "C" ]] || {
        warn "Operation cancelled."
        return 0
    }
    IFS=',' read -r -a requested_indices <<< "$selection"
    for token in "${requested_indices[@]}"; do
        token="${token//[[:space:]]/}"
        [[ "$token" =~ ^[0-9]+$ ]] || {
            err "Invalid selection '$token'. Use comma-separated numbers only; no bulk keyword is accepted."
            return 1
        }
        (( token >= 1 && token <= ${#CANDIDATE_PACKAGES[@]} )) || {
            err "Selection '$token' is outside the available range."
            return 1
        }
        [[ -z "${selected_indices[$token]:-}" ]] || {
            err "Duplicate selection '$token'."
            return 1
        }
        selected_indices[$token]=1
        SELECTED_PACKAGES+=("${CANDIDATE_PACKAGES[$((token-1))]}")
    done

    operation_count="${#SELECTED_PACKAGES[@]}"
    msg ""
    msg "${BOLD}=== URAAM | FINAL OPERATION PREVIEW ===${NC}"
    for pkg in "${SELECTED_PACKAGES[@]}"; do
        metadata="$(uad_metadata_for_package "$pkg")"
        IFS=$'\t' read -r risk category description <<< "$metadata"
        printf '  [WILL %s] [%s] %s\n' "${action^^}" "$risk" "$pkg"
    done
    for index in "${!CANDIDATE_PACKAGES[@]}"; do
        pkg="${CANDIDATE_PACKAGES[$index]}"
        if [[ -z "${selected_indices[$((index+1))]:-}" ]]; then
            printf '  [NOT SELECTED] [%s] %s\n' "${CANDIDATE_RISKS[$index]}" "$pkg"
        fi
    done
    printf '\nExact selected operations: %d\n' "$operation_count"
    (( operation_count > 0 )) || {
        warn "No packages selected. Nothing can be changed."
        return 0
    }

    printf '\nChoose mode: [d] Dry-run only (no changes) / [a] Apply / [c] Cancel: '
    read -r mode
    case "$mode" in
        d|D)
            ok "DRY RUN complete: $operation_count manually selected package(s) would be $action."
            info "No uninstall, disable, install, or package-state command was executed."
            return 0
            ;;
        a|A)
            if [[ ! -r "$UAD_METADATA_FILE" ]] ||
                ! jq -e 'type == "object" and length > 0' "$UAD_METADATA_FILE" >/dev/null 2>&1; then
                err "Cannot apply changes without a valid bundled UAD-NG risk catalogue."
                return 1
            fi
            ;;
        *) warn "Operation cancelled; no changes made."; return 0 ;;
    esac

    printf 'Type exactly "APPLY %s" to confirm these %s operation(s): ' "$operation_count" "$operation_count"
    read -r confirm
    [[ "$confirm" == "APPLY $operation_count" ]] || {
        warn "Confirmation did not match. No changes made."
        return 0
    }

    installed="$(device_package_list active)" || {
        err "Cannot refresh package inventory; no changes made."
        return 1
    }
    ready_count=0
    for pkg in "${SELECTED_PACKAGES[@]}"; do
        metadata="$(uad_metadata_for_package "$pkg")" || return 1
        IFS=$'\t' read -r risk _ _ <<< "$metadata"
        if ! is_whitelisted "$pkg" &&
            [[ "$risk" == "Recommended" || "$risk" == "Advanced" || "$risk" == "Expert" ]] &&
            package_is_installed "$pkg" "$installed"; then
            ((ready_count+=1))
        fi
    done
    if (( ready_count != operation_count )); then
        warn "Device or UAD safety state changed after preview ($operation_count planned, $ready_count still eligible)."
        warn "Run Preview again; no changes made."
        return 1
    fi

    start_log debloat "$LOGD_DIR" uraam-debloat || return 1
    for pkg in "${SELECTED_PACKAGES[@]}"; do
        printf '%s: ' "$pkg"
        if is_whitelisted "$pkg"; then
            err "became protected; skipped"
            ((skipped+=1))
            continue
        fi
        if [[ "$action" == uninstall ]]; then
            if run_device pm uninstall -k --user 0 "$pkg" >/dev/null 2>&1; then
                ok "uninstalled for user 0"
                ((success+=1))
            else
                err "uninstall failed"
                ((failed+=1))
            fi
        else
            if run_device pm disable-user --user 0 "$pkg" >/dev/null 2>&1; then
                ok "disabled"
                ((success+=1))
            else
                err "disable failed"
                ((failed+=1))
            fi
        fi
    done
    msg "${BLUE}----------------------------------------${NC}"
    msg "Summary: ${GREEN}$success succeeded${NC}, ${YELLOW}$skipped skipped${NC}, ${RED}$failed failed${NC}."
    msg "Log: $LOGFILE"
    pause
}

ubackup() {
    local output_dir="$BACKUPS_DIR" date_str output_file
    mkdir -p "$output_dir" || return 1
    date_str="$(date +%Y%m%d_%H%M%S)"
    output_file="$output_dir/Uraam_Restoration_List_${date_str}.json"

    local all_pkgs active_pkgs model android_ver
    all_pkgs="$(device_package_list active)" || return 1
    active_pkgs="$(device_package_list active)" || return 1
    [[ -n "$all_pkgs" ]] || { err "Unable to retrieve installed packages."; return 1; }

    model="$(device_getprop ro.product.model || true)"
    android_ver="$(device_getprop ro.build.version.release || true)"

    comm -23 <(printf '%s\n' "$all_pkgs") <(printf '%s\n' "$active_pkgs") |
        jq -R -s --arg date "$date_str" --arg model "$model" --arg android "$android_ver" '
            [split("\n")[] | select(test("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")) | {packageName:.}] as $apps
            | {
                name:("Uraam_Restore_List_"+$date),
                description:"Packages not currently installed for Android user 0",
                author:"URAAM", version:"4.4.6",
                device:$model, android_version:$android, created_at:$date, apps:$apps
            }
        ' > "$output_file" || { rm -f "$output_file"; return 1; }

    local count
    count="$(jq '.apps | length' "$output_file" 2>/dev/null)" || count=0
    if (( count == 0 )); then
        rm -f "$output_file"
        warn "No disabled or user-uninstalled packages were found."
        return 0
    fi
    ok "Saved $count package(s) to $output_file"
}

uraam_backup() {
    show_logo
    msg "${BLUE}===============================================${NC}"
    msg "${CYAN}URAAM | BACKUP CREATOR${NC}"
    msg "${BLUE}===============================================${NC}"
    require_backend || return 1
    read -r -p "Create a restoration list of packages missing for user 0? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Cancelled."; return 0; }
    start_log backup "$LOGB_DIR" uraam-backup || return 1
    ubackup
    pause
}

uraam_restore() {
    show_logo
    msg "${BLUE}=========================================${NC}"
    msg "${CYAN}URAAM | RESTORER${NC}"
    msg "${BLUE}=========================================${NC}"
    require_backend || return 1
    select_json_file "$BACKUPS_DIR" "Available restoration lists:" || return 1
    load_packages_from_json "$SELECTED_FILE" || { pause; return 1; }

    warn "The selected list contains ${#PACKAGES[@]} package(s)."
    read -r -p "Restore these packages for Android user 0? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Cancelled."; return 0; }

    start_log restore "$LOGR_DIR" uraam-restore || return 1
    local success=0 failed=0 pkg
    for pkg in "${PACKAGES[@]}"; do
        printf '%s: ' "$pkg"
        if run_device pm install-existing --user 0 "$pkg" >/dev/null 2>&1; then
            ok "restored"
            ((success+=1))
        else
            err "not restored (not present on device, or operation denied)"
            ((failed+=1))
        fi
    done
    msg "${BLUE}----------------------------------------${NC}"
    msg "Summary: ${GREEN}$success restored${NC}, ${RED}$failed failed${NC}."
    msg "Log: $LOGFILE"
    pause
}

# ---------------------------------------------------------------------------
# APK installation
# ---------------------------------------------------------------------------

install_one_apk() {
    local apk="$1"
    local remote="/data/local/tmp/uraam-$(date +%s)-$(basename "$apk")"

    case "$EXEC_TYPE" in
        ADB)
            local -a cmd=(adb)
            [[ -n "$BACKEND_SERIAL" ]] && cmd+=(-s "$BACKEND_SERIAL")
            "${cmd[@]}" install -r -g "$apk"
            ;;
        ROOT)
            su -c "cp $(printf '%q' "$apk") $(printf '%q' "$remote")" || return 1
            run_device pm install -r -g "$remote"
            local result=$?
            su -c "rm -f $(printf '%q' "$remote")" >/dev/null 2>&1 || true
            return "$result"
            ;;
        SHIZUKU)
            local shared_dir="$HOME/storage/downloads/URAAM"
            local shared_apk="$shared_dir/$(basename "$apk")"
            [[ -d "$HOME/storage" ]] || {
                err "Termux storage is not set up. Run termux-setup-storage first."
                return 1
            }
            mkdir -p "$shared_dir" || return 1
            cp -- "$apk" "$shared_apk" || return 1
            rish -c "pm install -r -g $(printf '%q' "$shared_apk")"
            local result=$?
            rm -f -- "$shared_apk"
            return "$result"
            ;;
        *)
            return 1
            ;;
    esac
}

uraam_installer() {
    show_logo
    msg "${BLUE}==========================================${NC}"
    msg "${CYAN}URAAM | APK INSTALLER${NC}"
    msg "Place APK files in: $APP_DIR"
    msg "${BLUE}----------------------------------------${NC}"
    require_backend || return 1

    local -a apks=()
    shopt -s nullglob
    apks=("$APP_DIR"/*.apk)
    shopt -u nullglob
    ((${#apks[@]} > 0)) || { err "No APK files found in $APP_DIR."; pause; return 1; }

    local confirm apk ok_count=0 fail_count=0
    printf 'Found %d APK(s).\n' "${#apks[@]}"
    read -r -p "Install all of them? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || return 0

    for apk in "${apks[@]}"; do
        printf 'Installing %s... ' "$(basename "$apk")"
        if install_one_apk "$apk" >/dev/null 2>&1; then
            ok "installed"
            ((ok_count+=1))
        else
            err "installation failed"
            ((fail_count+=1))
        fi
    done
    msg "Summary: ${GREEN}$ok_count installed${NC}, ${RED}$fail_count failed${NC}."
    pause
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

view_logs() {
    local directory="$1" label="$2"
    show_logo
    local -a logs=()
    shopt -s nullglob
    logs=("$directory"/*.log)
    shopt -u nullglob
    ((${#logs[@]} > 0)) || { warn "No $label logs found."; pause; return 0; }

    if command -v less >/dev/null 2>&1; then
        less -R "${logs[@]}"
    elif command -v nano >/dev/null 2>&1; then
        nano -v "${logs[@]}"
    else
        cat "${logs[@]}"
        pause
    fi
}

vl_menu() {
    show_logo
    printf ' [1] Debloat logs\n [2] Restore logs\n [3] Backup logs\n [4] Return\n [5] Exit\n'
    read -r -p "Choice: " choice
    case "$choice" in
        1) view_logs "$LOGD_DIR" debloat ;;
        2) view_logs "$LOGR_DIR" restore ;;
        3) view_logs "$LOGB_DIR" backup ;;
        4) return 0 ;;
        5) exit 0 ;;
        *) warn "Invalid option."; sleep 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Update engine
# ---------------------------------------------------------------------------

update_uraam() {
    show_logo
    msg "${BLUE}========================================${NC}"
    msg "${CYAN}=== URAAM | SCRIPT UPDATER ===${NC}"
    read -r -p "Download and replace the current script? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Update cancelled."; return 0; }

    command -v curl >/dev/null 2>&1 || { err "curl is required."; return 1; }
    local target_bin="$SOURCE"
    local raw_url="https://raw.githubusercontent.com/Ruraam/Uraam/main/uraam.sh"
    local tmp_file
    tmp_file="$(mktemp)" || return 1

    if ! curl -fL --retry 2 --connect-timeout 15 "$raw_url" -o "$tmp_file"; then
        rm -f "$tmp_file"
        err "Download failed."
        return 1
    fi
    bash -n "$tmp_file" || {
        rm -f "$tmp_file"
        err "Downloaded script has a Bash syntax error; current installation was not changed."
        return 1
    }

    if [[ -w "$target_bin" ]]; then
        if ! install -m 0755 "$tmp_file" "$target_bin"; then
            rm -f "$tmp_file"
            return 1
        fi
    else
        sudo install -m 0755 "$tmp_file" "$target_bin" || {
            rm -f "$tmp_file"
            return 1
        }
    fi
    rm -f "$tmp_file"
    ok "URAAM script updated."
    read -r -p "Press Enter to restart..."
    exec "$target_bin" "$@"
}

check_and_update() {
    show_logo
    if ! is_installed_via_deb uraam && ! is_installed_via_deb uraam-debian; then
        update_uraam
        return $?
    fi

    ensure_jq || return 1
    command -v curl >/dev/null 2>&1 || { err "curl is required."; return 1; }

    local repo_path api_url release_json latest_tag remote_ver local_ver deb_url tmp_deb
    repo_path="${REPO_URL#https://github.com/}"
    repo_path="${repo_path%.git}"
    api_url="https://api.github.com/repos/${repo_path}/releases/latest"

    release_json="$(curl -fsSL --retry 2 -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: URAAM-Updater' "$api_url")" || {
        err "Unable to contact GitHub release API."
        pause
        return 1
    }

    latest_tag="$(jq -r '.tag_name // empty' <<< "$release_json")"
    [[ -n "$latest_tag" ]] || {
        err "No published GitHub release found."
        jq -r '.message // empty' <<< "$release_json"
        pause
        return 1
    }

    remote_ver="${latest_tag#v}"
    local_ver="$(dpkg-query -W -f='${Version}' uraam 2>/dev/null || \
        dpkg-query -W -f='${Version}' uraam-debian 2>/dev/null || true)"
    local_ver="${local_ver#v}"
    printf 'Installed: %s\nLatest:    %s\n' "${local_ver:-unknown}" "$remote_ver"
    [[ "$local_ver" == "$remote_ver" ]] && { ok "URAAM is up to date."; pause; return 0; }

    deb_url="$(jq -r '.assets[]? | select(.name | test("uraam-debian.*\\.deb$")) | .browser_download_url' <<< "$release_json" | head -n1)"
    [[ -n "$deb_url" && "$deb_url" != null ]] || {
        err "A new release exists, but no uraam-debian .deb asset was found."
        pause
        return 1
    }

    read -r -p "Install version $latest_tag? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Update cancelled."; return 0; }

    tmp_deb="$(mktemp --suffix=.deb)" || return 1
    if ! curl -fL --retry 2 --connect-timeout 15 "$deb_url" -o "$tmp_deb"; then
        rm -f "$tmp_deb"
        err "Package download failed."
        return 1
    fi
    if ! dpkg-deb --info "$tmp_deb" >/dev/null 2>&1; then
        rm -f "$tmp_deb"
        err "Downloaded file is not a valid Debian package."
        return 1
    fi
    if sudo apt-get install -y "$tmp_deb"; then
        rm -f "$tmp_deb"
        ok "URAAM updated to $latest_tag. Restart the application."
        return 0
    fi
    rm -f "$tmp_deb"
    err "Package installation failed."
    return 1
}

# ---------------------------------------------------------------------------
# Main dashboard
# ---------------------------------------------------------------------------

show_main_menu() {
    show_logo
    msg "${BLUE}--------------------------------------------------------${NC}"
    msg ".      ${CYAN}=== URAAM v${URAAM_VERSION} Dashboard ===${NC}"
    msg "${BLUE}--------------------------------------------------------${NC}"
    detect_backend_status || true
    msg "${BLUE}--------------------------------------------------------${NC}"
    printf 'Debloat configurations: %s\n' "${USER_DEBLOAT_DIR/#$HOME/~}"
    printf 'APK directory:          %s\n' "${APP_DIR/#$HOME/~}"
    printf 'Backup / restore:       %s\n' "${BACKUPS_DIR/#$HOME/~}"
    msg "${BLUE}--------------------------------------------------------${NC}"
    printf ' [d] Debloat apps\n'
    printf ' [i] Install APK(s)\n'
    printf ' [b] Backup restoration list\n'
    printf ' [r] Restore packages\n'
    printf ' [w] Wireless menu\n'
    printf ' [l] View logs\n'
    printf ' [u] Update URAAM\n'
    printf ' [e] Exit\n'
}

handle_menu_choice() {
    case "$1" in
        d|D) uraam_debloat ;;
        i|I) uraam_installer ;;
        b|B) uraam_backup ;;
        r|R) uraam_restore ;;
        w|W) wireless_menu ;;
        l|L) vl_menu ;;
        u|U) check_and_update ;;
        e|E) msg "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) warn "Invalid option."; sleep 1 ;;
    esac
}

main() {
    init_directories || exit 1
    term_set_storage

    while true; do
        show_main_menu
        read -r -p "Enter choice: " user_choice || exit 0
        handle_menu_choice "$user_choice"
    done
}

if [[ "${URAAM_TESTING:-0}" != "1" ]]; then
    main "$@"
fi
\t' read -r risk category description <<< "$metadata"
        printf '\n  [BLOCKED] [UNSAFE] [%s] %s\n' "$category" "$pkg"
        printf '      %s\n' "$description"
    done
    for pkg in "${PREVIEW_UNKNOWN[@]}"; do
        metadata="$(uad_metadata_for_package "$pkg")"
        IFS=
    for pkg in "${PREVIEW_PROTECTED[@]}"; do
        printf '\n  [PROTECTED BY URAAM] %s\n' "$pkg"
    done
    for pkg in "${PREVIEW_MISSING[@]}"; do
        printf '\n  [NOT INSTALLED] %s\n' "$pkg"
    done

    msg ""
    printf 'Catalogue: %d selectable, %d Unsafe blocked, %d protected, %d absent.\n' \
        "${#CANDIDATE_PACKAGES[@]}" "${#PREVIEW_UNSAFE[@]}" \
        "${#PREVIEW_PROTECTED[@]}" "${#PREVIEW_MISSING[@]}"
    (( ${#CANDIDATE_PACKAGES[@]} > 0 )) || {
        warn "No selectable installed packages. Nothing can be changed."
        return 0
    }

    printf '\nSelect package numbers separated by commas (example: 1,3). Empty/C cancels: '
    read -r selection
    [[ -n "$selection" ]] || {
        warn "No packages selected. Nothing changed."
        return 0
    }
    [[ "$selection" != "c" && "$selection" != "C" ]] || {
        warn "Operation cancelled."
        return 0
    }
    IFS=',' read -r -a requested_indices <<< "$selection"
    for token in "${requested_indices[@]}"; do
        token="${token//[[:space:]]/}"
        [[ "$token" =~ ^[0-9]+$ ]] || {
            err "Invalid selection '$token'. Use comma-separated numbers only; no bulk keyword is accepted."
            return 1
        }
        (( token >= 1 && token <= ${#CANDIDATE_PACKAGES[@]} )) || {
            err "Selection '$token' is outside the available range."
            return 1
        }
        [[ -z "${selected_indices[$token]:-}" ]] || {
            err "Duplicate selection '$token'."
            return 1
        }
        selected_indices[$token]=1
        SELECTED_PACKAGES+=("${CANDIDATE_PACKAGES[$((token-1))]}")
    done

    operation_count="${#SELECTED_PACKAGES[@]}"
    msg ""
    msg "${BOLD}=== URAAM | FINAL OPERATION PREVIEW ===${NC}"
    for pkg in "${SELECTED_PACKAGES[@]}"; do
        metadata="$(uad_metadata_for_package "$pkg")"
        IFS=$'\t' read -r risk category description <<< "$metadata"
        printf '  [WILL %s] [%s] %s\n' "${action^^}" "$risk" "$pkg"
    done
    for index in "${!CANDIDATE_PACKAGES[@]}"; do
        pkg="${CANDIDATE_PACKAGES[$index]}"
        if [[ -z "${selected_indices[$((index+1))]:-}" ]]; then
            printf '  [NOT SELECTED] [%s] %s\n' "${CANDIDATE_RISKS[$index]}" "$pkg"
        fi
    done
    printf '\nExact selected operations: %d\n' "$operation_count"
    (( operation_count > 0 )) || {
        warn "No packages selected. Nothing can be changed."
        return 0
    }

    printf '\nChoose mode: [d] Dry-run only (no changes) / [a] Apply / [c] Cancel: '
    read -r mode
    case "$mode" in
        d|D)
            ok "DRY RUN complete: $operation_count manually selected package(s) would be $action."
            info "No uninstall, disable, install, or package-state command was executed."
            return 0
            ;;
        a|A)
            if [[ ! -r "$UAD_METADATA_FILE" ]] ||
                ! jq -e 'type == "object" and length > 0' "$UAD_METADATA_FILE" >/dev/null 2>&1; then
                err "Cannot apply changes without a valid bundled UAD-NG risk catalogue."
                return 1
            fi
            ;;
        *) warn "Operation cancelled; no changes made."; return 0 ;;
    esac

    printf 'Type exactly "APPLY %s" to confirm these %s operation(s): ' "$operation_count" "$operation_count"
    read -r confirm
    [[ "$confirm" == "APPLY $operation_count" ]] || {
        warn "Confirmation did not match. No changes made."
        return 0
    }

    installed="$(device_package_list active)" || {
        err "Cannot refresh package inventory; no changes made."
        return 1
    }
    ready_count=0
    for pkg in "${SELECTED_PACKAGES[@]}"; do
        metadata="$(uad_metadata_for_package "$pkg")" || return 1
        IFS=$'\t' read -r risk _ _ <<< "$metadata"
        if ! is_whitelisted "$pkg" &&
            [[ "$risk" == "Recommended" || "$risk" == "Advanced" || "$risk" == "Expert" ]] &&
            package_is_installed "$pkg" "$installed"; then
            ((ready_count+=1))
        fi
    done
    if (( ready_count != operation_count )); then
        warn "Device or UAD safety state changed after preview ($operation_count planned, $ready_count still eligible)."
        warn "Run Preview again; no changes made."
        return 1
    fi

    start_log debloat "$LOGD_DIR" uraam-debloat || return 1
    for pkg in "${SELECTED_PACKAGES[@]}"; do
        printf '%s: ' "$pkg"
        if is_whitelisted "$pkg"; then
            err "became protected; skipped"
            ((skipped+=1))
            continue
        fi
        if [[ "$action" == uninstall ]]; then
            if run_device pm uninstall -k --user 0 "$pkg" >/dev/null 2>&1; then
                ok "uninstalled for user 0"
                ((success+=1))
            else
                err "uninstall failed"
                ((failed+=1))
            fi
        else
            if run_device pm disable-user --user 0 "$pkg" >/dev/null 2>&1; then
                ok "disabled"
                ((success+=1))
            else
                err "disable failed"
                ((failed+=1))
            fi
        fi
    done
    msg "${BLUE}----------------------------------------${NC}"
    msg "Summary: ${GREEN}$success succeeded${NC}, ${YELLOW}$skipped skipped${NC}, ${RED}$failed failed${NC}."
    msg "Log: $LOGFILE"
    pause
}

ubackup() {
    local output_dir="$BACKUPS_DIR" date_str output_file
    mkdir -p "$output_dir" || return 1
    date_str="$(date +%Y%m%d_%H%M%S)"
    output_file="$output_dir/Uraam_Restoration_List_${date_str}.json"

    local all_pkgs active_pkgs model android_ver
    all_pkgs="$(device_package_list active)" || return 1
    active_pkgs="$(device_package_list active)" || return 1
    [[ -n "$all_pkgs" ]] || { err "Unable to retrieve installed packages."; return 1; }

    model="$(device_getprop ro.product.model || true)"
    android_ver="$(device_getprop ro.build.version.release || true)"

    comm -23 <(printf '%s\n' "$all_pkgs") <(printf '%s\n' "$active_pkgs") |
        jq -R -s --arg date "$date_str" --arg model "$model" --arg android "$android_ver" '
            [split("\n")[] | select(test("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")) | {packageName:.}] as $apps
            | {
                name:("Uraam_Restore_List_"+$date),
                description:"Packages not currently installed for Android user 0",
                author:"URAAM", version:"4.4.6",
                device:$model, android_version:$android, created_at:$date, apps:$apps
            }
        ' > "$output_file" || { rm -f "$output_file"; return 1; }

    local count
    count="$(jq '.apps | length' "$output_file" 2>/dev/null)" || count=0
    if (( count == 0 )); then
        rm -f "$output_file"
        warn "No disabled or user-uninstalled packages were found."
        return 0
    fi
    ok "Saved $count package(s) to $output_file"
}

uraam_backup() {
    show_logo
    msg "${BLUE}===============================================${NC}"
    msg "${CYAN}URAAM | BACKUP CREATOR${NC}"
    msg "${BLUE}===============================================${NC}"
    require_backend || return 1
    read -r -p "Create a restoration list of packages missing for user 0? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Cancelled."; return 0; }
    start_log backup "$LOGB_DIR" uraam-backup || return 1
    ubackup
    pause
}

uraam_restore() {
    show_logo
    msg "${BLUE}=========================================${NC}"
    msg "${CYAN}URAAM | RESTORER${NC}"
    msg "${BLUE}=========================================${NC}"
    require_backend || return 1
    select_json_file "$BACKUPS_DIR" "Available restoration lists:" || return 1
    load_packages_from_json "$SELECTED_FILE" || { pause; return 1; }

    warn "The selected list contains ${#PACKAGES[@]} package(s)."
    read -r -p "Restore these packages for Android user 0? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Cancelled."; return 0; }

    start_log restore "$LOGR_DIR" uraam-restore || return 1
    local success=0 failed=0 pkg
    for pkg in "${PACKAGES[@]}"; do
        printf '%s: ' "$pkg"
        if run_device pm install-existing --user 0 "$pkg" >/dev/null 2>&1; then
            ok "restored"
            ((success+=1))
        else
            err "not restored (not present on device, or operation denied)"
            ((failed+=1))
        fi
    done
    msg "${BLUE}----------------------------------------${NC}"
    msg "Summary: ${GREEN}$success restored${NC}, ${RED}$failed failed${NC}."
    msg "Log: $LOGFILE"
    pause
}

# ---------------------------------------------------------------------------
# APK installation
# ---------------------------------------------------------------------------

install_one_apk() {
    local apk="$1"
    local remote="/data/local/tmp/uraam-$(date +%s)-$(basename "$apk")"

    case "$EXEC_TYPE" in
        ADB)
            local -a cmd=(adb)
            [[ -n "$BACKEND_SERIAL" ]] && cmd+=(-s "$BACKEND_SERIAL")
            "${cmd[@]}" install -r -g "$apk"
            ;;
        ROOT)
            su -c "cp $(printf '%q' "$apk") $(printf '%q' "$remote")" || return 1
            run_device pm install -r -g "$remote"
            local result=$?
            su -c "rm -f $(printf '%q' "$remote")" >/dev/null 2>&1 || true
            return "$result"
            ;;
        SHIZUKU)
            local shared_dir="$HOME/storage/downloads/URAAM"
            local shared_apk="$shared_dir/$(basename "$apk")"
            [[ -d "$HOME/storage" ]] || {
                err "Termux storage is not set up. Run termux-setup-storage first."
                return 1
            }
            mkdir -p "$shared_dir" || return 1
            cp -- "$apk" "$shared_apk" || return 1
            rish -c "pm install -r -g $(printf '%q' "$shared_apk")"
            local result=$?
            rm -f -- "$shared_apk"
            return "$result"
            ;;
        *)
            return 1
            ;;
    esac
}

uraam_installer() {
    show_logo
    msg "${BLUE}==========================================${NC}"
    msg "${CYAN}URAAM | APK INSTALLER${NC}"
    msg "Place APK files in: $APP_DIR"
    msg "${BLUE}----------------------------------------${NC}"
    require_backend || return 1

    local -a apks=()
    shopt -s nullglob
    apks=("$APP_DIR"/*.apk)
    shopt -u nullglob
    ((${#apks[@]} > 0)) || { err "No APK files found in $APP_DIR."; pause; return 1; }

    local confirm apk ok_count=0 fail_count=0
    printf 'Found %d APK(s).\n' "${#apks[@]}"
    read -r -p "Install all of them? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || return 0

    for apk in "${apks[@]}"; do
        printf 'Installing %s... ' "$(basename "$apk")"
        if install_one_apk "$apk" >/dev/null 2>&1; then
            ok "installed"
            ((ok_count+=1))
        else
            err "installation failed"
            ((fail_count+=1))
        fi
    done
    msg "Summary: ${GREEN}$ok_count installed${NC}, ${RED}$fail_count failed${NC}."
    pause
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

view_logs() {
    local directory="$1" label="$2"
    show_logo
    local -a logs=()
    shopt -s nullglob
    logs=("$directory"/*.log)
    shopt -u nullglob
    ((${#logs[@]} > 0)) || { warn "No $label logs found."; pause; return 0; }

    if command -v less >/dev/null 2>&1; then
        less -R "${logs[@]}"
    elif command -v nano >/dev/null 2>&1; then
        nano -v "${logs[@]}"
    else
        cat "${logs[@]}"
        pause
    fi
}

vl_menu() {
    show_logo
    printf ' [1] Debloat logs\n [2] Restore logs\n [3] Backup logs\n [4] Return\n [5] Exit\n'
    read -r -p "Choice: " choice
    case "$choice" in
        1) view_logs "$LOGD_DIR" debloat ;;
        2) view_logs "$LOGR_DIR" restore ;;
        3) view_logs "$LOGB_DIR" backup ;;
        4) return 0 ;;
        5) exit 0 ;;
        *) warn "Invalid option."; sleep 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Update engine
# ---------------------------------------------------------------------------

update_uraam() {
    show_logo
    msg "${BLUE}========================================${NC}"
    msg "${CYAN}=== URAAM | SCRIPT UPDATER ===${NC}"
    read -r -p "Download and replace the current script? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Update cancelled."; return 0; }

    command -v curl >/dev/null 2>&1 || { err "curl is required."; return 1; }
    local target_bin="$SOURCE"
    local raw_url="https://raw.githubusercontent.com/Ruraam/Uraam/main/uraam.sh"
    local tmp_file
    tmp_file="$(mktemp)" || return 1

    if ! curl -fL --retry 2 --connect-timeout 15 "$raw_url" -o "$tmp_file"; then
        rm -f "$tmp_file"
        err "Download failed."
        return 1
    fi
    bash -n "$tmp_file" || {
        rm -f "$tmp_file"
        err "Downloaded script has a Bash syntax error; current installation was not changed."
        return 1
    }

    if [[ -w "$target_bin" ]]; then
        if ! install -m 0755 "$tmp_file" "$target_bin"; then
            rm -f "$tmp_file"
            return 1
        fi
    else
        sudo install -m 0755 "$tmp_file" "$target_bin" || {
            rm -f "$tmp_file"
            return 1
        }
    fi
    rm -f "$tmp_file"
    ok "URAAM script updated."
    read -r -p "Press Enter to restart..."
    exec "$target_bin" "$@"
}

check_and_update() {
    show_logo
    if ! is_installed_via_deb uraam && ! is_installed_via_deb uraam-debian; then
        update_uraam
        return $?
    fi

    ensure_jq || return 1
    command -v curl >/dev/null 2>&1 || { err "curl is required."; return 1; }

    local repo_path api_url release_json latest_tag remote_ver local_ver deb_url tmp_deb
    repo_path="${REPO_URL#https://github.com/}"
    repo_path="${repo_path%.git}"
    api_url="https://api.github.com/repos/${repo_path}/releases/latest"

    release_json="$(curl -fsSL --retry 2 -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: URAAM-Updater' "$api_url")" || {
        err "Unable to contact GitHub release API."
        pause
        return 1
    }

    latest_tag="$(jq -r '.tag_name // empty' <<< "$release_json")"
    [[ -n "$latest_tag" ]] || {
        err "No published GitHub release found."
        jq -r '.message // empty' <<< "$release_json"
        pause
        return 1
    }

    remote_ver="${latest_tag#v}"
    local_ver="$(dpkg-query -W -f='${Version}' uraam 2>/dev/null || \
        dpkg-query -W -f='${Version}' uraam-debian 2>/dev/null || true)"
    local_ver="${local_ver#v}"
    printf 'Installed: %s\nLatest:    %s\n' "${local_ver:-unknown}" "$remote_ver"
    [[ "$local_ver" == "$remote_ver" ]] && { ok "URAAM is up to date."; pause; return 0; }

    deb_url="$(jq -r '.assets[]? | select(.name | test("uraam-debian.*\\.deb$")) | .browser_download_url' <<< "$release_json" | head -n1)"
    [[ -n "$deb_url" && "$deb_url" != null ]] || {
        err "A new release exists, but no uraam-debian .deb asset was found."
        pause
        return 1
    }

    read -r -p "Install version $latest_tag? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Update cancelled."; return 0; }

    tmp_deb="$(mktemp --suffix=.deb)" || return 1
    if ! curl -fL --retry 2 --connect-timeout 15 "$deb_url" -o "$tmp_deb"; then
        rm -f "$tmp_deb"
        err "Package download failed."
        return 1
    fi
    if ! dpkg-deb --info "$tmp_deb" >/dev/null 2>&1; then
        rm -f "$tmp_deb"
        err "Downloaded file is not a valid Debian package."
        return 1
    fi
    if sudo apt-get install -y "$tmp_deb"; then
        rm -f "$tmp_deb"
        ok "URAAM updated to $latest_tag. Restart the application."
        return 0
    fi
    rm -f "$tmp_deb"
    err "Package installation failed."
    return 1
}

# ---------------------------------------------------------------------------
# Main dashboard
# ---------------------------------------------------------------------------

show_main_menu() {
    show_logo
    msg "${BLUE}--------------------------------------------------------${NC}"
    msg ".      ${CYAN}=== URAAM v${URAAM_VERSION} Dashboard ===${NC}"
    msg "${BLUE}--------------------------------------------------------${NC}"
    detect_backend_status || true
    msg "${BLUE}--------------------------------------------------------${NC}"
    printf 'Debloat configurations: %s\n' "${USER_DEBLOAT_DIR/#$HOME/~}"
    printf 'APK directory:          %s\n' "${APP_DIR/#$HOME/~}"
    printf 'Backup / restore:       %s\n' "${BACKUPS_DIR/#$HOME/~}"
    msg "${BLUE}--------------------------------------------------------${NC}"
    printf ' [d] Debloat apps\n'
    printf ' [i] Install APK(s)\n'
    printf ' [b] Backup restoration list\n'
    printf ' [r] Restore packages\n'
    printf ' [w] Wireless menu\n'
    printf ' [l] View logs\n'
    printf ' [u] Update URAAM\n'
    printf ' [e] Exit\n'
}

handle_menu_choice() {
    case "$1" in
        d|D) uraam_debloat ;;
        i|I) uraam_installer ;;
        b|B) uraam_backup ;;
        r|R) uraam_restore ;;
        w|W) wireless_menu ;;
        l|L) vl_menu ;;
        u|U) check_and_update ;;
        e|E) msg "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) warn "Invalid option."; sleep 1 ;;
    esac
}

main() {
    init_directories || exit 1
    term_set_storage

    while true; do
        show_main_menu
        read -r -p "Enter choice: " user_choice || exit 0
        handle_menu_choice "$user_choice"
    done
}

if [[ "${URAAM_TESTING:-0}" != "1" ]]; then
    main "$@"
fi
\t' read -r risk category description <<< "$metadata"
        printf '\n  [BLOCKED] [UNKNOWN] [%s] %s\n' "$category" "$pkg"
        printf '      %s\n' "$description"
    done
    for pkg in "${PREVIEW_PROTECTED[@]}"; do
        printf '\n  [PROTECTED BY URAAM] %s\n' "$pkg"
    done
    for pkg in "${PREVIEW_MISSING[@]}"; do
        printf '\n  [NOT INSTALLED] %s\n' "$pkg"
    done

    msg ""
    printf 'Catalogue: %d selectable, %d Unsafe blocked, %d protected, %d absent.\n' \
        "${#CANDIDATE_PACKAGES[@]}" "${#PREVIEW_UNSAFE[@]}" \
        "${#PREVIEW_PROTECTED[@]}" "${#PREVIEW_MISSING[@]}"
    (( ${#CANDIDATE_PACKAGES[@]} > 0 )) || {
        warn "No selectable installed packages. Nothing can be changed."
        return 0
    }

    printf '\nSelect package numbers separated by commas (example: 1,3). Empty/C cancels: '
    read -r selection
    [[ -n "$selection" ]] || {
        warn "No packages selected. Nothing changed."
        return 0
    }
    [[ "$selection" != "c" && "$selection" != "C" ]] || {
        warn "Operation cancelled."
        return 0
    }
    IFS=',' read -r -a requested_indices <<< "$selection"
    for token in "${requested_indices[@]}"; do
        token="${token//[[:space:]]/}"
        [[ "$token" =~ ^[0-9]+$ ]] || {
            err "Invalid selection '$token'. Use comma-separated numbers only; no bulk keyword is accepted."
            return 1
        }
        (( token >= 1 && token <= ${#CANDIDATE_PACKAGES[@]} )) || {
            err "Selection '$token' is outside the available range."
            return 1
        }
        [[ -z "${selected_indices[$token]:-}" ]] || {
            err "Duplicate selection '$token'."
            return 1
        }
        selected_indices[$token]=1
        SELECTED_PACKAGES+=("${CANDIDATE_PACKAGES[$((token-1))]}")
    done

    operation_count="${#SELECTED_PACKAGES[@]}"
    msg ""
    msg "${BOLD}=== URAAM | FINAL OPERATION PREVIEW ===${NC}"
    for pkg in "${SELECTED_PACKAGES[@]}"; do
        metadata="$(uad_metadata_for_package "$pkg")"
        IFS=$'\t' read -r risk category description <<< "$metadata"
        printf '  [WILL %s] [%s] %s\n' "${action^^}" "$risk" "$pkg"
    done
    for index in "${!CANDIDATE_PACKAGES[@]}"; do
        pkg="${CANDIDATE_PACKAGES[$index]}"
        if [[ -z "${selected_indices[$((index+1))]:-}" ]]; then
            printf '  [NOT SELECTED] [%s] %s\n' "${CANDIDATE_RISKS[$index]}" "$pkg"
        fi
    done
    printf '\nExact selected operations: %d\n' "$operation_count"
    (( operation_count > 0 )) || {
        warn "No packages selected. Nothing can be changed."
        return 0
    }

    printf '\nChoose mode: [d] Dry-run only (no changes) / [a] Apply / [c] Cancel: '
    read -r mode
    case "$mode" in
        d|D)
            ok "DRY RUN complete: $operation_count manually selected package(s) would be $action."
            info "No uninstall, disable, install, or package-state command was executed."
            return 0
            ;;
        a|A)
            if [[ ! -r "$UAD_METADATA_FILE" ]] ||
                ! jq -e 'type == "object" and length > 0' "$UAD_METADATA_FILE" >/dev/null 2>&1; then
                err "Cannot apply changes without a valid bundled UAD-NG risk catalogue."
                return 1
            fi
            ;;
        *) warn "Operation cancelled; no changes made."; return 0 ;;
    esac

    printf 'Type exactly "APPLY %s" to confirm these %s operation(s): ' "$operation_count" "$operation_count"
    read -r confirm
    [[ "$confirm" == "APPLY $operation_count" ]] || {
        warn "Confirmation did not match. No changes made."
        return 0
    }

    installed="$(device_package_list active)" || {
        err "Cannot refresh package inventory; no changes made."
        return 1
    }
    ready_count=0
    for pkg in "${SELECTED_PACKAGES[@]}"; do
        metadata="$(uad_metadata_for_package "$pkg")" || return 1
        IFS=$'\t' read -r risk _ _ <<< "$metadata"
        if ! is_whitelisted "$pkg" &&
            [[ "$risk" == "Recommended" || "$risk" == "Advanced" || "$risk" == "Expert" ]] &&
            package_is_installed "$pkg" "$installed"; then
            ((ready_count+=1))
        fi
    done
    if (( ready_count != operation_count )); then
        warn "Device or UAD safety state changed after preview ($operation_count planned, $ready_count still eligible)."
        warn "Run Preview again; no changes made."
        return 1
    fi

    start_log debloat "$LOGD_DIR" uraam-debloat || return 1
    for pkg in "${SELECTED_PACKAGES[@]}"; do
        printf '%s: ' "$pkg"
        if is_whitelisted "$pkg"; then
            err "became protected; skipped"
            ((skipped+=1))
            continue
        fi
        if [[ "$action" == uninstall ]]; then
            if run_device pm uninstall -k --user 0 "$pkg" >/dev/null 2>&1; then
                ok "uninstalled for user 0"
                ((success+=1))
            else
                err "uninstall failed"
                ((failed+=1))
            fi
        else
            if run_device pm disable-user --user 0 "$pkg" >/dev/null 2>&1; then
                ok "disabled"
                ((success+=1))
            else
                err "disable failed"
                ((failed+=1))
            fi
        fi
    done
    msg "${BLUE}----------------------------------------${NC}"
    msg "Summary: ${GREEN}$success succeeded${NC}, ${YELLOW}$skipped skipped${NC}, ${RED}$failed failed${NC}."
    msg "Log: $LOGFILE"
    pause
}

ubackup() {
    local output_dir="$BACKUPS_DIR" date_str output_file
    mkdir -p "$output_dir" || return 1
    date_str="$(date +%Y%m%d_%H%M%S)"
    output_file="$output_dir/Uraam_Restoration_List_${date_str}.json"

    local all_pkgs active_pkgs model android_ver
    all_pkgs="$(device_package_list active)" || return 1
    active_pkgs="$(device_package_list active)" || return 1
    [[ -n "$all_pkgs" ]] || { err "Unable to retrieve installed packages."; return 1; }

    model="$(device_getprop ro.product.model || true)"
    android_ver="$(device_getprop ro.build.version.release || true)"

    comm -23 <(printf '%s\n' "$all_pkgs") <(printf '%s\n' "$active_pkgs") |
        jq -R -s --arg date "$date_str" --arg model "$model" --arg android "$android_ver" '
            [split("\n")[] | select(test("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")) | {packageName:.}] as $apps
            | {
                name:("Uraam_Restore_List_"+$date),
                description:"Packages not currently installed for Android user 0",
                author:"URAAM", version:"4.4.6",
                device:$model, android_version:$android, created_at:$date, apps:$apps
            }
        ' > "$output_file" || { rm -f "$output_file"; return 1; }

    local count
    count="$(jq '.apps | length' "$output_file" 2>/dev/null)" || count=0
    if (( count == 0 )); then
        rm -f "$output_file"
        warn "No disabled or user-uninstalled packages were found."
        return 0
    fi
    ok "Saved $count package(s) to $output_file"
}

uraam_backup() {
    show_logo
    msg "${BLUE}===============================================${NC}"
    msg "${CYAN}URAAM | BACKUP CREATOR${NC}"
    msg "${BLUE}===============================================${NC}"
    require_backend || return 1
    read -r -p "Create a restoration list of packages missing for user 0? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Cancelled."; return 0; }
    start_log backup "$LOGB_DIR" uraam-backup || return 1
    ubackup
    pause
}

uraam_restore() {
    show_logo
    msg "${BLUE}=========================================${NC}"
    msg "${CYAN}URAAM | RESTORER${NC}"
    msg "${BLUE}=========================================${NC}"
    require_backend || return 1
    select_json_file "$BACKUPS_DIR" "Available restoration lists:" || return 1
    load_packages_from_json "$SELECTED_FILE" || { pause; return 1; }

    warn "The selected list contains ${#PACKAGES[@]} package(s)."
    read -r -p "Restore these packages for Android user 0? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Cancelled."; return 0; }

    start_log restore "$LOGR_DIR" uraam-restore || return 1
    local success=0 failed=0 pkg
    for pkg in "${PACKAGES[@]}"; do
        printf '%s: ' "$pkg"
        if run_device pm install-existing --user 0 "$pkg" >/dev/null 2>&1; then
            ok "restored"
            ((success+=1))
        else
            err "not restored (not present on device, or operation denied)"
            ((failed+=1))
        fi
    done
    msg "${BLUE}----------------------------------------${NC}"
    msg "Summary: ${GREEN}$success restored${NC}, ${RED}$failed failed${NC}."
    msg "Log: $LOGFILE"
    pause
}

# ---------------------------------------------------------------------------
# APK installation
# ---------------------------------------------------------------------------

install_one_apk() {
    local apk="$1"
    local remote="/data/local/tmp/uraam-$(date +%s)-$(basename "$apk")"

    case "$EXEC_TYPE" in
        ADB)
            local -a cmd=(adb)
            [[ -n "$BACKEND_SERIAL" ]] && cmd+=(-s "$BACKEND_SERIAL")
            "${cmd[@]}" install -r -g "$apk"
            ;;
        ROOT)
            su -c "cp $(printf '%q' "$apk") $(printf '%q' "$remote")" || return 1
            run_device pm install -r -g "$remote"
            local result=$?
            su -c "rm -f $(printf '%q' "$remote")" >/dev/null 2>&1 || true
            return "$result"
            ;;
        SHIZUKU)
            local shared_dir="$HOME/storage/downloads/URAAM"
            local shared_apk="$shared_dir/$(basename "$apk")"
            [[ -d "$HOME/storage" ]] || {
                err "Termux storage is not set up. Run termux-setup-storage first."
                return 1
            }
            mkdir -p "$shared_dir" || return 1
            cp -- "$apk" "$shared_apk" || return 1
            rish -c "pm install -r -g $(printf '%q' "$shared_apk")"
            local result=$?
            rm -f -- "$shared_apk"
            return "$result"
            ;;
        *)
            return 1
            ;;
    esac
}

uraam_installer() {
    show_logo
    msg "${BLUE}==========================================${NC}"
    msg "${CYAN}URAAM | APK INSTALLER${NC}"
    msg "Place APK files in: $APP_DIR"
    msg "${BLUE}----------------------------------------${NC}"
    require_backend || return 1

    local -a apks=()
    shopt -s nullglob
    apks=("$APP_DIR"/*.apk)
    shopt -u nullglob
    ((${#apks[@]} > 0)) || { err "No APK files found in $APP_DIR."; pause; return 1; }

    local confirm apk ok_count=0 fail_count=0
    printf 'Found %d APK(s).\n' "${#apks[@]}"
    read -r -p "Install all of them? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || return 0

    for apk in "${apks[@]}"; do
        printf 'Installing %s... ' "$(basename "$apk")"
        if install_one_apk "$apk" >/dev/null 2>&1; then
            ok "installed"
            ((ok_count+=1))
        else
            err "installation failed"
            ((fail_count+=1))
        fi
    done
    msg "Summary: ${GREEN}$ok_count installed${NC}, ${RED}$fail_count failed${NC}."
    pause
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

view_logs() {
    local directory="$1" label="$2"
    show_logo
    local -a logs=()
    shopt -s nullglob
    logs=("$directory"/*.log)
    shopt -u nullglob
    ((${#logs[@]} > 0)) || { warn "No $label logs found."; pause; return 0; }

    if command -v less >/dev/null 2>&1; then
        less -R "${logs[@]}"
    elif command -v nano >/dev/null 2>&1; then
        nano -v "${logs[@]}"
    else
        cat "${logs[@]}"
        pause
    fi
}

vl_menu() {
    show_logo
    printf ' [1] Debloat logs\n [2] Restore logs\n [3] Backup logs\n [4] Return\n [5] Exit\n'
    read -r -p "Choice: " choice
    case "$choice" in
        1) view_logs "$LOGD_DIR" debloat ;;
        2) view_logs "$LOGR_DIR" restore ;;
        3) view_logs "$LOGB_DIR" backup ;;
        4) return 0 ;;
        5) exit 0 ;;
        *) warn "Invalid option."; sleep 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Update engine
# ---------------------------------------------------------------------------

update_uraam() {
    show_logo
    msg "${BLUE}========================================${NC}"
    msg "${CYAN}=== URAAM | SCRIPT UPDATER ===${NC}"
    read -r -p "Download and replace the current script? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Update cancelled."; return 0; }

    command -v curl >/dev/null 2>&1 || { err "curl is required."; return 1; }
    local target_bin="$SOURCE"
    local raw_url="https://raw.githubusercontent.com/Ruraam/Uraam/main/uraam.sh"
    local tmp_file
    tmp_file="$(mktemp)" || return 1

    if ! curl -fL --retry 2 --connect-timeout 15 "$raw_url" -o "$tmp_file"; then
        rm -f "$tmp_file"
        err "Download failed."
        return 1
    fi
    bash -n "$tmp_file" || {
        rm -f "$tmp_file"
        err "Downloaded script has a Bash syntax error; current installation was not changed."
        return 1
    }

    if [[ -w "$target_bin" ]]; then
        if ! install -m 0755 "$tmp_file" "$target_bin"; then
            rm -f "$tmp_file"
            return 1
        fi
    else
        sudo install -m 0755 "$tmp_file" "$target_bin" || {
            rm -f "$tmp_file"
            return 1
        }
    fi
    rm -f "$tmp_file"
    ok "URAAM script updated."
    read -r -p "Press Enter to restart..."
    exec "$target_bin" "$@"
}

check_and_update() {
    show_logo
    if ! is_installed_via_deb uraam && ! is_installed_via_deb uraam-debian; then
        update_uraam
        return $?
    fi

    ensure_jq || return 1
    command -v curl >/dev/null 2>&1 || { err "curl is required."; return 1; }

    local repo_path api_url release_json latest_tag remote_ver local_ver deb_url tmp_deb
    repo_path="${REPO_URL#https://github.com/}"
    repo_path="${repo_path%.git}"
    api_url="https://api.github.com/repos/${repo_path}/releases/latest"

    release_json="$(curl -fsSL --retry 2 -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: URAAM-Updater' "$api_url")" || {
        err "Unable to contact GitHub release API."
        pause
        return 1
    }

    latest_tag="$(jq -r '.tag_name // empty' <<< "$release_json")"
    [[ -n "$latest_tag" ]] || {
        err "No published GitHub release found."
        jq -r '.message // empty' <<< "$release_json"
        pause
        return 1
    }

    remote_ver="${latest_tag#v}"
    local_ver="$(dpkg-query -W -f='${Version}' uraam 2>/dev/null || \
        dpkg-query -W -f='${Version}' uraam-debian 2>/dev/null || true)"
    local_ver="${local_ver#v}"
    printf 'Installed: %s\nLatest:    %s\n' "${local_ver:-unknown}" "$remote_ver"
    [[ "$local_ver" == "$remote_ver" ]] && { ok "URAAM is up to date."; pause; return 0; }

    deb_url="$(jq -r '.assets[]? | select(.name | test("uraam-debian.*\\.deb$")) | .browser_download_url' <<< "$release_json" | head -n1)"
    [[ -n "$deb_url" && "$deb_url" != null ]] || {
        err "A new release exists, but no uraam-debian .deb asset was found."
        pause
        return 1
    }

    read -r -p "Install version $latest_tag? [y/N]: " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { warn "Update cancelled."; return 0; }

    tmp_deb="$(mktemp --suffix=.deb)" || return 1
    if ! curl -fL --retry 2 --connect-timeout 15 "$deb_url" -o "$tmp_deb"; then
        rm -f "$tmp_deb"
        err "Package download failed."
        return 1
    fi
    if ! dpkg-deb --info "$tmp_deb" >/dev/null 2>&1; then
        rm -f "$tmp_deb"
        err "Downloaded file is not a valid Debian package."
        return 1
    fi
    if sudo apt-get install -y "$tmp_deb"; then
        rm -f "$tmp_deb"
        ok "URAAM updated to $latest_tag. Restart the application."
        return 0
    fi
    rm -f "$tmp_deb"
    err "Package installation failed."
    return 1
}

# ---------------------------------------------------------------------------
# Main dashboard
# ---------------------------------------------------------------------------

show_main_menu() {
    show_logo
    msg "${BLUE}--------------------------------------------------------${NC}"
    msg ".      ${CYAN}=== URAAM v${URAAM_VERSION} Dashboard ===${NC}"
    msg "${BLUE}--------------------------------------------------------${NC}"
    detect_backend_status || true
    msg "${BLUE}--------------------------------------------------------${NC}"
    printf 'Debloat configurations: %s\n' "${USER_DEBLOAT_DIR/#$HOME/~}"
    printf 'APK directory:          %s\n' "${APP_DIR/#$HOME/~}"
    printf 'Backup / restore:       %s\n' "${BACKUPS_DIR/#$HOME/~}"
    msg "${BLUE}--------------------------------------------------------${NC}"
    printf ' [d] Debloat apps\n'
    printf ' [i] Install APK(s)\n'
    printf ' [b] Backup restoration list\n'
    printf ' [r] Restore packages\n'
    printf ' [w] Wireless menu\n'
    printf ' [l] View logs\n'
    printf ' [u] Update URAAM\n'
    printf ' [e] Exit\n'
}

handle_menu_choice() {
    case "$1" in
        d|D) uraam_debloat ;;
        i|I) uraam_installer ;;
        b|B) uraam_backup ;;
        r|R) uraam_restore ;;
        w|W) wireless_menu ;;
        l|L) vl_menu ;;
        u|U) check_and_update ;;
        e|E) msg "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) warn "Invalid option."; sleep 1 ;;
    esac
}

main() {
    init_directories || exit 1
    term_set_storage

    while true; do
        show_main_menu
        read -r -p "Enter choice: " user_choice || exit 0
        handle_menu_choice "$user_choice"
    done
}

if [[ "${URAAM_TESTING:-0}" != "1" ]]; then
    main "$@"
fi
