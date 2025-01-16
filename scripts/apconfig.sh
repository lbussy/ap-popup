#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

#########################################################################
# TODO:
#   - Develop man pages
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
# @var AP_CIDR
# @brief Access Point CIDR.
# @details The CIDR block used by the Access Point for assigning IP addresses.
# @default "192.168.50.5/16"
#
# @var AP_GATEWAY
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
declare WIFI_INTERFACE="wlan0"             # WiFi interface used by the Access Point
declare AP_PROFILE_NAME="AP_Pop-Up"        # Access Point profile name
declare AP_SSID="AP_Pop-Up"                # Access Point SSID
declare AP_PASSWORD="1234567890"           # Access Point password
declare AP_CIDR="192.168.50.5/16"          # Access Point CIDR
declare AP_GATEWAY="192.168.50.254"        # Access Point Gateway
declare ENABLE_WIFI="y"                    # Enable WiFi automatically if disabled

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
# shellcheck disable=SC2317
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
MENU_ITEMS["setup_wifi_network"]="Setup New or Edit WiFi Connection"
MENU_ITEMS["update_hostname"]="Change Hostname"
MENU_ITEMS["update_access_point_ip"]="Update Access Point IP"
MENU_ITEMS["update_access_point_ssid"]="Change the Pop-Up AP SSID or Password"
MENU_ITEMS["switch_between_wifi_and_ap"]="Live Switch between WiFi Connection and Access Point"
MENU_ITEMS["run_ap_popup"]="Run AP Pop-Up Now (force check)"
MENU_ITEMS["install_repo_script"]="Upgrade AP Pop-Up"

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
    "setup_wifi_network"
    "update_hostname"
    "update_access_point_ip"
    "update_access_point_ssid"
    "switch_between_wifi_and_ap"
    "run_ap_popup"
    "install_repo_script"
)

# -----------------------------------------------------------------------------
# @brief Displays a menu based on the given menu array.
# @details The menu items are numbered sequentially, and the user is prompted
#          for input to select an option. Pressing Enter exits the menu.
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
# shellcheck disable=SC2317
display_menu() {
    # Debug declarations
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local choice
    local i=1
    local menu_array=("${!1}")  # Array of menu keys to display

    # Display the menu header
    printf "%b%b%s%b\n\n" "$BOLD" "$FGGLD" "$MENU_HEADER" "$RESET"

    printf "%bPlease select an option:%b\n\n" "$BOLD" "$RESET"

    # Display the menu items
    for func in "${menu_array[@]}"; do
        # Fixed-width format for consistent alignment
        printf "%-4d%-30s\n" "$i" "${MENU_ITEMS[$func]}"
        ((i++))
    done

    # Read user choice
    printf "\nEnter your choice (or press Enter to exit): "
    read -r choice || true
    printf "%s\n" "$choice"

    # Validate input
    if [[ -z "$choice" ]]; then
        printf "\nExiting.\n"
        debug_end "$debug"
        exit 0
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
        if [[ "$choice" -ge 1 && "$choice" -lt "$i" ]]; then
            local func="${menu_array[choice-1]}"
            "$func" "$debug"
        else
            printf "Invalid choice. Please try again.\n"
        fi
    else
        printf "Invalid input. Please enter a number.\n"
    fi

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
# shellcheck disable=SC2317
display_main_menu() {
    # Debug declarations
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Clear screen
    # DEBUG TODO clear
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
display_sub_menu() {
    # Debug declarations
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    while true; do
        # Clear screen
        # DEBUG TODO clear
        # Display the menu
        display_menu SUB_MENU[@] "$debug"
    done

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
# shellcheck disable=SC2317
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
### AP Config Functions
############

# -----------------------------------------------------------------------------
# @brief Populate Wi-Fi network data.
# @details Extracts Wi-Fi network information using nmcli, filters out entries
#          with blank SSID, and returns the network data as an indexed array.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
populate_wifi_networks() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local wifi_info retval
    clear
    printf "%s%sAdd or modify a WiFi Network%s\n" "$FGYLW" "$BOLD" "$RESET"
    printf "\nScanning for available WiFi networks, please wait.\n"
    wifi_info=$(nmcli -t -f all --color no dev wifi list 2>/dev/null)
    retval=$?

    if [[ $retval -ne 0 ]]; then
        printf "%s\n" "Error: Failed to execute 'nmcli'. Ensure NetworkManager is running and you have the necessary permissions." >&2
        exit 1
    fi

    if [[ -z "$wifi_info" ]]; then
        printf "%s\n" "No Wi-Fi networks detected. Ensure Wi-Fi is enabled and try again." >&2
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
display_wifi_networks() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local columns_to_display=(1 8 9 10) # SSID, SIGNAL, BARS, SECURITY
    local header="NAME:SSID:SSID-HEX:BSSID:MODE:CHAN:FREQ:RATE:SIGNAL:BARS:SECURITY:WPA-FLAGS:RSN-FLAGS:DEVICE:ACTIVE:IN-USE:DBUS-PATH"

    if [[ ${#wifi_networks[@]} -eq 0 ]]; then
        printf "%s\n" "No Wi-Fi networks detected." >&2
        exit 0
    fi

    IFS=":" read -r -a full_headers <<<"$header"
    local selected_headers=()
    for index in "${columns_to_display[@]}"; do
        if [[ $index -lt ${#full_headers[@]} ]]; then
            selected_headers+=("${full_headers[index]}")
        else
            printf "%s\n" "Error: Invalid column index $index in columns_to_display." >&2
            exit 1
        fi
    done

    local num_columns=${#columns_to_display[@]}
    local max_widths=()
    for ((i = 0; i < num_columns; i++)); do
        max_widths[i]=${#selected_headers[i]}
    done

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

    clear

    printf "%s%6s%s  " "$BOLD" "CHOICE" "$RESET"
    for ((i = 0; i < num_columns; i++)); do
        printf "%s%-*s%s  " "$BOLD" "${max_widths[i]}" "${selected_headers[i]}" "$RESET"
    done
    printf "\n"

    for key in $(printf "%s\n" "${!wifi_networks[@]}" | sort -n); do
        IFS=":" read -r -a fields <<<"${wifi_networks[$key]}"

        printf "%6s  " "$key"
        for ((i = 0; i < num_columns; i++)); do
            local column_index=${columns_to_display[i]}
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
        read -rp "Select a network by index (or press Enter to exit): " choice

        if [[ -z "$choice" ]]; then
            printf "%s\n" ""
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 0 && choice <= ${#wifi_networks[@]})); then
            break
        else
            printf "%s\n" "Invalid selection. Please enter a number between 0 and ${#wifi_networks[@]}." >&2
        fi
    done

    if [[ -z "$choice" || "$choice" -eq 0 ]]; then
        printf "%s\n" ""
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

    populate_wifi_networks "$debug"
    display_wifi_networks "$debug"
    selected_ssid=$(select_wifi_network "$debug")

    # Call the function with the SSID
    if [[ -z "$selected_ssid" ]]; then
        printf "No SSID selected.\n"
    else
        update_wifi_profile "$selected_ssid" "$debug"
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Toggle between WiFi and Access Point modes using the AP Pop-Up script.
# @details
# - Runs the AP Pop-Up script directly to switch between network modes.
# - Provides feedback if the script is unavailable or not installed.
#
# @global SCRIPT_NAME The name of the AP Pop-Up script.
# @global APP_PATH    The full path to the AP Pop-Up script.
# @return None
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
switch_between_wifi_and_ap() {
    # clear
    logI "Switching between WiFi and Access Point."

    # Check if the script is available and execute it
    if which "$APP_NAME" &>/dev/null; then
        # TODO: Need an argument to force the switch
        exec_command "Calling $APP_NAME" "sudo appop"
    else
        warn "$APP_NAME not available. Install first."
    fi
}

# -----------------------------------------------------------------------------
# @brief Update the Access Point (AP) IP address and Gateway in the configuration file.
# @details Allows the user to select a base IP range, enter the third and fourth
#          octets, and validates the resulting IP and gateway settings. Updates
#          the configuration file if changes are confirmed.
#
# @global AP_CIDR The current AP IP range in CIDR format.
# @global AP_GATEWAY The current AP Gateway.
# @global CONFIG_FILE Path to the configuration file.
#
# @return None
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
update_access_point_ip() {
    clear
    local choice third_octet fourth_octet base new_ip new_gateway confirm

    # Display current AP configuration
    cat << EOF

>> ${FGYLW}Current AP IP:${RESET} ${FGGRN}$AP_CIDR${RESET}
>> ${FGYLW}Current AP GW:${RESET} ${FGGRN}$AP_GATEWAY${RESET}

Choose a new network:
    1) 192.168.xxx.xxx
    2) 10.0.xxx.xxx
    3) Cancel

EOF

    read -n 1 -t 5 -sr choice || true
    printf "\n"
    case "$choice" in
        1) base="192.168." ;;
        2) base="10.0." ;;
        3) return ;;
        *) logW "Invalid selection." ; return ;;
    esac

    printf "\nEnter the third octet (0-255):\n"
    read -r third_octet
    if ! validate_host_number "$third_octet" 255; then return; fi

    printf "\nEnter the fourth octet (0-253):\n"
    read -r fourth_octet
    if ! validate_host_number "$fourth_octet" 253; then return; fi

    third_octet=$((10#$third_octet))
    fourth_octet=$((10#$fourth_octet))

    new_ip="${base}${third_octet}.${fourth_octet}/24"
    new_gateway="${base}${third_octet}.254"

    if ! validate_subnet "$new_ip" "$new_gateway"; then return; fi

    printf "\nValidating network configuration, this will take a moment.\n"
    if ! validate_ap_configuration "$new_ip" "$new_gateway"; then return; fi

    cat << EOF

<< ${FGYLW}New AP IP will be:${RESET} ${FGGRN}$new_ip${RESET}
<< ${FGYLW}New AP GW will be:${RESET} ${FGGRN}$new_gateway${RESET}

EOF

    printf "Apply these changes? (y/N): "
    read -n 1 -t 5 -sr confirm || true
    printf "\n"
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sed -i "s|^AP_CIDR=.*|AP_CIDR=\"$new_ip\"|" "$CONFIG_FILE"
        sed -i "s|^AP_GATEWAY=.*|AP_GATEWAY=\"$new_gateway\"|" "$CONFIG_FILE"
        AP_CIDR="$new_ip"
        AP_GATEWAY="$new_gateway"
        printf "Changes applied successfully.\n"
    else
        logI "Changes canceled."
    fi
}

# -----------------------------------------------------------------------------
# @brief Update the Access Point (AP) SSID and Password in the configuration file.
# @details Prompts the user to enter a new SSID and/or password for the AP, validates
#          the inputs, and updates the configuration file accordingly.
#          Ensures that SSIDs and passwords meet character and length requirements.
#
# @global AP_SSID The current AP SSID.
# @global AP_PASSWORD The current AP password.
# @global CONFIG_FILE Path to the configuration file.
#
# @return None
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
update_access_point_ssid() {
    # clear

    cat << EOF

>> ${FGYLW}Current AP SSID:${RESET} ${FGGRN}$AP_SSID${RESET}

Enter new SSID (1-32 characters, no leading/trailing spaces, Enter to keep current):
EOF
    read -r new_ssid

    # Trim and validate SSID
    new_ssid=$(printf "%s" "$new_ssid" | xargs | sed -e 's/^"//' -e 's/"$//')
    if [[ -n "$new_ssid" ]]; then
        if [[ ${#new_ssid} -ge 1 && ${#new_ssid} -le 32 && "$new_ssid" =~ ^[[:print:]]+$ && "$new_ssid" != *" "* ]]; then
            AP_SSID="$new_ssid"
            sed -i "s/^AP_SSID=.*/AP_SSID=\"$new_ssid\"/" "$CONFIG_FILE"
            printf "\n%s<< AP SSID updated to:%s %s%s%s\n" \
                "$FGYLW" "$RESET" "$FGGRN" "$new_ssid" "$RESET"

        else
            logE "Invalid SSID. Must be 1-32 printable characters with no leading/trailing spaces."
            return
        fi
    else
        printf "Keeping the current SSID.\n"
    fi

    cat << EOF

>> ${FGYLW}Current AP Password:${RESET} ${FGGRN}$AP_PASSWORD${RESET}

Enter new password (8-63 printable characters with no leading/trailing spaces, Enter to keep current):
EOF
    read -r new_pw

    # Trim and validate password
    new_pw=$(printf "%s" "$new_pw" | xargs)
    if [[ -n "$new_pw" ]]; then
        if [[ ${#new_pw} -ge 8 && ${#new_pw} -le 63 && "$new_pw" =~ ^[[:print:]]+$ ]]; then
            AP_PASSWORD="$new_pw"
            sed -i "s/^AP_PASSWORD=.*/AP_PASSWORD=\"$new_pw\"/" "$CONFIG_FILE"
            printf "\n%s<< AP Password updated to:%s %s%s%s\n" \
                "$FGYLW" "$RESET" "$FGGRN" "$new_pw" "$RESET"
        else
            logE "Invalid password. Must be 8-63 printable characters with no leading/trailing spaces."
        fi
    else
        printf "Keeping the current password.\n"
    fi
}

# -----------------------------------------------------------------------------
# @brief Change the system hostname using `nmcli`.
# @details Prompts the user to enter a new hostname, validates the input, and
#          updates the system hostname using `nmcli`, `/etc/hostname`, and `/etc/hosts`.
#          Reloads hostname-related services and updates the current session.
#
# @global HOSTNAME The shell's current hostname variable.
# @global FGYLW    Foreground yellow color code for terminal output.
# @global FGGRN    Foreground green color code for terminal output.
# @global RESET    Reset color code for terminal output.
# @return None
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
update_hostname() {
    # clear
    local current_hostname
    current_hostname=$(nmcli general hostname)

    cat << EOF

>> ${FGYLW}Current hostname:${RESET} ${FGGRN}$current_hostname${RESET}

Enter a new hostname (Enter to keep current):
EOF

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

# -----------------------------------------------------------------------------
# @brief Updates the password for an existing WiFi network or creates a new profile.
# @details Configures the selected WiFi network by either updating the password
#          of an existing profile or creating a new profile. Validates password
#          length and attempts to connect to the network.
#
# @param $1 The SSID of the WiFi network to configure.
#
# @global FGYLW Terminal formatting for yellow foreground.
# @global RESET Terminal formatting reset sequence.
#
# @return None
# @throws Logs an error message if connection attempts fail or input is invalid.
#
# @example
# update_wifi_profile "MyNetwork"
# Output:
#   Configuring WiFi network: MyNetwork
#   An existing profile for this SSID was found: MyNetwork
#   Enter the new password for the network (or press Enter to skip updating):
#   Password updated. Attempting to connect to MyNetwork.
#   Successfully connected to MyNetwork.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
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
        printf "%sEnter the new password for the network (or press Enter to skip updating):%s\n" "${FGYLW}" "${RESET}"
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
        printf "%sEnter the password for the network (minimum 8 characters):%s\n" "${FGYLW}" "${RESET}"
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

# -----------------------------------------------------------------------------
# @brief Validate a proposed Access Point (AP) configuration.
# @details Ensures there are no network conflicts, the gateway is not in use,
#          and the subnet and gateway are valid.
#
# @param $1 The new subnet in CIDR format (e.g., "192.168.0.1/24").
# @param $2 The new gateway IP address (e.g., "192.168.0.254").
# @return 0 if valid, 1 if invalid.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
validate_ap_configuration() {
    local new_subnet="$1"
    local new_gateway="$2"

    # Check for conflicts with existing networks
    if ! validate_network_conflict "$new_subnet"; then
        logE "The selected subnet conflicts with an existing network."
        return 1
    fi

    # Check if gateway is in use
    if ping -c 1 "${new_gateway%%/*}" &>/dev/null; then
        logE "The selected gateway IP $new_gateway is already in use."
        return 1
    fi

    # Check subnet validity
    if ! validate_subnet "$new_subnet" "$new_gateway"; then
        logE "Invalid subnet or gateway configuration."
        return 1
    fi

    logI "AP configuration validated successfully."
    return 0
}

# -----------------------------------------------------------------------------
# @brief Validate a proposed hostname.
# @details Checks if the hostname adheres to the following rules:
#          - Not empty.
#          - Length between 1 and 63 characters.
#          - Does not start or end with a hyphen or period.
#          - Contains only alphanumeric characters and hyphens.
#
# @param $1 The hostname to validate.
# @return 0 if the hostname is valid, 1 otherwise.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
validate_hostname() {
    local hostname="$1"

    # Check if the hostname is empty
    if [[ -z "$hostname" ]]; then
        logE "Error: Hostname cannot be empty."
        return 1
    fi

    # Check length (1 to 63 characters)
    if [[ ${#hostname} -lt 1 || ${#hostname} -gt 63 ]]; then
        logE "Error: Hostname must be between 1 and 63 characters."
        return 1
    fi

    # Check if the hostname starts or ends with a hyphen or period
    if [[ "$hostname" =~ ^[-.] || "$hostname" =~ [-.]$ ]]; then
        logE "Error: Hostname cannot start or end with a hyphen or period."
        return 1
    fi

    # Check for valid characters (alphanumeric and hyphen only)
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9-]+$ ]]; then
        logE "Error: Hostname can only contain alphanumeric characters and hyphens."
        return 1
    fi

    # If all checks pass, return success
    return 0
}

# -----------------------------------------------------------------------------
# @brief Validate that a given number is within a specific range.
# @details Ensures the input is a non-negative integer within the range 0 to the specified maximum value.
#
# @param $1 The number to validate.
# @param $2 The maximum allowed value.
# @return Outputs "true" if valid, logs a warning and outputs nothing if invalid.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
validate_host_number() {
    local num="$1"
    local max="$2"  # Maximum allowed value

    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 0 ] && [ "$num" -le "$max" ]; then
        echo true
    else
        logW "Invalid input. Must be a number between 0 and $max."
        echo
    fi
}

# -----------------------------------------------------------------------------
# @brief Check for conflicts between a new subnet and active networks.
# @details Compares the new subnet with active subnets on the system and logs
#          any conflicts.
#
# @param $1 The new AP subnet in CIDR format (e.g., "192.168.0.1/24").
# @return 0 if no conflicts, 1 if conflicts are detected.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
validate_network_conflict() {
    local new_subnet="$1"  # New AP subnet
    local active_networks

    # Get a list of active subnets
    active_networks=$(ip -o -f inet addr show | awk '/scope global/ {split($4,a,"/"); print a[1] "/" $5}')

    # Check for overlap
    for net in $active_networks; do
        if [[ "$new_subnet" == "$net" ]]; then
            logE "Conflict detected with active network: $net"
            return 1
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# @brief Validate a subnet and its gateway.
# @details Checks if the subnet follows the CIDR format and the gateway is a valid IP address.
#
# @param $1 The subnet in CIDR format (e.g., "192.168.0.1/24").
# @param $2 The gateway IP address (e.g., "192.168.0.254").
# @return 0 if valid, 1 if invalid.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
validate_subnet() {
    local ip="$1"
    local gw="$2"

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/24$ ]] && [[ "$gw" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0  # Valid
    else
        logW "Invalid subnet or gateway."
        return 1  # Invalid
    fi
}

# -----------------------------------------------------------------------------
# @brief Execute the AP Pop-Up script to manage WiFi and Access Point switching.
# @details
# - Runs the AP Pop-Up script if it is installed and available in the system's PATH.
# - Logs the operation and handles errors if the script is not found.
#
# @global SCRIPT_NAME The name of the AP Pop-Up script.
# @global APP_PATH    The full path to the AP Pop-Up script.
# @return None
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
run_ap_popup() {
    # clear
    logI "Running AP Pop-Up."

    # Check if the script is available and execute it
    if which "$APP_NAME" &>/dev/null; then
        # TODO:  Figure out if an argument is needed
        exec_command "Calling $APP_NAME" "sudo $APP_NAME"
    else
        warn "$APP_NAME not available. Install first."
    fi
}

# -----------------------------------------------------------------------------
# @brief Loads configuration variables from a specified configuration file.
# @details This function ensures that a configuration file exists, validates
#          its path, and then sources it to load the variables into the script.
#          It logs debugging information and handles errors gracefully.
#
# @global CONFIG_FILE The path to the configuration file to be sourced.
#
# @throws Exits the script with an error message if:
#         - CONFIG_FILE is not set or empty.
#         - The specified configuration file does not exist or is invalid.
#
# @return None. If successful, the configuration variables are loaded into
#         the current shell environment.
#
# @example
# CONFIG_FILE="/etc/appop.conf"
# load_config || exit 1
# echo "WiFi Interface: $WIFI_INTERFACE"
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# @brief Download and execute the install.sh script from the repo.
# @details This function fetches the install.sh script from the 'scripts' folder
#          in the repository using curl and executes it through sudo bash.
#          Supports optional debugging to trace the execution process.
#
# @param $1 Optional debug flag ("debug" to enable debug output).
#
# @global GIT_RAW Base URL for raw GitHub content.
# @global REPO_BRANCH The branch of the repository to target.
#
# @throws Exits with a non-zero status if the command execution fails.
#
# @return None.
#
# @example
# DRY_RUN=true install_repo_script "debug"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
install_repo_script() {
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
