#!/usr/bin/env bash
# URAAM read-only JSON bridge.
# This adapter deliberately exposes no destructive operation.
set -o pipefail
umask 077

API_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
URAAM_SCRIPT="${URAAM_SCRIPT:-$API_DIR/uraam.sh}"

json_error() {
    local message="$1" code="${2:-1}"
    jq -n --arg error "$message" '{status:"error",error:$error}'
    return "$code"
}

usage() {
    cat <<'EOF'
URAAM JSON API (read-only)

Usage:
  uraam-api.sh device-info
  uraam-api.sh list-packages
  uraam-api.sh --help

Commands:
  device-info    Return the selected backend and device identity.
  list-packages  Return the installed package inventory for Android user 0.

This initial API intentionally does not expose debloat, install, restore, or
other state-changing operations. Those require a separately reviewed API.
EOF
}

main() {
    local action="${1:-}"
    if (($# != 1)); then
        json_error "Expected exactly one API command. Use --help for usage." 2
        return $?
    fi
    case "$action" in
        -h|--help|help) usage; return 0 ;;
        device-info|list-packages) ;;
        *) json_error "Unsupported command. Use --help." 2; return $? ;;
    esac

    [[ -r "$URAAM_SCRIPT" ]] || {
        json_error "URAAM Bash engine not found: $URAAM_SCRIPT" 3
        return $?
    }
    command -v jq >/dev/null 2>&1 || {
        printf '%s\n' '{"status":"error","error":"jq is required"}'
        return 127
    }

    # Load the existing engine's functions without starting its interactive
    # dashboard. The engine remains the sole owner of device command logic.
    export URAAM_TESTING=1
    # shellcheck source=uraam.sh
    source "$URAAM_SCRIPT" || {
        json_error "Could not load the URAAM Bash engine." 3
        return $?
    }

    # Detection is read-only. Suppress the terminal-oriented status messages;
    # this process reserves stdout exclusively for its JSON response.
    detect_backend_status >/dev/null 2>&1 || true
    if [[ -z "$EXEC_TYPE" ]] || ! backend_is_available; then
        if [[ "$action" == device-info ]]; then
            jq -n --arg version "$URAAM_VERSION" \
                '{status:"disconnected",version:$version,backend:null,serial:null,model:null,oem:"unknown",rom:null}'
            return 0
        fi
        json_error "No active Android device backend is available." 4
        return $?
    fi

    case "$action" in
        device-info)
            device_brand
            local rom_info rom rom_version oem
            rom_info="$(device_rom_info)"
            rom="${rom_info%%|*}"
            rom_version="${rom_info#*|}"
            oem="$(device_oem_family)"
            jq -n \
                --arg version "$URAAM_VERSION" \
                --arg backend "$EXEC_TYPE" \
                --arg serial "$BACKEND_SERIAL" \
                --arg model "$CURRENT_MODEL" \
                --arg oem "$oem" \
                --arg rom "$rom" \
                --arg rom_version "$rom_version" \
                '{status:"connected",version:$version,backend:$backend,serial:(if $serial == "" then null else $serial end),model:$model,oem:$oem,rom:{name:$rom,version:$rom_version}}'
            ;;
        list-packages)
            local packages
            packages="$(device_package_list active 2>/dev/null)" || {
                json_error "Android returned no reliable installed-package inventory." 5
                return $?
            }
            jq -n --arg backend "$EXEC_TYPE" --arg serial "$BACKEND_SERIAL" \
                --argjson packages "$(printf '%s\n' "$packages" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
                '{status:"ok",backend:$backend,serial:(if $serial == "" then null else $serial end),user:0,count:($packages|length),packages:$packages}'
            ;;
    esac
}

main "$@"
