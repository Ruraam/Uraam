#!/usr/bin/env bash
# ==============================================================================
# Installer & Lifecycle Manager for URAAM
# Project : URAAM (Universal Ruvomain Android App-Manager)
# Author  : Ruvyrom & Community
# License : GPL-3.0
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Configuration & Endpoints
# ------------------------------------------------------------------------------
CURRENT_VERSION="5.0.0"
REPO_OWNER="Ruraam"
REPO_NAME="Uraam"
BRANCH="main"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/uraam.sh"

# ------------------------------------------------------------------------------
# UIStyles & TrueColor Palette
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    RED='\033[38;5;196m'
    GREEN='\033[38;5;46m'
    YELLOW='\033[38;5;220m'
    BLUE='\033[38;5;39m'
    PURPLE='\033[38;5;135m'
    CYAN='\033[38;5;51m'
    GRAY='\033[38;5;242m'
    WHITE='\033[38;5;231m'
    NC='\033[0m'
else
    BOLD='' DIM='' RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' GRAY='' WHITE='' NC=''
fi

IS_TERMUX=false
CURRENT_MODEL=""
SCRIPT_TMP=""

# ------------------------------------------------------------------------------
# Trap & Cleanups
# ------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    # Stop cursor hiding if interrupted
    printf '\033[?25h' 2>/dev/null || true
    if [[ -n "${SCRIPT_TMP:-}" && -e "$SCRIPT_TMP" ]]; then
        rm -f -- "$SCRIPT_TMP"
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# UI Primitives & Animations
# ------------------------------------------------------------------------------
msg() {
    printf '%b\n' "$*"
}

log_info() {
    printf "  ${BLUE}●${NC} %b\n" "$*"
}

log_success() {
    printf "  ${GREEN}✔${NC} %b\n" "$*"
}

log_warn() {
    printf "  ${YELLOW}▲${NC} %b\n" "$*"
}

log_error() {
    printf "  ${RED}✖${NC} %b\n" "$*"
}

log_step() {
    printf "  ${PURPLE}➜${NC} %b\n" "$*"
}

pause_menu() {
    local prompt="${1:-  ${GRAY}Press [ENTER] to return to menu...${NC}}"
    printf '\n'
    read -r -p "$(printf '%b' "$prompt")" _ || true
}

confirm_yes() {
    local prompt="$1"
    local answer=""
    printf "  ${YELLOW}?${NC} %b ${DIM}[y/N]${NC}: " "$prompt"
    read -r answer || true
    [[ "$answer" =~ ^[yY]([eE][sS])?$ ]]
}

run_with_spinner() {
    local msg="$1"
    shift
    local pid spinner i
    spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

    printf '\033[?25l' # Hide cursor
    "$@" >/dev/null 2>&1 &
    pid=$!

    i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}%s${NC} %b..." "${spinner[i]}" "$msg"
        i=$(( (i + 1) % 10 ))
        sleep 0.08
    done

    wait "$pid"
    local res=$?
    printf '\033[?25h' # Show cursor

    if [[ $res -eq 0 ]]; then
        printf "\r  ${GREEN}✔${NC} %b... ${GREEN}Done${NC}\n" "$msg"
        return 0
    else
        printf "\r  ${RED}✖${NC} %b... ${RED}Failed${NC}\n" "$msg"
        return $res
    fi
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
        log_error "Root privileges required (${DIM}sudo${NC} or ${DIM}su${NC} missing)."
        return 1
    fi
}

# ------------------------------------------------------------------------------
# System & Hardware Detection
# ------------------------------------------------------------------------------
is_termux() {
    [[ -d /data/data/com.termux ]] || [[ "${PREFIX:-}" == *"/com.termux"* ]]
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
        if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q 'install ok installed'; then
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

    CURRENT_MODEL="$(printf '%s ' "$vendor" "$product" "$(uname -s)" "$(uname -m)" | sed 's/[[:space:]]*$//')"
}

# ------------------------------------------------------------------------------
# Visual Banner
# ------------------------------------------------------------------------------
show_logo() {
    device_brand
    [[ -t 1 ]] && clear 2>/dev/null || true

    printf '%b' "$PURPLE"
    cat <<'EOF'
            _    _  _____   ___    ___   _   _
           |:|  |:||:::::\ /:::\  /:::\ |:\ /:|
           |:|\_|:||:|,|:||:|,|:||:|,|:||:|"|:|
            \:::::||:| |:\|:| |:||:| |:||:| |:|
EOF
    printf '%b' "$NC"
    msg "          ${BOLD}${WHITE}Universal Ruvomain Android App Manager${NC}"
    msg "          ${DIM}Installer & Maintenance Engine v${CURRENT_VERSION}${NC}"
    printf '\n'
    msg "  ╭─────────────────────────────────────────────────────╮"
    printf "  │  ${BLUE}%-11s${NC} : %-37s│\n" "Platform" "${CURRENT_MODEL:-Linux / Generic}"
    printf "  │  ${BLUE}%-11s${NC} : %-37s│\n" "Repository" "${REPO_OWNER}/${REPO_NAME}"
    printf "  │  ${BLUE}%-11s${NC} : %-37s              │\n" "Runtime" "$(have_command uraam && printf "${GREEN}Detected${NC}" || printf "${GRAY}Not detected${NC}")"
    msg "  ╰─────────────────────────────────────────────────────╯"
    printf '\n'
}

# ------------------------------------------------------------------------------
# Dependency Resolution
# ------------------------------------------------------------------------------
term_set_storage() {
    if is_termux; then
        IS_TERMUX=true
        PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

        if [[ ! -d "$HOME/storage" ]] && have_command termux-setup-storage; then
            log_warn "Android storage permission might be required for operations."
            termux-setup-storage || true
        fi
    else
        IS_TERMUX=false
    fi
}

install_dependencies() {
    local missing=("$@")
    ((${#missing[@]} == 0)) && return 0

    log_step "Installing core dependencies: ${BOLD}${missing[*]}${NC}"

    if [[ "$IS_TERMUX" == true ]]; then
        have_command pkg || {
            log_error "Termux package manager (${DIM}pkg${NC}) not reachable."
            return 1
        }
        pkg update -y && pkg install -y "${missing[@]}"
    elif have_command apt-get; then
        run_as_root apt-get update && run_as_root apt-get install -y "${missing[@]}"
    elif have_command pacman; then
        run_as_root pacman -Sy --needed --noconfirm "${missing[@]}"
    elif have_command dnf; then
        run_as_root dnf install -y "${missing[@]}"
    elif have_command zypper; then
        run_as_root zypper --non-interactive install "${missing[@]}"
    elif have_command apk; then
        run_as_root apk add "${missing[@]}"
    else
        log_error "No recognized package manager. Install manually: ${BOLD}${missing[*]}${NC}"
        return 1
    fi
}

check_dependencies() {
    term_set_storage
    local required=(curl jq)
    local missing=()
    local dep

    for dep in "${required[@]}"; do
        have_command "$dep" || missing+=("$dep")
    done

    if ((${#missing[@]} > 0)); then
        install_dependencies "${missing[@]}" || {
            log_error "Dependency resolution failed."
            return 1
        }
    fi
}

# ------------------------------------------------------------------------------
# Optional Linux desktop integration
# ------------------------------------------------------------------------------
gui_dependencies() {
    local packages=()
    [[ "$IS_TERMUX" == true ]] && { log_warn "URAAM Desktop is not available inside Termux."; return 1; }
    if have_command apt-get; then packages=(python3 python3-gi gir1.2-gtk-4.0)
    elif have_command pacman; then packages=(python python-gobject gtk4)
    elif have_command dnf; then packages=(python3 python3-gobject gtk4)
    elif have_command zypper; then packages=(python3 python3-gobject gtk4)
    elif have_command apk; then packages=(python3 py3-gobject3 gtk4)
    else log_error "Install Python 3, PyGObject and GTK4 manually."; return 1
    fi
    install_dependencies "${packages[@]}"
}

register_deb_gui() {
    [[ -r /usr/share/uraam/uraam.desktop ]] || {
        log_error "The packaged desktop entry is missing."
        return 1
    }
    run_as_root install -D -m 0644 /usr/share/uraam/uraam.desktop /usr/share/applications/uraam.desktop || return 1
    have_command update-desktop-database && run_as_root update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    have_command gtk-update-icon-cache && run_as_root gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    log_success "URAAM Desktop is registered in the applications menu."
}

install_standalone_gui() {
    local tmp_dir base_url
    [[ "$IS_TERMUX" == true ]] && return 1
    gui_dependencies || return 1
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/uraam-gui.XXXXXX")" || return 1
    base_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"
    log_info "Downloading URAAM Desktop components..."
    if ! curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 "$base_url/uraam-api.sh" -o "$tmp_dir/uraam-api.sh" ||
       ! curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 "$base_url/uraam-gui" -o "$tmp_dir/uraam-gui" ||
       ! curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 "$base_url/GUI/main.py" -o "$tmp_dir/main.py" ||
       ! curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 "$base_url/assets/uraam_logo.svg" -o "$tmp_dir/uraam.svg"; then
        rm -rf -- "$tmp_dir"; log_error "Unable to download all desktop components."; return 1
    fi
    if ! bash -n "$tmp_dir/uraam-api.sh" "$tmp_dir/uraam-gui" || ! python3 -m py_compile "$tmp_dir/main.py" || ! grep -q '<svg' "$tmp_dir/uraam.svg"; then
        rm -rf -- "$tmp_dir"; log_error "Desktop component validation failed."; return 1
    fi
    mkdir -p "$tmp_dir/GUI" || { rm -rf -- "$tmp_dir"; return 1; }
    mv "$tmp_dir/main.py" "$tmp_dir/GUI/main.py"
    cat > "$tmp_dir/uraam.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=URAAM Desktop
GenericName=Android App Manager
Comment=Manage Android applications with URAAM
Exec=uraam-gui
TryExec=uraam-gui
Icon=uraam
Terminal=false
Categories=Utility;System;
StartupWMClass=org.ruraam.uraam
EOF
    if ! run_as_root install -d /usr/local/share/uraam/GUI /usr/local/bin /usr/local/share/applications /usr/local/share/icons/hicolor/scalable/apps; then
        rm -rf -- "$tmp_dir"; return 1
    fi
    if ! run_as_root install -m 0644 "$tmp_dir/uraam-api.sh" /usr/local/share/uraam/uraam-api.sh ||
       ! run_as_root install -m 0644 "$tmp_dir/GUI/main.py" /usr/local/share/uraam/GUI/main.py ||
       ! run_as_root install -m 0644 "$tmp_dir/uraam.svg" /usr/local/share/icons/hicolor/scalable/apps/uraam.svg ||
       ! run_as_root install -m 0644 "$tmp_dir/uraam.desktop" /usr/local/share/applications/uraam.desktop; then
        rm -rf -- "$tmp_dir"; return 1
    fi
    cat > "$tmp_dir/uraam-gui" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec python3 /usr/local/share/uraam/GUI/main.py "$@"
EOF
    if ! run_as_root install -m 0755 "$tmp_dir/uraam-gui" /usr/local/bin/uraam-gui; then rm -rf -- "$tmp_dir"; return 1; fi
    run_as_root chmod 0755 /usr/local/share/uraam/uraam-api.sh || true
    have_command update-desktop-database && run_as_root update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
    have_command gtk-update-icon-cache && run_as_root gtk-update-icon-cache -q -t -f /usr/local/share/icons/hicolor >/dev/null 2>&1 || true
    rm -rf -- "$tmp_dir"
    log_success "URAAM Desktop installed. Find it in the applications menu or run uraam-gui."
}

# ------------------------------------------------------------------------------
# Standalone Mode
# ------------------------------------------------------------------------------
standalone_uraam() {
    show_logo
    log_step "${BOLD}URAAM Standalone Engine Installation${NC}"
    printf '\n'

    if ! confirm_yes "Download and deploy latest URAAM binary?"; then
        log_warn "Installation cancelled by user."
        pause_menu
        return 0
    fi

    local target_bin target_dir tmp_file
    if [[ "$IS_TERMUX" == true || ( -n "${PREFIX:-}" && "${PREFIX}" == *"/com.termux"* ) ]]; then
        target_bin="${PREFIX}/bin/uraam"
    else
        target_bin="/usr/local/bin/uraam"
    fi
    target_dir="$(dirname "$target_bin")"

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/uraam.XXXXXX")" || {
        log_error "Failed to allocate temporary memory pointer."
        return 1
    }

    printf '\n'
    log_info "Fetching binary from ${DIM}${RAW_SCRIPT_URL}${NC}"
    if ! curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 "$RAW_SCRIPT_URL" -o "$tmp_file"; then
        rm -f -- "$tmp_file"
        log_error "Network error during script extraction."
        pause_menu
        return 1
    fi

    if [[ ! -s "$tmp_file" ]] || ! head -n 1 "$tmp_file" | grep -q '^#!/.*bash'; then
        rm -f -- "$tmp_file"
        log_error "Integrity check failed: Not an executable bash binary."
        pause_menu
        return 1
    fi

    if ! bash -n "$tmp_file"; then
        rm -f -- "$tmp_file"
        log_error "Integrity check failed: Syntax tree malformed."
        pause_menu
        return 1
    fi

    if ! run_as_root mkdir -p "$target_dir" || ! run_as_root install -m 0755 "$tmp_file" "$target_bin"; then
        rm -f -- "$tmp_file"
        log_error "Failed to link binary into [${target_bin}]."
        pause_menu
        return 1
    fi
    rm -f -- "$tmp_file"

    log_success "URAAM successfully installed to ${BOLD}${target_bin}${NC}"
    if [[ "$IS_TERMUX" != true ]] && confirm_yes "Install optional URAAM Desktop (GTK4 GUI)?"; then
        install_standalone_gui || log_warn "URAAM CLI remains installed; desktop integration was not completed."
    fi

    if [[ "$IS_TERMUX" == true && ! -f "$HOME/.shortcuts/URAAM" ]]; then
        printf '\n'
        if confirm_yes "Create Home-Screen Quick-Launch (Termux:Widget)?"; then
            mkdir -p "$HOME/.shortcuts"
            cat > "$HOME/.shortcuts/URAAM" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec uraam "$@"
EOF
            chmod 0755 "$HOME/.shortcuts/URAAM"
            log_success "Shortcut linked: ~/.shortcuts/URAAM"
        fi
    fi

    printf '\n'
    if confirm_yes "Execute URAAM immediately?"; then
        exec "$target_bin"
    fi
}

# ------------------------------------------------------------------------------
# Debian Package Mode
# ------------------------------------------------------------------------------
deb_uraam() {
    show_logo

    if ! is_debian_like; then
        log_warn "Target system is non-Debian based. Routing to standalone installer..."
        sleep 1.2
        standalone_uraam
        return $?
    fi

    log_step "${BOLD}URAAM Debian Architecture Maintenance${NC}"
    printf '\n'

    local release_json latest_tag remote_ver local_ver deb_url tmp_deb

    log_info "Connecting to GitHub Releases API..."
    if ! release_json="$(curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 \
        -H "Accept: application/vnd.github+json" -H "User-Agent: URAAM-Installer" "$API_URL")"; then
        log_error "API endpoint unreachable."
        pause_menu
        return 1
    fi

    latest_tag="$(jq -r '.tag_name // empty' <<< "$release_json" 2>/dev/null)"
    if [[ -z "$latest_tag" ]]; then
        log_error "API rate-limit exceeded or invalid release schema."
        pause_menu
        return 1
    fi
    remote_ver="${latest_tag#v}"

    local_ver=""
    if have_command dpkg-query; then
        local_ver="$(dpkg-query -W -f='${Version}' uraam 2>/dev/null || true)"
        [[ -n "$local_ver" ]] || local_ver="$(dpkg-query -W -f='${Version}' uraam-debian 2>/dev/null || true)"
    fi
    local_ver="${local_ver#v}"

    msg "  ╭────────────────────────────────────────╮"
    printf "  │  Installed version : %-18s│\n" "${local_ver:-None}"
    printf "  │  Latest version    : %-18s│\n" "${remote_ver}"
    msg "  ╰────────────────────────────────────────╯"
    printf '\n'

    if [[ -n "$local_ver" ]] && dpkg --compare-versions "$local_ver" ge "$remote_ver" 2>/dev/null; then
        log_success "Current system runtime is strictly up-to-date."
        if confirm_yes "Install dependencies for optional URAAM Desktop (GTK4 GUI)?"; then
            if [[ -x /usr/bin/uraam-gui && -r /usr/share/uraam/GUI/main.py ]]; then
                gui_dependencies && register_deb_gui && log_success "URAAM Desktop dependencies are ready."
            else
                log_warn "This package does not include URAAM Desktop. Update to a release with GUI integration first."
            fi
        fi
        pause_menu
        return 0
    fi

    deb_url="$(jq -r '
        [.assets[]? |
        select(.name | test("uraam(-debian)?[^/]*\\.deb$"; "i")) |
        .browser_download_url][0] // empty
    ' <<< "$release_json" 2>/dev/null)"

    if [[ -z "$deb_url" ]]; then
        log_error "Missing compiled Debian (.deb) asset for build ${latest_tag}."
        pause_menu
        return 1
    fi

    if ! confirm_yes "Download and apply update package (${BOLD}${latest_tag}${NC})?"; then
        log_warn "Operation interrupted."
        pause_menu
        return 0
    fi

    tmp_deb="$(mktemp "${TMPDIR:-/tmp}/uraam-${remote_ver}.XXXXXX.deb")" || return 1
    printf '\n'
    log_info "Downloading package payload..."

    if ! curl --fail --location --show-error --retry 2 --connect-timeout 15 --progress-bar -o "$tmp_deb" "$deb_url"; then
        rm -f -- "$tmp_deb"
        log_error "Download transmission lost."
        pause_menu
        return 1
    fi

    if ! have_command dpkg-deb || ! dpkg-deb --info "$tmp_deb" >/dev/null 2>&1; then
        rm -f -- "$tmp_deb"
        log_error "Corrupted package control headers."
        pause_menu
        return 1
    fi

    log_step "Injecting into APT package database..."
    if run_as_root apt-get install -y "$tmp_deb"; then
        rm -f -- "$tmp_deb"
        log_success "URAAM successfully updated to ${BOLD}${latest_tag}${NC}."
        if confirm_yes "Install optional URAAM Desktop (GTK4 GUI)?"; then
            if gui_dependencies; then register_deb_gui || log_warn "GUI dependencies are installed, but desktop registration failed."; else log_warn "The Bash version is installed, but GUI dependencies could not be installed."; fi
        fi
        pause_menu
        return 0
    fi

    rm -f -- "$tmp_deb"
    log_error "dpkg engine installation failure."
    pause_menu
    return 1
}

# ------------------------------------------------------------------------------
# Uninstallation
# ------------------------------------------------------------------------------
uninstall_uraam() {
    show_logo
    log_step "${BOLD}${RED}Dangerous Action: Complete Uninstall${NC}"
    printf '\n'

    if ! confirm_yes "${RED}Do you strictly confirm removing URAAM binaries?${NC}"; then
        log_info "Operation aborted."
        pause_menu
        return 0
    fi

    printf '\n'
    if [[ "$IS_TERMUX" == true ]]; then
        have_command dpkg && dpkg -r uraam-termux 2>/dev/null || true
        rm -f -- "${PREFIX}/bin/uraam"
        rm -f -- "$HOME/.shortcuts/URAAM"
    else
        if is_debian_like && is_installed_via_deb; then
            run_as_root apt-get remove -y uraam uraam-debian 2>/dev/null || true
        fi
        if [[ -e /usr/local/bin/uraam ]]; then
            run_as_root rm -f -- /usr/local/bin/uraam || return 1
        fi
        run_as_root rm -f -- /usr/local/bin/uraam-gui /usr/local/share/applications/uraam.desktop /usr/local/share/icons/hicolor/scalable/apps/uraam.svg || return 1
        run_as_root rm -rf -- /usr/local/share/uraam || return 1
        have_command update-desktop-database && run_as_root update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
        have_command gtk-update-icon-cache && run_as_root gtk-update-icon-cache -q -t -f /usr/local/share/icons/hicolor >/dev/null 2>&1 || true
    fi

    log_success "URAAM executable system hooks successfully removed."
    log_info "Local configurations and backup archives have been intentionally preserved."
    pause_menu
}

# ------------------------------------------------------------------------------
# Core Menu Loop
# ------------------------------------------------------------------------------
show_menu() {
    local choice install_label

    while true; do
        show_logo

        install_label="Install / Update Engine"
        if is_installed_via_deb; then
            install_label="Update / Reinstall System Package (.deb)"
        elif have_command uraam; then
            install_label="Synchronize / Update Executable"
        fi

        msg "  ${BOLD}Select an action:${NC}"
        printf '\n'
        printf "    ${CYAN}[1]${NC} %b\n" "$install_label"
        printf "    ${CYAN}[2]${NC} %b\n" "Uninstall URAAM"
        printf "    ${GRAY}[0] Exit Session${NC}\n"
        printf '\n'

        read -r -p "  Enter index [0-2]: " choice || choice="0"

        case "$choice" in
            1) deb_uraam ;;
            2) uninstall_uraam ;;
            0)
                [[ -t 1 ]] && clear 2>/dev/null || true
                msg "${GREEN}Process closed. Have a nice debloating!${NC}"
                return 0
                ;;
            *)
                log_error "Invalid selection index."
                sleep 0.8
                ;;
        esac
    done
}

main() {
    term_set_storage
    check_dependencies
    show_menu
}

main "$@"
