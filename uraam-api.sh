#!/usr/bin/env bash
# URAAM read-only JSON bridge.
# This adapter deliberately exposes no destructive operation.
set -o pipefail
umask 077

API_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
URAAM_SCRIPT="${URAAM_SCRIPT:-$API_DIR/uraam.sh}"

component_section_json() {
    local dump_raw="$1" package_id="$2" wanted="$3" component_lines
    if component_lines="$(awk -v wanted="$wanted" -v package="$package_id" '
        BEGIN {
            sections["Activities:"]=1
            sections["Services:"]=1
            sections["Receivers:"]=1
            sections["Providers:"]=1
        }
        {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line in sections) {
                in_section=(line == wanted)
                if (in_section) found=1
                next
            }
            if (!in_section) next
            split(line, fields, /[[:space:]]+/)
            candidate=fields[1]
            prefix=package "/"
            if (index(candidate, prefix) == 1) {
                class_name=substr(candidate, length(prefix)+1)
                if (class_name ~ /^\.?[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$/) print candidate
            }
        }
        END { if (!found) exit 2 }
    ' <<< "$dump_raw" 2>/dev/null)"; then
        printf '%s\n' "$component_lines" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique'
    else
        printf '%s\n' null
    fi
}

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
  uraam-api.sh package-info:<package.id>
  uraam-api.sh --help

Commands:
  device-info    Return the selected backend and device identity.
  list-packages  Return the installed package inventory for Android user 0.
  package-info   Return read-only APK path and version metadata for one package.

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
        package-info:*)
            PACKAGE_ID="${action#package-info:}"
            [[ "$PACKAGE_ID" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$ ]] || {
                json_error "Invalid Android package identifier." 2
                return $?
            }
            ;;
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
        package-info:*)
            local package_id paths_raw dump_raw version_name version_code line
            local activities_json services_json receivers_json providers_json
            local -a apk_paths=()
            package_id="${action#package-info:}"
            paths_raw="$(run_device_bounded pm path --user 0 "$package_id" 2>/dev/null)" || {
                json_error "Android could not resolve this package." 5
                return $?
            }
            while IFS= read -r line; do
                # Accept only Package Manager's documented package:/absolute/path
                # form. Reject raw paths, relative paths, whitespace/control
                # characters and dot-segment traversal before exposing a path.
                [[ "$line" == package:/* ]] || continue
                line="${line#package:}"
                [[ "$line" =~ ^(/[A-Za-z0-9._~+=,@%-]+)+$ ]] || continue
                [[ "$line" != *"/./"* && "$line" != *"/../"* && "$line" != */. && "$line" != */.. ]] || continue
                apk_paths+=("$line")
            done <<< "$paths_raw"
            (("${#apk_paths[@]}" > 0)) || {
                json_error "Package is not installed for Android user 0, or Android returned an invalid APK path." 5
                return $?
            }
            dump_raw="$(run_device_bounded dumpsys package "$package_id" 2>/dev/null || true)"
            version_name="$(sed -n 's/.*versionName=\([^[:space:]]*\).*/\1/p' <<< "$dump_raw" | head -n 1)"
            version_code="$(sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' <<< "$dump_raw" | head -n 1)"
            # Android's requested-permissions block is separate from the
            # install/runtime grant blocks. Report names only; never infer grants.
            requested_permissions="$(awk '
                /^[[:space:]]*requested permissions:[[:space:]]*$/ { in_section=1; found=1; next }
                in_section && /^[[:space:]]*$/ { exit }
                in_section {
                    value=$0
                    sub(/^[[:space:]]+/, "", value)
                    sub(/[[:space:]]+$/, "", value)
                    if (value ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_]+)+$/) print value
                }
                END { if (!found) exit 1 }
            ' <<< "$dump_raw" 2>/dev/null || true)"
            if grep -Eq '^[[:space:]]*requested permissions:[[:space:]]*$' <<< "$dump_raw"; then
                permissions_json="$(printf '%s\n' "$requested_permissions" | jq -Rsc 'split("\n") | map(select(length > 0))')"
            else
                permissions_json=null
            fi
            activities_json="$(component_section_json "$dump_raw" "$package_id" Activities:)"
            services_json="$(component_section_json "$dump_raw" "$package_id" Services:)"
            receivers_json="$(component_section_json "$dump_raw" "$package_id" Receivers:)"
            providers_json="$(component_section_json "$dump_raw" "$package_id" Providers:)"
            jq -n --arg package "$package_id" --arg backend "$EXEC_TYPE" \
                --arg version_name "$version_name" --arg version_code "$version_code" \
                --argjson requested_permissions "$permissions_json" \
                --argjson activities "$activities_json" --argjson services "$services_json" \
                --argjson receivers "$receivers_json" --argjson providers "$providers_json" \
                --args \
                '{status:"ok",package:$package,backend:$backend,paths:$ARGS.positional,
                  version_name:(if $version_name == "" then null else $version_name end),
                  version_code:(if $version_code == "" then null else $version_code end),
                  requested_permissions:$requested_permissions,
                  permissions_semantics:"requested_only_not_grant_status",
                  components:{activities:$activities,services:$services,receivers:$receivers,providers:$providers},
                  components_semantics:"entries_from_matching_dumpsys_sections_only",
                  metadata_source:"dumpsys package",read_only:true}' \
                "${apk_paths[@]}"
            ;;
        list-packages)
            local packages system_packages user_packages
            packages="$(device_package_list active 2>/dev/null)" || {
                json_error "Android returned no reliable installed-package inventory." 5
                return $?
            }
            # Classification is best-effort and read-only. Keep the inventory
            # available when an Android build does not support these filters.
            system_packages="$(device_package_list system 2>/dev/null || true)"
            user_packages="$(device_package_list user 2>/dev/null || true)"
            jq -n --arg backend "$EXEC_TYPE" --arg serial "$BACKEND_SERIAL" \
                --argjson packages "$(printf '%s\n' "$packages" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
                --argjson system_packages "$(printf '%s\n' "$system_packages" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
                --argjson user_packages "$(printf '%s\n' "$user_packages" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
                '($packages | map(. as $p | {key:$p,value:(if (($system_packages | index($p)) != null and ($user_packages | index($p)) == null) then "system" elif (($user_packages | index($p)) != null and ($system_packages | index($p)) == null) then "user" else "unknown" end)}) | from_entries) as $types |
                 {status:"ok",backend:$backend,serial:(if $serial == "" then null else $serial end),user:0,count:($packages|length),packages:$packages,package_types:$types,
                  classification_available:([$types[] | select(. == "unknown")] | length == 0),
                  system_count:([$types[] | select(. == "system")] | length),
                  user_count:([$types[] | select(. == "user")] | length),
                  unclassified_count:([$types[] | select(. == "unknown")] | length)}'
            ;;
    esac
}

main "$@"
