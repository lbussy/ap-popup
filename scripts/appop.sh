#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

##
# @file appop.sh
# @brief Main script to manage WiFi and Access Point modes using NetworkManager.
#
# This script automatically toggles between a known WiFi network and an AP on a
# Raspberry Pi or similar system. If no known networks are detected, it starts
# an AP (Access Point). If known networks appear, it switches back to WiFi.
#
# Configuration variables such as SSID, password, IP range, and gateway are read
# from `/etc/ap_popup.conf`. Ensure that NetworkManager and nmcli are installed,
# and that hostapd or other conflicting services are disabled.

# *************************************
# * WiFi and Access Point Setup Script
# * Author: Lee Bussy
# * Date: December 13, 2024
# *************************************

#!/bin/bash

# Global configuration variables (overridden by /etc/ap_popup.conf)
# @brief WiFi interface used by the Access Point.
WIFI_INTERFACE="${WIFI_INTERFACE:-wlan0}"

# @brief Access Point profile name in NetworkManager.
AP_PROFILE_NAME="${AP_PROFILE_NAME:-AP_Pop-Up}"

# @brief Access Point SSID.
AP_SSID="${AP_SSID:-AP_Pop-Up}"

# @brief Access Point password.
AP_PASSWORD="${AP_PASSWORD:-1234567890}"

# @brief Access Point CIDR address (e.g., 192.168.50.5/24).
AP_CIDR="${AP_CIDR:-192.168.50.5/24}"

# @brief Access Point gateway IP.
AP_GATEWAY="${AP_GATEWAY:-192.168.50.254}"

# @brief If 'y', enable WiFi if currently disabled.
ENABLE_WIFI="${ENABLE_WIFI:-y}"

##
# @brief Print a timestamped log message.
#
# @param[in] level Log level (INFO, WARNING, ERROR).
# @param[in] message The message to log.
log() {
    local level="$1"
    local message="$2"
    printf "[%s] %s: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message"
}

##
# @brief Load configuration from /etc/ap_popup.conf if it exists.
#
# This allows overriding the default configuration variables defined above.
load_config() {
    if [ -f /etc/ap_popup.conf ]; then
        # shellcheck disable=SC1091
        source /etc/ap_popup.conf
    fi
}

##
# @brief Load saved WiFi and AP profiles from NetworkManager.
#
# Populates GLOBAL_SAVED_NETWORK_PROFILES and GLOBAL_SAVED_AP_PROFILES by examining
# existing connections of type 802-11-wireless and checking their modes (ap or infrastructure).
load_saved_profiles() {
    GLOBAL_SAVED_NETWORK_PROFILES=()
    GLOBAL_SAVED_AP_PROFILES=()

    while IFS=: read -r _ name type; do
        if [ "$type" = "802-11-wireless" ]; then
            local mode
            mode=$(nmcli -t -f 802-11-wireless.mode connection show "$name" | tr -d '[:space:]')
            if [ "$mode" = "ap" ]; then
                GLOBAL_SAVED_AP_PROFILES+=("$name")
            elif [ "$mode" = "infrastructure" ]; then
                GLOBAL_SAVED_NETWORK_PROFILES+=("$name")
            fi
        fi
    done < <(nmcli -t -f AUTOCONNECT-PRIORITY,NAME,TYPE connection | sort -nr)
}

##
# @brief Get the current active WiFi connection.
#
# Sets GLOBAL_ACTIVE_CONNECTION to the name of the active connection on $WIFI_INTERFACE if any.
get_active_wifi_connection() {
    local active_name
    active_name=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$WIFI_INTERFACE" '$2 == dev {print $1}')
    GLOBAL_ACTIVE_CONNECTION="$active_name"
}

##
# @brief Check if the current active connection is an AP.
#
# Sets GLOBAL_IS_ACTIVE_AP to 'y' if AP mode, 'n' otherwise.
check_if_ap_is_active() {
    local mode=""
    if [ -n "$GLOBAL_ACTIVE_CONNECTION" ]; then
        mode=$(nmcli -t -f 802-11-wireless.mode connection show "$GLOBAL_ACTIVE_CONNECTION" | tr -d '[:space:]')
    fi
    GLOBAL_IS_ACTIVE_AP="n"
    [ "$mode" = "ap" ] && GLOBAL_IS_ACTIVE_AP="y"
}

##
# @brief Scan for nearby WiFi SSIDs using nmcli and identify known networks.
#
# Populates DETECTED_SSIDS with profiles of known networks that match scanned SSIDs.
scan_for_nearby_ssids() {
    nmcli device wifi rescan 2>/dev/null || log "WARNING" "Failed to initiate WiFi scan."
    sleep 2

    local nmclilines
    nmclilines=$(nmcli -t -f SSID device wifi list || true)

    if [ -z "$nmclilines" ]; then
        log "INFO" "No SSIDs found during scan."
        DETECTED_SSIDS=("NoSSid")
        return
    fi

    readarray -t ssidlst <<< "$nmclilines"

    log "INFO" "Nearby SSIDs: ${ssidlst[*]}"

    DETECTED_SSIDS=()
    for profile in "${GLOBAL_SAVED_NETWORK_PROFILES[@]}"; do
        local saved_ssid
        saved_ssid=$(nmcli -t -f 802-11-wireless.ssid connection show "$profile" | tr -d '[:space:]')
        for ssid in "${ssidlst[@]}"; do
            if [ -n "$ssid" ] && [ "$ssid" = "$saved_ssid" ]; then
                DETECTED_SSIDS+=("$profile")
                break
            fi
        done
    done

    [ "${#DETECTED_SSIDS[@]}" -eq 0 ] && DETECTED_SSIDS=("NoSSid")
}

##
# @brief Enable WiFi if it is disabled and ENABLE_WIFI is 'y'.
ensure_wifi_is_enabled() {
    local wifi_status
    wifi_status=$(nmcli -t -f WIFI radio)
    if [ "$wifi_status" = "disabled" ] && [ "$ENABLE_WIFI" = "y" ]; then
        log "INFO" "WiFi is disabled. Enabling WiFi..."
        if ! nmcli radio wifi on; then
            log "ERROR" "Failed to enable WiFi. Exiting."
            exit 1
        fi
        sleep 5
    fi
}

##
# @brief Create a new AP profile using nmcli if it does not already exist.
#
# Sets up an AP with the configured SSID, password, IP range, and gateway.
create_ap_profile() {
    nmcli device wifi hotspot \
        ifname "$WIFI_INTERFACE" \
        con-name "$AP_PROFILE_NAME" \
        ssid "$AP_SSID" \
        band bg \
        channel 6 \
        password "$AP_PASSWORD"

    nmcli connection modify "$AP_PROFILE_NAME" \
        ipv4.method shared \
        ipv4.addr "$AP_CIDR" \
        ipv4.gateway "$AP_GATEWAY" \
        wifi.powersave disable

    GLOBAL_SAVED_AP_PROFILES+=("$AP_PROFILE_NAME")
    nmcli connection reload
}

##
# @brief Activate the Access Point profile. Creates it if missing.
#
# Tries to bring up the AP. If it fails, resets the profile and tries again.
activate_access_point() {
    # Check if AP profile is known, if not create it
    local found_ap="n"
    for ap_profile in "${GLOBAL_SAVED_AP_PROFILES[@]}"; do
        if [ "$ap_profile" = "$AP_PROFILE_NAME" ]; then
            found_ap="y"
            break
        fi
    done
    if [ "$found_ap" = "n" ]; then
        create_ap_profile
    fi

    if ! nmcli connection up "$AP_PROFILE_NAME" 2>/dev/null; then
        log "ERROR" "Failed to activate AP. Resetting profile..."
        nmcli connection delete "$AP_PROFILE_NAME" || true
        create_ap_profile
        nmcli connection up "$AP_PROFILE_NAME"
    fi

    sleep 3
    get_active_wifi_connection
    check_if_ap_is_active
    if [ "$GLOBAL_IS_ACTIVE_AP" = "y" ]; then
        local ap_ip
        ap_ip=$(nmcli -t -f IP4.ADDRESS connection show "$AP_PROFILE_NAME" | cut -d'/' -f1 || true)
        log "INFO" "Access Point $AP_PROFILE_NAME activated at $ap_ip."
    else
        log "ERROR" "Failed to activate Access Point."
    fi
}

##
# @brief Connect to a known WiFi network if available; otherwise, start the AP.
#
# If AP is active, it first brings it down, then tries known networks. If none works, starts AP.
connect_to_network_or_ap() {
    check_if_ap_is_active
    if [ "$GLOBAL_IS_ACTIVE_AP" = "y" ]; then
        nmcli connection down "$GLOBAL_ACTIVE_CONNECTION" || log "WARNING" "Failed to bring down AP connection."
    fi

    for profile in "${DETECTED_SSIDS[@]}"; do
        if nmcli connection up "$profile" 2>/dev/null; then
            log "INFO" "Connected to network $profile."
            get_active_wifi_connection
            return
        fi
    done

    log "WARNING" "No network available. Starting Access Point."
    activate_access_point
}

##
# @brief Display script usage information.
display_help() {
    local script_name
    script_name=$(basename "$0")
    cat << EOF
Usage: sudo $script_name [options]

Default Behavior:
  - Attempts to connect to a known WiFi network.
  - If none found, starts an AP.

Options:
  -a | --start-ap  Force activation of the Access Point.
  -h | --help      Display this help message.

This script manages WiFi connections using NetworkManager. When no known networks
are available, it creates an AP for local access.
EOF
}

##
# @brief Process command-line options.
#
# Supported:
# -h | --help: Show help and exit.
# -a | --start-ap: Force AP activation and exit.
#
# @param[in] $@ Command-line arguments.
process_command_line_options() {
    if [ $# -eq 0 ]; then
        log "INFO" "No options provided. Proceeding with default behavior."
        return
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                display_help
                exit 0
                ;;
            -a|--start-ap)
                log "INFO" "Forcing Access Point activation."
                activate_access_point
                exit 0
                ;;
            -*)
                log "ERROR" "Invalid option '$1'. Use -h for usage information."
                exit 1
                ;;
            *)
                log "ERROR" "Unrecognized argument '$1'. Use -h for help."
                exit 1
                ;;
        esac
        shift
    done
}

##
# @brief Handle the currently active WiFi connection state.
#
# If AP is active and known WiFi is detected, switch to WiFi. Otherwise, if no SSID detected
# or no active connection, start the AP.
handle_active_connection() {
    log "INFO" "Checking the current active WiFi connection..."
    if [ -n "$GLOBAL_ACTIVE_CONNECTION" ]; then
        check_if_ap_is_active
        if [ "$GLOBAL_IS_ACTIVE_AP" = "y" ]; then
            log "INFO" "Active connection $GLOBAL_ACTIVE_CONNECTION is an AP."
            if [ "${#GLOBAL_SAVED_NETWORK_PROFILES[@]}" -gt 0 ]; then
                scan_for_nearby_ssids
                if [ "${DETECTED_SSIDS[0]}" != "NoSSid" ]; then
                    log "INFO" "Known WiFi SSID detected. Switching to network."
                    connect_to_network_or_ap
                    return
                fi
            fi
        else
            log "INFO" "Active connection $GLOBAL_ACTIVE_CONNECTION is a network."
        fi
    fi

    # If no active connection or no known SSIDs, start AP
    if [ "${DETECTED_SSIDS[0]}" = "NoSSid" ] || [ -z "$GLOBAL_ACTIVE_CONNECTION" ]; then
        log "WARNING" "No active connection or known SSIDs detected. Activating AP."
        activate_access_point
    fi
}

##
# @brief Check if systemd is present.
#
# Exits if not running on a systemd-based system.
check_systemd() {
    if [ ! -d /run/systemd/system ]; then
        log "ERROR" "This script requires a systemd-based system."
        exit 1
    fi
}

##
# @brief Check for required commands (nmcli, iw).
#
# Exits if any required command is missing.
check_dependencies() {
    for cmd in nmcli iw; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "ERROR" "Command '$cmd' is required but not found. Install it and try again."
            log "INFO" "e.g., on Debian: sudo apt install network-manager wireless-tools"
            exit 1
        fi
    done
}

##
# @brief Main entry point of the script.
#
# Loads config, checks prerequisites, ensures WiFi is on, processes CLI options,
# loads profiles, checks active connections, and toggles between WiFi and AP as needed.
#
# @param[in] $@ Command-line arguments.
main() {
    echo "Test Startup."    # DEBUG
    echo "Test End."        # DEBUG
    return 0                # DEBUG

    log "INFO" "Starting WiFi and Access Point Setup Script..."

    load_config
    check_systemd
    check_dependencies

    # Validate critical variables
    if [ -z "${WIFI_INTERFACE:-}" ] || [ -z "${AP_SSID:-}" ] || [ -z "${AP_PROFILE_NAME:-}" ]; then
        log "ERROR" "Critical variables (WIFI_INTERFACE, AP_SSID, AP_PROFILE_NAME) are not set. Exiting."
        exit 1
    fi

    if ! systemctl is-active --quiet NetworkManager.service; then
        log "ERROR" "NetworkManager is not running. Exiting."
        exit 1
    fi

    ensure_wifi_is_enabled
    process_command_line_options "$@"
    load_saved_profiles

    get_active_wifi_connection
    handle_active_connection

    log "INFO" "Current WiFi profile: $GLOBAL_ACTIVE_CONNECTION"
    log "INFO" "Is this a local AP? $GLOBAL_IS_ACTIVE_AP"
    log "INFO" "Script execution complete."
}

main "$@"
