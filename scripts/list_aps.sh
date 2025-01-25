#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

default_color() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    tput "$@" 2>/dev/null || printf "\n"  # Fallback to an empty string on error

    debug_end "$debug"
    return 0
}

init_colors() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # General text attributes
    BOLD=$(default_color bold)
    # shellcheck disable=SC2034
    DIM=$(default_color dim)
    SMSO=$(default_color smso)
    RMSO=$(default_color rmso)
    UNDERLINE=$(default_color smul)
    NO_UNDERLINE=$(default_color rmul)
    BLINK=$(default_color blink)
    NO_BLINK=$(default_color sgr0)
    ITALIC=$(default_color sitm)
    NO_ITALIC=$(default_color ritm)
    MOVE_UP=$(default_color cuu1)
    CLEAR_LINE=$(tput el)

    # Foreground colors
    FGBLK=$(default_color setaf 0)
    FGRED=$(default_color setaf 1)
    FGGRN=$(default_color setaf 2)
    FGYLW=$(default_color setaf 3)
    FGGLD=$(default_color setaf 220)
    FGBLU=$(default_color setaf 4)
    FGMAG=$(default_color setaf 5)
    FGCYN=$(default_color setaf 6)
    FGWHT=$(default_color setaf 7)
    FGRST=$(default_color setaf 9)
    FGRST=$(default_color setaf 39)

    # Background colors
    BGBLK=$(default_color setab 0)
    BGRED=$(default_color setab 1)
    BGGRN=$(default_color setab 2)
    BGYLW=$(default_color setab 3)
    BGGLD=$(default_color setab 220)
    [[ -z "$BGGLD" ]] && BGGLD="$BGYLW"  # Fallback to yellow
    BGBLU=$(default_color setab 4)
    BGMAG=$(default_color setab 5)
    BGCYN=$(default_color setab 6)
    BGWHT=$(default_color setab 7)
    BGRST=$(default_color setab 9)

    # Reset all
    RESET=$(default_color sgr0)

    # Set variables as readonly
    # shellcheck disable=2303
    # shellcheck disable=SC2034
    readonly RESET BOLD SMSO RMSO UNDERLINE NO_UNDERLINE
    # shellcheck disable=SC2034
    readonly BLINK NO_BLINK ITALIC NO_ITALIC MOVE_UP CLEAR_LINE
    # shellcheck disable=SC2034
    readonly FGBLK FGRED FGGRN FGYLW FGBLU FGMAG FGCYN FGWHT FGRST FGGLD
    # shellcheck disable=SC2034
    readonly BGBLK BGRED BGGRN BGYLW BGBLU BGMAG BGCYN BGWHT BGRST

    debug_end "$debug"
    return 0
}

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

# -----------------------------------------------------------------------------
# @brief Populate Wi-Fi network data.
# @details Extracts Wi-Fi network information using nmcli, filters out entries
#          with blank SSID, and returns the network data as an indexed array.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
populate_wifi_networks() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local wifi_info retval
    wifi_info=$(nmcli -t -f all --color no dev wifi list 2>/dev/null)
    retval=$?

    if [[ $retval -ne 0 ]]; then
        warn "Failed to execute 'nmcli'. Ensure NetworkManager is running and you have the necessary permissions."
        exit 1
    fi

    if [[ -z "$wifi_info" ]]; then
        printf "No Wi-Fi networks detected. Ensure Wi-Fi is enabled and try again.\n" >&2
        exit 0
    fi

    wifi_info="${wifi_info//\\:/-}"

    local filtered_wifi_info
    filtered_wifi_info=$(echo "$wifi_info" | awk -F ':' '$2 != ""')

    IFS=$'\n' read -rd '' -a wifi_entries <<<"$filtered_wifi_info" || true

    local index=1
    declare -A ssid_to_best_signal
    declare -A ssid_to_entry

    for entry in "${wifi_entries[@]}"; do
        IFS=":" read -r -a fields <<<"$entry"
        local ssid="${fields[1]}"
        local signal="${fields[8]}"

        # Ensure the SSID is not empty
        if [[ -n "$ssid" ]]; then
            if [[ "$debug" == "debug" ]]; then
                wifi_networks[index]="$entry"
                ((index++))
            else
                # Initialize the key in the associative array if not set
                if [[ -z "${ssid_to_best_signal[$ssid]:-}" || $signal -gt ${ssid_to_best_signal[$ssid]} ]]; then
                    ssid_to_best_signal[$ssid]=$signal
                    ssid_to_entry[$ssid]=$entry
                fi
            fi
        fi
    done

    if [[ ! $debug == "debug" ]]; then
        for ssid in "${!ssid_to_entry[@]}"; do
            wifi_networks[index]="${ssid_to_entry[$ssid]}"
            ((index++))
        done
    fi
        debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Display Wi-Fi networks in a formatted table.
# @details Outputs a table of Wi-Fi networks with selected columns and a
#          numeric index for user selection. Handles empty network list.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
# -----------------------------------------------------------------------------
# @brief Display Wi-Fi networks in a formatted table.
# @details Outputs a table of Wi-Fi networks with selected columns and a
#          numeric index for user selection.
# -----------------------------------------------------------------------------
display_wifi_networks() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Define the columns to display
    local fields_to_display=(
        "SSID"
        "SIGNAL"
        "BARS"
        "SECURITY"
    )
    local field_indices=(1 8 9 10)  # Indices of the selected fields in Wi-Fi data

    if [[ ${#wifi_networks[@]} -eq 0 ]]; then
        exit 0
    fi

    # Calculate column widths based on field names
    local num_fields=${#fields_to_display[@]}
    local max_widths=()
    for ((i = 0; i < num_fields; i++)); do
        max_widths[i]=${#fields_to_display[i]}
    done

    # Adjust column widths based on data
    for key in "${!wifi_networks[@]}"; do
        IFS=":" read -r -a fields <<<"${wifi_networks[$key]}"
        for ((i = 0; i < num_fields; i++)); do
            local column_index=${field_indices[i]}
            local field_length=${#fields[column_index]}
            if ((field_length > max_widths[i])); then
                max_widths[i]=$field_length
            fi
        done
    done

    # Print header row
    printf "%s%6s%s  " "$BOLD" "CHOICE" "$RESET"
    for ((i = 0; i < num_fields; i++)); do
        printf "%s%-*s%s  " "$BOLD" "${max_widths[i]}" "${fields_to_display[i]}" "$RESET"
    done
    printf "\n"

    # Print data rows
    for key in $(printf "%s\n" "${!wifi_networks[@]}" | sort -n); do
        IFS=":" read -r -a fields <<<"${wifi_networks[$key]}"

        printf "%6s  " "$key"
        for ((i = 0; i < num_fields; i++)); do
            local column_index=${field_indices[i]}
            printf "%-*s  " "${max_widths[i]}" "${fields[column_index]}"
        done
        printf "\n"
    done

    printf "\n"
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Prompt user to select a Wi-Fi network by index.
# @details Allows the user to enter an index corresponding to a Wi-Fi network.
#          Pressing Enter or selecting "0" returns a blank value.
#
# @return The SSID of the selected network or blank for "0" or Enter.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
select_wifi_network() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local choice
    while :; do
        read -rp "Select a network by number (or press Enter to exit): " choice

        if [[ -z "$choice" ]]; then
            printf "%s\n" ""
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 0 && choice <= ${#wifi_networks[@]})); then
            break
        else
            printf "Invalid selection. Please enter a number between 0 and %s.\n" ${#wifi_networks[@]} >&2
        fi
    done

    if [[ -z "$choice" || "$choice" -eq 0 ]]; then
        printf "\n"
    else
        IFS=":" read -r -a selected_fields <<<"${wifi_networks[$choice]}"
        printf "%s\n" "${selected_fields[1]}"
    fi
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Set up and select a Wi-Fi network.
# @details Orchestrates the process of populating Wi-Fi data, displaying
#          available networks, and allowing the user to select one. Optionally,
#          prepares for subsequent actions with the selected SSID.
#
# @return The selected SSID is output for further processing.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
setup_wifi_network() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local selected_ssid

    clear
    printf "%s%sAdd or modify a WiFi Network%s\n" "$FGYLW" "$BOLD" "$RESET"
    printf "\nScanning for available WiFi networks, please wait.\n"

    populate_wifi_networks "$debug"
    printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"
    display_wifi_networks "$debug"
    selected_ssid=$(select_wifi_network "$debug")

    # Call the function with the SSID
    if [[ -z "$selected_ssid" ]]; then
        printf "No SSID selected.\n"
        sleep 1
    else
        update_wifi_profile "$selected_ssid" "$debug"
    fi

    debug_end "$debug"
    return 0
}

_main() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    init_colors "$debug"
    setup_wifi_network "$debug"
    debug_end "$debug"
    return 0
}

main() { _main "$@"; return "$?"; }

debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
main "$@" "$debug"
debug_end "$debug"
exit $?
