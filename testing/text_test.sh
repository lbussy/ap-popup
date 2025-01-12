#!/bin/bash

# -----------------------------------------------------------------------------
# @brief Capture and display Wi-Fi details from nmcli using an associative array.
# @details Stores all fields in an associative array but displays only selected
#          columns in a neatly formatted table with proper padding.
#
# @example
# ./wifi_table_fixed.sh
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

# Determine maximum width for each selected column (include headers)
num_columns=${#columns_to_display[@]}
declare -a max_widths
for ((i = 0; i < $num_columns; i++)); do
    max_widths[i]=${#selected_headers[i]} # Start with the width of the header
done

# Ensure maximum widths include all rows
for row_key in "${!wifi_data[@]}"; do
    IFS=":" read -r -a fields <<<"${wifi_data[$row_key]}"
    for ((i = 0; i < $num_columns; i++)); do
        column_index=${columns_to_display[i]}
        field_length=${#fields[column_index]}
        if ((field_length > max_widths[i])); then
            max_widths[i]=$field_length
        fi
    done
done

# Print headers
for ((i = 0; i < $num_columns; i++)); do
    printf "%-*s  " "${max_widths[i]}" "${selected_headers[i]}"
done
echo

# Print rows
for row_key in $(echo "${!wifi_data[@]}" | tr ' ' '\n' | sort -n -t '_' -k 2); do
    IFS=":" read -r -a fields <<<"${wifi_data[$row_key]}"

    # Display only selected columns
    for ((i = 0; i < $num_columns; i++)); do
        column_index=${columns_to_display[i]}
        printf "%-*s  " "${max_widths[i]}" "${fields[column_index]}"
    done
    echo
done
