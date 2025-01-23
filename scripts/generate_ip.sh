#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

# -----------------------------------------------------------------------------
# @var THIS_SCRIPT
# @brief The name of the current Bash script.
# @details Automatically determines the name of the script using BASH_SOURCE. 
#          Falls back to a default if BASH_SOURCE is unavailable or empty.
# -----------------------------------------------------------------------------

declare THIS_SCRIPT="${BASH_SOURCE[0]}"
if [[ -z "$THIS_SCRIPT" || "$THIS_SCRIPT" == "bash" ]]; then
    THIS_SCRIPT="${FALLBACK_SCRIPT_NAME:-template.sh}"
fi

declare AP_IP="192.168.50.5/16" # Access Point CIDR
declare AP_GW="192.168.50.254"  # Access Point Gateway

# -----------------------------------------------------------------------------
# @brief Starts the debug process.
# @details This function checks if the "debug" flag is present in the
#          arguments, and if so, prints the debug information including the
#          function name, the caller function name, and the line number where
#          the function was called.
#
# @param "$@" Arguments to check for the "debug" flag.
#
# @return Returns the "debug" flag if present, or an empty string if not.
#
# @example
# debug_start "debug"  # Prints debug information
# debug_start          # Does not print anything, returns an empty string
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# @brief Filters out the "debug" flag from the arguments.
# @details This function removes the "debug" flag from the list of arguments
#          and returns the filtered arguments. The debug flag is not passed
#          to other functions to avoid unwanted debug outputs.
#
# @param "$@" Arguments to filter.
#
# @return Returns a string of filtered arguments, excluding "debug".
#
# @example
# debug_filter "arg1" "debug" "arg2"  # Returns "arg1 arg2"
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# @brief Prints a debug message if the debug flag is set.
# @details This function checks if the "debug" flag is present in the
#          arguments. If the flag is present, it prints the provided debug
#          message along with the function name and line number from which the
#          function was called.
#
# @param "$@" Arguments to check for the "debug" flag and the debug message.
# @global debug A flag to indicate whether debug messages should be printed.
#
# @return None.
#
# @example
# debug_print "debug" "This is a debug message"
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# @brief Ends the debug process.
# @details This function checks if the "debug" flag is present in the
#          arguments. If the flag is present, it prints debug information
#          indicating the exit of the function, along with the function name
#          and line number from where the function was called.
#
# @param "$@" Arguments to check for the "debug" flag.
# @global debug Debug flag, passed from the calling function.
#
# @return None
#
# @example
# debug_end "debug"
# -----------------------------------------------------------------------------
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
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Validates the format and compatibility of a subnet and gateway.
# @details This function checks if the given subnet is in a valid CIDR format
#          and if the gateway IP address falls within the subnet range. It
#          ensures the subnet and gateway configuration is logically correct
#          before applying it.
#
# @param $1 The subnet to validate in CIDR format (e.g., 192.168.1.0/24).
# @param $2 The gateway IP address to validate (e.g., 192.168.1.1).
# @param $@ Debug flag (optional). If "debug" is provided, debug information
#           will be printed.
#
# @global None.
#
# @return 0 if the subnet and gateway are valid.
#         1 if the format is invalid or the gateway does not belong to the subnet.
#
# @example
# validate_subnet "192.168.1.0/24" "192.168.1.1" "debug"
# -----------------------------------------------------------------------------
validate_subnet() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local ip="$1"            # Subnet to validate (CIDR format)
    local gw="$2"            # Gateway IP address to validate
    local retval=0           # Return value (0 for valid, 1 for invalid)

    # Check if the subnet and gateway are in the correct format
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/24$ ]] && [[ "$gw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Extract the network address from the subnet
        local network
        network=$(ipcalc "$ip" | awk '/Network:/ {print $2}')
        
        # Validate if the gateway is within the subnet range
        if [[ "$gw" != "$network"/* ]]; then
            printf "Gateway %s is not within the subnet %s.\n" "$gw" "$ip" >&2
            retval=1
        fi
    else
        printf "Invalid subnet or gateway format.\n" >&2
        retval=1
    fi

    # Ensure cleanup and exit with the appropriate return value
    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Checks for conflicts between the provided subnet and active networks.
# @details This function compares the given subnet against the subnets of all
#          active network interfaces. If a conflict is detected, it reports the
#          conflict and returns an error status. This ensures that the new
#          subnet does not overlap with any existing network.
#
# @param $1 The new subnet for the AP in CIDR format (e.g., 192.168.1.0/24).
# @param $@ Debug flag (optional). If "debug" is provided, debug information
#           will be printed.
#
# @global None.
#
# @return 0 if no conflicts are found.
#         1 if a conflict is detected with an active network.
#
# @example
# validate_network_conflict "192.168.1.0/24" "debug"
# -----------------------------------------------------------------------------
validate_network_conflict() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local new_subnet="$1"     # The subnet to check for conflicts (CIDR format)
    local active_networks     # List of active subnets on the system
    local retval=0            # Return value (0 for no conflict, 1 for conflict)

    # Retrieve a list of active subnets from the system's network interfaces
    active_networks=$(ip -o -f inet addr show | awk '/scope global/ {print $4}')

    # Iterate through each active subnet and check for conflicts
    for net in $active_networks; do
        if [[ "$new_subnet" == "$net" ]]; then
            printf "Conflict detected with active network: %s\n" "$net" >&2
            retval=1
            break  # Exit the loop once a conflict is found
        fi
    done

    # Ensure cleanup and exit with the appropriate return value
    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Validates the Access Point (AP) subnet and gateway configuration.
# @details This function performs multiple validation checks to ensure that the
#          provided subnet and gateway are valid and do not conflict with
#          existing networks or active IP addresses. The function checks for:
#          - Conflicts with active network subnets.
#          - Subnet and gateway format validity.
#          - Whether the gateway IP is already in use.
#
# @param $1 The new subnet for the AP in CIDR format (e.g., 192.168.1.0/24).
# @param $2 The new gateway IP address for the AP (e.g., 192.168.1.1).
# @param $@ Debug flag (optional). If "debug" is provided, debug information
#           will be printed.
#
# @global None.
#
# @return 0 if the configuration is valid.
#         1 if a conflict or validation error occurs.
#
# @example
# validate_ap_configuration "192.168.1.0/24" "192.168.1.1" "debug"
# -----------------------------------------------------------------------------
validate_ap_configuration() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local new_subnet="$1"     # The new subnet for the AP (CIDR format)
    local new_gateway="$2"    # The new gateway IP address for the AP
    local retval=0            # Return value (0 for success, 1 for error)

    # Check for conflicts with active network subnets
    if ! validate_network_conflict "$new_subnet" "$debug"; then
        printf "The selected subnet conflicts with an existing network.\n" >&2
        retval=1
    # Check for validity of the subnet and gateway configuration
    elif ! validate_subnet "$new_subnet" "$new_gateway" "$debug"; then
        printf "Invalid subnet or gateway configuration.\n" >&2
        retval=1
    # Check if the gateway IP is already in use
    elif ping -c 1 -w 1 "${new_gateway%%/*}" &>/dev/null; then
        printf "The gateway %s is already in use.\n" "$new_gateway" >&2
        retval=1
    fi

    # Ensure cleanup and exit with the appropriate return value
    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Updates the Access Point (AP) IP address and network configuration.
# @details This function prompts the user to select an IP address block and
#          construct a new IP address, network, and gateway for the AP. The 
#          function validates the configuration and checks for conflicts or 
#          invalid inputs before applying the changes.
#
# @param $@ Debug flag (optional). If "debug" is provided, debug information
#           will be printed.
#
# @global AP_IP Stores the current AP IP address in CIDR format.
# @global AP_GW Stores the current AP gateway address.
#
# @return 0 if the IP address is successfully updated or the user exits,
#         1 if an error occurs.
#
# @example
# update_ap_ip "debug"
# -----------------------------------------------------------------------------
update_ap_ip() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local base_ip=""          # Base IP address for the selected network block
    local second_octet=""     # Second octet of the IP address
    local third_octet=""      # Third octet of the IP address
    local fourth_octet=""     # Fourth octet of the IP address
    local ip_address=""       # Constructed IP address
    local ip_network=""       # Constructed network address in CIDR format
    local gateway=""          # Constructed gateway address

    clear
    printf "Current AP IP: %s\n" "$AP_IP"
    printf "Current AP GW: %s\n" "$AP_GW"
    printf "\nSelect an IP address block (press Enter to exit):\n\n"
    printf "1   10.0.0.0/8\n"
    printf "2   172.16.0.0/12\n"
    printf "3   192.168.0.0/16\n\n"
    read -n 1 -srp "Enter your choice (1-3): " choice
    printf "\n"

    # Exit if the user presses Enter without making a choice
    [[ -z "$choice" ]] && { debug_end "$debug"; return 0; }

    # Determine the base IP address and valid range based on the user's choice
    case "$choice" in
        1) base_ip="10"; range_msg="(0-255)" ;;       # 10.0.0.0/8 network
        2) base_ip="172"; range_msg="(16-31)" ;;      # 172.16.0.0/12 network
        3) base_ip="192.168"; range_msg="(0-255)" ;;  # 192.168.0.0/16 network
        *) printf "Invalid choice.\n"; debug_end "$debug"; return 1 ;;
    esac

    printf "\nConstruct an IP address for AP within the selected network.\n\n" "$base_ip"
    
    # Prompt for the second octet
    while :; do
        read -rp "Enter the second octet ${range_msg}, or press Enter to exit: " second_octet
        if [[ -z "$second_octet" ]]; then
            debug_end "$debug"
            return 0
        fi
        if [[ "$second_octet" =~ ^[0-9]+$ ]] && [[ "$choice" != 2 || "$second_octet" -ge 16 && "$second_octet" -le 31 ]]; then
            break
        fi
        printf "Invalid input. Please enter a valid octet.\n"
    done

    # Prompt for the third octet (0-255)
    while :; do
        read -rp "Enter the second octet 0-255, or press Enter to exit: " third_octet
        # Exit if the user presses Enter without providing input
        if [[ -z "$third_octet" ]]; then
            debug_end "$debug"
            return 0
        fi
        # Validate the input: Must be a number between 0 and 255
        if [[ "$third_octet" =~ ^[0-9]+$ ]] && (( third_octet >= 0 && third_octet <= 255 )); then
            break  # Valid input, exit the loop
        else
            printf "Invalid input. Please enter a number between 0 and 255.\n" >&2
        fi
    done

    # Prompt for the fourth octet (0-253)
    while :; do
        read -rp "Enter the fourth octet (0-253), or press Enter to exit: " fourth_octet
        # Exit if the user presses Enter without providing input
        if [[ -z "$third_octet" ]]; then
            debug_end "$debug"
            return 0
        fi
        # Validate the input: Must be a number between 0 and 253
        if [[ "$fourth_octet" =~ ^[0-9]+$ ]] && (( fourth_octet >= 0 && fourth_octet <= 253 )); then
            printf "Breaking.\n"
            break  # Valid input, exit the loop
        else
            printf "Invalid input. Please enter a number between 0 and 253.\n" >&2
        fi
    done
    
    printf "Broke out\n"
    debug_end "$debug"

    # Construct the IP address, network, and gateway
    # ip_address="$base_ip.$second_octet.$third_octet.$fourth_octet"
    # ip_network="$base_ip.$second_octet.$third_octet.0/24"
    # gateway="$base_ip.$second_octet.$third_octet.254"

    # # Validate and apply the configuration
    # if validate_ap_configuration "$ip_network" "$gateway" "$debug"; then
    #     printf "\nYour selected IP address: %s\n" "$ip_address"
    #     printf "Your selected IP network: %s\n" "$ip_network"
    #     printf "Gateway for this network: %s\n" "$gateway"
    # else
    #     printf "Configuration validation failed.\n"
    # fi

    #debug_end "$debug"
}

save_config() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    # This is DEBUG only
    printf "\nSaving config.\n"
    printf "AP_IP=%s\n" "$AP_IP"
    printf "AP_GW=%s\n" "$AP_GW"
    debug_end "$debug"
}

_main() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    update_ap_ip
    debug_end "$debug"
}

main() { _main "$@"; return "$?"; }

debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
main "$@" "$debug"
debug_end "$debug"
exit $?
