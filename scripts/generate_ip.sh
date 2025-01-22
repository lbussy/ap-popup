#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

AP_CIDR="192.168.50.5/16"          # Access Point CIDR
AP_GATEWAY="192.168.50.254"        # Access Point Gateway

# -----------------------------------------------------------------------------
# @brief Allows a user to select a base IP block, input custom octets, and 
#        calculates a valid IP address, network, and its gateway.
# @details Prompts the user to select a predefined base IP block, input
#          values for the second, third, and fourth octets based on the network,
#          validates inputs, constructs the final IP address, its network,
#          and the gateway. User can press Enter at any prompt to exit.
#
# @example
# ./script.sh
# -----------------------------------------------------------------------------
generate_ip() {
    local base_ip
    local second_octet
    local third_octet
    local fourth_octet
    local ip_address
    local ip_network
    local gateway

    clear

    # Display current AP configuration
    printf "Current AP IP: %s\n" "$AP_CIDR"
    printf "Current AP GW: %s\n" "$AP_GATEWAY"

    printf "\nSelect an IP address block (press Enter to exit):\n\n"
    printf "1   10.0.0.0/8\n"
    printf "2   172.16.0.0/12\n"
    printf "3   192.168.0.0/16\n\n"
    read -n 1 -sr -p "Enter your choice (1-3): " choice
    printf "%s\n" "$choice"

    # Exit if the user presses Enter without input
    if [[ -z "$choice" ]]; then
        return 0
    fi

    # Determine the base IP address and behavior based on user choice
    case "$choice" in
        1) 
            base_ip="10"
            # Ask for the second, third, and fourth octets
            printf "\nYou will now construct an IP address for the 10.0.0.0/8 network.\n\n"
            while :; do
                read -p "Enter the second octet (0-255, press Enter to exit): " second_octet
                if [[ -z "$second_octet" ]]; then return 0; fi
                if [[ "$second_octet" =~ ^[0-9]+$ ]] && [ "$second_octet" -ge 0 ] && [ "$second_octet" -le 255 ]; then
                    break
                else
                    printf "Invalid input. Please enter a number between 0 and 255.\n"
                fi
            done
            ;;
        2) 
            base_ip="172"
            # Ask for the second octet (16-31), third, and fourth octets
            printf "\nYou will now construct an IP address for the 172.16.0.0/12 network.\n\n"
            while :; do
                read -p "Enter the second octet (16-31, press Enter to exit): " second_octet
                if [[ -z "$second_octet" ]]; then return 0; fi
                if [[ "$second_octet" =~ ^[0-9]+$ ]] && [ "$second_octet" -ge 16 ] && [ "$second_octet" -le 31 ]; then
                    break
                else
                    printf "Invalid input. Please enter a number between 16 and 31.\n"
                fi
            done
            ;;
        3) 
            base_ip="192.168"
            # Ask for the third and fourth octets
            printf "\nYou will now construct an IP address for the 192.168.0.0/16 network.\n\n"
            ;;
        *)
            printf "Invalid choice.\n"
            sleep 2
            return 1
            ;;
    esac

    # Prompt for the third octet (0-255)
    while :; do
        read -p "Enter the third octet (0-255, press Enter to exit): " third_octet
        if [[ -z "$third_octet" ]]; then
            return 0
        elif [[ "$third_octet" =~ ^[0-9]+$ ]] && [ "$third_octet" -ge 0 ] && [ "$third_octet" -le 255 ]; then
            break
        else
            printf "Invalid input. Please enter a number between 0 and 255.\n"
        fi
    done

    # Prompt for the fourth octet (0-253)
    while :; do
        read -p "Enter the fourth octet (0-253, press Enter to exit): " fourth_octet
        if [[ -z "$fourth_octet" ]]; then
            return 0
        elif [[ "$fourth_octet" =~ ^[0-9]+$ ]] && [ "$fourth_octet" -ge 0 ] && [ "$fourth_octet" -le 253 ]; then
            break
        else
            printf "Invalid input. Please enter a number between 0 and 253.\n"
        fi
    done

    # Construct the final IP address, network, and gateway
    if [[ "$choice" -eq 3 ]]; then
        ip_address="$base_ip.$third_octet.$fourth_octet"
        ip_network="$base_ip.$third_octet.0"
        gateway="$base_ip.$third_octet.254"
    else
        ip_address="$base_ip.$second_octet.$third_octet.$fourth_octet"
        ip_network="$base_ip.$second_octet.$third_octet.0"
        gateway="$base_ip.$second_octet.$third_octet.254"
    fi

    printf "\nYour selected IP address: %s\n" "$ip_address"
    printf "Your selected IP network: %s/24\n" "$ip_network"
    printf "Gateway for this network: %s\n" "$gateway"
}

# Example usage
generate_ip
