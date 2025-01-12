#!/bin/bash

# -----------------------------------------------------------------------------
# @brief Capture and display Wi-Fi details from nmcli using an associative array.
# @details Stores all fields in an associative array, allows selection of a Wi-Fi
#          network using a whiptail menu with radio buttons, and displays the
#          selected network's SSID along with the other details.
#
# @example
# ./wifi_table_whiptail_radio.sh
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Column Positions by Array Index
# -----------------------------------------------------------------------------
# 0   - NAME
# 1   - SSID
# 2   - SSID-HEX
# 3   - BSSID
# 4   - MODE
# 5   - CHAN
# 6   - FREQ
# 7   - RATE
# 8   - SIGNAL
# 9   - BARS
# 10  - SECURITY
# 11  - WPA-FLAGS
# 12  - RSN-FLAGS
# 13  - DEVICE
# 14  - ACTIVE
# 15  - IN-USE
# 16  - DBUS-PATH
# -----------------------------------------------------------------------------

# Capture the output of the updated nmcli command and replace '\:' with '-' for interim processing
wifi_info=$(nmcli -t -f all --color no dev wifi list | sed 's/\\:/-/g')

# Filter out entries with blank SSID
filtered_wifi_info=$(echo "$wifi_info" | awk -F ':' '$2 != ""')

# Convert to array for processing
IFS=$'\n' read -rd '' -a wifi_entries <<<"$filtered_wifi_info"

# Separate headers from the data
header="NAME:SSID:SSID-HEX:BSSID:MODE:CHAN:FREQ:RATE:SIGNAL:BARS:SECURITY:WPA-FLAGS:RSN-FLAGS:DEVICE:ACTIVE:IN-USE:DBUS-PATH"
wifi_entries=("${wifi_entries[@]}")

# Declare an associative array to hold the data
declare -A wifi_data
row_index=0

# Populate the associative array with parsed data
for entry in "${wifi_entries[@]}"; do
    wifi_data["row_$row_index"]="$entry"
    ((row_index++))
done

# Columns to display (selected by zero-based indices)
columns_to_display=(14 15 13 1 4 5 7 10 8 9) # ACTIVE, IN-USE, DEVICE, SSID, MODE, CHAN, RATE, SECURITY, SIGNAL, BARS

# Extract column headers for the selected fields
IFS=":" read -r -a full_headers <<<"$header"
declare -a selected_headers
for index in "${columns_to_display[@]}"; do
    selected_headers+=("${full_headers[index]}")
done

# Prepare an array for the whiptail menu with radio buttons
network_menu=()
for row_key in $(echo "${!wifi_data[@]}" | tr ' ' '\n' | sort -n -t '_' -k 2); do
    IFS=":" read -r -a fields <<<"${wifi_data[$row_key]}"
    
    # Create a formatted string with all selected columns
    display_string="${fields[14]}  ${fields[15]}  ${fields[13]}  ${fields[1]}  ${fields[4]}  ${fields[5]}  ${fields[7]}  ${fields[10]}  ${fields[8]}  ${fields[9]}"

    # Add the formatted string as an option for whiptail radio buttons
    network_menu+=("$row_key" "$display_string" "OFF")
done

# Display whiptail menu with radio buttons
selected_row_key=$(whiptail --title "Select Wi-Fi Network" --radiolist "Choose a Wi-Fi network to connect to:" 15 50 10 "${network_menu[@]}" 3>&1 1>&2 2>&3)

# Display SSID and details of the selected network
if [ $? -eq 0 ]; then
    IFS=":" read -r -a selected_fields <<<"${wifi_data[$selected_row_key]}"
    selected_ssid="${selected_fields[1]}"
    echo "You selected network: $selected_ssid"
    echo "Full details:"
    echo "ACTIVE: ${selected_fields[14]}"
    echo "IN-USE: ${selected_fields[15]}"
    echo "DEVICE: ${selected_fields[13]}"
    echo "SSID: ${selected_fields[1]}"
    echo "MODE: ${selected_fields[4]}"
    echo "CHAN: ${selected_fields[5]}"
    echo "RATE: ${selected_fields[7]}"
    echo "SECURITY: ${selected_fields[10]}"
    echo "SIGNAL: ${selected_fields[8]}"
    echo "BARS: ${selected_fields[9]}"
else
    echo "No network selected." 
fi
