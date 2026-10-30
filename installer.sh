#!/usr/bin/env bash
# ==============================================================================
# Installer Script for URAAM
# Project : URAAM (Universal Ruvomain Android App-Manager)
# Author  : Ruvyrom
# License : GPL-3.0
# Description: Installer/updater for Debian/Ubuntu, other Linux distributions
#              (standalone mode), and Android (Termux).
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

CURRENT_VERSION="4.4.3"
REPO_OWNER="Ruraam"
REPO_NAME="Uraam"
BRANCH="main"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/uraam.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

IS_TERMUX=false
CURRENT_MODEL=""
SCRIPT_TMP=""

# ------------------------------------------------------------------------------
# General helpers
# ------------------------------------------------------------------------------

cleanup() {
    if [[ -n "${SCRIPT_TMP:-}" && -e "$SCRIPT_TMP" ]]; then
        rm -f -- "$SCRIPT_TMP"
    fi
}
trap cleanup EXIT

msg() {
    printf '%b\n' "$*"
}

pause_menu() {
    local prompt="${1:-Press Enter to return to the menu...}"
    read -r -p "$prompt" _ || true
}

confirm_yes() {
    local answer=""
    read -r -p "${1:-Continue?} [y/N]: " answer || true
    [[ "$answer" =~ ^[yY]([eE][sS])?$ ]]
}

have_command() {
    command -v "$1" >/dev/null 2>&1
}

run_as_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        "$@"
    elif have_command sudo; then
        sudo "$@"
    elif have_command su; then
        su -c "$(printf '%q ' "$@")"
    else
        msg "${RED}[X] Root privileges are required (sudo or su not found).${NC}"
        return 1
    fi
}

is_termux() {
    [[ -d /data/data/com.termux ]] ||
    [[ "${PREFIX:-}" == *"/com.termux"* ]]
}

is_debian_like() {
    [[ -r /etc/os-release ]] || return 1

    local id="" id_like=""
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"

    case "$id" in
        debian|ubuntu|linuxmint|pop|elementary|zorin) return 0 ;;
    esac

    [[ " ${id_like,,} " == *" debian "* || " ${id_like,,} " == *" ubuntu "* ]]
}

is_installed_via_deb() {
    local package_name
    [[ "$IS_TERMUX" == true ]] && return 1
    have_command dpkg-query || return 1

    for package_name in "${@:-uraam-debian}" uraam-debian uraam; do
        [[ -n "$package_name" ]] || continue
        if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null |
            grep -q 'install ok installed'; then
            return 0
        fi
    done
    return 1
}

device_brand() {
    local brand="" model="" android_version="" vendor="" product=""

    if have_command getprop; then
        brand="$(getprop ro.product.manufacturer 2>/dev/null || true)"
        model="$(getprop ro.product.model 2>/dev/null || true)"
        android_version="$(getprop ro.build.version.release 2>/dev/null || true)"
    fi

    if [[ -n "$brand" || -n "$model" ]]; then
        [[ -n "$android_version" ]] && android_version=" (Android ${android_version})"
        CURRENT_MODEL="${brand:+${brand^} }${model}${android_version}"
        return
    fi

    if [[ -r /sys/devices/virtual/dmi/id/sys_vendor ]]; then
        vendor="$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || true)"
    fi
    if [[ -r /sys/devices/virtual/dmi/id/product_name ]]; then
        product="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)"
    fi

    CURRENT_MODEL="$(printf '%s ' "$vendor" "$product" "$(uname -s)" "$(uname -m)" |
        sed 's/[[:space:]]*$//')"
}

show_logo() {
    device_brand
    [[ -t 1 ]] && clear 2>/dev/null || true

    printf '%b' "$PURPLE"
    cat <<'EOF'
::| ::|::::::\ ::::\  ::::\ ::::::|
::|\_::|::|,::|::|,::|::|,::|:::"::|
`:::::|::| ::\::| ::|::| ::|::| ::|
EOF
    printf '%b\n' "$NC"
    msg "${BLUE}====================================================${NC}"
    msg "     Automated Installer & Manager for URAAM CLI"
    [[ -n "$CURRENT_MODEL" ]] && msg "Target: ${CYAN}${CURRENT_MODEL}${NC}"
    msg "Version: ${CURRENT_VERSION}"
    msg "${BLUE}====================================================${NC}"
    printf '\n'
}

# ------------------------------------------------------------------------------
# Platform and dependency handling
# ------------------------------------------------------------------------------

term_set_storage() {
    if is_termux; then
        IS_TERMUX=true
        PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

        if [[ ! -d "$HOME/storage" ]] &&
           have_command termux-setup-storage; then
            msg "${YELLOW}[!] Storage access may be needed for backups and shared files.${NC}"
            termux-setup-storage || true
        fi
    else
        IS_TERMUX=false
    fi
}

install_dependencies() {
    local missing=("$@")

    ((${#missing[@]} == 0)) && return 0

    msg "${YELLOW}[!] Missing tools: ${missing[*]}${NC}"

    if [[ "$IS_TERMUX" == true ]]; then
        have_command pkg || {
            msg "${RED}[X] Termux package manager (pkg) is unavailable.${NC}"
            return 1
        }
        pkg update -y || return 1
        pkg install -y "${missing[@]}"
    elif have_command apt-get; then
        run_as_root apt-get update || return 1
        run_as_root apt-get install -y "${missing[@]}"
    elif have_command pacman; then
        run_as_root pacman -Sy --needed --noconfirm "${missing[@]}"
    elif have_command dnf; then
        run_as_root dnf install -y "${missing[@]}"
    elif have_command zypper; then
        run_as_root zypper --non-interactive install "${missing[@]}"
    elif have_command apk; then
        run_as_root apk add "${missing[@]}"
    else
        msg "${RED}[X] No supported package manager found. Install manually: ${missing[*]}${NC}"
        return 1
    fi
}

check_dependencies() {
    term_set_storage

    # ADB is intentionally not a mandatory installer dependency.
    # URAAM's runtime can use ADB, ROOT or Shizuku depending on the device.
    local required=(curl jq)
    local missing=()
    local dep

    for dep in "${required[@]}"; do
        have_command "$dep" || missing+=("$dep")
    done

    if ((${#missing[@]} > 0)); then
        install_dependencies "${missing[@]}" || {
            msg "${RED}[X] Could not install required dependencies.${NC}"
            return 1
        }
    fi

    for dep in "${required[@]}"; do
        have_command "$dep" || {
            msg "${RED}[X] Required command still missing: ${dep}${NC}"
            return 1
        }
    done
}

# ------------------------------------------------------------------------------
# Standalone installation/update
# ------------------------------------------------------------------------------

standalone_uraam() {
    show_logo
    msg "${BLUE}--------------------------------------------${NC}"
    msg "   ${CYAN}=== URAAM | Standalone Installer ===${NC}"
    msg "${BLUE}--------------------------------------------${NC}"

    if ! confirm_yes "${YELLOW}[?] Download and install/update URAAM?"; then
        msg "${YELLOW}[!] Update canceled.${NC}"
        return 0
    fi

    local target_bin target_dir tmp_file
    if [[ "$IS_TERMUX" == true ]]; then
        target_bin="${PREFIX}/bin/uraam"
    elif [[ -n "${PREFIX:-}" && "${PREFIX}" == *"/com.termux"* ]]; then
        target_bin="${PREFIX}/bin/uraam"
    else
        target_bin="/usr/local/bin/uraam"
    fi
    target_dir="$(dirname "$target_bin")"

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/uraam.XXXXXX")" || {
        msg "${RED}[X] Could not create a temporary file.${NC}"
        return 1
    }

    msg "${CYAN}[*] Downloading URAAM from ${RAW_SCRIPT_URL}${NC}"
    if ! curl --fail --location --silent --show-error \
        --retry 2 --connect-timeout 15 "$RAW_SCRIPT_URL" -o "$tmp_file"; then
        rm -f -- "$tmp_file"
        msg "${RED}[X] Download failed. Check the repository URL and connection.${NC}"
        pause_menu
        return 1
    fi

    if [[ ! -s "$tmp_file" ]] || ! head -n 1 "$tmp_file" | grep -q '^#!/.*bash'; then
        rm -f -- "$tmp_file"
        msg "${RED}[X] Downloaded file does not look like a valid Bash script.${NC}"
        pause_menu
        return 1
    fi

    if ! bash -n "$tmp_file"; then
        rm -f -- "$tmp_file"
        msg "${RED}[X] Downloaded script has a Bash syntax error; installation canceled.${NC}"
        pause_menu
        return 1
    fi

    if ! run_as_root mkdir -p "$target_dir"; then
        rm -f -- "$tmp_file"
        return 1
    fi

    if ! run_as_root install -m 0755 "$tmp_file" "$target_bin"; then
        rm -f -- "$tmp_file"
        msg "${RED}[X] Could not install URAAM to ${target_bin}.${NC}"
        return 1
    fi
    rm -f -- "$tmp_file"

    msg "${GREEN}[✓] URAAM installed/updated successfully: ${target_bin}${NC}"

    if [[ "$IS_TERMUX" == true && ! -f "$HOME/.shortcuts/URAAM" ]]; then
        printf '\n'
        if confirm_yes "Create a Termux:Widget home-screen shortcut?"; then
            mkdir -p "$HOME/.shortcuts"
            cat >"$HOME/.shortcuts/URAAM" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec uraam "$@"
EOF
            chmod 0755 "$HOME/.shortcuts/URAAM"
            msg "${GREEN}[✓] Shortcut created in ~/.shortcuts/URAAM.${NC}"
        fi
    fi

    if confirm_yes "Restart URAAM now?"; then
        exec "$target_bin"
    fi
}

# ------------------------------------------------------------------------------
# Debian package update
# ------------------------------------------------------------------------------

get_latest_release() {
    curl --fail --location --silent --show-error \
        --retry 2 --connect-timeout 15 \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: URAAM-Installer" \
        "$API_URL"
}

version_is_current_or_newer() {
    local installed="$1"
    local latest="$2"

    [[ -z "$installed" ]] && return 1
    [[ "$installed" == "$latest" ]] && return 0

    if have_command dpkg; then
        dpkg --compare-versions "$installed" ge "$latest"
    else
        [[ "$installed" == "$latest" ]]
    fi
}

deb_uraam() {
    show_logo

    if ! is_debian_like; then
        msg "${YELLOW}[!] This system is not Debian-based; using standalone installation.${NC}"
        standalone_uraam
        return $?
    fi

    msg "${BLUE}--------------------------------------------${NC}"
    msg "       ${CYAN}=== URAAM | DEB Installer ===${NC}"
    msg "${BLUE}--------------------------------------------${NC}"
    msg "${CYAN}[*] Checking the latest GitHub release...${NC}"

    local release_json latest_tag remote_ver local_ver deb_url tmp_deb
    if ! release_json="$(get_latest_release)"; then
        msg "${RED}[X] Unable to contact the GitHub Releases API.${NC}"
        pause_menu
        return 1
    fi

    latest_tag="$(jq -r '.tag_name // empty' <<<"$release_json" 2>/dev/null)"
    if [[ -z "$latest_tag" ]]; then
        local error_message
        error_message="$(jq -r '.message // empty' <<<"$release_json" 2>/dev/null)"
        msg "${RED}[X] No release tag was returned by GitHub.${NC}"
        [[ -n "$error_message" ]] && msg "${RED}GitHub: ${error_message}${NC}"
        pause_menu
        return 1
    fi
    remote_ver="${latest_tag#v}"

    local_ver=""
    if have_command dpkg-query; then
        local_ver="$(dpkg-query -W -f='${Version}' uraam 2>/dev/null || true)"
        [[ -n "$local_ver" ]] ||
            local_ver="$(dpkg-query -W -f='${Version}' uraam-debian 2>/dev/null || true)"
    fi
    local_ver="${local_ver#v}"

    msg "${YELLOW}Installed version: ${local_ver:-not installed}${NC}"
    msg "${GREEN}Latest version:    ${remote_ver}${NC}"

    if version_is_current_or_newer "$local_ver" "$remote_ver"; then
        msg "${GREEN}[✓] URAAM is already up to date.${NC}"
        pause_menu
        return 0
    fi

    deb_url="$(jq -r '
        [.assets[]? |
         select(.name | test("uraam(-debian)?[^/]*\\.deb$"; "i")) |
         .browser_download_url][0] // empty
    ' <<<"$release_json" 2>/dev/null)"

    if [[ -z "$deb_url" ]]; then
        msg "${RED}[X] Release ${latest_tag} has no matching .deb asset.${NC}"
        pause_menu
        return 1
    fi

    if ! confirm_yes "${YELLOW}[?] Download and install ${latest_tag}?"; then
        msg "${YELLOW}[!] Update canceled.${NC}"
        pause_menu
        return 0
    fi

    tmp_deb="$(mktemp "${TMPDIR:-/tmp}/uraam-${remote_ver}.XXXXXX.deb")" || return 1
    msg "${CYAN}[*] Downloading Debian package...${NC}"

    if ! curl --fail --location --show-error --retry 2 \
        --connect-timeout 15 --progress-bar -o "$tmp_deb" "$deb_url"; then
        rm -f -- "$tmp_deb"
        msg "${RED}[X] Download failed.${NC}"
        pause_menu
        return 1
    fi

    if ! have_command dpkg-deb || ! dpkg-deb --info "$tmp_deb" >/dev/null 2>&1; then
        rm -f -- "$tmp_deb"
        msg "${RED}[X] The downloaded file is not a valid Debian package.${NC}"
        pause_menu
        return 1
    fi

    msg "${CYAN}[*] Installing package...${NC}"
    if run_as_root apt-get install -y "$tmp_deb"; then
        rm -f -- "$tmp_deb"
        msg "${GREEN}[✓] URAAM successfully updated to ${latest_tag}.${NC}"
        msg "${YELLOW}[!] Restart URAAM to apply the update.${NC}"
        pause_menu
        return 0
    fi

    rm -f -- "$tmp_deb"
    msg "${RED}[X] Package installation failed.${NC}"
    pause_menu
    return 1
}

# ------------------------------------------------------------------------------
# Uninstallation
# ------------------------------------------------------------------------------

uninstall_uraam() {
    show_logo
    if ! confirm_yes "${RED}[?] Are you sure you want to uninstall URAAM?"; then
        msg "${YELLOW}[*] Uninstallation aborted.${NC}"
        pause_menu
        return 0
    fi

    if [[ "$IS_TERMUX" == true ]]; then
        if have_command dpkg; then
            dpkg -r uraam-termux 2>/dev/null || true
        fi
        rm -f -- "${PREFIX}/bin/uraam"
    else
        if is_debian_like && is_installed_via_deb; then
            if have_command dpkg-query &&
               dpkg-query -W -f='${Status}' uraam 2>/dev/null |
                   grep -q 'install ok installed'; then
                run_as_root apt-get remove -y uraam || true
            elif dpkg-query -W -f='${Status}' uraam-debian 2>/dev/null |
                     grep -q 'install ok installed'; then
                run_as_root apt-get remove -y uraam-debian || true
            fi
        fi

        # Remove only the standalone executable in the standard local path.
        if [[ -e /usr/local/bin/uraam ]]; then
            run_as_root rm -f -- /usr/local/bin/uraam || return 1
        fi
    fi

    msg "${GREEN}[✓] URAAM executable/package has been uninstalled.${NC}"
    msg "${YELLOW}[!] User configuration, logs and backups were preserved.${NC}"
    pause_menu
}

# ------------------------------------------------------------------------------
# Main menu
# ------------------------------------------------------------------------------

show_menu() {
    local choice install_label

    while true; do
        show_logo

        install_label="1) Install / Update URAAM"
        if is_installed_via_deb; then
            install_label="1) Update / Reinstall URAAM (.deb)"
        elif have_command uraam; then
            install_label="1) Update / Reinstall URAAM"
        fi

        msg "${YELLOW}Please choose an option:${NC}"
        msg "  ${CYAN}${install_label}${NC}"
        msg "  ${CYAN}2) Uninstall URAAM${NC}"
        msg "  ${CYAN}0) Exit${NC}"
        msg "${BLUE}---------------------------------------${NC}"

        read -r -p "Enter choice [0-2]: " choice || choice="0"

        case "$choice" in
            1) deb_uraam ;;
            2) uninstall_uraam ;;
            0)
                [[ -t 1 ]] && clear 2>/dev/null || true
                msg "${GREEN}Goodbye!${NC}"
                return 0
                ;;
            *)
                msg "${RED}[!] Invalid choice.${NC}"
                sleep 1
                ;;
        esac
    done
}

main() {
    term_set_storage

    if ! check_dependencies; then
        msg "${RED}[X] Dependency check failed. Exiting.${NC}"
        return 1
    fi

    show_menu
}

main "$@"
