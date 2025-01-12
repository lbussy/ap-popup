#!/bin/bash

# -----------------------------------------------------------------------------
# @brief Display Wi-Fi networks with a 1-based index and allow user selection.
# @details Lists Wi-Fi networks with their details, prepending a 1-based index
#          to the left. The user can select a network by entering the index,
#          and the script returns the SSID of the selected network. Selecting
#          "0" returns a blank value.
#
# @example
# ./wifi_network_selector.sh
# -----------------------------------------------------------------------------

# Global associative array to hold Wi-Fi network data
declare -A wifi_networks

populate_wifi_networks() {
    # Capture the output of nmcli and replace '\:' with '-' for processing
    local wifi_info; 
    wifi_info=$(nmcli -t -f all --color no dev wifi list | sed 's/\\:/-/g')

    # Filter out entries with blank SSID
    local filtered_wifi_info
    filtered_wifi_info=$(echo "$wifi_info" | awk -F ':' '$2 != ""')

    # Convert to array for processing
    IFS=$'\n' read -rd '' -a wifi_entries <<<"$filtered_wifi_info"

    # Populate the global associative array
    local index=1
    for entry in "${wifi_entries[@]}"; do
        wifi_networks[$index]="$entry"
        ((index++))
    done
}

display_wifi_networks() {
    # Define columns to display (selected by zero-based indices)
    local columns_to_display=(1 8 9 10) # SSID, SIGNAL, BARS, SECURITY
    local header="NAME:SSID:SSID-HEX:BSSID:MODE:CHAN:FREQ:RATE:SIGNAL:BARS:SECURITY:WPA-FLAGS:RSN-FLAGS:DEVICE:ACTIVE:IN-USE:DBUS-PATH"

    # Extract column headers for the selected fields
    IFS=":" read -r -a full_headers <<<"$header"
    local selected_headers=()
    for index in "${columns_to_display[@]}"; do
        selected_headers+=("${full_headers[index]}")
    done

    # Determine maximum width for each selected column (include headers)
    local num_columns=${#columns_to_display[@]}
    local max_widths=()
    for ((i = 0; i < num_columns; i++)); do
        max_widths[i]=${#selected_headers[i]} # Start with the width of the header
    done

    # Ensure maximum widths include all rows
    for key in "${!wifi_networks[@]}"; do
        IFS=":" read -r -a fields <<<"${wifi_networks[$key]}"
        for ((i = 0; i < num_columns; i++)); do
            local column_index=${columns_to_display[i]}
            local field_length=${#fields[column_index]}
            if ((field_length > max_widths[i])); then
                max_widths[i]=$field_length
            fi
        done
    done

    # Print headers with index column
    printf "%4s  " "IDX"
    for ((i = 0; i < num_columns; i++)); do
        printf "%-*s  " "${max_widths[i]}" "${selected_headers[i]}"
    done
    echo

    # Print rows with index
    for key in $(printf "%s\n" "${!wifi_networks[@]}" | sort -n); do
        IFS=":" read -r -a fields <<<"${wifi_networks[$key]}"

        # Print index and selected columns
        printf "%4s  " "$key"
        for ((i = 0; i < num_columns; i++)); do
            local column_index=${columns_to_display[i]}
            printf "%-*s  " "${max_widths[i]}" "${fields[column_index]}"
        done
        echo
    done

    # Print the "0" option aligned with the rest
    printf "%4s  %-*s  %-*s  %-*s  %-*s\n" "0" "${max_widths[0]}" "Return blank" "${max_widths[1]}" "" "${max_widths[2]}" "" "${max_widths[3]}" ""
    echo
}

select_wifi_network() {
    # Prompt user for selection
    local choice
    while :; do
        read -rp "Select a network by index (or 0 to return blank): " choice

        # Validate input
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 0 && choice <= ${#wifi_networks[@]})); then
            break
        else
            echo "Invalid selection. Please enter a number between 0 and ${#wifi_networks[@]}." >&2
        fi
    done

    # Return the selected SSID or blank
    if ((choice == 0)); then
        echo ""
    else
        IFS=":" read -r -a selected_fields <<<"${wifi_networks[$choice]}"
        echo "${selected_fields[1]}" # Return the SSID
    fi
}

# Populate the global associative array with Wi-Fi data
populate_wifi_networks

# Display the Wi-Fi networks
display_wifi_networks

# Allow the user to select one
selected_ssid=$(select_wifi_network)
echo -e "\nSelected SSID: $selected_ssid"
