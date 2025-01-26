#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

declare REPO_NAME="${REPO_NAME:-ap-popup}"
declare REPO_DISPLAY_NAME="${REPO_DISPLAY_NAME:-AP Pop-Up}"
declare MENU_HEADER="${MENU_HEADER:-$REPO_DISPLAY_NAME Controller Menu}"  # Global menu header

declare THIS_SCRIPT="${BASH_SOURCE[0]}"
if [[ -z "$THIS_SCRIPT" || "$THIS_SCRIPT" == "bash" ]]; then
    THIS_SCRIPT="${FALLBACK_SCRIPT_NAME:-template.sh}"
fi

# WIFI_INTERFACE="wlan1"      # WiFi interface used by the Access Point
# AP_PROFILE_NAME="AP_Pop-Up" # Access Point profile name
# AP_SSID="AP_Pop-Up"         # Access Point SSID
# AP_PASSWORD="1234567890"    # Access Point password
# AP_IP="192.168.50.5/24"     # Access Point CIDR
# AP_GW="192.168.50.254"      # Access Point Gateway
# ENABLE_WIFI="y"             # Enable WiFi automatically if disabled

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
    local this_script
    this_script=$(basename "${THIS_SCRIPT:-main}")
    this_script="${this_script%.*}"
    local func_name="${FUNCNAME[1]:-main}"
    local caller_name="${FUNCNAME[2]:-main}"
    local caller_line=${BASH_LINENO[1]:-0}
    local current_line=${BASH_LINENO[0]:-0}

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG]\t[%s:%s():%d] Starting function called by %s():%d.\n" \
            "$this_script" "$func_name" "$current_line"  "$caller_name" "$caller_line" >&2
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

    # Loop through all arguments to identify the "debug" flag
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
    local this_script
    this_script=$(basename "${THIS_SCRIPT:-main}")
    this_script="${this_script%.*}"
    local caller_name="${FUNCNAME[1]:-main}"
    local caller_line="${BASH_LINENO[0]:-0}"

    # Assign the remaining argument to the message, defaulting to <unset>
    local message="${1:-<unset>}"

    # Print debug information if the debug flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG]\t[%s:%s:%d] '%s'.\n" \
               "$this_script" "$caller_name" "$caller_line" "$message" >&2
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
    local this_script
    this_script=$(basename "${THIS_SCRIPT:-main}")
    this_script="${this_script%.*}"
    local func_name="${FUNCNAME[1]:-main}"
    local caller_name="${FUNCNAME[2]:-main}"
    local caller_line=${BASH_LINENO[1]:-0}
    local current_line=${BASH_LINENO[0]:-0}

    # Print debug information if the flag is set
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG]\t[%s:%s():%d] Exiting function returning to %s():%d.\n" \
            "$this_script" "$func_name" "$current_line"  "$caller_name" "$caller_line" >&2
    fi
}

# shellcheck disable=SC2317
pause() {
    printf "Press any key to continue. "
    read -n 1 -sr < /dev/tty || true
    printf "\n"
}

# shellcheck disable=SC2317
debug_pause() {
    # Get the calling function and line number
    local caller_name="${FUNCNAME[1]:-main}"
    local caller_line="${BASH_LINENO[0]:-0}"

    # Display the prompt with the calling function and line number
    printf "[PAUSE]\t[%s():%d] Press any key to continue. " "$caller_name" "$caller_line"
    read -n 1 -sr < /dev/tty || true
    printf "\n"
}

###############################################################################

############
### Handle Network Configuration Functions
############

validate_input() {
    local value="$1"
    local regex="$2"
    local error_message="$3"

    if [[ ! "$value" =~ $regex ]]; then
        printf "Error: %s\n" "$error_message" >&2
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# @brief Safely execute `nmcli` commands with error handling and output capture.
# @details Executes the given `nmcli` command and captures its output into a
#          variable. Avoids the use of `eval` for better security and stability.
#
# @param ... Arguments to pass to the `nmcli` command.
# @return 0 if the `nmcli` command executes successfully, 1 otherwise.
#         The output is stored in the `safe_nmcli_output` variable if captured.
#
# @example
# safe_nmcli_output=$(safe_nmcli connection show -t -f NAME,DEVICE || exit 1)
# -----------------------------------------------------------------------------
safe_nmcli() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    # shellcheck disable=SC2294
    eval set -- "$@" # This is needed to retain array config without debug
    local args=("$@")
    local output
    local retval

    # Log the command for debugging
    debug_print "Constructed command: nmcli ${args[*]}" "$debug"

    # Execute the `nmcli` command safely using the array
    if output=$(nmcli "${args[@]}" 2>&1); then
        debug_print "Command executed successfully: nmcli ${args[*]}" "$debug"
        debug_print "Results: $output" "$debug"
        printf "%s\n" "$output"  # Return the command output
        retval=0
    else
        retval=$?
        debug_print "[ERROR] $output" "$debug"
        printf "[ERROR] Failed to execute: nmcli %s\n" "${args[*]}" >&2
        case "$output" in
            *"not authorized"*)
                printf "Please run the script with appropriate permissions.\n" >&2
                ;;
            *"no such connection"*)
                printf "The specified connection does not exist.\n" >&2
                ;;
            *)
                printf "An error occurred. Check your configuration and try again.\n" >&2
                ;;
        esac
    fi

    debug_end "$debug"
    return "$retval"
}

edit_connection_field() {
    # Initialize debug and process inputs
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local connection_name="$1"
    shift
    local field_map_declaration="$1"
    shift
    local rows=("$@") # Process remaining arguments as rows array

    # Reconstruct field_map
    eval "$field_map_declaration"

    printf "\n"
    printf "Select a field to edit by its index, or press Enter to exit: "
    read -r selection

    # Exit if Enter is pressed without input
    [[ -z "$selection" ]] && debug_end "$debug" && return 0

    # Validate selection    
    if [[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 0 && selection < ${#rows[@]})); then
        IFS=":" read -r idx field value <<<"${rows[$selection]}"

        # Find the nmcli key
        local nmcli_key="${!field_map[@]}"  # Default empty
        for key in "${!field_map[@]}"; do
            [[ "${field_map[$key]}" == "$field" ]] && nmcli_key="$key" && break
        done

        if [[ -z "$nmcli_key" ]]; then
            printf "Error: Unable to find the corresponding key for '%s'.\n" "$field" >&2
            debug_end "$debug"
            return 1
        fi

        printf "\nYou selected '%s', currently set to: '%s'\n" "$field" "$value"

        # Special cases for fields
        local new_value
        case "$nmcli_key" in
            "connection.interface-name")
                new_value=$(choose_active_wifi_interface "$debug")
                ;;
            "802-11-wireless-security.key-mgmt")
                new_value=$(choose_key_management "$debug")
                ;;
            "connection.autoconnect")
                printf "\n"
                printf "Select Autoconnect Action:\n"
                printf "1    yes\n"
                printf "2    no\n"
                printf "\n"
                printf "Enter choice (1 or 2) or press Enter to cancel: "
                read -r choice
                case "$choice" in
                    1) new_value="yes" ;;
                    2) new_value="no" ;;
                    "")
                        printf "\n"
                        printf "No changes made to '%s'.\n" "$field" >&2
                        pause
                        debug_end "$debug"
                        return 1
                        ;;
                    *)
                        printf "\nInvalid choice. No changes made to '%s'.\n" "$field" >&2
                        pause
                        debug_end "$debug"
                        return 1
                        ;;
                esac
                ;;
            "connection.autoconnect-priority")
                while :; do
                    read -rp "Enter a new priority (or press Enter to keep current): " new_value

                    # Allow blank input or validate the input as an integer
                    if [[ -z "$new_value" || "$new_value" =~ ^-?[0-9]+$ ]]; then
                        break  # Valid integer or blank, exit the loop
                    else
                        printf "Invalid input. Please enter a valid integer or press Enter to keep current.\n"
                    fi
                done
                ;;
            *)
                read -rp "Enter a new value for '$field' (or press Enter to cancel): " new_value
                ;;
        esac

        # Handle empty input
        if [[ -z "$new_value" ]]; then
            printf "No changes made to '%s'.\n" "$field" >&2
            debug_end "$debug"
            return 1
        fi

        # Apply changes for specific cases
        local change_retval
        if [[ "$nmcli_key" == "802-11-wireless-security.key-mgmt" ]]; then
            handle_key_mgmt "$connection_name" "$nmcli_key" "$new_value"
            change_retval="$?"
        elif [[ "$nmcli_key" == "connection.interface-name" && "$new_value" == "None (any)" ]]; then
            safe_nmcli connection modify "$connection_name" "$nmcli_key" "" "$debug" 2>/dev/null
            change_retval="$?"
        else
            safe_nmcli connection modify "$connection_name" "$nmcli_key" "$new_value" "$debug" 2>/dev/null
            change_retval="$?"
        fi

        # Confirm change
        if [[ "$change_retval" -eq 0 ]]; then
            printf "\nSuccessfully updated '%s' to '%s'.\n" "$field" "$new_value" >&2
            pause
        else
            printf "\nFailed to update '%s'.\n" "$field" >&2
            pause
        fi
    else
        printf "Invalid selection. Please enter a valid index.\n" >&2
    fi

    debug_end "$debug"
    return 1
}

handle_key_mgmt() {
    local connection_name="$1"
    local nmcli_key="$2"
    local key_mgmt="$3"

    if [[ "$key_mgmt" == "none" ]]; then
        safe_nmcli connection modify "$connection_name" "$nmcli_key" none "$debug" 2>/dev/null
        local retval="$?"
        if [[ "$retval" -eq 0 ]]; then
            printf "Key Management updated to 'none'.\n" >&2
            return 0
        else
            printf "Failed to update Key Management to 'none'.\n" >&2
            return 1
        fi
    else
        safe_nmcli connection modify "$connection_name" "$nmcli_key" "$key_mgmt" "$debug" 2>/dev/null
        local retval="$?"
        if [[ "$retval" -ne 0 ]]; then
            printf "Failed to update Key Management to '%s'.\n" "$key_mgmt" >&2
            return 1
        fi

        printf "Updated Key Management to '%s'.\n" "$key_mgmt" >&2
        printf "\n" >&2
        printf "Enter passkey for '%s': " "$connection_name" >&2
        read -r passkey

        if [[ -n "$passkey" ]]; then
            safe_nmcli connection modify "$connection_name" 802-11-wireless-security.psk "$passkey" "$debug" 2>/dev/null
            local passkey_retval="$?"
            if [[ "$passkey_retval" -eq 0 ]]; then
                printf "Passkey updated successfully for '%s'.\n" "$connection_name" >&2
                return 0
            else
                printf "Failed to update passkey for '%s'.\n" "$connection_name" >&2
                return 1
            fi
        else
            printf "No passkey entered. The connection passkey was not updated.\n" >&2
            return 0
        fi
    fi
}

choose_active_wifi_interface() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Retrieve active Wi-Fi interfaces
    local active_interfaces
    active_interfaces=$(safe_nmcli -t -f DEVICE,TYPE,STATE device "$debug" | grep ":wifi:" | cut -d':' -f1)
    local retval=$?

    if [[ $retval -ne 0 || -z "$active_interfaces" ]]; then
        printf "Error: No active Wi-Fi interfaces detected.\n" >&2
        printf "Ensure that Wi-Fi hardware is enabled and try again.\n" >&2
        debug_end "$debug"
        return 1
    fi

    # Convert active interfaces into a list
    local interfaces_array=()
    while IFS= read -r interface; do
        interfaces_array+=("$interface")
    done <<< "$active_interfaces"

    # Add "None (any)" option to the list
    interfaces_array+=("Any")

    # Display choices to the user
    printf "\n"
    printf "Available Wi-Fi interfaces:\n\n" >&2
    for i in "${!interfaces_array[@]}"; do
        printf "%d    %s\n" "$((i + 1))" "${interfaces_array[$i]}" >&2
    done

    # Prompt the user to choose an interface
    local choice
    printf "\n" >&2
    read -rp "Enter the number of your choice (default is any): " choice >&2

    if [[ -z "$choice" ]]; then
        # Default to "3 None (any)"
        choice=3
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice > 0 && choice <= ${#interfaces_array[@]})); then
        local selected_interface="${interfaces_array[$((choice - 1))]}"
        printf "Selected Wi-Fi interface: %s\n" "$selected_interface" >&2
        echo "$selected_interface"
        debug_end "$debug"
        return 0
    else
        printf "Invalid selection. Please try again.\n" >&2
        debug_end "$debug"
        return 1
    fi
}

choose_key_management() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Display choices for key management
    printf "\n" >&2
    printf "Select Key Management Type:\n\n" >&2
    printf "1    wpa-psk (default)\n" >&2
    printf "2    none\n\n" >&2
    printf "Enter the number of your choice (default is wpa-psk): " >&2

    # Read user input
    local choice
    read -r choice

    # Default to "wpa-psk" if no input
    if [[ -z "$choice" ]]; then
        choice=1
    fi

    # Return the selected key management type
    case "$choice" in
        1)
            printf "wpa-psk\n"
            debug_print "Key Management selected: wpa-psk" "$debug"
            ;;
        2)
            printf "none\n"
            debug_print "Key Management selected: none" "$debug"
            ;;
        *)
            printf "Invalid choice. Defaulting to wpa-psk.\n" >&2
            printf "wpa-psk\n"
            debug_print "Invalid input. Defaulted to Key Management: wpa-psk" "$debug"
            ;;
    esac

    debug_end "$debug"
    return 0
}

modify_wifi_connection() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local connection_name="$1"

    declare -A field_map=(
        ["connection.id"]="Connection"
        ["802-11-wireless.ssid"]="SSID"
        ["connection.interface-name"]="Interface Name"
        ["802-11-wireless-security.key-mgmt"]="Key Management"
        ["802-11-wireless-security.psk"]="Pre-Shared Key"
        ["connection.autoconnect"]="Autoconnect"
        ["connection.autoconnect-priority"]="Auto-Connect Priority"
    )

    local ordered_keys=(
        "connection.id"
        "802-11-wireless.ssid"
        "connection.interface-name"
        "802-11-wireless-security.key-mgmt"
        "802-11-wireless-security.psk"
        "connection.autoconnect"
        "connection.autoconnect-priority"
    )

    while :; do
        local details
        details=$(safe_nmcli -t -f "$(IFS=','; echo "${ordered_keys[*]}")" connection show "$connection_name" "$debug" 2>/dev/null)
        local retval="$?"
        if [[ $retval -ne 0 ]]; then
            printf "Error: Unable to retrieve details for connection '%s'.\n" "$connection_name" >&2
            debug_end "$debug"
            return 1
        fi

        local active_status
        active_status=$(safe_nmcli -t -f NAME,ACTIVE connection show "$debug" | grep "^$connection_name:" | cut -d':' -f2)
        active_status="${active_status:-no}"

        local index=0
        local rows=()
        for key in "${ordered_keys[@]}"; do
            local value
            if [[ "$key" == "ACTIVE" ]]; then
                value="$active_status"
            else
                value=$(printf "%s\n" "$details" | grep "^$key:" | cut -d':' -f2-)
            fi
            rows+=("$index:${field_map[$key]}:${value:-}")
            ((index++))
        done

        local max_idx_width=5
        local max_field_width=5
        local max_value_width=5

        for row in "${rows[@]}"; do
            IFS=":" read -r idx field value <<<"$row"
            (( ${#idx} > max_idx_width )) && max_idx_width=${#idx}
            (( ${#field} > max_field_width )) && max_field_width=${#field}
            (( ${#value} > max_value_width )) && max_value_width=${#value}
        done

        ##clear
        printf "%s\n\n" "$MENU_HEADER"
        printf "Details for connection '%s':\n\n" "$connection_name"
        printf "%-*s  %-*s  %-*s\n" "$max_idx_width" "INDEX" "$max_field_width" "FIELD" "$max_value_width" "VALUE"
        printf "%-*s  %-*s  %-*s\n" "$max_idx_width" "$(printf "%0.s-" $(seq 1 "$max_idx_width"))" \
                                    "$max_field_width" "$(printf "%0.s-" $(seq 1 "$max_field_width"))" \
                                    "$max_value_width" "$(printf "%0.s-" $(seq 1 "$max_value_width"))"
        for row in "${rows[@]}"; do
            IFS=":" read -r idx field value <<<"$row"
            printf "%-*s  %-*s  %-*s\n" "$max_idx_width" "$idx" "$max_field_width" "$field" "$max_value_width" "$value"
        done

        # Pass rows to edit_connection_field and capture its return value
        edit_connection_field "$connection_name" "$(declare -p field_map)" "${rows[@]}" "$debug"
        local edit_result=$?
        # 1 = reload edit menu, 0 = return
        if [[ "$edit_result" == 0 ]]; then
            break
        fi
    done

    debug_end "$debug"
}

populate_configured_networks() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local network_info retval
    # Retrieve only necessary fields excluding SSID
    network_info=$(safe_nmcli -t -f NAME,AUTOCONNECT,AUTOCONNECT-PRIORITY,ACTIVE,DEVICE,TYPE --color no connection show "$debug" | grep -i ":802-11-wireless" 2>/dev/null)
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

    # Build the final array with SSID and replace blank DEVICE with connection.interface-name
    local final_networks=()
    while IFS=":" read -r name autoconnect priority active device; do
        local ssid interface_name
        # Retrieve SSID dynamically for each entry
        ssid=$(safe_nmcli -t -f 802-11-wireless.ssid connection show "$name" "$debug" 2>/dev/null | cut -d':' -f2)
        # Retrieve connection.interface-name if DEVICE is blank
        if [[ -z "$device" || "$device" == "--" ]]; then
            interface_name=$(safe_nmcli -t -f connection.interface-name connection show "$name" "$debug" 2>/dev/null | cut -d':' -f2)
            device="${interface_name:-}"
        fi
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

    #clear
    # Display the menu header
    printf "%s\n\n" "$MENU_HEADER"
    printf "Edit Configured WiFi Networks:\n\n"

    # Define the columns to display
    local fields_to_display=(
        "NAME"
        "SSID"
        "AUTOCONNECT"
        "PRIORITY"
        "ACTIVE"
        "DEVICE"
    )

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
        if [[ -n "$entry" ]]; then  # Ensure entry is not empty
            IFS=":" read -r -a fields <<<"$entry"
            for ((i = 0; i < num_fields; i++)); do
                # Safely access fields[i] and calculate length
                local field_value="${fields[i]:-}"  # Default to an empty string if unset
                local field_length=${#field_value}  # Get the length of the value
                if ((field_length > max_widths[i])); then
                    max_widths[i]=$field_length
                fi
            done
        fi
    done

    # Print header row
    printf "%6s  " "CHOICE"
    for ((i = 0; i < num_fields; i++)); do
        printf "%-*s  " "${max_widths[i]}" "${fields_to_display[i]}"
    done
    printf "\n"

    # Print dashes under the header
    printf "%6s  " "------"
    for ((i = 0; i < num_fields; i++)); do
        printf "%-*s  " "${max_widths[i]}" "$(printf "%0.s-" $(seq 1 "${max_widths[i]}"))"
    done
    printf "\n"

    # Print data rows
    local index=0
    for entry in "${configured_networks[@]}"; do
        if [[ -n "$entry" ]]; then  # Ensure entry is not empty
            IFS=":" read -r -a fields <<<"$entry"
            printf "%6s  " "$index"
            for ((i = 0; i < num_fields; i++)); do
                printf "%-*s  " "${max_widths[i]}" "${fields[i]:-}"
            done
            printf "\n"
            ((index++))
        fi
    done

    printf "\n"
    debug_end "$debug"
}

select_configured_network() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local choice

    printf "Select a connection to edit by the index, select 'C' to (c)reate\n" >&2
    printf "a new connection, or select 'D' to (d)elete a connection. Press\n" >&2
    printf "'Enter' to exit with no changes.\n\n" >&2

    while :; do
        read -rp "Choice: " choice

        if [[ -z "$choice" ]]; then
            # User pressed Enter without input, exit the loop
            debug_print "User exited without making a selection." "$debug"
            debug_end "$debug"
            return 1
        elif [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 0 && choice < ${#configured_networks[@]})); then
            # Numeric selection, return the corresponding network name
            IFS=":" read -r -a selected_fields <<<"${configured_networks[$choice]}"
            selected_fields[4]="${selected_fields[4]//_/\\:}"  # Convert TIMESTAMP-REAL back
            printf "%s\n" "${selected_fields[0]}"
            debug_print "User selected network: ${selected_fields[0]}" "$debug"
            debug_end "$debug"
            return 0
        elif [[ "$choice" =~ ^[Cc]$ ]]; then
            # "C" or "c" selected, return "c"
            debug_print "User chose to create a new connection." "$debug"
            printf "c\n"
            debug_end "$debug"
            return 0
        elif [[ "$choice" =~ ^[Dd]$ ]]; then
            # "D" or "d" selected, return "d"
            debug_print "User chose to delete a connection." "$debug"
            printf "d\n"
            debug_end "$debug"
            return 0
        else
            # Invalid input
            printf "Invalid selection. Please enter a valid choice.\n" >&2
            debug_print "Invalid input from user: $choice" "$debug"
        fi
    done
}

create_new_connection() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    #clear
    printf "%s\n\n" "$MENU_HEADER"
    printf "Creating a new Wi-Fi connection. SSID and Connection ID\n"
    printf "are required. Leave any other field blank to use defaults.\n\n"

    declare -A field_map=(
        ["802-11-wireless.ssid"]="SSID [Required]"
        ["connection.id"]="Connection Name (ID) (default is SSID)"
        ["connection.interface-name"]="Interface Name (select from available interfaces or leave blank for default)"
        ["802-11-wireless-security.key-mgmt"]="Key Management (default: wpa-psk)"
        ["802-11-wireless-security.psk"]="Wi-Fi Password (8-63 ASCII characters or 64 hex digits)"
        ["connection.autoconnect"]="Auto-Connect (default: yes)"
        ["connection.autoconnect-priority"]="Auto-Connect Priority (default: 0)"
    )

    declare -a field_order=(
        "802-11-wireless.ssid"
        "connection.id"
        "connection.interface-name"
        "802-11-wireless-security.key-mgmt"
        "802-11-wireless-security.psk"
        "connection.autoconnect"
        "connection.autoconnect-priority"
    )

    declare -A defaults=(
        ["connection.autoconnect-priority"]="0"
        ["802-11-wireless-security.key-mgmt"]="wpa-psk"
        ["connection.autoconnect"]="yes"
    )

    declare -A connection_data

    for key in "${field_order[@]}"; do
        while :; do
            if [[ "$key" == "connection.interface-name" ]]; then
                # Call choose_active_wifi_interface to select an interface
                printf "\nSelect an active Wi-Fi interface:\n" >&2
                local selected_interface
                selected_interface=$(choose_active_wifi_interface "$debug")
                local retval="$?"
                if [[ "$retval" -eq 0 ]]; then
                    connection_data["$key"]="$selected_interface"
                    if [[ "$selected_interface" == "Any" ]]; then
                        connection_data["$key"]=""  # Set to blank for "Any"
                        printf "Interface selected: Any (will use default).\n" >&2
                    else
                        printf "Interface selected: %s\n" "$selected_interface" >&2
                    fi
                else
                    printf "No interface available. Leaving blank for default.\n" >&2
                    connection_data["$key"]=""  # Use blank value for default
                fi
                break
            elif [[ "$key" == "802-11-wireless-security.key-mgmt" ]]; then
                # Call choose_key_management to select the key management type
                connection_data["$key"]=$(choose_key_management "$debug")
                break
            else
                # Handle other fields as before
                read -rp "${field_map[$key]}: " input
                case "$key" in
                    "802-11-wireless.ssid")
                        if validate_input "$input" "^[a-zA-Z0-9 _-]+$" \
                            "'${field_map[$key]}' is required and must only contain letters, numbers, spaces, underscores, or hyphens."; then
                            connection_data["$key"]="$input"
                            break
                        fi
                        ;;
                    "connection.id")
                        if [[ -z "$input" ]]; then
                            if [[ -n "${connection_data["802-11-wireless.ssid"]}" ]]; then
                                connection_data["$key"]="${connection_data["802-11-wireless.ssid"]}"
                                break
                            else
                                printf "Error: SSID must be entered before setting Connection Name.\n" >&2
                            fi
                        elif validate_input "$input" "^[a-zA-Z0-9 _-]+$" \
                            "'${field_map[$key]}' must only contain letters, numbers, spaces, underscores, or hyphens."; then
                            connection_data["$key"]="$input"
                            break
                        fi
                        ;;
                    "802-11-wireless-security.psk")
                        if [[ -z "$input" || ("${#input}" -ge 8 && "${#input}" -le 63) ]]; then
                            connection_data["$key"]="$input"
                            break
                        else
                            printf "Error: Password must be 8-63 characters.\n" >&2
                        fi
                        ;;
                    "connection.autoconnect-priority")
                        if [[ -z "$input" || "$input" =~ ^-?[0-9]+$ ]]; then
                            connection_data["$key"]="${input:-${defaults[$key]:-}}"
                            break
                        else
                            printf "Error: Priority must be a valid integer. Default is '%s'.\n" "${defaults[$key]:-0}" >&2
                        fi
                        ;;
                    *)
                        connection_data["$key"]="${input:-${defaults[$key]:-}}"
                        break
                        ;;
                esac
            fi
        done
    done

    printf "\nCreating connection...\n"
    local retval
    if [[ -z "${connection_data["802-11-wireless-security.psk"]}" ]]; then
        # Open network
        debug_print "safe_nmcli connection add type wifi" \
            "con-name ${connection_data["connection.id"]}" \
            "ifname '${connection_data["connection.interface-name"]}'" \
            "ssid ${connection_data["802-11-wireless.ssid"]}" \
            "autoconnect ${connection_data["connection.autoconnect"]}" \
            "connection.autoconnect-priority ${connection_data["connection.autoconnect-priority"]}" \
            "wifi-sec.key-mgmt none" "$debug"
        safe_nmcli connection add type wifi \
            con-name "${connection_data["connection.id"]}" \
            ifname "${connection_data["connection.interface-name"]}'" \
            ssid "${connection_data["802-11-wireless.ssid"]}" \
            autoconnect "${connection_data["connection.autoconnect"]}" \
            connection.autoconnect-priority "${connection_data["connection.autoconnect-priority"]}" \
            wifi-sec.key-mgmt "none" "$debug"
        retval="$?"
    else
        # Password-protected network
        debug_print "safe_nmcli connection add type wifi" \
            "con-name ${connection_data["connection.id"]}" \
            "ifname ${connection_data["connection.interface-name"]}" \
            "ssid ${connection_data["802-11-wireless.ssid"]}" \
            "autoconnect ${connection_data["connection.autoconnect"]}" \
            "connection.autoconnect-priority ${connection_data["connection.autoconnect-priority"]}" \
            "wifi-sec.key-mgmt ${connection_data["802-11-wireless-security.key-mgmt"]}" \
            "wifi-sec.psk '${connection_data["802-11-wireless-security.psk"]}'" "$debug"
        safe_nmcli connection add type wifi \
            con-name "${connection_data["connection.id"]}" \
            ifname "${connection_data["connection.interface-name"]}" \
            ssid "${connection_data["802-11-wireless.ssid"]}" \
            autoconnect "${connection_data["connection.autoconnect"]}" \
            connection.autoconnect-priority "${connection_data["connection.autoconnect-priority"]}" \
            wifi-sec.key-mgmt "${connection_data["802-11-wireless-security.key-mgmt"]}" \
            wifi-sec.psk "'${connection_data["802-11-wireless-security.psk"]}'" "$debug"
        retval="$?"
    fi

    if [[ "$retval" -eq 0 ]]; then
        printf "Wi-Fi connection '%s' created successfully.\n" "${connection_data["connection.id"]}"
    else
        printf "Failed to create Wi-Fi connection '%s'.\n" "${connection_data["connection.id"]}" >&2
    fi

    debug_end "$debug"
}

wifi_client_config() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local selected_network

    while :; do
        populate_configured_networks "$debug"
        display_configured_networks "$debug"
        selected_network=$(select_configured_network "$debug")

        if [[ -z "$selected_network" ]]; then
            # User pressed Enter without input, exit the loop
            debug_print "User exited the configuration menu." "$debug"
            debug_end "$debug"
            break
        elif [[ "$selected_network" == "c" ]]; then
            create_new_connection "$debug"
            pause
        elif [[ "$selected_network" == "d" ]]; then
            # Prompt for network number to delete
            printf "\n" >&2
            printf "Select a connection to delete by its index, or press Enter to cancel.\n" >&2
            read -rp "Choice: " delete_choice

            if [[ -z "$delete_choice" ]]; then
                printf "Deletion canceled.\n"
                debug_print "Deletion canceled by user." "$debug"
                pause
            elif [[ "$delete_choice" =~ ^[0-9]+$ ]] && ((delete_choice >= 0 && delete_choice < ${#configured_networks[@]})); then
                # Confirm deletion
                IFS=":" read -r -a selected_fields <<<"${configured_networks[$delete_choice]}"
                printf "Are you sure you want to delete the network '%s'? (y/N): " "${selected_fields[0]}"
                read -r confirm_delete
                if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
                    # Delete the network
                    safe_nmcli connection delete "${selected_fields[0]}" "$debug"
                    if [[ $? -eq 0 ]]; then
                        printf "Network '%s' deleted successfully.\n" "${selected_fields[0]}"
                        debug_print "Deleted network: ${selected_fields[0]}" "$debug"
                    else
                        printf "Failed to delete network '%s'.\n" "${selected_fields[0]}" >&2
                        debug_print "Failed to delete network: ${selected_fields[0]}" "$debug"
                    fi
                else
                    printf "Deletion canceled.\n"
                    debug_print "User chose not to delete network: ${selected_fields[0]}" "$debug"
                fi
                pause
            else
                printf "Invalid selection.\n" >&2
                debug_print "Invalid deletion input: $delete_choice" "$debug"
                pause
            fi
        elif [[ ${#selected_network} -gt 1 ]]; then
            modify_wifi_connection "$selected_network" "$debug"
        else
            printf "Invalid selection.\n" >&2
            debug_print "Invalid menu selection: $selected_network" "$debug"
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
    printf "\n"
    printf "Saving password.\n"
    printf "Foo=%s\n" "$Foo"
    debug_end "$debug"
}

_main() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    wifi_client_config "$debug"
    #concatenate_and_normalize "  Hello   world " "  this  is  " '"a test"' 'of  the "function"'
    debug_end "$debug"
}

main() { _main "$@"; return "$?"; }

debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
main "$@" "$debug"
debug_end "$debug"
exit $?
