#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

#########################################################################
# TODO:
#   - Develop man pages
#   - Figure out if we need logging
#   - Setup a New WiFi Network or Change Password fails to register choice
#   - Examine: declare -ar SYSTEM_READS=()
#   - Figure out:
#       - run_ap_popup()
			# echo "Using sudo $sc -a will activate the Access Point regardless of any existing WiFi profile"
			# echo "and stop the timed checks. Use sudo $sc to return to normal use."
			# if [ "$active_ap" = "n" ]; then
			# 	systemctl stop AccessPopup.timer
			# 	start_ap
			# 	exit
			# else
			# 	echo "Access Point $active is already active"
			# 	exit
			# fi
#       - Then:
            # # check if timer is active. Will have been disabled if arg -a used.
            # tup="$(systemctl list-timers AccessPopup.timer | grep 'AccessPopup.timer')"
            # if [ -z "$tup" ];then
            #     systemctl start AccessPopup.timer
            # fi
#       vs
#       - switch_between_wifi_and_ap()
# - Add update from GitHub in menu
#

# -----------------------------------------------------------------------------
# @file apconfig(.sh)
# @brief    Script for managing the AP Pop-Up application.
# @details  This script is installed and run from the /usr/local/sbin/
#           path location. It allows configuration of the functionality
#           managed by AP Pop-Up.
#
# @usage    sudo apconfig <debug>
#
# @author Lee Bussy
# @date January 11, 2025
# @version 1.0.0
#
# @copyright
# This project is open-source and can be modified or distributed under the
# terms of the MIT license.
#
# -----------------------------------------------------------------------------
# @section parameters Parameters
# @optional $1 Turn on verbose debug with the argument "debug"
#
# -----------------------------------------------------------------------------

############
### Global Script Declarations
############

# -----------------------------------------------------------------------------
# @details This script uses configuration variables for setting up the Access
#          Point. Defaults are declared below and can be overridden by sourcing
#          a configuration file (e.g., /etc/appop.conf).
#
# @section Default Variables
# @var WIFI_INTERFACE
# @brief WiFi interface used by the Access Point.
# @details This interface will be configured for the Access Point functionality.
# @default "wlan0"
#
# @var AP_PROFILE_NAME
# @brief Access Point profile name.
# @details The profile name for the Access Point configuration.
# @default "AP_Pop-Up"
#
# @var AP_SSID
# @brief Access Point SSID.
# @details The SSID (network name) broadcasted by the Access Point.
# @default "AP_Pop-Up"
#
# @var AP_PASSWORD
# @brief Access Point password.
# @details The password required to connect to the Access Point. Ensure this
#          value meets your security requirements.
# @default "1234567890"
#
# @var AP_IP
# @brief Access Point CIDR.
# @details The CIDR block used by the Access Point for assigning IP addresses.
# @default "192.168.50.5/16"
#
# @var AP_GW
# @brief Access Point Gateway.
# @details The gateway address for the Access Point.
# @default "192.168.50.254"
#
# @var ENABLE_WIFI
# @brief Enable WiFi automatically if disabled.
# @details Determines whether WiFi should be enabled automatically.
# @default "y"
#
# @note To override these values, source the configuration file at runtime:
#       source /etc/appop.conf
# -----------------------------------------------------------------------------
declare WIFI_INTERFACE="wlan0"      # WiFi interface used by the Access Point
declare AP_PROFILE_NAME="AP_Pop-Up" # Access Point profile name
declare AP_SSID="AP_Pop-Up"         # Access Point SSID
declare AP_PASSWORD="1234567890"    # Access Point password
declare AP_IP="192.168.50.5/16"     # Access Point CIDR
declare AP_GW="192.168.50.254"      # Access Point Gateway
declare ENABLE_WIFI="y"             # Enable WiFi automatically if disabled

# -----------------------------------------------------------------------------
# @var REQUIRE_SUDO
# @brief Indicates whether root privileges are required to run the script.
# @details This variable determines if the script requires execution with root
#          privileges. It defaults to `true`, meaning the script will enforce
#          that it is run with `sudo` or as a root user. This behavior can be
#          overridden by setting the `REQUIRE_SUDO` environment variable to
#          `false`.
#
# @default true
#
# @example
# REQUIRE_SUDO=false ./template.sh  # Run the script without enforcing root
#                                     privileges.
# -----------------------------------------------------------------------------
readonly REQUIRE_SUDO="${REQUIRE_SUDO:-true}"

# -----------------------------------------------------------------------------
# @brief Determines the script name to use.
# @details This block of code determines the value of `THIS_SCRIPT` based on
#          the following logic:
#          1. If `THIS_SCRIPT` is already set in the environment, it is used.
#          2. If `THIS_SCRIPT` is not set, the script checks if
#             `${BASH_SOURCE[0]}` is available:
#             - If `${BASH_SOURCE[0]}` is set and not equal to `"bash"`, the
#               script extracts the filename (without the path) using
#               `basename` and assigns it to `THIS_SCRIPT`.
#             - If `${BASH_SOURCE[0]}` is unbound or equals `"bash"`, it falls
#               back to using the value of `FALLBACK_SCRIPT_NAME`, which
#               defaults to `debug_print.sh`.
#
# @var FALLBACK_SCRIPT_NAME
# @brief Default name for the script in case `BASH_SOURCE[0]` is unavailable.
# @details This variable is used as a fallback value if `BASH_SOURCE[0]` is
#          not set or equals `"bash"`. The default value is `"debug_print.sh"`.
#
# @var THIS_SCRIPT
# @brief Holds the name of the script to use.
# @details The script attempts to determine the name of the script to use. If
#          `THIS_SCRIPT` is already set in the environment, it is used
#          directly. Otherwise, the script tries to extract the filename from
#          `${BASH_SOURCE[0]}` (using `basename`). If that fails, it defaults
#          to `FALLBACK_SCRIPT_NAME`.
# -----------------------------------------------------------------------------
declare FALLBACK_SCRIPT_NAME="${FALLBACK_SCRIPT_NAME:-apconfig.sh}"
if [[ -z "${THIS_SCRIPT:-}" ]]; then
    if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]:-}" != "bash" ]]; then
        # Use BASH_SOURCE[0] if it is available and not "bash"
        THIS_SCRIPT=$(basename "${BASH_SOURCE[0]}")
    else
        # If BASH_SOURCE[0] is unbound or equals "bash", use
        # FALLBACK_SCRIPT_NAME
        THIS_SCRIPT="${FALLBACK_SCRIPT_NAME}"
    fi
fi

# TODO
declare REPO_ORG="${REPO_ORG:-lbussy}"
declare REPO_NAME="${REPO_NAME:-ap-popup}"
declare REPO_DISPLAY_NAME="${REPO_DISPLAY_NAME:-AP Pop-Up}"
declare REPO_BRANCH="${REPO_BRANCH:-test_apconfig}"
declare GIT_TAG="${GIT_TAG:-1.0.0}"
declare SEM_VER="${SEM_VER:-${GIT_TAG}-${REPO_BRANCH}}"
declare GIT_RAW="${GIT_RAW:-"https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"}"
readonly APP_NAME="${APP_NAME:-appop}"
readonly CONFIG_FILE="/etc/$APP_NAME.conf"

# -----------------------------------------------------------------------------
# Declare Menu Variables
# -----------------------------------------------------------------------------
declare -A MENU_ITEMS       # Associative array of menu items
declare -a MAIN_MENU        # Array defining the main menu screen
declare MENU_HEADER="${MENU_HEADER:-$REPO_DISPLAY_NAME Controller Menu}"  # Global menu header

# -----------------------------------------------------------------------------
# Declare Usage Variables
# -----------------------------------------------------------------------------
declare OPTIONS_LIST=()     # List of -f--fl arguemtns for command line parsing

# -----------------------------------------------------------------------------
# @var MIN_BASH_VERSION
# @brief Specifies the minimum supported Bash version.
# @details Defines the minimum Bash version required to execute the script. By
#          default, it is set to `4.0`. This value can be overridden by setting
#          the `MIN_BASH_VERSION` environment variable before running the
#          script.
#          To disable version checks entirely, set this variable to `"none"`.
#
# @default "4.0"
#
# @example
# MIN_BASH_VERSION="none" ./template.sh  # Disable Bash version checks.
# MIN_BASH_VERSION="5.0" ./template.sh   # Require at least Bash 5.0.
# -----------------------------------------------------------------------------
readonly MIN_BASH_VERSION="${MIN_BASH_VERSION:-4.0}"

# -----------------------------------------------------------------------------
# @var MIN_OS
# @brief Specifies the minimum supported OS version.
# @details Defines the lowest OS version that the script supports. This value
#          should be updated as compatibility requirements evolve. It is used
#          to ensure the script is executed only on compatible systems.
#
# @default 11
#
# @example
# if [[ "$CURRENT_OS_VERSION" -lt "$MIN_OS" ]]; then
#     echo "This script requires OS version $MIN_OS or higher."
#     exit 1
# fi
# -----------------------------------------------------------------------------
readonly MIN_OS="${MIN_OS:-11}"

# -----------------------------------------------------------------------------
# @var MAX_OS
# @brief Specifies the maximum supported OS version.
# @details Defines the highest OS version that the script supports. If the
#          script is executed on a system with an OS version higher than this
#          value, it may not function as intended. Set this to `-1` to indicate
#          no upper limit on supported OS versions.
#
# @default 15
#
# @example
# if [[ "$CURRENT_OS_VERSION" -gt "$MAX_OS" && "$MAX_OS" -ne -1 ]]; then
#     echo "This script supports OS versions up to $MAX_OS."
#     exit 1
# fi
# -----------------------------------------------------------------------------
readonly MAX_OS="${MAX_OS:-15}"  # (use -1 for no upper limit)

# -----------------------------------------------------------------------------
# @var DEPENDENCIES
# @type array
# @brief List of required external commands for the script.
# @details This array defines the external commands that the script depends on
#          to function correctly. Each command in this list is checked for
#          availability at runtime. If a required command is missing, the script
#          may fail or display an error message.
#
#          Best practices:
#          - Ensure all required commands are included.
#          - Use a dependency-checking function to verify their presence early
#            in the script.
#
# @default
# A predefined set of common system utilities
#
# @note Update this list as needed to reflect the actual commands used in the script.
#
# @example
# for cmd in "${DEPENDENCIES[@]}"; do
#     if ! command -v "$cmd" &>/dev/null; then
#         echo "Error: Missing required command: $cmd"
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
declare -ar DEPENDENCIES=(
    "awk"
    "grep"
    "tput"
    "cut"
    "tr"
    "getconf"
    "cat"
    "sed"
    "basename"
    "getent"
    "date"
    "printf"
    "whoami"
    "touch"
    "dpkg"
    "git"
    "dpkg-reconfigure"
    "curl"
    "wget"
    "realpath"
)
readonly DEPENDENCIES

# -----------------------------------------------------------------------------
# @var ENV_VARS_BASE
# @type array
# @brief Base list of required environment variables.
# @details Defines the core environment variables that the script relies on,
#          regardless of the runtime context. These variables must be set to
#          ensure the script functions correctly.
#
#          - `HOME`: Specifies the home directory of the current user.
#          - `COLUMNS`: Defines the width of the terminal, used for formatting.
#          - `SUDO_USER`: Identifies the user who invoked the script with sudo.
#
# @example
# for var in "${ENV_VARS_BASE[@]}"; do
#     if [[ -z "${!var}" ]]; then
#         echo "Error: Required environment variable '$var' is not set."
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
declare -ar ENV_VARS=(
    "SUDO_USER"  # Identifies the user who invoked the script using `sudo`.
    "HOME"       # Home directory of the current user
    "COLUMNS"    # Terminal width for formatting, often dynamic in the OS
)

# -----------------------------------------------------------------------------
# @var COLUMNS
# @brief Terminal width in columns.
# @details The `COLUMNS` variable represents the width of the terminal in
#          characters. It is used for formatting output to fit within the
#          terminal's width. If not already set by the environment, it defaults
#          to `80` columns. This value can be overridden externally by setting
#          the `COLUMNS` environment variable before running the script.
#
# @default 80
#
# @example
# echo "The terminal width is set to $COLUMNS columns."
# -----------------------------------------------------------------------------
COLUMNS="${COLUMNS:-80}"

# -----------------------------------------------------------------------------
# @var SYSTEM_READS
# @type array
# @brief List of critical system files to check.
# @details Defines the absolute paths to system files that the script depends on
#          for its execution. These files must be present and readable to ensure
#          the script operates correctly. The following files are included:
#          - `/etc/os-release`: Contains operating system identification data.
#          - `/proc/device-tree/compatible`: Identifies hardware compatibility,
#            commonly used in embedded systems like Raspberry Pi.
#
# @example
# for file in "${SYSTEM_READS[@]}"; do
#     if [[ ! -r "$file" ]]; then
#         echo "Error: Required system file '$file' is missing or not readable."
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
declare -ar SYSTEM_READS=(
    "/etc/os-release"               # OS identification file
    "/proc/device-tree/compatible"  # Hardware compatibility file
)
readonly SYSTEM_READS

# -----------------------------------------------------------------------------
# @var WARN_STACK_TRACE
# @type string
# @brief Flag to enable stack trace logging for warnings.
# @details Controls whether stack traces are printed alongside warning
#          messages. This feature is particularly useful for debugging and
#          tracking the script's execution path in complex workflows.
#
#          Possible values:
#          - `"true"`: Enables stack trace logging for warnings.
#          - `"false"`: Disables stack trace logging for warnings (default).
#
# @default "false"
#
# @example
# WARN_STACK_TRACE=true ./template.sh  # Enable stack traces for warnings.
# WARN_STACK_TRACE=false ./template.sh # Disable stack traces for warnings.
# -----------------------------------------------------------------------------
readonly WARN_STACK_TRACE="${WARN_STACK_TRACE:-false}"

############
### Template Functions
############

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
}

# -----------------------------------------------------------------------------
# @brief Prints a stack trace with optional formatting and a message.
# @details This function generates and displays a formatted stack trace for
#          debugging purposes. It includes a log level and optional details,
#          with color-coded formatting and proper alignment.
#
# @param $1 [optional] Log level (DEBUG, INFO, WARN, ERROR, CRITICAL).
#           Defaults to INFO.
# @param $2 [optional] Primary message for the stack trace.
# @param $@ [optional] Additional context or details for the stack trace.
#
# @global FUNCNAME Array of function names in the call stack.
# @global BASH_LINENO Array of line numbers corresponding to the call stack.
# @global THIS_SCRIPT The name of the current script, used for logging.
# @global COLUMNS Console width, used for formatting output.
#
# @throws None.
#
# @return None. Outputs the stack trace and message to standard output.
#
# @example
# stack_trace WARN "Unexpected condition detected."
# -----------------------------------------------------------------------------
stack_trace() {
    # Determine log level and message
    local level="${1:-INFO}"
    local message=""
    # Block width and character for header/footer
    local char="-"

    # Recalculate terminal columns
    COLUMNS=$( (command -v tput >/dev/null && tput cols) || printf "80")
    COLUMNS=$((COLUMNS > 0 ? COLUMNS : 80)) # Ensure COLUMNS is a positive number
    local width
    width=${COLUMNS:-80}                    # Max console width

    # Check if $1 is a valid level, otherwise treat it as the message
    case "$level" in
        DEBUG|INFO|WARN|WARNING|ERROR|CRIT|CRITICAL)
            shift
            ;;
        *)
            message="$level"
            level="INFO"
            shift
            ;;
    esac

    # Concatenate all remaining arguments into $message
    for arg in "$@"; do
        message+="$arg "
    done
    # Trim leading/trailing whitespace
    message=$(printf "%s" "$message" | xargs)

    # Define functions to skip
    local skip_functions=("die" "warn" "stack_trace")
    local encountered_main=0 # Track the first occurrence of main()

    # Generate title case function name for the banner
    local raw_function_name="${FUNCNAME[0]}"
    local header_name header_level
    header_name=$(printf "%s" "$raw_function_name" | sed -E 's/_/ /g; s/\b(.)/\U\1/g; s/(\b[A-Za-z])([A-Za-z]*)/\1\L\2/g')
    header_level=$(printf "%s" "$level" | sed -E 's/\b(.)/\U\1/g; s/(\b[A-Za-z])([A-Za-z]*)/\1\L\2/g')
    header_name="$header_level $header_name"

    # Helper: Skip irrelevant functions
    should_skip() {
        local func="$1"
        for skip in "${skip_functions[@]}"; do
            if [[ "$func" == "$skip" ]]; then
                return 0
            fi
        done
        if [[ "$func" == "main" && $encountered_main -gt 0 ]]; then
            return 0
        fi
        [[ "$func" == "main" ]] && ((encountered_main++))
        return 1
    }

    # Build the stack trace
    local displayed_stack=()
    local longest_length=0
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
        local func="${FUNCNAME[i]}"
        local line="${BASH_LINENO[i - 1]}"
        local current_length=${#func}

        if should_skip "$func"; then
            continue
        elif (( current_length > longest_length )); then
            longest_length=$current_length
        fi

        displayed_stack=("$(printf "%s|%s" "$func()" "$line")" "${displayed_stack[@]}")
    done

    # General text attributes
    local reset="\033[0m"     # Reset text formatting
    local bold="\033[1m"      # Bold text

    # Foreground colors
    local fgred="\033[31m"    # Red text
    local fggrn="\033[32m"    # Green text
    # shellcheck disable=SC2034
    local fgylw="\033[33m"    # Yellow text
    local fgblu="\033[34m"    # Blue text
    local fgmag="\033[35m"    # Magenta text
    local fgcyn="\033[36m"    # Cyan text
    local fggld="\033[38;5;220m"  # Gold text (ANSI 256 color)

    # Determine color and label based on level
    local color label
    case "$level" in
        DEBUG) color=$fgcyn; label="[DEBUG]";;
        INFO) color=$fggrn; label="[INFO ]";;
        WARN|WARNING) color=$fggld; label="[WARN ]";;
        ERROR) color=$fgmag; label="[ERROR]";;
        CRIT|CRITICAL) color=$fgred; label="[CRIT ]";;
    esac

    # Create header and footer
    local dash_count=$(( (width - ${#header_name} - 2) / 2 ))
    local header_l header_r
    header_l="$(printf '%*s' "$dash_count" '' | tr ' ' "$char")"
    header_r="$header_l"
    [[ $(( (width - ${#header_name}) % 2 )) -eq 1 ]] && header_r="${header_r}${char}"
    local header
    header=$(printf "%b%s%b %b%b%s%b %b%s%b" \
        "$color" \
        "$header_l" \
        "$reset" \
        "$color" \
        "$bold" \
        "$header_name" \
        "$reset" \
        "$color" \
        "$header_r" \
        "$reset")
    local footer line
    # Generate the repeated character string
    line="$(printf '%*s' "$width" '' | tr ' ' "$char")"
    # Construct the footer
    footer="$(printf '%b%s%b' "$color" "$line" "$reset")"

    # Print header
    printf "%s\n" "$header"

    # Print the message, if provided
    if [[ -n "$message" ]]; then
        # Fallback mechanism for wrap_messages
        local result primary overflow secondary
        if command -v wrap_messages >/dev/null 2>&1; then
            result=$(wrap_messages "$width" "$message" || true)
            primary="${result%%"${delimiter}"*}"
            result="${result#*"${delimiter}"}"
            overflow="${result%%"${delimiter}"*}"
        else
            primary="$message"
        fi
        # Print the formatted message
        printf "%b%s%b\n" "${color}" "${primary}" "${reset}"
        printf "%b%s%b\n" "${color}" "${overflow}" "${reset}"
    fi

    # Print stack trace
    local indent=$(( (width / 2) - ((longest_length + 28) / 2) ))
    indent=$(( indent < 0 ? 0 : indent ))
    if [[ -z "${displayed_stack[*]}" ]]; then
        printf "%b[WARN ]%b Stack trace is empty.\n" "$fggld" "$reset" >&2
    else
        for ((i = ${#displayed_stack[@]} - 1, idx = 0; i >= 0; i--, idx++)); do
            IFS='|' read -r func line <<< "${displayed_stack[i]}"
            printf "%b%*s [%d] Function: %-*s Line: %4s%b\n" \
                "$color" "$indent" ">" "$idx" "$((longest_length + 2))" "$func" "$line" "$reset"
        done
    fi

    # Print footer
    printf "%s\n\n" "$footer"
}

# -----------------------------------------------------------------------------
# @brief Logs a warning message with optional details and stack trace.
# @details This function logs a warning message with color-coded formatting
#          and optional details. It adjusts the output to fit within the
#          terminal's width and supports message wrapping if the
#          `wrap_messages` function is available. If `WARN_STACK_TRACE` is set
#          to `true`, a stack trace is also logged.
#
# @param $1 [Optional] The primary warning message. Defaults to
#                      "A warning was raised on this line" if not provided.
# @param $@ [Optional] Additional details to include in the warning message.
#
# @global FALLBACK_SCRIPT_NAME The name of the script to use if the script
#                              name cannot be determined.
# @global FUNCNAME             Bash array containing the function call stack.
# @global BASH_LINENO          Bash array containing the line numbers of
#                              function calls in the stack.
# @global WRAP_DELIMITER       The delimiter used for separating wrapped
#                              message parts.
# @global WARN_STACK_TRACE     If set to `true`, a stack trace will be logged.
# @global COLUMNS              The terminal's column width, used to format
#                              the output.
#
# @return None.
#
# @example
# warn "Configuration file missing." "Please check /etc/config."
# warn "Invalid syntax in the configuration file."
#
# @note This function requires `tput` for terminal width detection and ANSI
#       formatting, with fallbacks for minimal environments.
# -----------------------------------------------------------------------------
warn() {
    # Initialize variables
    local script="${FALLBACK_SCRIPT_NAME:-unknown}"  # This script's name
    local func_name="${FUNCNAME[1]:-main}"          # Calling function
    local caller_line=${BASH_LINENO[0]:-0}          # Calling line

    # Get valid error code
    local error_code
    if [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
        error_code=$((10#$1))  # Convert to numeric
        shift
    else
        error_code=1  # Default to 1 if not numeric
    fi

    # Configurable delimiter
    local delimiter="${WRAP_DELIMITER:-␞}"

    # Get the primary message
    local message
    message=$(sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "${1:-A warning was raised on this line}")
    [[ $# -gt 0 ]] && shift

    # Process details
    local details
    details=$(sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "$*")

    # Recalculate terminal columns
    COLUMNS=$( (command -v tput >/dev/null && tput cols) || printf "80")
    COLUMNS=$((COLUMNS > 0 ? COLUMNS : 80)) # Ensure COLUMNS is a positive number
    local width
    width=${COLUMNS:-80}                    # Max console width

    # Escape sequences for colors and attributes
    local reset="\033[0m"           # Reset text
    local bold="\033[1m"            # Bold text
    local fggld="\033[38;5;220m"    # Gold text
    local fgcyn="\033[36m"          # Cyan text
    local fgblu="\033[34m"          # Blue text

    # Format prefix
    format_prefix() {
        local color=${1:-"\033[0m"}
        local label="${2:-'[WARN ] [unknown:main:0]'}"
        # Create prefix
        printf "%b%b%s%b %b[%s:%s:%s]%b " \
            "${bold}" \
            "${color}" \
            "${label}" \
            "${reset}" \
            "${bold}" \
            "${script}" \
            "${func_name}" \
            "${caller_line}" \
            "${reset}"
    }

    # Generate prefixes
    local warn_prefix extd_prefix dets_prefix
    warn_prefix=$(format_prefix "$fggld" "[WARN ]")
    extd_prefix=$(format_prefix "$fgcyn" "[EXTND]")
    dets_prefix=$(format_prefix "$fgblu" "[DETLS]")

    # Strip ANSI escape sequences for length calculation
    local plain_warn_prefix adjusted_width
    plain_warn_prefix=$(printf "%s" "$warn_prefix" | sed -E 's/(\x1b\[[0-9;]*[a-zA-Z]|\x1b\([a-zA-Z])//g; s/^[[:space:]]*//; s/[[:space:]]*$//')
    adjusted_width=$((width - ${#plain_warn_prefix} - 1))

    # Fallback mechanism for `wrap_messages`
    local result primary overflow secondary
    if command -v wrap_messages >/dev/null 2>&1; then
        result=$(wrap_messages "$adjusted_width" "$message" "$details" || true)
        primary="${result%%"${delimiter}"*}"
        result="${result#*"${delimiter}"}"
        overflow="${result%%"${delimiter}"*}"
        secondary="${result#*"${delimiter}"}"
    else
        primary="$message"
        overflow=""
        secondary="$details"
    fi

    # Print the primary message
    printf "%s%s\n" "$warn_prefix" "$primary" >&2

    # Print overflow lines
    if [[ -n "$overflow" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$extd_prefix" "$line" >&2
        done <<< "$overflow"
    fi

    # Print secondary details
    if [[ -n "$secondary" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$dets_prefix" "$line" >&2
        done <<< "$secondary"
    fi

    # Execute stack trace if WARN_STACK_TRACE is enabled
    if [[ "${WARN_STACK_TRACE:-false}" == "true" ]]; then
        stack_trace "WARNING" "${message}" "${secondary}"
    fi
}

# -----------------------------------------------------------------------------
# @brief Terminates the script with a critical error message.
# @details This function is used to log a critical error message with optional
#          details and exit the script with the specified error code. It
#          supports formatting the output with ANSI color codes, dynamic
#          column widths, and optional multi-line message wrapping.
#
#          If the optional `wrap_messages` function is available, it will be
#          used to wrap and combine messages. Otherwise, the function falls
#          back to printing the primary message and details as-is.
#
# @param $1 [optional] Numeric error code. Defaults to 1.
# @param $2 [optional] Primary error message. Defaults to "Critical error".
# @param $@ [optional] Additional details to include in the error message.
#
# @global FALLBACK_SCRIPT_NAME The script name to use as a fallback.
# @global FUNCNAME             Bash array containing the call stack.
# @global BASH_LINENO          Bash array containing line numbers of the stack.
# @global WRAP_DELIMITER       Delimiter used when combining wrapped messages.
# @global COLUMNS              The terminal's column width, used to adjust
#                              message formatting.
#
# @return None. This function does not return.
# @exit Exits the script with the specified error code.
#
# @example
# die 127 "File not found" "Please check the file path and try again."
# die "Critical configuration error"
# -----------------------------------------------------------------------------
die() {
    # Initialize variables
    local script="${FALLBACK_SCRIPT_NAME:-unknown}"  # This script's name
    local func_name="${FUNCNAME[1]:-main}"          # Calling function
    local caller_line=${BASH_LINENO[0]:-0}          # Calling line

    # Get valid error code
    if [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
        error_code=$((10#$1))  # Convert to numeric
        shift
    else
        error_code=1  # Default to 1 if not numeric
    fi

    # Configurable delimiter
    local delimiter="${WRAP_DELIMITER:-␞}"

    # Process the primary message
    local message
    message=$(sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "${1:-Critical error}")

    # Only shift if there are remaining arguments
    [[ $# -gt 0 ]] && shift

    # Process details
    local details
    details=$(sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//' <<< "$*")

    # Recalculate terminal columns
    COLUMNS=$( (command -v tput >/dev/null && tput cols) || printf "80")
    COLUMNS=$((COLUMNS > 0 ? COLUMNS : 80)) # Ensure COLUMNS is a positive number
    local width
    width=${COLUMNS:-80}                    # Max console width

    # Escape sequences as safe(r) alternatives to global tput values
    # General attributes
    local reset="\033[0m"
    local bold="\033[1m"
    # Foreground colors
    local fgred="\033[31m" # Red text
    local fgcyn="\033[36m" # Cyan text
    local fgblu="\033[34m" # Blue text

    # Format prefix
    format_prefix() {
        local color=${1:-"\033[0m"}
        local label="${2:-'[CRIT ] [unknown:main:0]'}"
        # Create prefix
        printf "%b%b%s%b %b[%s:%s:%s]%b " \
            "${bold}" \
            "${color}" \
            "${label}" \
            "${reset}" \
            "${bold}" \
            "${script}" \
            "${func_name}" \
            "${caller_line}" \
            "${reset}"
    }

    # Generate prefixes
    local crit_prefix extd_prefix dets_prefix
    crit_prefix=$(format_prefix "$fgred" "[CRIT ]")
    extd_prefix=$(format_prefix "$fgcyn" "[EXTND]")
    dets_prefix=$(format_prefix "$fgblu" "[DETLS]")

    # Strip ANSI escape sequences for length calculation
    local plain_crit_prefix adjusted_width
    plain_crit_prefix=$(printf "%s" "$crit_prefix" | sed -E 's/(\x1b\[[0-9;]*[a-zA-Z]|\x1b\([a-zA-Z])//g; s/^[[:space:]]*//; s/[[:space:]]*$//')
    adjusted_width=$((width - ${#plain_crit_prefix} - 1))

    # Fallback mechanism for `wrap_messages` since it is external
    local result primary overflow secondary
    if command -v wrap_messages >/dev/null 2>&1; then
        result=$(wrap_messages "$adjusted_width" "$message" "$details" || true)
        primary="${result%%"${delimiter}"*}"
        result="${result#*"${delimiter}"}"
        overflow="${result%%"${delimiter}"*}"
        secondary="${result#*"${delimiter}"}"
    else
        primary="$message"
        overflow=""
        secondary="$details"
    fi

    # Print the primary message
    printf "%s%s\n" "$crit_prefix" "$primary" >&2

    # Print overflow lines
    if [[ -n "$overflow" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$extd_prefix" "$line" >&2
        done <<< "$overflow"
    fi

    # Print secondary details
    if [[ -n "$secondary" ]]; then
        while IFS= read -r line; do
            printf "%s%s\n" "$dets_prefix" "$line" >&2
        done <<< "$secondary"
    fi

    # Execute stack trace
    stack_trace "CRITICAL" "${message}" "${secondary}"

    # Exit with the specified error code
    exit "$error_code"
}

# -----------------------------------------------------------------------------
# @brief Add a dot (`.`) at the beginning of a string if it's missing.
# @details This function ensures the input string starts with a leading dot.
#          If the input string is empty, the function logs a warning and
#          returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string with a leading dot if it was missing.
# @retval 1 If the input string is empty.
#
# @example
# add_dot "example"   # Outputs ".example"
# add_dot ".example"  # Outputs ".example"
# add_dot ""          # Logs a warning and returns an error.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
add_dot() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "Input to add_dot cannot be empty."
            debug_end "$debug"
        return 1
    fi

    # Add a leading dot if it's missing
    if [[ "$input" != .* ]]; then
        input=".$input"
    fi

    debug_end "$debug"
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Removes a leading dot from the input string, if present.
# @details This function checks if the input string starts with a dot (`.`)
#          and removes it. If the input is empty, an error message is logged.
#          The function handles empty strings by returning an error and logging
#          an appropriate warning message.
#
# @param $1 [required] The input string to process.
#
# @return 0 on success, 1 on failure (when the input is empty).
#
# @example
# remove_dot ".hidden"  # Output: "hidden"
# remove_dot "visible"  # Output: "visible"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
remove_dot() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "ERROR" "Input to remove_dot cannot be empty."
        debug_end "$debug"
        return 1
    fi

    # Remove the leading dot if present
    if [[ "$input" == *. ]]; then
        input="${input#.}"
    fi

    debug_end "$debug"
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Adds a period to the end of the input string if it doesn't already
#        have one.
# @details This function checks if the input string has a trailing period.
#          If not, it appends one. If the input is empty, an error is logged.
#
# @param $1 [required] The input string to process.
#
# @return The input string with a period added at the end (if missing).
# @return 1 If the input string is empty.
#
# @example
# result=$(add_period "Hello")
# echo "$result"  # Output: "Hello."
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
add_period() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "Input to add_period cannot be empty."
        debug_end "$debug" # Next line must be a return/print/exit
        return 1
    fi

    # Add a trailing period if it's missing
    if [[ "$input" != *. ]]; then
        input="$input."
    fi

    debug_end "$debug"
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Remove a trailing period (`.`) from a string if present.
# @details This function processes the input string and removes a trailing
#          period if it exists. If the input string is empty, the function logs
#          an error and returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string without a trailing period if one was
#         present.
# @retval 1 If the input string is empty.
#
# @example
# remove_period "example."  # Outputs "example"
# remove_period "example"   # Outputs "example"
# remove_period ""          # Logs an error and returns an error code.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
remove_period() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input=${1:-}  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "ERROR" "Input to remove_period cannot be empty."
            debug_end "$debug"
        return 1
    fi

    # Remove the trailing period if present
    if [[ "$input" == *. ]]; then
        input="${input%.}"
    fi

    debug_end "$debug"
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Add a trailing slash (`/`) to a string if it's missing.
# @details This function ensures that the input string ends with a trailing
#          slash. If the input string is empty, the function logs an error and
#          returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string with a trailing slash if one was missing.
# @retval 1 If the input string is empty.
#
# @example
# add_slash "/path/to/directory"  # Outputs "/path/to/directory/"
# add_slash "/path/to/directory/" # Outputs "/path/to/directory/"
# add_slash ""                    # Logs an error and returns an error code.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
add_slash() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to add_slash cannot be empty."
            debug_end "$debug"
        return 1
    fi

    # Add a trailing slash if it's missing
    if [[ "$input" != */ ]]; then
        input="$input/"
    fi

    debug_end "$debug"
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Remove a trailing slash (`/`) from a string if present.
# @details This function ensures that the input string does not end with a
#          trailing slash. If the input string is empty, the function logs an
#          error and returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string without a trailing slash if one was
#         present.
# @retval 1 If the input string is empty.
#
# @example
# remove_slash "/path/to/directory/"  # Outputs "/path/to/directory"
# remove_slash "/path/to/directory"   # Outputs "/path/to/directory"
# remove_slash ""                     # Logs an error and returns an error code
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
remove_slash() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to remove_slash cannot be empty."
            debug_end "$debug"
        return 1
    fi

    # Remove the trailing slash if present
    if [[ "$input" == */ ]]; then
        input="${input%/}"
    fi

    debug_end "$debug"
    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Pauses execution and waits for user input to continue.
# @details This function displays a message prompting the user to press any key
#          to continue. It waits for a key press, then resumes execution.
#
# @example
# pause
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
pause() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    printf "Press any key to continue.\n"
    read -n 1 -sr key || true
    printf "\n"
    debug_print "$key" "$debug"

    debug_end "$debug"
    return 0
}

############
### Print/Display Environment Functions
############

# -----------------------------------------------------------------------------
# @brief Print the script version and optionally log it.
# @details This function displays the version of the script stored in the global
#          variable `SEM_VER`. If called by `process_args`, it uses `printf` to
#          display the version; otherwise, it logs the version using `logI`.
#          If the debug flag is set to "debug," additional debug information
#          will be printed.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global THIS_SCRIPT The name of the script.
# @global SEM_VER The version of the script.
# @global REPO_NAME The name of the repository.
#
# @return None
#
# @example
# print_version debug
# -----------------------------------------------------------------------------
print_version() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Check the name of the calling function
    local caller="${FUNCNAME[1]}"

    if [[ "$caller" == "process_args" ]]; then
        printf "%s: version %s\n" "$THIS_SCRIPT" "$SEM_VER" # Display the script name and version
    fi

    debug_end "$debug"
    return 0
}

############
### Check Environment Functions
############

# -----------------------------------------------------------------------------
# @brief Enforce that the script is run directly with `sudo`.
# @details Ensures the script is executed with `sudo` privileges and not:
#          - From a `sudo su` shell.
#          - As the root user directly.
#
# @global REQUIRE_SUDO Boolean indicating if `sudo` is required.
# @global SUDO_USER User invoking `sudo`.
# @global SUDO_COMMAND The command invoked with `sudo`.
# @global THIS_SCRIPT Name of the current script.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return None
# @exit 1 if the script is not executed correctly.
#
# @example
# enforce_sudo debug
# -----------------------------------------------------------------------------
enforce_sudo() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    if [[ "$REQUIRE_SUDO" == true ]]; then
        if [[ "$EUID" -eq 0 && -n "$SUDO_USER" && "$SUDO_COMMAND" == *"$0"* ]]; then
            debug_print "Sudo conditions met. Proceeding." "$debug"
            # Script is properly executed with `sudo`
        elif [[ "$EUID" -eq 0 && -n "$SUDO_USER" ]]; then
            debug_print "Script run from a root shell. Exiting." "$debug"
            die 1 "This script should not be run from a root shell." \
                  "Run it with 'sudo $THIS_SCRIPT' as a regular user."
        elif [[ "$EUID" -eq 0 ]]; then
            debug_print "Script run as root. Exiting." "$debug"
            die 1 "This script should not be run as the root user." \
                  "Run it with 'sudo $THIS_SCRIPT' as a regular user."
        else
            debug_print "Script not run with sudo. Exiting." "$debug"
            die 1 "This script requires 'sudo' privileges." \
                  "Please re-run it using 'sudo $THIS_SCRIPT'."
        fi
    fi

    debug_print "Function parameters:" \
        "\n\t- REQUIRE_SUDO='${REQUIRE_SUDO:-(not set)}'" \
        "\n\t- EUID='$EUID'" \
        "\n\t- SUDO_USER='${SUDO_USER:-(not set)}'" \
        "\n\t- SUDO_COMMAND='${SUDO_COMMAND:-(not set)}'" "$debug"

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check for required dependencies and report any missing ones.
# @details Iterates through the dependencies listed in the global array
#          `DEPENDENCIES`, checking if each one is installed. Logs missing
#          dependencies and exits the script with an error code if any are
#          missing.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global DEPENDENCIES Array of required dependencies.
#
# @return None
# @exit 1 if any dependencies are missing.
#
# @example
# validate_depends debug
# -----------------------------------------------------------------------------
validate_depends() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Declare local variables
    local missing=0  # Counter for missing dependencies
    local dep        # Iterator for dependencies

    # Iterate through dependencies
    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            warn "Missing dependency: $dep"
            ((missing++))
            debug_print "Missing dependency: $dep" "$debug"
        else
            debug_print "Found dependency: $dep" "$debug"
        fi
    done

    # Handle missing dependencies
    if ((missing > 0)); then
            debug_end "$debug"
        die 1 "Missing $missing dependencies. Install them and re-run the script."
    fi

    debug_print "All dependencies are present." "$debug"

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check the availability of critical system files.
# @details Verifies that each file listed in the `SYSTEM_READS` array exists
#          and is readable. Logs an error for any missing or unreadable files
#          and exits the script if any issues are found.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global SYSTEM_READS Array of critical system file paths to check.
#
# @return None
# @exit 1 if any required files are missing or unreadable.
#
# @example
# validate_sys_accs debug
# -----------------------------------------------------------------------------
validate_sys_accs() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Declare local variables
    local missing=0  # Counter for missing or unreadable files
    local file       # Iterator for files

    # Iterate through system files
    for file in "${SYSTEM_READS[@]}"; do
        if [[ ! -r "$file" ]]; then
            warn "Missing or unreadable file: $file"
            ((missing++))
            debug_print "Missing or unreadable file: $file" "$debug"
        else
            debug_print "File is accessible: $file" "$debug"
        fi
    done

    # Handle missing files
    if ((missing > 0)); then
            debug_end "$debug"
        die 1 "Missing or unreadable $missing critical system files."
    fi

    debug_print "All critical system files are accessible." "$debug"

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Validate the existence of required environment variables.
# @details Checks if the environment variables specified in the `ENV_VARS`
#          array are set. Logs any missing variables and exits the script if
#          any are missing.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global ENV_VARS Array of required environment variables.
#
# @return None
# @exit 1 if any environment variables are missing.
#
# @example
# validate_env_vars debug
# -----------------------------------------------------------------------------
validate_env_vars() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Declare local variables
    local missing=0  # Counter for missing environment variables
    local var        # Iterator for environment variables

    # Iterate through environment variables
    for var in "${ENV_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            printf "ERROR: Missing environment variable: %s\n" "$var" >&2
            ((missing++))
            debug_print "Missing environment variable: $var" "$debug"
        else
            debug_print "Environment variable is set: $var=${!var}" "$debug"
        fi
    done

    # Handle missing variables
    if ((missing > 0)); then
        printf "ERROR: Missing %d required environment variables. Ensure all required environment variables are set and re-run the script.\n" "$missing" >&2
            debug_end "$debug"
        exit 1
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check if the script is running in a Bash shell.
# @details Ensures the script is executed with Bash, as it may use Bash-
#          specific features. If the "debug" argument is passed, detailed
#          logging will be displayed for each check.
#
# @param $1 [Optional] "debug" to enable verbose output for all checks.
#
# @global BASH_VERSION The version of the Bash shell being used.
#
# @return None
# @exit 1 if not running in Bash.
#
# @example
# check_bash
# check_bash debug
# -----------------------------------------------------------------------------
check_bash() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Ensure the script is running in a Bash shell
    if [[ -z "${BASH_VERSION:-}" ]]; then
            debug_end "$debug"
        die 1 "This script requires Bash. Please run it with Bash."
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check if the current Bash version meets the minimum required version.
# @details Compares the current Bash version against a required version
#          specified in the global variable `MIN_BASH_VERSION`. If
#          `MIN_BASH_VERSION` is "none", the check is skipped. Outputs debug
#          information if enabled.
#
# @param $1 [Optional] "debug" to enable verbose output for this check.
#
# @global MIN_BASH_VERSION Minimum required Bash version (e.g., "4.0") or
#                          "none".
# @global BASH_VERSINFO Array containing the major and minor versions of the
#         running Bash.
#
# @return None
# @exit 1 if the Bash version is insufficient.
#
# @example
# check_sh_ver
# check_sh_ver debug
# -----------------------------------------------------------------------------
check_sh_ver() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local required_version="${MIN_BASH_VERSION:-none}"

    # If MIN_BASH_VERSION is "none", skip version check
    if [[ "$required_version" == "none" ]]; then
        debug_print "Bash version check is disabled (MIN_BASH_VERSION='none')." "$debug"
    else
        debug_print "Minimum required Bash version is set to '$required_version'." "$debug"

        # Extract the major and minor version components from the required version
        local required_major="${required_version%%.*}"
        local required_minor="${required_version#*.}"
        required_minor="${required_minor%%.*}"

        # Log current Bash version for debugging
        debug_print "Current Bash version is ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}." "$debug"

        # Compare the current Bash version with the required version
        if (( BASH_VERSINFO[0] < required_major ||
              (BASH_VERSINFO[0] == required_major && BASH_VERSINFO[1] < required_minor) )); then
                    debug_end "$debug"
            die 1 "This script requires Bash version $required_version or newer."
        fi
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check Raspbian OS version compatibility.
# @details This function ensures that the Raspbian version is within the
#          supported range and logs an error if the compatibility check fails.
#
# @param $1 [Optional] "debug" to enable verbose output for this check.
#
# @global MIN_OS Minimum supported OS version.
# @global MAX_OS Maximum supported OS version (-1 indicates no upper limit).
# @global log_message Function for logging messages.
# @global die Function to handle critical errors and terminate the script.
#
# @return None Exits the script with an error code if the OS version is
#         incompatible.
#
# @example
# check_release
# check_release debug
# -----------------------------------------------------------------------------
check_release() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local ver  # Holds the extracted version ID from /etc/os-release.

    # Ensure the file exists and is readable.
    if [[ ! -f /etc/os-release || ! -r /etc/os-release ]]; then
        die 1 "Unable to read /etc/os-release. Ensure this script is run on a compatible system."
    fi

    # Extract the VERSION_ID from /etc/os-release.
    if [[ -f /etc/os-release ]]; then
        ver=$(grep "VERSION_ID" /etc/os-release | awk -F "=" '{print $2}' | tr -d '"')
    else
        warn "File /etc/os-release not found."
        ver="unknown"
    fi
    debug_print "Raspbian version '$ver' detected." "$debug"

    # Ensure the extracted version is not empty.
    if [[ -z "${ver:-}" ]]; then
            debug_end "$debug"
        die 1 "VERSION_ID is missing or empty in /etc/os-release."
    fi

    # Check if the version is older than the minimum supported version.
    if [[ "$ver" -lt "$MIN_OS" ]]; then
            debug_end "$debug"
        die 1 "Raspbian version $ver is older than the minimum supported version ($MIN_OS)."
    fi

    # Check if the version is newer than the maximum supported version, if applicable.
    if [[ "$MAX_OS" -ne -1 && "$ver" -gt "$MAX_OS" ]]; then
            debug_end "$debug"
        die 1 "Raspbian version $ver is newer than the maximum supported version ($MAX_OS)."
    fi

    debug_end "$debug"
    return 0
}

############
### Logging Functions
############

# -----------------------------------------------------------------------------
# @brief Pads a number with leading spaces to achieve the desired width.
# @details This function takes a number and a specified width, and returns the
#          number formatted with leading spaces if necessary. The number is
#          guaranteed to be a valid non-negative integer, and the width is
#          checked to ensure it is a positive integer. If "debug" is passed as
#          the second argument, it defaults the width to 4 and provides debug
#          information.
#
# @param $1 [required] The number to be padded (non-negative integer).
# @param $2 [optional] The width of the output (defaults to 4 if not provided).
#
# @return 0 on success.
#
# @example
# pad_with_spaces 42 6  # Output: "   42"
# pad_with_spaces 123 5  # Output: "  123"
# -----------------------------------------------------------------------------
pad_with_spaces() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Declare locals
    local number="${1:-0}"  # Input number (mandatory)
    local width="${2:-4}"   # Optional width (default is 4)

    # If the second parameter is "debug", adjust the arguments
    if [[ "$width" == "debug" ]]; then
        debug="$width"
        width=4  # Default width to 4 if "debug" was passed in place of width
    fi

    # Validate input for the number
    if [[ -z "${number:-}" || ! "$number" =~ ^[0-9]+$ ]]; then
        die 1 "Input must be a valid non-negative integer."
    fi

    # Ensure the width is a positive integer
    if [[ ! "$width" =~ ^[0-9]+$ || "$width" -lt 1 ]]; then
        die 1 "Error: Width must be a positive integer."
    fi

    # Strip leading zeroes to prevent octal interpretation
    number=$((10#$number))  # Forces the number to be interpreted as base-10

    # Format the number with leading spaces and return it as a string
    printf "%${width}d\n" "$number"

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Wraps a message into lines with ellipses for overflow or continuation.
# @details This function splits the message into lines, appending an ellipsis
#          for overflowed lines and prepending it for continuation lines. The
#          primary and secondary messages are processed separately and combined
#          with a delimiter.
#
# @param $1 [required] The message string to wrap.
# @param $2 [required] Maximum width of each line (numeric).
# @param $3 [optional] The secondary message string to include (defaults to
#                      an empty string).
#
# @global None.
#
# @throws None.
#
# @return A single string with wrapped lines and ellipses added as necessary.
#         The primary and secondary messages are separated by a delimiter.
#
# @example
# wrapped=$(wrap_messages "This is a long message" 50)
# echo "$wrapped"
# -----------------------------------------------------------------------------
wrap_messages() {
    local line_width=$1
    local primary=$2
    local secondary=${3:-}
    local delimiter="␞"

    # Validate input
    if [[ -z "$line_width" || ! "$line_width" =~ ^[0-9]+$ || "$line_width" -le 1 ]]; then
        printf "Error: Invalid line width '%s' in %s(). Must be a positive integer.\n" \
            "$line_width" "${FUNCNAME[0]}" >&2
        return 1
    fi

    # Inner function to wrap a single message
    wrap_message() {
        local message=$1
        local width=$2
        local result=()
        # Address faulty width with a min of 10
        local adjusted_width=$((width > 10 ? width - 1 : 10))

        while IFS= read -r line; do
            result+=("$line")
        done <<< "$(printf "%s\n" "$message" | fold -s -w "$adjusted_width")"

        for ((i = 0; i < ${#result[@]}; i++)); do
            result[i]=$(printf "%s" "${result[i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if ((i == 0)); then
                result[i]="${result[i]}…"
            elif ((i == ${#result[@]} - 1)); then
                result[i]="…${result[i]}"
            else
                result[i]="…${result[i]}…"
            fi
        done

        printf "%s\n" "${result[@]}"
    }

    # Process primary message
    local overflow=""
    if [[ ${#primary} -gt $line_width ]]; then
        local wrapped_primary
        wrapped_primary=$(wrap_message "$primary" "$line_width")
        overflow=$(printf "%s\n" "$wrapped_primary" | tail -n +2)
        primary=$(printf "%s\n" "$wrapped_primary" | head -n 1)
    fi

    # Process secondary message
    if [[ -n ${#secondary} && ${#secondary} -gt $line_width ]]; then
        secondary=$(wrap_message "$secondary" "$line_width")
    fi

    # Combine results
    printf "%s%b%s%b%s" \
        "$primary" \
        "$delimiter" \
        "$overflow" \
        "$delimiter" \
        "$secondary"
}

# -----------------------------------------------------------------------------
# @brief Log a message with optional details to the console and/or file.
# @details Handles combined logic for logging to console and/or file,
#          supporting optional details. If details are provided, they are
#          logged with an "[EXTENDED]" tag.
#
# @param $1 Timestamp of the log entry.
# @param $2 Log level (e.g., DEBUG, INFO, WARN, ERROR).
# @param $3 Color code for the log level.
# @param $4 Line number where the log entry originated.
# @param $5 The main log message.
# @param $6 [Optional] Additional details for the log entry.
#
# @global LOG_OUTPUT Specifies where to output logs ("console", "file", or
#         "both").
# @global LOG_FILE File path for log storage if `LOG_OUTPUT` includes "file".
# @global THIS_SCRIPT The name of the current script.
# @global RESET ANSI escape code to reset text formatting.
#
# @return None
# -----------------------------------------------------------------------------
print_log_entry() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Declare local variables at the start of the function
    local timestamp="$1"
    local level="$2"
    local color="$3"
    local lineno="$4"
    local message="$5"

    # Skip logging if the message is empty
    if [[ -z "$message" ]]; then
            debug_end "$debug"
        return 1
    fi

    # Log to file if required
    if [[ "$LOG_OUTPUT" == "file" || "$LOG_OUTPUT" == "both" ]]; then
        printf "%s [%s] [%s:%d] %s\\n" "$timestamp" "$level" "$THIS_SCRIPT" "$lineno" "$message" >> "$LOG_FILE"
    fi

    # Log to console if required and USE_CONSOLE is true
    if [[ "$USE_CONSOLE" == "true" && ("$LOG_OUTPUT" == "console" || "$LOG_OUTPUT" == "both") ]]; then
        printf "%b[%s]%b %s\\n" "$color" "$level" "$RESET" "$message"
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Generate a timestamp and line number for log entries.
#
# @details This function retrieves the current timestamp and the line number of
#          the calling script. If the optional debug flag is provided, it will
#          print debug information, including the function name, caller's name,
#          and the line number where the function was called.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return A pipe-separated string in the format: "timestamp|line_number".
#
# @example
# prepare_log_context "debug"
# -----------------------------------------------------------------------------
prepare_log_context() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local timestamp
    local lineno

    # Generate the current timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Retrieve the line number of the caller
    lineno="${BASH_LINENO[2]}"

    # Pass debug flag to pad_with_spaces
    lineno=$(pad_with_spaces "$lineno" "$debug") # Pass debug flag

    # Return the pipe-separated timestamp and line number
    printf "%s|%s\n" "$timestamp" "$lineno"

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Log a message with the specified log level.
# @details Logs messages to both the console and/or a log file, depending on
#          the configured log output. The function uses the `LOG_PROPERTIES`
#          associative array to determine the log level, color, and severity.
#          If the "debug" argument is provided, debug logging is enabled for
#          additional details.
#
# @param $1 Log level (e.g., DEBUG, INFO, ERROR). The log level controls the
#           message severity.
# @param $2 Main log message to log.
# @param $3 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global LOG_LEVEL The current logging verbosity level.
# @global LOG_PROPERTIES Associative array defining log level properties, such
#         as severity and color.
# @global LOG_FILE Path to the log file (if configured).
# @global USE_CONSOLE Boolean flag to enable or disable console output.
# @global LOG_OUTPUT Specifies where to log messages ("file", "console",
#         "both").
#
# @return None
#
# @example
# log_message "INFO" "This is a message"
# log_message "INFO" "This is a message" "debug"
# -----------------------------------------------------------------------------
log_message() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Ensure the calling function is log_message_with_severity()
    if [[ "${FUNCNAME[1]}" != "log_message_with_severity" ]]; then
        warn "log_message() can only be called from log_message_with_severity()."
            debug_end "$debug"
        return 1
    fi

    local level="UNSET"
    local message="<no message>"

    local context timestamp lineno custom_level color severity config_severity

    # Get level if it exists (must be one of the predefined values)
    if [[ -n "$1" && "$1" =~ ^(DEBUG|INFO|WARNING|ERROR|CRITICAL|EXTENDED)$ ]]; then
        level="$1"
        shift  # Move to the next argument
    fi

    # Get message if it exists and is not "debug"
    if [[ -n "$1" ]]; then
        message="$1"
        shift  # Move to the next argument
    fi

    # Validate the log level and message if needed
    if [[ "$level" == "UNSET" || -z "${LOG_PROPERTIES[$level]:-}" || "$message" == "<no message>" ]]; then
        warn "Invalid log level '$level' or empty message."
            debug_end "$debug"
        return 1
    fi

    # Prepare log context (timestamp and line number)
    context=$(prepare_log_context "$debug")  # Pass debug flag to sub-function
    IFS="|" read -r timestamp lineno <<< "$context"

    # Extract log properties for the specified level
    IFS="|" read -r custom_level color severity <<< "${LOG_PROPERTIES[$level]}"

    # Check if all three values (custom_level, color, severity) were successfully parsed
    if [[ -z "$custom_level" || -z "$color" || -z "$severity" ]]; then
        warn "Malformed log properties for level '$level'. Using default values."
        custom_level="UNSET"
        color="$RESET"
        severity=0
    fi

    # Extract severity threshold for the configured log level
    IFS="|" read -r _ _ config_severity <<< "${LOG_PROPERTIES[$LOG_LEVEL]}"

    # Check for valid severity level
    if [[ -z "$config_severity" || ! "$config_severity" =~ ^[0-9]+$ ]]; then
        warn "Malformed severity value for level '$LOG_LEVEL'."
            debug_end "$debug"
        return 1
    fi

    # Skip logging if the message's severity is below the configured threshold
    if (( severity < config_severity )); then
            debug_end "$debug"
        return 0
    fi

    # Call print_log_entry to handle actual logging (to file and console)
    print_log_entry "$timestamp" "$custom_level" "$color" "$lineno" "$message" "$debug"

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Log a message with the specified severity level.
# @details This function logs messages at the specified severity level and
#          handles extended details and debug information if provided.
#
# @param $1 Severity level (e.g., DEBUG, INFO, WARNING, ERROR, CRITICAL).
# @param $2 Main log message.
# @param $3 [Optional] Extended details for the log entry.
# @param $4 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return None
#
# @example
# log_message_with_severity "ERROR" /
#   "This is an error message" "Additional details" "debug"
# -----------------------------------------------------------------------------
log_message_with_severity() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Exit if the calling function is not one of the allowed ones.
    # shellcheck disable=2076
    if [[ ! "logD logI logW logE logC logX" =~ "${FUNCNAME[1]}" ]]; then
        warn "Invalid calling function: ${FUNCNAME[1]}"
            debug_end "$debug"
        exit 1
    fi

    # Initialize variables
    local severity="INFO" # Default to INFO
    local message=""
    local extended_message=""

    # Get level if it exists (must be one of the predefined values)
    if [[ -n "$1" && "$1" =~ ^(DEBUG|INFO|WARNING|ERROR|CRITICAL|EXTENDED)$ ]]; then
        severity="$1"
    fi

    # Process arguments
    if [[ -n "$2" ]]; then
        message="$2"
    else
        warn "Message is required."
        debug_end "$debug"
        return 1
    fi

    if [[ -n "$3" ]]; then
        extended_message="$3"
    fi

    # Print debug information if the flag is set
    debug_print "Logging message at severity '$severity' with message='$message'." "$debug"
    debug_print "Extended message: '$extended_message'" "$debug"

    # Log the primary message
    log_message "$severity" "$message" "$debug"

    # Log the extended message if present
    if [[ -n "$extended_message" ]]; then
        logX "$extended_message" "$debug"
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Logging wrapper functions for various severity levels.
# @details These functions provide shorthand access to
#          `log_message_with_severity()` with a predefined severity level. They
#          standardize the logging process by ensuring consistent severity
#          labels and argument handling.
#
# @param $1 [string] The primary log message. Must not be empty.
# @param $2 [optional, string] The extended message for additional details
#           (optional), sent to logX.
# @param $3 [optional, string] The debug flag. If set to "debug", enables
#           debug-level logging.
#
# @global None
#
# @return None
#
# @functions
# - logD(): Logs a message with severity level "DEBUG".
# - logI(): Logs a message with severity level "INFO".
# - logW(): Logs a message with severity level "WARNING".
# - logE(): Logs a message with severity level "ERROR".
# - logC(): Logs a message with severity level "CRITICAL".
# - logX(): Logs a message with severity level "EXTENDED".
#
# @example
#   logD "Debugging application startup."
#   logI "Application initialized successfully."
#   logW "Configuration file is missing a recommended value."
#   logE "Failed to connect to the database."
#   logC "System is out of memory and must shut down."
#   logX "Additional debug information for extended analysis."
# -----------------------------------------------------------------------------
# shellcheck disable=2317
logD() { log_message_with_severity "DEBUG" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=2317
logI() { log_message_with_severity "INFO" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=2317
logW() { log_message_with_severity "WARNING" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=2317
logE() { log_message_with_severity "ERROR" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=2317
logC() { log_message_with_severity "CRITICAL" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=2317
logX() { log_message_with_severity "EXTENDED" "${1:-}" "${2:-}" "${3:-}"; }

# -----------------------------------------------------------------------------
# @brief Ensure the log file exists and is writable, with fallback to `/tmp` if
#        necessary.
# @details This function validates the specified log file's directory to ensure
#          it exists and is writable. If the directory is invalid or
#          inaccessible, it attempts to create it. If all else fails, the log
#          file is redirected to `/tmp`. A warning message is logged if
#          fallback is used.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global LOG_FILE Path to the log file (modifiable to fallback location).
# @global THIS_SCRIPT The name of the script (used to derive fallback log file
#         name).
#
# @return None
#
# @example
# init_log "debug"  # Ensures log file is created and available for writing
#                   # with debug output.
# -----------------------------------------------------------------------------
init_log() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local scriptname="${THIS_SCRIPT%%.*}"  # Extract script name without extension
    local homepath log_dir fallback_log

    # Get the home directory of the current user
    homepath=$(
        getent passwd "${SUDO_USER:-$(whoami)}" | {
            IFS=':' read -r _ _ _ _ _ homedir _
            printf "%s" "$homedir"
        }
    )

    # Determine the log file location
    LOG_FILE="${LOG_FILE:-$homepath/$scriptname.log}"

    # Extract the log directory from the log file path
    log_dir="${LOG_FILE%/*}"

    # Check if the log directory exists and is writable
    debug_print "Checking if log directory '$log_dir' exists and is writable." "$debug"

    if [[ -d "$log_dir" && -w "$log_dir" ]]; then
        # Attempt to create the log file
        if ! touch "$LOG_FILE" &>/dev/null; then
            warn "Cannot create log file: $LOG_FILE"
            log_dir="/tmp"
        else
            # Change ownership of the log file if possible
            if [[ -n "${SUDO_USER:-}" && "${REQUIRE_SUDO:-true}" == "true" ]]; then
                chown "$SUDO_USER:$SUDO_USER" "$LOG_FILE" &>/dev/null || warn "Failed to set ownership to SUDO_USER: $SUDO_USER"
            else
                chown "$(whoami):$(whoami)" "$LOG_FILE" &>/dev/null || warn "Failed to set ownership to current user: $(whoami)"
            fi
        fi
    else
        log_dir="/tmp"
    fi

    # Fallback to /tmp if the directory is invalid
    if [[ "$log_dir" == "/tmp" ]]; then
        fallback_log="/tmp/$scriptname.log"
        LOG_FILE="$fallback_log"
        debug_print "Falling back to log file in /tmp: $LOG_FILE" "$debug"
        warn "Falling back to log file in /tmp: $LOG_FILE"
    fi

    # Attempt to create the log file in the fallback location
    if ! touch "$LOG_FILE" &>/dev/null; then
            debug_end "$debug"
        die 1 "Unable to create log file even in fallback location: $LOG_FILE"
    fi

    # Final debug message after successful log file setup
    debug_print "Log file successfully created at: $LOG_FILE" "$debug"

    readonly LOG_FILE
    export LOG_FILE

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Retrieve the terminal color code or attribute.
#
# @details This function uses `tput` to retrieve a terminal color code or
#          attribute (e.g., `sgr0` for reset, `bold` for bold text). If the
#          attribute is unsupported by the terminal, it returns an empty
#          string.
#
# @param $1 The terminal color code or attribute to retrieve.
#
# @return The corresponding terminal value or an empty string if unsupported.
# -----------------------------------------------------------------------------
default_color() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    tput "$@" 2>/dev/null || printf "\n"  # Fallback to an empty string on error

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Initialize terminal colors and text formatting.
# @details This function sets up variables for foreground colors, background
#          colors, and text formatting styles. It checks terminal capabilities
#          and provides fallback values for unsupported or non-interactive
#          environments.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return None
#
# @example
# init_colors "debug"  # Initializes terminal colors with debug output.
# -----------------------------------------------------------------------------
init_colors() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # General text attributes
    BOLD=$(default_color bold)
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
    # shellcheck disable=SC2034
    readonly RESET BOLD SMSO RMSO UNDERLINE NO_UNDERLINE DIM
    # shellcheck disable=SC2034
    readonly BLINK NO_BLINK ITALIC NO_ITALIC MOVE_UP CLEAR_LINE
    # shellcheck disable=SC2034
    readonly FGBLK FGRED FGGRN FGYLW FGBLU FGMAG FGCYN FGWHT FGRST FGGLD
    # shellcheck disable=SC2034
    readonly BGBLK BGRED BGGRN BGYLW BGBLU BGMAG BGCYN BGWHT BGRST

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Generate a separator string for terminal output.
# @details Creates heavy or light horizontal rules based on terminal width.
#          Optionally outputs debug information if the debug flag is set.
#
# @param $1 Type of rule: "heavy" or "light".
# @param $2 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return The generated rule string or error message if an invalid type is
#         provided.
#
# @example
# generate_separator "heavy"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
generate_separator() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Normalize separator type to lowercase
    local type="${1,,}"
    local width="${COLUMNS:-80}"

    # Validate separator type
    if [[ "$type" != "heavy" && "$type" != "light" ]]; then
        warn "Invalid separator type: '$1'. Must be 'heavy' or 'light'."
            debug_end "$debug"
        return 1
    fi

    # Generate the separator based on type
    case "$type" in
        heavy)
            # Generate a heavy separator (═)
            printf '═%.0s' $(seq 1 "$width")
            ;;
        light)
            # Generate a light separator (─)
            printf '─%.0s' $(seq 1 "$width")
            ;;
        *)
            # Handle invalid separator type
            warn "Invalid separator type: $type"
                    debug_end "$debug"
            return 1
            ;;
    esac

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Validate the logging configuration, including LOG_LEVEL.
# @details This function checks whether the current LOG_LEVEL is valid. If
#          LOG_LEVEL is not defined in the `LOG_PROPERTIES` associative array,
#          it defaults to "INFO" and displays a warning message.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global LOG_LEVEL The current logging verbosity level.
# @global LOG_PROPERTIES Associative array defining log level properties.
#
# @return void
#
# @example
# validate_log_level "debug"  # Enables debug output
# validate_log_level          # No debug output
# -----------------------------------------------------------------------------
validate_log_level() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Ensure LOG_LEVEL is a valid key in LOG_PROPERTIES
    if [[ -z "${LOG_PROPERTIES[$LOG_LEVEL]:-}" ]]; then
        # Print error message if LOG_LEVEL is invalid
        warn "Invalid LOG_LEVEL '$LOG_LEVEL'. Defaulting to 'INFO'."
        LOG_LEVEL="INFO"  # Default to "INFO"
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Sets up the logging environment for the script.
#
# @details
# This function initializes terminal colors, configures the logging
# environment, defines log properties, and validates both the log level and
# properties. It must be called before any logging-related functions.
#
# - Initializes terminal colors using `init_colors`.
# - Sets up the log file and directory using `init_log`.
# - Defines global log properties (`LOG_PROPERTIES`), including severity
#   levels, colors, and labels.
# - Validates the configured log level and ensures all required log properties
#   are defined.
#
# @note This function should be called once during script initialization.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return void
# -----------------------------------------------------------------------------
setup_log() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Initialize terminal colors
    init_colors "$debug"

    # Initialize logging environment
    init_log "$debug"

    # Define log properties (severity, colors, and labels)
    declare -gA LOG_PROPERTIES=(
        ["DEBUG"]="DEBUG|${FGCYN}|0"
        ["INFO"]="INFO |${FGGRN}|1"
        ["WARNING"]="WARN |${FGGLD}|2"
        ["ERROR"]="ERROR|${FGMAG}|3"
        ["CRITICAL"]="CRIT |${FGRED}|4"
        ["EXTENDED"]="EXTD |${FGBLU}|0"
    )

    # Debug message for log properties initialization
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG] Log properties initialized:\n" >&2

        # Iterate through LOG_PROPERTIES to print each level with its color
        for level in DEBUG INFO WARNING ERROR CRITICAL EXTENDED; do
            IFS="|" read -r custom_level color severity <<< "${LOG_PROPERTIES[$level]}"
            printf "[DEBUG] %s: %b%s%b\n" "$level" "$color" "$custom_level" "$RESET" >&2
        done
    fi

    # Validate the log level and log properties
    validate_log_level "$debug"

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Toggle the USE_CONSOLE variable on or off.
# @details This function updates the global USE_CONSOLE variable to either
#          "true" (on) or "false" (off) based on the input argument. It also
#          prints debug messages when the debug flag is passed.
#
# @param $1 The desired state: "on" (to enable console logging) or "off" (to
#           disable console logging).
# @param $2 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global USE_CONSOLE The flag to control console logging.
#
# @return 0 on success, 1 on invalid input.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
toggle_console_log() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Declare local variables
    local state="${1,,}"      # Convert input to lowercase for consistency

    # Validate $state
    if [[ "$state" != "on" && "$state" != "off" ]]; then
        warn "Invalid state: '$state'. Must be 'on' or 'off'."
            debug_end "$debug"
        return 1
    fi

    # Process the desired state
    case "$state" in
        on)
            USE_CONSOLE="true"
            debug_print "Console logging enabled. USE_CONSOLE='$USE_CONSOLE', CONSOLE_STATE='$CONSOLE_STATE'" "$debug"
            ;;
        off)
            USE_CONSOLE="false"
            debug_print "Console logging disabled. USE_CONSOLE='$USE_CONSOLE', CONSOLE_STATE='$CONSOLE_STATE'" "$debug"
            ;;
        *)
            warn "Invalid argument for toggle_console_log: $state"
                    debug_end "$debug"
            return 1
            ;;
    esac

    debug_end "$debug"
    return 0
}

############
### Common Script Functions
############

# -----------------------------------------------------------------------------
# @brief Execute a new shell operation (departs this script).
# @details Executes or simulates a shell command based on the DRY_RUN flag.
#          Supports optional debugging to trace the execution process.
#
# @param $1 Name of the operation or process (for reference in logs).
# @param $2 The shell command to execute.
# @param $3 Optional debug flag ("debug" to enable debug output).
#
# @global FUNCNAME Used to fetch the current and caller function names.
# @global BASH_LINENO Used to fetch the calling line number.
# @global DRY_RUN When set, simulates command execution instead of running it.
#
# @throws Exits with a non-zero status if the command execution fails.
#
# @return None.
#
# @example
# DRY_RUN=true exec_new_shell "ListFiles" "ls -l" "debug"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
exec_new_shell() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local exec_name="${1:-Unnamed Operation}"
    local exec_process="${2:-true}"

    # Debug information
    debug_print "exec_name: $exec_name" "$debug"
    debug_print "exec_process: $exec_process" "$debug"

    # Basic status prefixes
    local running_pre="Running"
    local complete_pre="Complete"
    local failed_pre="Failed"

    # If DRY_RUN is enabled, show that in the prefix
    if [[ "$DRY_RUN" == "true" ]]; then
        running_pre+=" (dry)"
        complete_pre+=" (dry)"
        failed_pre+=" (dry)"
    fi
    running_pre+=":"
    complete_pre+=":"
    failed_pre+=":"

    # Print ephemeral “Running” line
    printf "%b[-]%b %s %s\n" "${FGGLD}" "${RESET}" "$running_pre" "$exec_name"
    sleep 0.02  # Ensure visibility for fast commands

    # Validate the command before executing
    if ! command -v "${exec_process%% *}" >/dev/null 2>&1; then
        # Move up & clear ephemeral “Running” line
        printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"
        printf "%b[✘]%b %s %s.\n" "${FGRED}" "${RESET}" "$failed_pre" "$exec_name"
        debug_end "$debug"
        return 127
    fi

    # 2) If DRY_RUN == "true", skip real exec
    if [[ "$DRY_RUN" == "true" ]]; then
        sleep 1
        # Move up & clear ephemeral “Running” line before spawning a new shell
        printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"
        printf "%b[✔]%b %s %s.\n" "${FGGRN}" "${RESET}" "$complete_pre" "$exec_name"
        debug_end "$debug"
        return 0
    fi

    # Attempt to execute the command in a new shell
    printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"
    printf "%b[✔]%b %s %s.\n" "${FGGRN}" "${RESET}" "$complete_pre" "$exec_name"
    # shellcheck disable=SC2093
    exec $exec_process

    # If exec fails, handle the failure
    local retval=$?
    printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"
    printf "%b[✘]%b %s %s.\n" "${FGRED}" "${RESET}" "$failed_pre" "$exec_name"
    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Executes a command in a separate Bash process.
# @details This function manages the execution of a shell command, handling the
#          display of status messages. It supports dry-run mode, where the
#          command is simulated without execution. The function prints success
#          or failure messages and handles the removal of the "Running" line
#          once the command finishes.
#
# @param exec_name The name of the command or task being executed.
# @param exec_process The command string to be executed.
# @param debug Optional flag to enable debug messages. Set to "debug" to
#              enable.
#
# @return Returns 0 if the command was successful, non-zero otherwise.
#
# @note The function supports dry-run mode, controlled by the DRY_RUN variable.
#       When DRY_RUN is true, the command is only simulated without actual
#       execution.
#
# @example
# exec_command "Test Command" "echo Hello World" "debug"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
exec_command() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local exec_name="$1"
    local exec_process="$2"

    # Debug information
    debug_print "exec_name: $exec_name" "$debug"
    debug_print "exec_process: $exec_process" "$debug"

    # Basic status prefixes
    local running_pre="Running"
    local complete_pre="Complete"
    local failed_pre="Failed"

    # If DRY_RUN is enabled, show that in the prefix
    if [[ "$DRY_RUN" == "true" ]]; then
        running_pre+=" (dry)"
        complete_pre+=" (dry)"
        failed_pre+=" (dry)"
    fi
    running_pre+=":"
    complete_pre+=":"
    failed_pre+=":"

    # 1) Print ephemeral “Running” line
    printf "%b[-]%b %s %s\n" "${FGGLD}" "${RESET}" "$running_pre" "$exec_name"
    # Optionally ensure it shows up (especially if the command is super fast):
    sleep 0.02

    # 2) If DRY_RUN == "true", skip real exec
    if [[ "$DRY_RUN" == "true" ]]; then
        # Move up & clear ephemeral line
        sleep 1
        printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"
        printf "%b[✔]%b %s %s.\n" "${FGGRN}" "${RESET}" "$complete_pre" "$exec_name"
            debug_end "$debug"
        return 0
    fi

    # 3) Actually run the command (stdout/stderr handling is up to you):
    bash -c "$exec_process" &>/dev/null
    local status=$?

    # 4) Move up & clear ephemeral “Running” line
    printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"

    # 5) Print final success/fail
    if [[ $status -eq 0 ]]; then
        printf "%b[✔]%b %s %s.\n" "${FGGRN}" "${RESET}" "$complete_pre" "$exec_name"
    else
        printf "%b[✘]%b %s %s.\n" "${FGRED}" "${RESET}" "$failed_pre" "$exec_name"
        # If specifically “command not found” exit code:
        if [[ $status -eq 127 ]]; then
            warn "Command not found: $exec_process"
        else
            warn "Command failed with status $status: $exec_process"
        fi
    fi

    debug_end "$debug"
    return "$status"
}

# -----------------------------------------------------------------------------
# @brief Handles script exit operations and logs the exit message.
# @details This function is designed to handle script exit operations by logging
#          the exit message along with the status code, function name, and line
#          number where the exit occurred. The function also supports an optional
#          message and exit status, with default values provided if not supplied.
#          After logging the exit message, the script will terminate with the
#          specified exit status.
#
# @param $1 [optional] Exit status code (default is 1 if not provided).
# @param $2 [optional] Message to display upon exit (default is "Exiting
#           script.").
#
# @return None.
#
# @example
# exit_script 0 "Completed successfully"
# exit_script 1 "An error occurred"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
exit_script() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Local variables
    local exit_status="${1:-}"              # First parameter as exit status
    local message="${2:-Exiting script.}"   # Main error message wit default
    local details                           # Additional details
    local lineno="${BASH_LINENO[0]}"        # Line number of calling line
    lineno=$(pad_with_spaces "$lineno")     # Pad line number with spaces
    local caller_func="${FUNCNAME[1]}"      # Calling function name

    # Determine exit status if not numeric
    if ! [[ "$exit_status" =~ ^[0-9]+$ ]]; then
        exit_status=1
    else
        shift  # Remove the exit_status from the arguments
    fi

    # Remove trailing dot if needed
    message=$(remove_dot "$message")
    # Log the provided or default message
    printf "[EXIT ] '%s' from %s:%d status (%d).\n" "$message" "$caller_func" "$lineno" "$exit_status"

    debug_end "$debug"
    exit "$exit_status"  # Exit with the provided status
}

############
### Menu Functions
############

# -----------------------------------------------------------------------------
# @var MENU_ITEMS
# @brief Stores menu item details.
# @details Keys are unique identifiers for menu items, and values are formatted
#          strings containing display names and the corresponding function to
#          call.
# -----------------------------------------------------------------------------
# Live Switch between WiFi Connection and Access Point
MENU_ITEMS["live_switch"]="Live Switch Modes"
# Force Auto Negotiate
MENU_ITEMS["force_auto_negotiate"]="Force Auto-Negotiate"
# Access Point Configuration
MENU_ITEMS["display_ap_menu"]="Update Access Point Configuration"
MENU_ITEMS["update_ap_ssid"]="Update Access Point Name"
MENU_ITEMS["update_ap_password"]="Update Access Point Password"
MENU_ITEMS["update_ap_ip"]="Update Access Point IP Block"
# WiFi Client Configuration:
#   List connections and allow the user to select a connection to edit (1-9)
#   (C)reate a new connection
#   Change (P)riority
MENU_ITEMS["wifi_client_config"]="WiFi Client Configuration"
# Check for Upgrade
MENU_ITEMS["upgrade_utility"]="Check for Upgrade"

# -----------------------------------------------------------------------------
# @var MAIN_MENU
# @brief Array defining the main menu options.
# @details Contains keys that correspond to the `MENU_ITEMS` associative array.
#          These keys define the options available in the main menu.
#
# @example
# MAIN_MENU=(
#     "option_one"
#     "option_two"
#     "display_sub_menu"
# )
# -----------------------------------------------------------------------------
# shellcheck disable=SC2034
MAIN_MENU=(
    "live_switch"
    "force_auto_negotiate"
    "display_ap_menu"
    "wifi_client_config"
    "upgrade_utility"
)

# -----------------------------------------------------------------------------
# @var AP_MENU
# @brief Array defining the sub-menu options.
# @details Contains keys that correspond to the `MENU_ITEMS` associative array.
#          These keys define the options available in the sub-menu.
#
# @example
# AP_MENU=(
#     "option_three"
#     "display_main_menu"
# )
# -----------------------------------------------------------------------------
# shellcheck disable=SC2034
AP_MENU=(
    "update_ap_ssid"
    "update_ap_password"
    "update_ap_ip"
)

# -----------------------------------------------------------------------------
# @brief Displays a menu based on the given menu array.
# @details The menu items are numbered sequentially, and the user is prompted
#          for input to select an option.
#
# @param $1 Array of menu keys to display.
# @param $2 Debug flag for optional debug output.
#
# @global MENU_ITEMS Uses this global array to retrieve menu details.
# @global MENU_HEADER Prints the global menu header.
#
# @throws Prints an error message if an invalid choice is made.
#
# @return Executes the corresponding function for the selected menu item.
# -----------------------------------------------------------------------------
display_menu() {
    # Debug declarations
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local choice
    local menu_array_name="$1"  # Name of the array (e.g., MAIN_MENU[@], SUB_MENU[@])
    local menu_array=("${!menu_array_name}")  # Dereference the array

    while :; do
        # Display the menu header
        printf "%s\n\n" "$MENU_HEADER"
        printf "Please select an option:\n\n"

        # Display the menu items
        local i=1
        for func in "${menu_array[@]}"; do
            # Fixed-width format for consistent alignment
            printf "%-4d%-30s\n" "$i" "${MENU_ITEMS[$func]}"
            ((i++))
        done

        # Read user choice
        printf "\nEnter your choice (or press Enter to exit): "
        read -n 1 -sr choice < /dev/tty || true
        printf "\n"  # Add a newline after the choice for formatting

        # Validate input
        if [[ -z "$choice" ]]; then
            # Exit if the current menu is the main menu
            if [[ "$menu_array_name" == "MAIN_MENU[@]" ]]; then
                debug_end "$debug"
                exit 0  # Exit the entire program
            else
                clear
                debug_end "$debug"
                return 0  # Return to the caller
            fi
        elif [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -ge 1 && "$choice" -lt "$i" ]]; then
                local func="${menu_array[choice-1]}"
                "$func" "$debug"
                clear
            else
                printf "Invalid choice. Please try again.\n"
            fi
        else
            printf "Invalid input. Please enter a number.\n"
        fi
    done

    # Debug log: function exit
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Displays the main menu.
# @details Calls the `display_menu` function with the main menu array.
#
# @param $1 Debug flag for optional debug output.
#
# @return Calls `display_menu` with the main menu array.
# -----------------------------------------------------------------------------
display_main_menu() {
    # Debug declarations
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Clear screen
    clear
    # Display the menu
    display_menu MAIN_MENU[@] "$debug"

    # Debug log: function exit
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Displays the sub-menu.
# @details Calls the `display_menu` function with the sub-menu array. Loops
#          within the sub-menu until the user chooses to exit.
#
# @param $1 Debug flag for optional debug output.
#
# @return Calls `display_menu` with the sub-menu array in a loop.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
display_ap_menu() {
    # Debug declarations
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Clear screen
    clear
    # Display the menu
    display_menu AP_MENU[@] "$debug"

    # Debug log: function exit
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Entry point for the menu.
# @details Initializes debugging if the "debug" flag is passed, starts the
#          main menu loop, and ensures proper debug logging upon exit.
#
# @param $@ Arguments passed to the script. Pass "debug" for debug mode.
#
# @example
# Execute the menu
#   do_menu "$debug"
# -----------------------------------------------------------------------------
do_menu() {
    # Debug declarations
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Main script execution starts here
    while true; do
        display_main_menu "$debug"
    done

    # Debug log: function exit
    debug_end "$debug"
}

############
### Arguments Functions
############

# -----------------------------------------------------------------------------
# @brief List of flagged arguments.
# @details Each entry in the list corresponds to a flagged argument, containing
#          the flag(s), a complex flag indicating if a secondary argument is
#          required, the associated function, a description, and an exit flag
#          indicating whether the function should terminate after processing.
#
# @var OPTIONS_LIST
# @brief List of flagged arguments.
# @details This list holds the flags (which may include multiple pipe-delimited
#          options), the associated function to call, whether a secondary
#          argument is required, and whether the function should exit after
#          processing.
# -----------------------------------------------------------------------------
OPTIONS_LIST=(
    "-h|--help 0 usage Displays these usage instructions 1"
    "-v|--version 0 print_version Displays application version 1"
)

# -----------------------------------------------------------------------------
# @brief Processes command-line arguments.
# @details This function processes flagged options (defined in `OPTIONS_LIST`).
#
# @param $@ [optional] Command-line arguments passed to the function.
#
# @global OPTIONS_LIST List of valid flagged options and their associated
#                      functions.
# @global debug_flag Optional debug flag to enable debugging information.
#
# @return 0 on success, or the status code of the last executed command.
# -----------------------------------------------------------------------------
process_args() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local retval=0
    local args=("$@")
    local invalid_argument=false

    # Loop through all the arguments passed to the function.
    while (( ${#args[@]} > 0 )); do
        local current_arg="${args[0]}"
        local processed_argument=false

        # Skip empty arguments.
        if [[ -z "${current_arg}" ]]; then
            args=("${args[@]:1}")  # Remove the blank argument and continue
            continue
        fi

        # Process options (starting with "-").
        if [[ "${current_arg:0:1}" == "-" ]]; then
            # Loop through all flagged options (OPTIONS_LIST)
            for entry in "${OPTIONS_LIST[@]}"; do
                local flag
                local complex_flag
                local function_name
                local description
                local exit_flag
                flag=$(echo "$entry" | cut -d' ' -f1)
                complex_flag=$(echo "$entry" | cut -d' ' -f2)
                function_name=$(echo "$entry" | cut -d' ' -f3)
                description=$(echo "$entry" | cut -d' ' -f4- | rev | cut -d' ' -f2- | rev)
                exit_flag=$(echo "$entry" | awk '{print $NF}')

                # Split flags and check if current_arg matches.
                IFS='|' read -ra flag_parts <<< "$flag"  # Split the flag by "|"
                for part in "${flag_parts[@]}"; do
                    part=$(echo "$part" | xargs)  # Trim spaces

                    # Check if the current argument matches any of the flags
                    if [[ "$current_arg" == "$part" ]]; then
                        # If it's a complex flag, we expect a following argument
                        if (( complex_flag == 1 )); then
                            local next_arg
                            if [[ ${#args[@]} -ge 2 ]]; then
                                next_arg="${args[1]}"
                            else
                                die 1 "Error: Missing argument for flag '$part'."
                            fi

                            # Call the function with the next argument as a parameter
                            $function_name "$next_arg" "$debug"
                            retval="$?"

                            # Remove the processed flag and its argument
                            args=("${args[@]:2}")
                            processed_argument=true
                        else
                            # Call the function with no arguments
                            $function_name
                            retval="$?"
                            # Remove the processed flag
                            args=("${args[@]:1}")
                            processed_argument=true
                        fi

                        # Exit if exit_flag is set
                        if (( exit_flag == 1 )); then
                            debug_end "$debug"
                            exit "$retval"
                        fi
                        continue
                    fi
                done
            done
        fi

        # Handle invalid arguments by setting the flag.
        if [[ "$processed_argument" != true ]]; then
            args=("${args[@]:1}")
            invalid_argument=true
            continue
        fi
    done

    # If any invalid argument is found, show usage instructions.
    if [[ "$invalid_argument" == true ]]; then
        usage stderr
    fi

    debug_end "$debug"
    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Prints usage information for the script.
# @details This function prints out the usage instructions for the script,
#          including the script name, command-line options, and their
#          descriptions. The usage of word arguments and flag arguments is
#          displayed separately. It also handles the optional inclusion of
#          the `sudo` command based on the `REQUIRE_SUDO` environment variable.
#          Additionally, it can direct output to either stdout or stderr based
#          on the second argument.
#
# @param $@ [optional] Command-line arguments passed to the function,
#                      typically used for the debug flag.
# @global REQUIRE_SUDO If set to "true", the script name will include "sudo"
#                      in the usage message.
# @global THIS_SCRIPT The script's name, used for logging.
#
# @return 0 on success.
# -----------------------------------------------------------------------------
usage() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local output_redirect="1"  # Default to stdout (1)
    local args=()

    # Check for the "stderr" argument to redirect output to stderr.
    for arg in "$@"; do
        if [[ "$arg" == "stderr" ]]; then
            output_redirect="2"  # Set to stderr (2)
            shift
            break  # Exit the loop as soon as we find "stderr"
        fi
    done

    # Check if "sudo" should be appended to the script name
    local script_name
    [[ "${REQUIRE_SUDO:-}" == "true" ]] && script_name+="sudo "
    script_name+=" ./$THIS_SCRIPT"

    sem_ver=$(print_version "${debug}")
    printf "%s version %s.\n" "$REPO_DISPLAY_NAME" "$sem_ver"

    # Print the usage with the correct script name
    printf "\nUsage: %s [debug]\n\n" "$script_name" >&$output_redirect

    local max_flag_len=0
    for entry in "${OPTIONS_LIST[@]}"; do
        local flag; flag=$(echo "$entry" | cut -d' ' -f1)
        local flag_len=${#flag}
        if (( flag_len > max_flag_len )); then
            max_flag_len=$flag_len
        fi
    done

    # Second pass to print with padded formatting for flag arguments
    for entry in "${OPTIONS_LIST[@]}"; do
        local flag; flag=$(echo "$entry" | cut -d' ' -f1)
        local complex_flag; complex_flag=$(echo "$entry" | cut -d' ' -f2)
        local description; description=$(echo "$entry" | cut -d' ' -f4- | rev | cut -d' ' -f2- | rev)
        local exit_flag=$((1 - $(echo "$entry" | awk '{print $NF}')))  # Invert the value

        printf "  %$((max_flag_len))s: %s\n" "$(echo "$flag" | tr '|' ' ')" "$description" >&$output_redirect
    done

    debug_end "$debug"
    return 0
}

############
### Handle AP Configuration
############

# -----------------------------------------------------------------------------
# @brief Updates the Access Point (AP) SSID.
# @details This function allows the user to update the global AP_SSID variable.
#          It validates the SSID to ensure it meets length and character
#          requirements, trims whitespace, and confirms saving the new
#          configuration.
#
# @global AP_SSID The current SSID of the Access Point.
#
# @param $@ Debug flag (optional). If "debug" is provided, debug information
#           will be printed.
#
# @return None.
#
# @example
#   update_ap_ssid "debug"
# -----------------------------------------------------------------------------
update_ap_ssid() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    clear

    # Display current SSID
    printf "Current AP SSID: %s\n\n" "$AP_SSID"
    printf "Create a new SSID for the Access Point:\n"
    printf "    %s\n" "- Must be 1-32 characters"
    printf "    %s\n" "- No leading or trailing spaces"
    printf "    %s\n" "- No embedded spaces"
    printf "\nPress Enter to keep the current SSID.\n"
    printf "> "

    # Read the new SSID
    read -r new_ssid

    # Trim and validate SSID
    new_ssid=$(printf "%s" "$new_ssid" | xargs)
    debug_print "Trimmed new SSID: '$new_ssid'" "$debug"

    if [[ -n "$new_ssid" ]]; then
        if [[ ${#new_ssid} -ge 1 && ${#new_ssid} -le 32 && "$new_ssid" =~ ^[[:graph:]]+$ ]]; then
            AP_SSID="$new_ssid"
            printf "\nSSID updated to: %s\n" "$AP_SSID"
            debug_print "Valid SSID: '$new_ssid'" "$debug"

            # Confirmation loop to save the configuration
            while :; do
                read -rp "Do you want to save this new configuration? (y/n): " save_choice
                case "$save_choice" in
                    [Yy])
                        save_config "$debug"
                        printf "Configuration saved successfully.\n"
                        break
                        ;;
                    [Nn])
                        printf "Configuration was not saved.\n"
                        break
                        ;;
                    *)
                        printf "Invalid choice. Please enter 'y' or 'n'.\n"
                        ;;
                esac
            done
        else
            printf "\nInvalid SSID. Must be 1-32 printable characters with no leading/trailing spaces.\n"
            debug_print "Invalid SSID provided: '$new_ssid'" "$debug"
        fi
    else
        printf "\nKeeping the current SSID: %s\n" "$AP_SSID"
        debug_print "No change to SSID. Current SSID retained: '$AP_SSID'" "$debug"
    fi
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Updates the Access Point (AP) password.
# @details This function allows the user to update the global AP_PASSWORD
#          variable. It validates the password to ensure it meets length and
#          character requirements, trims whitespace, and confirms saving the
#          new configuration.
#
# @global AP_PASSWORD The current password of the Access Point.
#
# @param $@ Debug flag (optional). If "debug" is provided, debug information
#           will be printed.
#
# @return None.
#
# @example
#   update_ap_password "debug"
# -----------------------------------------------------------------------------
update_ap_password() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    clear

    # Display current password
    printf "Current AP Password: %s\n\n" "$AP_PASSWORD"
    printf "%s\n" "Create a new password for your Access Point"
    printf "    %s\n" "-- Must be 8-63 characters"
    printf "    %s\n" "-- No leading or trailing spaces"
    printf "    %s\n" "-- Printable characters only"
    printf "\nPress Enter to keep the current password.\n"
    printf "> "

    # Read the new password
    read -r new_pw

    # Trim and validate password
    new_pw=$(printf "%s" "$new_pw" | xargs)
    debug_print "Trimmed new password: '$new_pw'" "$debug"

    if [[ -n "$new_pw" ]]; then
        if [[ ${#new_pw} -ge 8 && ${#new_pw} -le 63 && "$new_pw" =~ ^[[:print:]]+$ ]]; then
            debug_print "Valid password provided: '$new_pw'" "$debug"

            # Confirmation loop to save the configuration
            while :; do
                read -rp "Do you want to save this password? (y/n): " save_choice
                case "$save_choice" in
                    [Yy])
                        AP_PASSWORD="$new_pw"
                        save_config "$debug"
                        printf "Configuration saved successfully.\n"
                        break
                        ;;
                    [Nn])
                        printf "Configuration was not saved.\n"
                        break
                        ;;
                    *)
                        printf "Invalid choice. Please enter 'y' or 'n'.\n"
                        ;;
                esac
            done
        else
            printf "\nInvalid password. Must be 8-63 printable characters with no leading/trailing spaces.\n"
            debug_print "Invalid password provided: '$new_pw'" "$debug"
        fi
    else
        printf "\nKeeping the current password.\n"
        debug_print "No change to password. Current password retained: '$AP_PASSWORD'" "$debug"
    fi
    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Converts an IP address from dotted decimal format to an integer.
# @details This function takes an IPv4 address in dotted decimal notation
#          (e.g., 192.168.0.1) and converts it into a 32-bit integer. The
#          conversion is done by treating each octet as a byte and shifting
#          its value to the appropriate position in the 32-bit integer.
#
# @param $1 The IPv4 address in dotted decimal format (e.g., "192.168.0.1").
#
# @return Prints the 32-bit integer representation of the IP address.
#
# @example
#   local int_ip
#   int_ip=$(convert_ip_to_int "192.168.0.1")
#   echo "$int_ip"  # Outputs: 3232235521
# -----------------------------------------------------------------------------
convert_ip_to_int() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local ip="$1"  # IPv4 address in dotted decimal format
    IFS='.' read -r a b c d <<< "$ip"  # Split the IP address into four octets
    local result=$(( a * 16777216 + b * 65536 + c * 256 + d ))  # Calculate integer
    debug_end "$debug"
    printf "%d\n" "$result"  # Output the integer representation of the IP address
}

# -----------------------------------------------------------------------------
# @brief Calculates the subnet mask for a given CIDR value.
# @details This function computes the subnet mask for an IPv4 address using the
#          given CIDR value. The calculation avoids bitwise shifts to ensure
#          compatibility with versions of Bash that may not support them.
#
# @param $1 The CIDR value (e.g., 24 for a /24 subnet).
#
# @return Prints the calculated subnet mask as an integer.
#
# @example
#   local mask
#   mask=$(calculate_mask 24)
#   printf "Subnet mask: %d\n" "$mask"  # Outputs: 4294967040
# -----------------------------------------------------------------------------
calculate_mask() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local cidr="$1"               # The CIDR value for the subnet (0-32)
    local full_mask=0xFFFFFFFF    # The full 32-bit mask in hexadecimal
    local shift=$(( 32 - cidr ))  # Number of bits to shift for the mask

    # Calculate the shifted mask using multiplication instead of bitwise shifts
    local shifted_mask=$(( full_mask * (2 ** shift) ))

    # Apply the full mask to ensure the result is valid
    local mask=$(( shifted_mask & full_mask ))

    # Print the calculated mask
    debug_end "$debug"
    printf "%d\n" "$mask"
}

# -----------------------------------------------------------------------------
# @brief Validates the format and compatibility of a subnet and gateway.
# @details This function checks if the given subnet is in a valid CIDR format
#          and if the gateway IP address falls within the subnet range. It
#          ensures the subnet and gateway configuration is logically correct
#          before applying it. The function also validates the IPv4 address
#          format for both subnet and gateway.
#
# @param $1 The subnet to validate in CIDR format (e.g., 192.168.1.0/24).
# @param $2 The gateway IP address to validate (e.g., 192.168.1.1).
# @param $@ Debug flag (optional). If "debug" is provided, debug information
#           will be printed.
#
# @return 0 if the subnet and gateway are valid.
#         1 if the format is invalid or the gateway does not belong to the subnet.
# -----------------------------------------------------------------------------
validate_subnet() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local ip="$1"            # Subnet to validate (CIDR format)
    local gw="$2"            # Gateway IP address to validate
    local retval=0           # Return value (0 for valid, 1 for invalid)

    # Validate IPv4 address format for subnet and gateway
    if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        printf "Invalid subnet format: %s\n" "$ip" >&2
        debug_end "$debug"
        return 1
    fi
    if ! [[ "$gw" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        printf "Invalid gateway format: %s\n" "$gw" >&2
        debug_end "$debug"
        return 1
    fi

    # Extract the base IP and CIDR
    local base_ip="${ip%%/*}"
    local cidr="${ip##*/}"
    local gw_ip="$gw"

    # Validate CIDR range
    if (( cidr < 0 || cidr > 32 )); then
        printf "Invalid CIDR value: %s\n" "$cidr" >&2
        debug_end "$debug"
        return 1
    fi

    # Convert base IP and gateway IP to integers
    local base_ip_int
    base_ip_int=$(convert_ip_to_int "$base_ip")

    local gw_ip_int
    gw_ip_int=$(convert_ip_to_int "$gw_ip")

    local mask
    mask=$(calculate_mask "$cidr")

    # Calculate the network range
    local network=$(( base_ip_int & mask ))
    local broadcast=$(( network | ~mask & 0xFFFFFFFF ))

    debug_print "Calculated network: $network, mask: $mask, broadcast: $broadcast" "$debug"

    # Check if the gateway is within the network range
    if (( gw_ip_int < network || gw_ip_int > broadcast )); then
        printf "Gateway %s is not within the subnet %s.\n" "$gw" "$ip" >&2
        retval=1
    fi

    debug_print "Validation result: $retval" "$debug"
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
    local new_subnet="$1"
    local new_gateway="$2"
    local retval=0

    debug_print "Validating new subnet: $new_subnet"
    debug_print "Validating new gateway: $new_gateway"

    # Check for conflicts with active network subnets
    if ! validate_network_conflict "$new_subnet" "$debug"; then
        debug_print "Subnet conflict detected for $new_subnet"
        printf "The selected subnet conflicts with an existing network.\n" >&2
        retval=1
    # Check for validity of the subnet and gateway configuration
    elif ! validate_subnet "$new_subnet" "$new_gateway" "$debug"; then
        debug_print "Invalid subnet or gateway detected"
        printf "Invalid subnet or gateway configuration.\n" >&2
        retval=1
    # Check if the gateway IP is already in use
    elif ping -c 1 -w 1 "${new_gateway%%/*}" &>/dev/null; then
        debug_print "Gateway $new_gateway is already in use"
        printf "The gateway %s is already in use.\n" "$new_gateway" >&2
        retval=1
    fi

    debug_print "Validation result: $retval"
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

    printf "\nConstruct an IP address for AP within the selected network.\n\n"

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
        read -rp "Enter the third octet 0-255, or press Enter to exit: " third_octet
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
        if [[ -z "$fourth_octet" ]]; then
            debug_end "$debug"
            return 0
        fi
        # Validate the input: Must be a number between 0 and 253
        if [[ "$fourth_octet" =~ ^[0-9]+$ ]] && (( fourth_octet >= 0 && fourth_octet <= 253 )); then
            break  # Valid input, exit the loop
        else
            printf "Invalid input. Please enter a number between 0 and 253.\n" >&2
        fi
    done

    # Construct the IP address, network, and gateway
    ip_address="$base_ip.$second_octet.$third_octet.$fourth_octet"
    ip_network="$base_ip.$second_octet.$third_octet.0/24"
    gateway="$base_ip.$second_octet.$third_octet.254"
    # Validate and apply the configuration
    if validate_ap_configuration "$ip_network" "$gateway" "$debug"; then
        printf "\nYour selected AP IP address: %s\n" "$ip_address"
        printf "Your selected IP network: %s\n" "$ip_network"
        printf "Gateway for this network: %s\n" "$gateway"

        # Loop until the user provides a valid response
        while :; do
            read -rp "Do you want to save this configuration? (y/n): " save_choice
            case "$save_choice" in
                [Yy])
                    AP_IP="$ip_address/24"
                    AP_GW="$gateway"
                    save_config "$debug"
                    printf "Configuration saved successfully.\n"
                    break
                    ;;
                [Nn])
                    printf "Configuration was not saved.\n"
                    break
                    ;;
                *)
                    printf "Invalid choice. Please enter 'y' or 'n'.\n"
                    ;;
            esac
        done
    else
        printf "Configuration validation failed.\n"
    fi

    debug_end "$debug"
}

############
### Handle Configured Networks Functions
############



############
### AP Config Functions
############

live_switch() {
    # TODO
    # Debug declarations
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Execute menu action
    printf "\nRunning %s().\n" "${FUNCNAME[0]}"
    pause "$debug"

    # Debug log: function exit
    debug_end "$debug"
}

force_auto_negotiate() {
    # TODO
    # Debug declarations
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Execute menu action
    printf "\nRunning %s().\n" "${FUNCNAME[0]}"
    pause

    # Debug log: function exit
    debug_end "$debug"
}

upgrade_utility() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local script_name="install.sh"
    local script_url="${GIT_RAW}/${REPO_BRANCH}/scripts/${script_name}"

    # Debug information
    debug_print "Fetching script from URL: $script_url" "$debug"

    # Validate the URL using exec_command
    if exec_command "Validate URL" "curl --head --silent --fail $script_url" "$debug"; then
        debug_print "URL is valid. Proceeding to download and execute." "$debug"
    else
        warn "Unable to get install script from Git repo $REPO_ORG/$REPO_NAME."
    fi

    # Construct the curl command to pipe the script to sudo bash
    local exec_process="curl -fsSL $script_url | sudo bash"

    # Execute the command using exec_new_shell
    exec_new_shell "Install script" "$exec_process" "$debug"

    debug_end "$debug"
}

# TODO: Do we use this?
update_hostname() {
    # clear
    local current_hostname
    current_hostname=$(nmcli general hostname)

    printf "\n"
    printf ">> ${FGYLW}Current hostname:${RESET} ${FGGRN}%s${RESET}\n" "$current_hostname"
    printf "\n"
    printf "Enter a new hostname (Enter to keep current):\n"

    read -r new_hostname || true

    if [ -n "$new_hostname" ] && [ "$new_hostname" != "$current_hostname" ]; then
        # Validate the new hostname
        if validate_hostname "$new_hostname"; then
            printf "\n"
            exec_command "Update hostname via nmcli" "nmcli general hostname $new_hostname"
            exec_command "Update /etc/hostname" "printf '%s\n' \"$new_hostname\" | tee /etc/hostname"
            exec_command "Update /etc/hosts" "sed -i 's/$(hostname)/$new_hostname/g' /etc/hosts"
            exec_command "Set hostname with hostnamectl" "hostnamectl set-hostname $new_hostname"
            exec_command "Update shell session's HOSTNAME variable" "export HOSTNAME=$new_hostname"
            exec_command "Reload hostname-related services" "systemctl restart avahi-daemon"

            printf "\n%s<< Hostname updated to:%s %s%s%s\n" \
                "$FGYLW" "$RESET" "$FGGRN" "$new_hostname" "$RESET"
        else
            printf "Invalid hostname. Please follow the hostname rules.\n" >&2
        fi
    else
        printf "Hostname unchanged.\n"
    fi
}

# TODO: Do we use this?
validate_hostname() {
    local hostname="$1"

    # Check if the hostname is empty
    if [[ -z "$hostname" ]]; then
        printf "Hostname cannot be empty.\n"
        return 1
    fi

    # Check length (1 to 63 characters)
    if [[ ${#hostname} -lt 1 || ${#hostname} -gt 63 ]]; then
        printf "Hostname must be between 1 and 63 characters.\n"
        return 1
    fi

    # Check if the hostname starts or ends with a hyphen or period
    if [[ "$hostname" =~ ^[-.] || "$hostname" =~ [-.]$ ]]; then
        printf "Hostname cannot start or end with a hyphen or period.\n"
        return 1
    fi

    # Check for valid characters (alphanumeric and hyphen only)
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9-]+$ ]]; then
        printf "Hostname can only contain alphanumeric characters and hyphens.\n"
        return 1
    fi

    # If all checks pass, return success
    return 0
}

# TODO: Not sure we are using this version
update_wifi_profile() {
    local ssid="$1"
    local password=""
    local existing_profile=""
    local connection_status=""

    printf "\nConfiguring WiFi network: %s%s%s\n" "${FGYLW}" "${ssid}" "${RESET}"

    # Check if a profile already exists for this SSID
    existing_profile=$(nmcli -t -f NAME con show | grep -F "$ssid")

    if [ -n "$existing_profile" ]; then
        # Existing profile found
        printf "An existing profile for this SSID was found: %s\n" "$existing_profile"
        printf "%bEnter the new password for the network (or press Enter to skip updating):%b\n" "${FGYLW}" "${RESET}"
        read -r password

        if [ -n "$password" ] && [ "${#password}" -ge 8 ]; then
            nmcli connection modify "$existing_profile" wifi-sec.psk "$password"
            printf "Password updated. Attempting to connect to %s.\n" "$existing_profile"
            connection_status=$(nmcli device wifi connect "$existing_profile" 2>&1)
            local retval=$?
            if [ "$retval" -eq 0 ]; then
                printf "Successfully connected to %s.\n" "$ssid"
            else
                printf "Failed to connect to %s. Error: %s\n" "$ssid" "$connection_status"
                nmcli connection delete "$existing_profile" >/dev/null 2>&1
                printf "The profile has been deleted. Please try again.\n"
            fi
        elif [ -n "$password" ]; then
            printf "Password must be at least 8 characters. No changes were made.\n"
        else
            printf "No password entered. Keeping the existing configuration.\n"
        fi
    else
        # No existing profile found, create a new one
        printf "\nNo existing profile found for %s.\n" "$ssid"
        printf "%bEnter the password for the network (minimum 8 characters):%b\n" "${FGYLW}" "${RESET}"
        read -r password

        if [ -n "$password" ] && [ "${#password}" -ge 8 ]; then
            printf "\nCreating a new profile and attempting to connect to %s.\n" "$ssid"
            connection_status=$(nmcli device wifi connect "$ssid" password "$password" 2>&1)
            local retval=$?
            if [ "$retval" -eq 0 ]; then
                printf "Successfully connected to %s and profile saved.\n" "$ssid"
            else
                printf "Failed to connect to %s. Error: %s\n" "$ssid" "$connection_status"
                printf "The new profile has not been saved.\n"
            fi
        else
            printf "Password must be at least 8 characters. No profile was created.\n"
        fi
    fi
}

execute_repo_script() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local script_name="install.sh"
    local script_url="${GIT_RAW}/${REPO_BRANCH}/scripts/${script_name}"

    # Debug information
    debug_print "Fetching script from URL: $script_url" "$debug"

    # Validate the URL using exec_command
    if exec_command "Validate URL" "curl --head --silent --fail $script_url" "$debug"; then
        debug_print "URL is valid. Proceeding to download and execute." "$debug"
    else
        warn "Unable to get install script from Git repo $REPO_ORG/$REPO_NAME."
    fi

    # Construct the curl command to pipe the script to sudo bash
    local exec_process="curl -fsSL $script_url | sudo bash"

    # Execute the command using exec_new_shell
    exec_new_shell "Install script" "$exec_process" "$debug"

    debug_end "$debug"
}

load_config() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Ensure CONFIG_FILE is set and non-empty
    if [[ -z "$CONFIG_FILE" ]]; then
        die "CONFIG_FILE is not set. Please specify the path to the configuration file."
    fi

    # Ensure the configuration file exists and is a regular file
    if [[ -f "$CONFIG_FILE" ]]; then
        # Source the configuration file to load its variables
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        debug_print "Configuration file '$CONFIG_FILE' loaded successfully." "$debug"
    else
        die "Configuration file '$CONFIG_FILE' not found or is not a regular file."
    fi

    debug_end "$debug"
}

save_config() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Ensure CONFIG_FILE is set and non-empty
    if [[ -z "$CONFIG_FILE" ]]; then
        die "CONFIG_FILE is not set. Please specify the path to save the configuration file."
    fi

    local retval base_name
    base_name="$(basename "${CONFIG_FILE}")"
    # Attempt to write to the configuration file
    {
        echo "# ${base_name}"
        echo "# Generated by save_config() on $(date)"
        echo "# Configuration for appop"
        echo "WIFI_INTERFACE=\"$WIFI_INTERFACE\""
        echo "AP_PROFILE_NAME=\"$AP_PROFILE_NAME\""
        echo "AP_SSID=\"$AP_SSID\""
        echo "AP_PASSWORD=\"$AP_PASSWORD\""
        echo "AP_IP=\"$AP_IP\""
        echo "AP_GW=\"$AP_GW\""
        echo "ENABLE_WIFI=\"$ENABLE_WIFI\""
    } > "$CONFIG_FILE"
    # shellcheck disable=SC2320
    retval=$?

    # Check for successful write
    if [[ $? -eq 0 ]]; then
        debug_print "Configuration saved to '$CONFIG_FILE' successfully." "$debug"
    else
        die "Failed to save configuration to '$CONFIG_FILE'. Check file permissions."
    fi

    debug_end "$debug"
}

############
### Main Functions
############

_main() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Check and set up the environment
    init_colors "$debug"               # Populate ANSI color variables
    process_args "$@"                  # Parse command-line arguments
    enforce_sudo "$debug"              # Ensure proper privileges for script execution
    validate_depends "$debug"          # Ensure required dependencies are installed
    validate_sys_accs "$debug"         # Verify critical system files are accessible
    validate_env_vars "$debug"         # Check for required environment variables
    check_bash "$debug"                # Ensure the script is executed in a Bash shell
    check_sh_ver "$debug"              # Verify the Bash version meets minimum requirements
    check_release "$debug"             # Check Raspbian OS version compatibility

    load_config "$@" "$debug"          # Load configuration file
    do_menu "$@" "$debug"              # Display main menu
    save_config "$@" "$debug"          # Save configuration file

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Main function entry point.
# @details This function calls `_main` to initiate the script execution. By
#          calling `main`, we enable the correct reporting of the calling
#          function in Bash, ensuring that the stack trace and function call
#          are handled appropriately during the script execution.
#
# @param "$@" Arguments to be passed to `_main`.
# @return Returns the status code from `_main`.
# -----------------------------------------------------------------------------
main() { _main "$@"; return "$?"; }

debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
main "$@" "$debug"
debug_end "$debug"
exit $?
