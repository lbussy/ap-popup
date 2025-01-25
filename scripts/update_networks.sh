#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

declare THIS_SCRIPT="${BASH_SOURCE[0]}"
if [[ -z "$THIS_SCRIPT" || "$THIS_SCRIPT" == "bash" ]]; then
    THIS_SCRIPT="${FALLBACK_SCRIPT_NAME:-template.sh}"
fi

WIFI_INTERFACE="wlan1"      # WiFi interface used by the Access Point
AP_PROFILE_NAME="AP_Pop-Up" # Access Point profile name
AP_SSID="AP_Pop-Up"         # Access Point SSID
AP_PASSWORD="1234567890"    # Access Point password
AP_IP="192.168.50.5/24"     # Access Point CIDR
AP_GW="192.168.50.254"      # Access Point Gateway
ENABLE_WIFI="y"             # Enable WiFi automatically if disabled

debug_start() {
    local debug=""
    local args=()  # Array to hold non-debug arguments

    # Look for the "debug" flag in the provided arguments
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            break  # Exit the loop as soon as we find "debug"
        fi
    done

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-main}"
    local caller_name="${FUNCNAME[2]:-main}"
    local caller_line=${BASH_LINENO[1]:-0}

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG in %s] Starting function %s() called by %s():%d.\n" \
        "$THIS_SCRIPT" "$func_name" "$caller_name" "$caller_line" >&2
    fi

    # Return the debug flag if present, or an empty string if not
    printf "%s\n" "${debug:-}"
    return 0
}

debug_filter() {
    local args=()  # Array to hold non-debug arguments

    # Iterate over each argument and exclude "debug"
    for arg in "$@"; do
        if [[ "$arg" != "debug" ]]; then
            args+=("$arg")
        fi
    done

    # Print the filtered arguments, safely quoting them for use in a command
    printf "%q " "${args[@]}"
}

debug_print() {
    local debug=""
    local args=()  # Array to hold non-debug arguments

    # Loop through all arguments and identify the "debug" flag
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
        else
            args+=("$arg")  # Add non-debug arguments to the array
        fi
    done

    # Restore the positional parameters with the filtered arguments
    set -- "${args[@]}"

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local caller_name="${FUNCNAME[1]:-main}"
    local caller_line="${BASH_LINENO[0]:-0}"

    # Assign the remaining argument to the message, defaulting to <unset>
    local message="${1:-<unset>}"

    # Print debug information if the debug flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG in %s] '%s' from %s():%d.\n" \
        "$THIS_SCRIPT" "$message" "$caller_name" "$caller_line" >&2
    fi
}

debug_end() {
    local debug=""
    local args=()  # Array to hold non-debug arguments

    # Loop through all arguments and identify the "debug" flag
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            break  # Exit the loop as soon as we find "debug"
        fi
    done

    # Handle empty or unset FUNCNAME and BASH_LINENO gracefully
    local func_name="${FUNCNAME[1]:-main}"
    local caller_name="${FUNCNAME[2]:-main}"
    local caller_line="${BASH_LINENO[0]:-0}"

    # Print debug information if the debug flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG in %s] Exiting function %s() called by %s():%d.\n" \
        "$THIS_SCRIPT" "$func_name" "$caller_name" "$caller_line" >&2
    fi
}

pause() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    printf "Press any key to continue.\n"
    read -n 1 -sr key < /dev/tty || true
    printf "\n"
    debug_print "$key" "$debug"

    debug_end "$debug"
    return 0
}

###############################################################################

############
### Handle Configured Networks Functions
############

show_wifi_connection_details() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local connection_name="$1"

    # Ensure a connection name is provided
    if [[ -z "$connection_name" ]]; then
        printf "Error: Connection name is required.\n" >&2
        debug_end "$debug"
        return 1
    fi

    # Mapping for field names
    declare -A field_map=(
        ["connection.id"]="Connection"
        ["connection.interface-name"]="Interface Name"
        ["802-11-wireless.ssid"]="SSID"
        ["802-11-wireless-security.key-mgmt"]="Key Management"
        ["802-11-wireless-security.psk"]="Pre-Shared Key"
        ["connection.autoconnect"]="Autoconnect"
    )

    # Build the list of fields dynamically from the field_map keys
    local field_list
    field_list=$(IFS=','; echo "${!field_map[*]}")

    # Retrieve details using nmcli
    local details retval
    details=$(nmcli -t -f "$field_list" connection show "$connection_name" 2>/dev/null)
    retval="$?"

    # Check if nmcli succeeded
    if [[ "$retval" -ne 0 ]]; then
        printf "Error: Unable to retrieve details for connection '%s'. Please check if it exists or is active.\n" "$connection_name" >&2
        debug_print "nmcli failed with exit code $retval for connection '$connection_name'" "$debug"
        debug_end "$debug"
        return 1
    fi

    # Display the details in a user-friendly format
    printf "Details for connection '%s':\n" "$connection_name"
    printf "%s\n" "-----------------------------------------"

    # Loop through the details and map field names
    while IFS=: read -r field value; do
        local mapped_field="${field_map[$field]:-$field}"  # Default to field if no mapping
        printf "%-20s: %s\n" "$mapped_field" "$value"
    done <<< "$details"

    debug_end "$debug"
    return 0
}

populate_configured_networks() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local network_info retval
    # Retrieve only necessary fields excluding SSID
    network_info=$(nmcli -t -f NAME,AUTOCONNECT,AUTOCONNECT-PRIORITY,ACTIVE,DEVICE,TYPE --color no connection show | grep -i ":802-11-wireless" 2>/dev/null)
    retval=$?

    if [[ $retval -ne 0 ]]; then
        printf "%s\n" "Failed to return data from 'nmcli'." >&2
        exit 1
    fi

    if [[ -z "$network_info" ]]; then
        printf "%s\n" "No configured networks found." >&2
        exit 0
    fi

    # Trim the last field ":802-11-wireless"
    network_info="${network_info//:802-11-wireless/}"

    # Replace escaped colons in TIMESTAMP-REAL with underscores
    network_info="${network_info//\\:/_}"

    # Build the final array with SSID inserted
    local final_networks=()
    while IFS=":" read -r name autoconnect priority active device; do
        local ssid
        # Retrieve SSID dynamically for each entry
        ssid=$(nmcli -t -f 802-11-wireless.ssid connection show "$name" 2>/dev/null | cut -d':' -f2)
        # Combine fields, inserting SSID after NAME
        final_networks+=("$name:$ssid:$autoconnect:$priority:$active:$device")
    done <<< "$network_info"

    # Convert final_networks to the configured_networks array
    configured_networks=("${final_networks[@]}")

    debug_print "${configured_networks[*]}" >&2
    debug_end "$debug"
}

display_configured_networks() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Define the columns to display
    local fields_to_display=(
        "NAME"
        "SSID"
        "AUTOCONNECT"
        "PRIORITY"
        "ACTIVE"
        "DEVICE"
    )
    local field_indices=(0 1 2 3 4 5)  # Indices now include SSID

    if [[ ${#configured_networks[@]} -eq 0 ]]; then
        printf "%s\n" "No configured networks found." >&2
        exit 0
    fi

    # Calculate column widths based on field names
    local num_fields=${#fields_to_display[@]}
    local max_widths=()
    for ((i = 0; i < num_fields; i++)); do
        max_widths[i]=${#fields_to_display[i]}
    done

    # Adjust column widths based on data
    for entry in "${configured_networks[@]}"; do
        IFS=":" read -r -a fields <<<"$entry"
        for ((i = 0; i < num_fields; i++)); do
            local field_length=${#fields[i]}
            if ((field_length > max_widths[i])); then
                max_widths[i]=$field_length
            fi
        done
    done

    # Print header row
    printf "%6s  " "CHOICE"
    for ((i = 0; i < num_fields; i++)); do
        printf "%-*s  " "${max_widths[i]}" "${fields_to_display[i]}"
    done
    printf "\n"

    # Print data rows
    local index=0
    for entry in "${configured_networks[@]}"; do
        IFS=":" read -r -a fields <<<"$entry"

        # Wrap the index number with ${BOLD} and ${RESET}
        printf "%6s  " "$index"
        for ((i = 0; i < num_fields; i++)); do
            printf "%-*s  " "${max_widths[i]}" "${fields[i]}"
        done
        printf "\n"
        ((index++))
    done

    # Add static menu items directly after the data rows without a blank line
    printf "%6s  %s\n" "C" "(C)reate a new connection"
    printf "%6s  %s\n" "P" "Change (P)riority"

    printf "\n"
    debug_end "$debug"
}

select_configured_network() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local choice

    while :; do
        read -rp "Select a connection by the choice column (or press Enter to exit): " choice

        if [[ -z "$choice" ]]; then
            # User pressed Enter without input, exit the loop
            debug_end "$debug"
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 0 && choice < ${#configured_networks[@]})); then
            # Numeric selection, return the corresponding network name
            IFS=":" read -r -a selected_fields <<<"${configured_networks[$choice]}"
            selected_fields[4]="${selected_fields[4]//_/\\:}"  # Convert TIMESTAMP-REAL back
            printf "%s\n" "${selected_fields[0]}"
            debug_end "$debug"
            return
        elif [[ "$choice" =~ ^[Cc]$ ]]; then
            # "C" or "c" selected, return "c"
            printf "c\n"
            debug_end "$debug"
            return
        elif [[ "$choice" =~ ^[Pp]$ ]]; then
            # "P" or "p" selected, return "p"
            printf "p\n"
            debug_end "$debug"
            return
        else
            # Invalid input
            printf "%s\n" "Invalid selection. Please enter a valid choice." >&2
        fi
    done
}

wifi_client_config() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local selected_network

    while :; do
        clear
        populate_configured_networks "$debug"
        display_configured_networks "$debug"
        selected_network=$(select_configured_network "$debug")

        if [[ -z "$selected_network" ]]; then
            # User pressed Enter without input, exit the loop
            debug_end "$debug"
            return
        elif [[ "$selected_network" == "c" ]]; then
            # TODO
            printf "Creating a new connection\n"
            pause
        elif [[ "$selected_network" == "p" ]]; then
            # TODO
            printf "Changing Priority\n"
            pause
        elif [[ ${#selected_network} -gt 1 ]]; then
            show_wifi_connection_details "$selected_network"
            pause
        else
            printf "Invalid selection.\n"
            pause
        fi
    done

    debug_end "$debug"
    return 0
}

###############################################################################

save_config() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    # This is DEBUG only
    printf "\nSaving password.\n"
    printf "AP_PASSWORD=%s\n" "$AP_PASSWORD"
    debug_end "$debug"
}

_main() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    wifi_client_config "$debug"
    debug_end "$debug"
}

main() { _main "$@"; return "$?"; }

debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
main "$@" "$debug"
debug_end "$debug"
exit $?
