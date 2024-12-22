#!/usr/bin/env bash
set -uo pipefail # Setting -e is far too much work here
IFS=$'\n\t'

#########################################################################
# TODO:
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
#   - Make installed (called by .sh) idempotent/upgrade
# - Add update from GitHub in menu
#

# -----------------------------------------------------------------------------
# @var THIS_SCRIPT
# @brief The name of the script to be used in the current context.
# @details Defaults to:
#          1. The value of the `THIS_SCRIPT` environment variable (if set).
#          2. The name of the script currently running.
#          3. The default name "apconfig.sh".
# -----------------------------------------------------------------------------
declare THIS_SCRIPT="${THIS_SCRIPT:-${0##*/}}"
THIS_SCRIPT="${THIS_SCRIPT:-apconfig.sh}"

# -----------------------------------------------------------------------------
# @var RE_RUN
# @brief Optional environment variable to control re-execution behavior.
# @details Ensures that the `RE_RUN` variable is declared to prevent unbound 
#          variable errors. Defaults to "false" if not explicitly set.
# @default false
# -----------------------------------------------------------------------------
declare RE_RUN="${RE_RUN:-false}" # Use existing value, or default to "false".

# -----------------------------------------------------------------------------
# @var MAN_PAGES
# @brief List of man pages to be installed for the application.
# @details Specifies the man pages associated with the application. Each entry
#          corresponds to a specific section of the manual:
#          - `apconfig.1`: General usage guide for `apconfig`.
#          - `appop.1`: General usage guide for `appop`.
#          - `appop.5`: Configuration file reference for `appop`.
# 
# @var DIRECTORIES
# @brief List of directories used during man page installation and configuration.
# @details These directories are involved in storing and managing files related 
#          to the application:
#          - `man`: Contains the man pages for the application.
#          - `src`: Contains source files for the application.
#          - `conf`: Contains configuration files for the application.
# -----------------------------------------------------------------------------
readonly MAN_PAGES=("apconfig.1" "appop.1" "appop.5") # List of application man pages.
readonly DIRECTORIES=("man" "src" "conf")           # Relevant directories for installation.

# -----------------------------------------------------------------------------
# @file         appop.sh
# @brief        Configuration and installation details for the bash-based daemon.
# @details      This script sets variables and paths required for installing 
#               and configuring the `appop` daemon and its supporting files.
#               
#               Variables:
#               - SOURCE_APP_NAME: Name of the source script that will be installed as `appop`.
#               - DEST_APP_NAME: The final installed name of the main script (no extension).
#               - APP_PATH: Path to where the main script (appop) will be installed.
#               - SYSTEMD_PATH: Path to the systemd directory for services/timers.
#               - SERVICE_FILE: Name of the systemd service file to be created/managed.
#               - TIMER_FILE: Name of the systemd timer file to be created/managed.
#               - CONFIG_FILE: Path to the AP Pop-Up configuration file.
#               - LOG_PATH: Path to the directory where logs for the application will be stored.
# -----------------------------------------------------------------------------
readonly SOURCE_APP_NAME="${SOURCE_APP_NAME:-appop.sh}" # Name of the script that will be installed as `appop`.
readonly DEST_APP_NAME="${SOURCE_APP_NAME%.*}" # The final installed name of the main script (no extension).
readonly APP_PATH="/usr/bin/$DEST_APP_NAME" # Path to where the main script (appop) will be installed.
readonly SYSTEMD_PATH="/etc/systemd/system/" # Path to the systemd directory for services/timers.
readonly SERVICE_FILE="$DEST_APP_NAME.service" # Name of the systemd service file to be created/managed.
readonly TIMER_FILE="$DEST_APP_NAME.timer" # Name of the systemd timer file to be created/managed.
readonly CONFIG_FILE="/etc/$DEST_APP_NAME.conf" # Path to the AP Pop-Up configuration file.
declare LOG_PATH="${LOG_PATH:-/var/log/$DEST_APP_NAME}" # Path to the logs for the application.

# -----------------------------------------------------------------------------
# @var CONTROLLER_NAME
# @brief The final installed name of the main controller script (without extension).
# @details Derived from the current script's name (`THIS_SCRIPT`) by removing 
#          the file extension. This name will be used for the installed controller.
#
# @var CONTROLLER_PATH
# @brief The path where the controller script will be installed.
# @details Combines `/usr/local/sbin/` with the `CONTROLLER_NAME` to determine 
#          the full installation path of the controller script.
# -----------------------------------------------------------------------------
readonly CONTROLLER_NAME="${THIS_SCRIPT%.*}"                # Final name of the main controller script.
readonly CONTROLLER_PATH="/usr/local/sbin/$CONTROLLER_NAME" # Full path for the installed controller script.

# -----------------------------------------------------------------------------
# @var DRY_RUN
# @brief Global control for dry-run functionality.
# @details Placeholder to avoid unbound variable errors. Can be set to `true` 
#          here to enable dry-run mode globally or overridden via command-line 
#          variables. Defaults to `false` if not set.
#
# @var IS_PATH
# @brief Indicates whether the script was executed from a `PATH` location.
# @details Defaults to `false`. Dynamically set to `true` during execution if 
#          the script is confirmed to have been executed from a directory 
#          listed in the `PATH` environment variable.
#
# @var IS_GITHUB_REPO
# @brief Indicates whether the script resides in a GitHub repository or subdirectory.
# @details Defaults to `false`. Dynamically set to `true` during execution if 
#          the script is detected to be within a GitHub repository (i.e., a `.git` 
#          folder exists in the directory hierarchy).
# -----------------------------------------------------------------------------
declare DRY_RUN="${DRY_RUN:-false}"          # Controls global dry-run functionality.
declare IS_PATH="${IS_PATH:-false}"          # Indicates script execution from a PATH directory.
declare IS_GITHUB_REPO="${IS_GITHUB_REPO:-false}" # Indicates script resides in a GitHub repository.

# -----------------------------------------------------------------------------
# @var REPO_ORG
# @brief The GitHub organization or user associated with the application repository.
# @details Specifies the owner of the GitHub repository. Defaults to `lbussy` 
#          but can be overridden via environment variables.
#
# @var REPO_NAME
# @brief The name of the application repository.
# @details Used to identify the repository containing the application source code.
#          Defaults to `ap-config` but can be customized via environment variables.
#
# @var GIT_BRCH
# @brief The Git branch used for sourcing the application.
# @details Indicates the branch of the repository from which the application 
#          should source updates or configuration. Defaults to `main`.
#
# @var SEM_VER
# @brief The semantic version of the application.
# @details Provides versioning information for the application. This value is 
#          used for runtime contextual messaging and defaults to `1.0.0`.
# -----------------------------------------------------------------------------
declare REPO_ORG="${REPO_ORG:-lbussy}"      # GitHub organization/user for the repository.
declare REPO_NAME="${REPO_NAME:-ap-popup}"  # Name of the application repository.
declare GIT_BRCH="${GIT_BRCH:-main}"        # Git branch for sourcing the application.
declare SEM_VER="${SEM_VER:-1.0.0}"         # Semantic version of the application.

# -----------------------------------------------------------------------------
# @brief Logging and runtime behavior configuration.
# @details These variables control how the application behaves at runtime, 
#          including logging options and output destinations. They can be 
#          updated dynamically via environment variables or command-line arguments.
#
# @var LOG_OUTPUT
# @brief Controls logging destinations.
# @details Specifies where log output should be directed. Possible values are:
#          - "file": Logs only to the file.
#          - "console": Logs only to the console.
#          - "both": Logs to both the file and the console.
#          - unset: Defaults to "both".
# @default "both"
#
# @var LOG_FILE
# @brief Path to the log file.
# @details Specifies the file path for logging. If not set, logging to a file 
#          is disabled. This can be customized through environment variables.
# @default Blank (not set).
#
# @var LOG_LEVEL
# @brief Controls the logging verbosity level.
# @details Defines the granularity of log messages. Defaults to "DEBUG". 
#          Other possible levels (e.g., INFO, WARN, ERROR) may be configured.
# @default "DEBUG"
#
# @var USE_CONSOLE
# @brief Determines if logs are output to the console.
# @details When `true`, logs are displayed on the console alongside file logging 
#          (if enabled). When `false`, logs are only written to the file, suitable 
#          for automated or non-interactive environments.
# @default "true"
#
# @var TERSE
# @brief Toggles terse logging mode.
# @details In terse mode (`true`), logs are minimal and concise, designed for 
#          automated environments. When `false`, logs are verbose, providing 
#          detailed information for debugging and manual review.
# @default "false"
#
# @var WARN_STACK_TRACE
# @brief Flag to enable stack trace logging for warnings.
# @details Controls whether stack traces are printed alongside warning
#           messages. This is useful for debugging and tracking the
#           script's execution path.
# @default "false"
# Possible values:
# - `"true"`: Enable stack trace logging for warnings.
# - `"false"`: Disable stack trace logging for warnings (default).
# -----------------------------------------------------------------------------
declare LOG_OUTPUT="${LOG_OUTPUT:-both}"       # Default to logging to both console and file.
declare LOG_FILE="${LOG_FILE:-}"               # Use the provided LOG_FILE or default to blank.
declare LOG_LEVEL="${LOG_LEVEL:-DEBUG}"        # Default log level is DEBUG if not set.
declare USE_CONSOLE="${USE_CONSOLE:-true}"     # Default to logging to the console.
declare TERSE="${TERSE:-false}"                # Default to verbose logging mode.
declare WARN_STACK_TRACE="${WARN_STACK_TRACE:-false}"  # Default to false if not set

# -----------------------------------------------------------------------------
# @brief Environment prerequisite configuration.
# @details These variables control how the script checks for environment prerequisites 
#          such as privileges, connectivity, system requirements, and supported models. 
#          They can be updated dynamically via environment variables to adjust behavior 
#          at runtime.
#
# @var REQUIRE_SUDO
# @brief Indicates whether root privileges are required to run the script.
# @details Defaults to `true`. Can be overridden by setting the `REQUIRE_SUDO` 
#          environment variable before execution.
# @default true
#
# @var REQUIRE_INTERNET
# @brief Indicates whether internet connectivity is required.
# @details Controls whether the script verifies internet connectivity during initialization. 
#          Possible values:
#          - `"true"`: Internet connectivity is required.
#          - `"false"`: Internet connectivity is not required.
# @default "true"
#
# @var REQUIRE_MIN_BASH_VERSION
# @brief Minimum supported Bash version.
# @details Specifies the minimum Bash version required for the script to execute. 
#          Defaults to `4.0`. Set to `"none"` to disable version checks.
# @default "4.0"
#
# @var REQUIRE_MIN_OS
# @brief Minimum supported OS version.
# @details Defines the lowest OS version on which the script can run.
# @default 11
#
# @var REQUIRE_MAX_OS
# @brief Maximum supported OS version.
# @details Defines the highest OS version the script is expected to support. 
#          Use `-1` to indicate no upper limit.
# @default 15
#
# @var REQUIRE_BITNESS
# @brief Supported system bitness.
# @details Specifies whether the script supports 32-bit, 64-bit, or both types 
#          of systems. Acceptable values:
#          - `"32"`: Only 32-bit systems.
#          - `"64"`: Only 64-bit systems.
#          - `"both"`: Both 32-bit and 64-bit systems.
# @default "32"
#
# @var SUPPORTED_MODELS
# @brief Associative array of Raspberry Pi models and their support statuses.
# @details Keys represent model identifiers (e.g., name, revision codes), and 
#          values indicate whether the model is supported (`"Supported"`) or 
#          not (`"Not Supported"`). This array is readonly to prevent modifications 
#          at runtime.
# -----------------------------------------------------------------------------
readonly REQUIRE_SUDO="${REQUIRE_SUDO:-true}"            # Indicates if root privileges are required.
readonly REQUIRE_INTERNET="${REQUIRE_INTERNET:-true}"    # Controls internet connectivity checks.
readonly REQUIRE_MIN_BASH_VERSION="${REQUIRE_MIN_BASH_VERSION:-4.0}" # Minimum Bash version required.
readonly REQUIRE_MIN_OS=11                               # Minimum supported OS version.
readonly REQUIRE_MAX_OS=15                               # Maximum supported OS version.
readonly REQUIRE_BITNESS="32"                            # Supported bitness: 32-bit, 64-bit, or both.

declare -A SUPPORTED_MODELS=(
    # Unsupported Models
    ["Raspberry Pi 400|400|bcm2711"]="Not Supported"                  # Raspberry Pi 400
    ["Raspberry Pi Compute Module 4|4-compute-module|bcm2711"]="Not Supported" # Compute Module 4
    ["Raspberry Pi Compute Module 3|3-compute-module|bcm2837"]="Not Supported" # Compute Module 3
    ["Raspberry Pi Compute Module|compute-module|bcm2835"]="Not Supported"     # Original Compute Module

    # Supported Models
    ["Raspberry Pi 5|5-model-b|bcm2712"]="Supported"                  # Raspberry Pi 5 Model B
    ["Raspberry Pi 4 Model B|4-model-b|bcm2711"]="Supported"          # Raspberry Pi 4 Model B
    ["Raspberry Pi 3 Model A+|3-model-a-plus|bcm2837"]="Supported"    # Raspberry Pi 3 Model A+
    ["Raspberry Pi 3 Model B+|3-model-b-plus|bcm2837"]="Supported"    # Raspberry Pi 3 Model B+
    ["Raspberry Pi 3 Model B|3-model-b|bcm2837"]="Supported"          # Raspberry Pi 3 Model B
    ["Raspberry Pi 2 Model B|2-model-b|bcm2836"]="Supported"          # Raspberry Pi 2 Model B
    ["Raspberry Pi Model A+|model-a-plus|bcm2835"]="Supported"        # Raspberry Pi Model A+
    ["Raspberry Pi Model B+|model-b-plus|bcm2835"]="Supported"        # Raspberry Pi Model B+
    ["Raspberry Pi Model B Rev 2|model-b-rev2|bcm2835"]="Supported"   # Raspberry Pi Model B Rev 2
    ["Raspberry Pi Model A|model-a|bcm2835"]="Supported"              # Raspberry Pi Model A
    ["Raspberry Pi Model B|model-b|bcm2835"]="Supported"              # Raspberry Pi Model B
    ["Raspberry Pi Zero 2 W|model-zero-2-w|bcm2837"]="Supported"      # Raspberry Pi Zero 2 W
    ["Raspberry Pi Zero|model-zero|bcm2835"]="Supported"              # Raspberry Pi Zero
    ["Raspberry Pi Zero W|model-zero-w|bcm2835"]="Supported"          # Raspberry Pi Zero W
)
readonly SUPPORTED_MODELS

# -----------------------------------------------------------------------------
# @brief Dependency and environment validation configuration.
# @details These variables are used to validate the presence of required 
#          dependencies, environment variables, system files, and APT packages 
#          to ensure the script runs correctly. Dependencies are checked 
#          dynamically, and missing packages may be installed if required.
#
# @var DEPENDENCIES
# @type array
# @brief List of required external commands for the script.
# @details
# Specifies the external commands the script relies on. Each command is 
# validated for availability during execution. Update this list as the script evolves.
# @default A predefined list of commonly used system utilities.
#
# @var COLUMNS
# @brief Terminal width in columns.
# @details
# Defines the width of the terminal in characters. Defaults to `80` if not set 
# by the environment. Can be used for formatting purposes.
# @default 80
#
# @var ENV_VARS_BASE
# @type array
# @brief Base list of required environment variables.
# @details
# Always-required environment variables for the script, such as:
# - `HOME`: User's home directory.
# - `COLUMNS`: Terminal width for formatting.
#
# @var ENV_VARS
# @type array
# @brief Complete list of required environment variables.
# @details
# Dynamically constructed by extending `ENV_VARS_BASE`. Adds `SUDO_USER` if the script 
# requires root privileges (`REQUIRE_SUDO=true`).
#
# @var SYSTEM_READS
# @type array
# @brief List of critical system files.
# @details
# Absolute paths to system files that the script depends on. These files are checked 
# for existence and readability during execution. Examples include:
# - `/etc/os-release`: OS identification data.
# - `/proc/device-tree/compatible`: Hardware compatibility information.
#
# @var APT_PACKAGES
# @type array
# @brief List of required APT packages.
# @details
# Specifies APT packages needed by the script. These are checked for installation 
# and added dynamically if missing. Includes:
# - `jq`: JSON parsing utility.
# -----------------------------------------------------------------------------
declare -ar DEPENDENCIES=(
    "awk" "grep" "tput" "cut" "tr" "getconf" "cat" "sed" "basename" 
    "getent" "date" "printf" "whoami" "touch" "dpkg" "git" 
    "dpkg-reconfigure" "curl" "wget" "realpath"
)
readonly DEPENDENCIES

COLUMNS="${COLUMNS:-80}"  # Default to 80 columns if unset.

declare -ar ENV_VARS_BASE=(
    "HOME"       # Home directory of the current user.
    "COLUMNS"    # Terminal width for formatting.
)
readonly ENV_VARS_BASE

declare -a ENV_VARS
if [[ "$REQUIRE_SUDO" == true ]]; then
    ENV_VARS=("${ENV_VARS_BASE[@]}" "SUDO_USER")
else
    ENV_VARS=("${ENV_VARS_BASE[@]}")
fi
readonly ENV_VARS

declare -ar SYSTEM_READS=(
    "/etc/os-release"               # OS identification file.
    "/proc/device-tree/compatible"  # Hardware compatibility file.
)
readonly SYSTEM_READS

declare APT_PACKAGES=(
    "jq"  # JSON parsing utility.
)
readonly APT_PACKAGES

############
### Common Functions
############

# -----------------------------------------------------------------------------
# @brief Pads a number with spaces.
# @details Formats the input number by adding leading spaces to achieve the 
#          specified width. If the width is not provided, it defaults to 4 
#          characters. Ensures input is a valid non-negative integer and the 
#          width is a positive integer.
#
# @param $1 The number to pad. Must be a non-negative integer (e.g., "7").
# @param $2 (Optional) The width of the output. Defaults to 4 if not specified.
# @return A string containing the number padded with spaces to the specified width.
#
# @note
# - Input validation ensures that the number and width are valid integers.
# - Leading zeroes in the input are stripped to avoid octal interpretation.
#
# @example
# pad_with_spaces 7 5
# Output: "    7"  # The number "7" padded to a width of 5 characters.
# -----------------------------------------------------------------------------
pad_with_spaces() {
    local number="$1"       # Input number
    local width="${2:-4}"   # Optional width (default is 4)

    # Validate input
    if [[ -z "${number:-}" || ! "$number" =~ ^[0-9]+$ ]]; then
        die 1 "Input must be a valid non-negative integer."
    fi

    if [[ ! "$width" =~ ^[0-9]+$ || "$width" -lt 1 ]]; then
        die 1 "Error: Width must be a positive integer."
    fi

    # Strip leading zeroes to prevent octal interpretation
    number=$((10#$number))  # Forces the number to be interpreted as base-10

    # Format the number with leading spaces and return it as a string
    printf "%${width}d\n" "$number"
}

# -----------------------------------------------------------------------------
# @brief Print a detailed stack trace of the call hierarchy.
# @details Outputs a detailed stack trace, showing the sequence of function calls 
#          leading up to the point where this function was invoked. Includes optional 
#          error messages and colorized output depending on terminal capabilities.
#
# @param $1 [Log Level] The severity level of the stack trace (e.g., DEBUG, INFO, WARN, ERROR, CRITICAL).
#                        If omitted or invalid, defaults to DEBUG.
# @param $2 [Optional Message] An additional error message to display at the top of the stack trace.
#
# @global BASH_LINENO An array of line numbers corresponding to each function in the call stack.
# @global FUNCNAME An array of function names in the call stack.
# @global BASH_SOURCE An array of source file names in the call stack.
#
# @return None
#
# @note
# - The function validates input parameters and applies defaults if necessary.
# - Colorized output depends on terminal capabilities (requires support for at least 8 colors).
# - The function dynamically determines the log level and applies appropriate formatting.
#
# @example
# stack_trace "ERROR" "An unexpected error occurred"
# Output:
# ------------------ STACK TRACE ------------------
# Error: An unexpected error occurred
# [1] Function: main called from [script.sh:42]
# [2] Function: helper called from [script.sh:21]
# -------------------------------------------------
# -----------------------------------------------------------------------------
stack_trace() {
    local level="$1"
    local message="$2"
    local color=""                   # Default: no color
    local label=""                   # Log level label for display
    local header="------------------ STACK TRACE ------------------"
    local tput_colors_available      # Terminal color support
    local lineno="${BASH_LINENO[0]}" # Line number where the error occurred
    lineno=$(pad_with_spaces "$lineno") # Pad with zeroes

    # Check terminal color support
    tput_colors_available=$(tput colors 2>/dev/null || printf "0\n")

    # Disable colors if terminal supports less than 8 colors
    if [[ "$tput_colors_available" -lt 8 ]]; then
        color="\033[0m"  # No color
    fi

    # Validate level or default to DEBUG
    case "$level" in
        "DEBUG"|"INFO"|"WARN"|"ERROR"|"CRITICAL")
            ;;
        *)
            # If the first argument is not a valid level, treat it as a message
            message="$level"
            level="DEBUG"
            ;;
    esac

    # Determine color and label based on the log level
    case "$level" in
        "DEBUG")
            [[ "$tput_colors_available" -ge 8 ]] && color="\033[0;36m"  # Cyan
            label="Debug"
            ;;
        "INFO")
            [[ "$tput_colors_available" -ge 8 ]] && color="\033[0;32m"  # Green
            label="Info"
            ;;
        "WARN")
            [[ "$tput_colors_available" -ge 8 ]] && color="\033[0;33m"  # Yellow
            label="Warning"
            ;;
        "ERROR")
            [[ "$tput_colors_available" -ge 8 ]] && color="\033[0;31m"  # Red
            label="Error"
            ;;
        "CRITICAL")
            [[ "$tput_colors_available" -ge 8 ]] && color="\033[0;31m"  # Bright Red
            label="Critical"
            ;;
    esac

    # Print stack trace header
    printf "%b%s%b\n" "$color" "$header" "\033[0m" >&2
    if [[ -n "$message" ]]; then
        # If a message is provided
        printf "%b%s: %s%b\n" "$color" "$label" "$message" "\033[0m" >&2
    else
        # Default message with the line number of the caller
        local lineno="${BASH_LINENO[1]}"
        lineno=$(pad_with_spaces "$lineno") # Pad with zeroes
        printf "%b%s stack trace called by line: %s%b\n" "$color" "$label" "$lineno" "\033[0m" >&2
    fi

    # Print each function in the stack trace
    for ((i = 2; i < ${#FUNCNAME[@]}; i++)); do
        local script="${BASH_SOURCE[i]##*/}"
        local lineno="${BASH_LINENO[i - 1]}"
        lineno=$(pad_with_spaces "$lineno") # Pad with zeroes
        printf "%b[%d] Function: %s called from [%s:%s]%b\n" \
            "$color" $((i - 1)) "${FUNCNAME[i]}" "$script" "$lineno" "\033[0m" >&2
    done

    # Print stack trace footer (line of "-" matching $header)
    # shellcheck disable=SC2183
    printf "%b%s%b\n" "$color" "$(printf '%*s' "${#header}" | tr ' ' '-')" "\033[0m" >&2
}

# -----------------------------------------------------------------------------
# @brief Logs a warning or error message with optional details and a stack trace.
# @details Logs messages at the WARNING or ERROR level, optionally including 
#          additional details and a stack trace for warnings if enabled. The 
#          log level, error level, main message, and additional details can 
#          all be specified as arguments.
#
# @param $1 [Optional] The error level (numeric). Defaults to 0.
# @param $2 [Optional] The log level (WARNING or ERROR). Defaults to WARNING.
# @param $3 [Optional] The main log message. Defaults to "A warning was raised on this line."
# @param $4 [Optional] Additional details to include in the log.
#
# @global WARN_STACK_TRACE Enables stack trace logging for warnings when set to true.
# @global BASH_LINENO Array of line numbers in the call stack.
# @global SCRIPT_NAME The name of the script being executed.
#
# @return None
#
# @note
# - If `WARN_STACK_TRACE` is set to true, a stack trace is included for WARNING-level logs.
# - Input parameters are validated, and default values are applied if missing.
#
# @example
# warn 2 "ERROR" "File not found" "Path: /invalid/path"
# -----------------------------------------------------------------------------
warn() {
    local error_level="${1:-0}"          # Default error level is 0
    local level="${2:-WARNING}"         # Default log level is WARNING
    local message="${3:-A warning was raised on this line}" # Default log message
    local details="${4:-}"              # Default to no additional details
    local lineno="${BASH_LINENO[1]:-0}" # Line number where the function was called
    lineno=$(pad_with_spaces "$lineno") # Pad with spaces for consistent formatting
    message="${message}: ($error_level)"

    if [[ "$level" == "WARNING" ]]; then
        logW "$message" "$details"
    elif [[ "$level" == "ERROR" ]]; then
        logE "$message" "$details"
    fi

    if [[ "$WARN_STACK_TRACE" == "true" && "$level" == "WARNING" ]]; then
        stack_trace "$level" "Stack trace for $level at line $lineno: $message"
    fi
}

# -----------------------------------------------------------------------------
# @brief Logs a critical error, prints a stack trace, and exits the script.
# @details This function handles unrecoverable errors by logging a critical 
#          error message, printing a stack trace, and exiting the script with 
#          the specified status code. Additional error details can also be logged.
#
# @param $1 [Optional] Exit status code. Defaults to 1 if not numeric.
# @param $2 [Optional] Main error message to log.
# @param $@ [Optional] Additional details to log.
#
# @global BASH_LINENO Array of line numbers in the call stack.
# @global SCRIPT_NAME The name of the script being executed.
#
# @return Exits the script with the provided or default exit status.
#
# @note
# - If no valid exit status is provided, it defaults to 1.
# - The function logs the critical error message and optional details, then prints 
#   a stack trace and exits.
#
# @example
# die 2 "Critical error occurred" "Invalid configuration detected"
# -----------------------------------------------------------------------------
die() {
    local exit_status="$1"              # First parameter as exit status
    local message                       # Main error message
    local details                       # Additional details
    local lineno="${BASH_LINENO[0]}"    # Line number where the error occurred
    local script="$THIS_SCRIPT"         # Script name
    local level="CRITICAL"              # Error level
    local tag="CRIT "                   # Log level tag
    lineno=$(pad_with_spaces "$lineno") # Pad with spaces for consistent formatting

    if ! [[ "$exit_status" =~ ^[0-9]+$ ]]; then
        exit_status=1
        message="$1"
        shift
    else
        shift
        message="$1"
        shift
    fi
    details="$*" # Remaining parameters as details

    if [[ -n "$message" ]]; then
        printf "[%s]\t[%s:%s]\t%s\n" "$tag" "$script" "$lineno" "$message" >&2
        if [[ -n "$details" ]]; then
            printf "[%s]\t[%s:%s]\tDetails: %s\n" "$tag" "$script" "$lineno" "$details" >&2
        fi
    fi

    printf "[%s]\t[%s:%s]\tUnrecoverable error (exit status: %d).\n" \
        "$tag" "$script" "$lineno" "$exit_status" >&2

    if [[ -z "${message:-}" ]]; then
        stack_trace "$level" "Stack trace from line $lineno."
    else
        stack_trace "$level" "Stack trace from line $lineno: $message"
    fi

    exit "$exit_status"
}

# -----------------------------------------------------------------------------
# @brief Exit the script with an optional message.
# @details Prints the provided message to the console or logs it, then exits the script.
#
# @param $1 [Optional] The exit message to display. Defaults to "Exiting." if no argument is provided.
#
# @return None
#
# @example
# exit_script "Installation aborted by user."
# Output: "Installation aborted by user."
# -----------------------------------------------------------------------------
exit_script() {
    local message="${1:-Exiting.}"  # Default message if no argument is provided

    printf "%s\n" "$message"  # Print the provided or default message
    exit 0
}

# -----------------------------------------------------------------------------
# @brief Add a dot (`.`) at the beginning of a string if it's missing.
# @details Ensures the input string starts with a dot (`.`). If the input is empty, 
#          the function logs an error and returns a non-zero exit code.
#
# @param $1 The input string to process.
# @return The modified string with a leading dot, or an error if the input is invalid.
#
# @note
# - If the input already starts with a dot, it is returned unchanged.
# - If the input is empty, an error is logged, and the function exits with a status of 1.
#
# @example
# add_dot "example"
# Output: ".example"
# -----------------------------------------------------------------------------
add_dot() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to add_dot cannot be empty."
        return 1
    fi

    # Add a leading dot if it's missing
    if [[ "${input:-}" != .* ]]; then
        input=".$input"
    fi

    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Remove a leading dot (`.`) from a string if present.
# @details Ensures the input string does not start with a dot (`.`). If the input 
#          is empty, the function logs an error and returns a non-zero exit code.
#
# @param $1 The input string to process.
# @return The modified string without a leading dot, or an error if the input is invalid.
#
# @note
# - If the input does not start with a dot, it is returned unchanged.
# - If the input is empty, an error is logged, and the function exits with a status of 1.
#
# @example
# remove_dot ".example"
# Output: "example"
# -----------------------------------------------------------------------------
remove_dot() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to remove_dot cannot be empty."
        return 1
    fi

    # Remove the leading dot if present
    if [[ "$input" == .* ]]; then
        input="${input#.}"
    fi

    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Add a trailing slash (`/`) to a string if it's missing.
# @details Ensures the input string ends with a slash (`/`). If the input is empty, 
#          the function logs an error and returns a non-zero exit code.
#
# @param $1 The input string to process.
# @return The modified string with a trailing slash, or an error if the input is invalid.
#
# @note
# - If the input already ends with a slash, it is returned unchanged.
# - If the input is empty, an error is logged, and the function exits with a status of 1.
#
# @example
# add_slash "/path/to/directory"
# Output: "/path/to/directory/"
# -----------------------------------------------------------------------------
add_slash() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to add_slash cannot be empty."
        return 1
    fi

    # Add a trailing slash if it's missing
    if [[ "$input" != */ ]]; then
        input="$input/"
    fi

    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Remove a trailing slash (`/`) from a string if present.
# @details Ensures the input string does not end with a slash (`/`). If the input 
#          is empty, the function logs an error and returns a non-zero exit code.
#
# @param $1 The input string to process.
# @return The modified string without a trailing slash, or an error if the input is invalid.
#
# @note
# - If the input does not end with a slash, it is returned unchanged.
# - If the input is empty, an error is logged, and the function exits with a status of 1.
#
# @example
# remove_slash "/path/to/directory/"
# Output: "/path/to/directory"
# -----------------------------------------------------------------------------
remove_slash() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to remove_slash cannot be empty."
        return 1
    fi

    # Remove the trailing slash if present
    if [[ "$input" == */ ]]; then
        input="${input%/}"
    fi

    printf "%s\n" "$input"
}

############
### Print/Display Environment Functions
############

# -----------------------------------------------------------------------------
# @brief Print the system information to the log.
# @details Extracts and logs the system's name and version using data from 
#          `/etc/os-release`. If the information cannot be retrieved, a warning 
#          message is logged instead.
#
# @global None
# @return None
#
# @note
# - Logs a warning if the system information is unavailable or cannot be extracted.
# - Uses `logI` to log the system name and version when available.
#
# @example
# print_system
# Output (example):
# System: Ubuntu 22.04.1 LTS.
# -----------------------------------------------------------------------------
print_system() {
    local system_name  # Holds the extracted system name and version

    # Extract system name and version from /etc/os-release
    system_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d '=' -f2 | tr -d '"')

    # Check if system_name is empty
    if [[ -z "${system_name:-}" ]]; then
        logW "System: Unknown (could not extract system information)." # Warning if system information is unavailable
    else
        logI "System: $system_name." # Log the system information
    fi
}

# -----------------------------------------------------------------------------
# @brief Print the script version and optionally log it.
# @details Displays the version of the script stored in the global variable 
#          `SEM_VER`. If called by `parse_args`, the version is printed to stdout. 
#          Otherwise, it is logged using `logI`.
#
# @global THIS_SCRIPT The name of the script.
# @global SEM_VER The version of the script.
#
# @return None
#
# @note
# - If called by `parse_args`, outputs the version to stdout using `printf`.
# - If called by another function, logs the version information using `logI`.
#
# @example
# print_version
# Output (example):
# Running MyRepo's 'my_script.sh', version 1.0.0
# -----------------------------------------------------------------------------
print_version() {
    local caller  # Holds the name of the calling function

    # Check the name of the calling function
    caller="${FUNCNAME[1]}"

    if [[ "$caller" == "parse_args" ]]; then
        printf "%s: version %s\n" "$THIS_SCRIPT" "$SEM_VER" # Display the script name and version
    else
        logI "Running $(repo_to_title_case "$REPO_NAME")'s '$THIS_SCRIPT', version $SEM_VER" # Log the script name and version
    fi
}

############
### Check Environment Functions
############

# -----------------------------------------------------------------------------
# @brief Determines the execution context of the script.
# @details Identifies how the script was executed and returns a corresponding 
#          context code based on the following classifications:
#          - `0`: Script executed via a pipe.
#          - `1`: Script executed with `bash` in an unusual way.
#          - `2`: Script executed directly (local or from PATH).
#          - `3`: Script executed from within a GitHub repository.
#          - `4`: Script executed from a PATH location.
#
# @return Integer context code as described above.
#
# @note
# - Uses `warn()` for warnings and `die()` for critical errors.
# - Traverses up to 10 directory levels to detect a GitHub repository.
# - Safeguards against invalid or inaccessible script paths.
#
# @example
# determine_execution_context
# Context return code: 0 (pipe), 1 (unusual bash), 2 (direct execution), etc.
# -----------------------------------------------------------------------------
determine_execution_context() {
    local script_path   # Full path of the script
    local current_dir   # Temporary variable to traverse directories
    local max_depth=10  # Limit for directory traversal depth
    local depth=0       # Counter for directory traversal

    # Check if the script is executed via pipe
    if [[ "$0" == "bash" ]]; then
        if [[ -p /dev/stdin ]]; then
            return 0  # Execution via pipe
        else
            warn "Unusual bash execution detected."
            return 1  # Unusual bash execution
        fi
    fi

    # Get the script path
    script_path=$(realpath "$0" 2>/dev/null) || script_path=$(pwd)/$(basename "$0")
    if [[ ! -f "$script_path" ]]; then
        die 1 "Unable to resolve script path: $script_path"
    fi

    # Initialize current_dir with the directory part of script_path
    current_dir="${script_path%/*}"
    current_dir="${current_dir:-.}"

    # Safeguard against invalid current_dir during initialization
    if [[ ! -d "$current_dir" ]]; then
        die 1 "Invalid starting directory: $current_dir"
    fi

    # Traverse upwards to detect a GitHub repository
    while [[ "$current_dir" != "/" && $depth -lt $max_depth ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            return 3  # Execution within a GitHub repository
        fi
        current_dir=$(dirname "$current_dir") # Move up one directory
        ((depth++))
    done

    # Handle loop termination conditions
    if [[ $depth -ge $max_depth ]]; then
        die 1 "Directory traversal exceeded maximum depth ($max_depth)."
    fi

    # Check if the script is executed from a PATH location
    local resolved_path
    resolved_path=$(command -v "$(basename "$0")" 2>/dev/null)
    if [[ "$resolved_path" == "$script_path" ]]; then
        return 4  # Execution from a PATH location
    fi

    # Default: Direct execution from the local filesystem
    return 2
}

# -----------------------------------------------------------------------------
# @brief Handles the script execution context and performs relevant actions.
# @details Determines the execution context by calling `determine_execution_context()`. 
#          Based on the context, sets and exports global variables, logs messages, 
#          and optionally outputs debug information about the script's state.
#
# @param $1 [Optional] "debug" argument to enable debug output.
#
# @global USE_LOCAL Indicates whether local mode is enabled.
# @global IS_GITHUB_REPO Indicates whether the script resides in a GitHub repository.
# @global THIS_SCRIPT The name of the script being executed.
#
# @return None
#
# @note
# - Validates the execution context and sets appropriate global variables.
# - Provides debug output if the "debug" argument is passed.
#
# @example
# handle_execution_context debug
# Outputs execution context details in debug mode.
# -----------------------------------------------------------------------------
handle_execution_context() {
    # TODO: Need to replace is_running_from_installed_path()
    # TODO: Need to replace is_daemon_installed()
    local debug_enabled="false"
    [[ "${1:-}" == "debug" ]] && debug_enabled="true"

    # Call determine_execution_context and capture its output
    determine_execution_context
    local context=$?  # Capture the return code to determine context

    # Validate the context
    if ! [[ "$context" =~ ^[0-4]$ ]]; then
        die 1 "Invalid context code returned: $context"
    fi

    # Initialize and set global variables based on the context
    case $context in
        0)
            THIS_SCRIPT="piped_script"
            USE_LOCAL=false
            IS_GITHUB_REPO=false
            IS_PATH=false
            $debug_enabled && printf "Execution context: Script was piped (e.g., 'curl url | sudo bash').\n"
            ;;
        1)
            THIS_SCRIPT="piped_script"
            USE_LOCAL=false
            IS_GITHUB_REPO=false
            IS_PATH=false
            warn "Execution context: Script run with 'bash' in an unusual way."
            ;;
        2)
            THIS_SCRIPT=$(basename "$0")
            USE_LOCAL=true
            IS_GITHUB_REPO=false
            IS_PATH=false
            $debug_enabled && printf "Execution context: Script executed directly from %s.\n" "$THIS_SCRIPT"
            ;;
        3)
            THIS_SCRIPT=$(basename "$0")
            USE_LOCAL=true
            IS_GITHUB_REPO=true
            IS_PATH=false
            $debug_enabled && printf "Execution context: Script is within a GitHub repository.\n"
            ;;
        4)
            THIS_SCRIPT=$(basename "$0")
            USE_LOCAL=true
            IS_GITHUB_REPO=false
            IS_PATH=true
            $debug_enabled && printf "Execution context: Script executed from a PATH location (%s).\n" "$(command -v "$THIS_SCRIPT")"
            ;;
        *)
            die 99 "Unknown execution context."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# @brief Enforce that the script is run directly with `sudo`.
# @details Ensures the script is executed with `sudo` privileges under the correct 
#          conditions and not:
#          - From a `sudo su` shell.
#          - As the root user directly without `sudo`.
#          If the conditions are not met, the script exits with an error message.
#
# @global REQUIRE_SUDO Indicates whether `sudo` privileges are required.
# @global SUDO_USER The username of the user who invoked `sudo`.
# @global SUDO_COMMAND The command invoked with `sudo`.
# @global THIS_SCRIPT The name of the current script.
#
# @return None
# @exit 1 If the script is not executed with the correct `sudo` privileges.
#
# @note
# - If `REQUIRE_SUDO` is set to `true`, the function validates the execution context.
# - Improper execution contexts (e.g., from a root shell or as the root user) are rejected.
#
# @example
# enforce_sudo
# -----------------------------------------------------------------------------
enforce_sudo() {
    if [[ "$REQUIRE_SUDO" == true ]]; then
        if [[ "$EUID" -eq 0 && -n "$SUDO_USER" && "$SUDO_COMMAND" == *"$0"* ]]; then
            return 0  # Script is properly executed with `sudo`
        elif [[ "$EUID" -eq 0 && -n "$SUDO_USER" ]]; then
            die 1 "This script should not be run from a root shell." \
                  "Run it with 'sudo $THIS_SCRIPT' as a regular user."
        elif [[ "$EUID" -eq 0 ]]; then
            die 1 "This script should not be run as the root user." \
                  "Run it with 'sudo $THIS_SCRIPT' as a regular user."
        else
            die 1 "This script requires 'sudo' privileges." \
                  "Please re-run it using 'sudo $THIS_SCRIPT'."
        fi
    fi
}

# -----------------------------------------------------------------------------
# @brief Validate required dependencies and report any missing ones.
# @details Iterates through the global `DEPENDENCIES` array to check if each 
#          required dependency is installed. Logs an error for any missing 
#          dependencies and exits the script if one or more are not found.
#
# @global DEPENDENCIES Array of required dependencies.
#
# @return None
# @exit 1 If one or more dependencies are missing.
#
# @note
# - Dependencies are logged individually as errors if missing.
# - The script exits with a non-zero status if any dependencies are missing.
#
# @example
# validate_depends
# -----------------------------------------------------------------------------
validate_depends() {
    local missing=0  # Counter for missing dependencies
    local dep        # Iterator for dependencies

    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            logE "Missing dependency: $dep"
            ((missing++))
        fi
    done

    if ((missing > 0)); then
        die 1 "Missing $missing dependencies. Install them and re-run the script."
    fi
}

# -----------------------------------------------------------------------------
# @brief Validate the availability of critical system files.
# @details Checks that each file in the global `SYSTEM_READS` array exists and is 
#          readable. Logs an error for any missing or unreadable files and exits 
#          the script if issues are found.
#
# @global SYSTEM_READS Array of critical system file paths to check.
#
# @return None
# @exit 1 If one or more files are missing or unreadable.
#
# @note
# - Files must exist and have read permissions.
# - If any issues are found, the script logs the errors and exits with a non-zero status.
#
# @example
# validate_sys_accs
# -----------------------------------------------------------------------------
validate_sys_accs() {
    local missing=0  # Counter for missing or unreadable files
    local file       # Iterator for files

    for file in "${SYSTEM_READS[@]}"; do
        if [[ ! -r "$file" ]]; then
            logE "Missing or unreadable file: $file"
            ((missing++))
        fi
    done

    if ((missing > 0)); then
        die 1 "Missing or unreadable $missing critical system files. Ensure they are accessible and re-run the script."
    fi
}

# -----------------------------------------------------------------------------
# @brief Validate the existence of required environment variables.
# @details Checks whether the environment variables listed in the global `ENV_VARS` 
#          array are set. Logs any missing variables as errors and exits the script 
#          if one or more variables are missing.
#
# @global ENV_VARS Array of required environment variables.
#
# @return None
# @exit 1 If any environment variables are missing.
#
# @note
# - Logs an error for each missing variable.
# - Ensures the script has access to all required environment variables.
#
# @example
# validate_env_vars
# -----------------------------------------------------------------------------
validate_env_vars() {
    local missing=0  # Counter for missing environment variables
    local var        # Iterator for environment variables

    for var in "${ENV_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            logE "Missing environment variable: $var"
            ((missing++))
        fi
    done

    if ((missing > 0)); then
        die 1 "Missing $missing required environment variables." \
              "Ensure they are set and re-run the script."
    fi
}

# -----------------------------------------------------------------------------
# @brief Check if the script is running in a Bash shell.
# @details Ensures the script is executed in a Bash shell, as it relies on Bash-specific features. 
#          Logs an error and exits if not running in Bash.
#
# @param $1 [Optional] "debug" to enable verbose output for the check.
#
# @global BASH_VERSION The version of the Bash shell being used.
#
# @return None
# @exit 1 If the script is not running in Bash.
#
# @example
# check_bash debug
# -----------------------------------------------------------------------------
check_bash() {
    local debug_enabled="false"
    [[ "${1:-}" == "debug" ]] && debug_enabled="true"

    $debug_enabled && logD "Starting Bash environment check."

    if [[ -z "${BASH_VERSION:-}" ]]; then
        logE "This script requires Bash. Please run it with Bash."
        $debug_enabled && logD "BASH_VERSION is empty or undefined."
        exit_script 1
    fi

    $debug_enabled && logD "Bash environment is valid. Detected Bash version: $BASH_VERSION."
}

# -----------------------------------------------------------------------------
# @brief Check if the current Bash version meets the minimum required version.
# @details Validates that the running Bash version satisfies the global `REQUIRE_MIN_BASH_VERSION`. 
#          Skips the check if `REQUIRE_MIN_BASH_VERSION` is set to "none".
#
# @param $1 [Optional] "debug" to enable verbose output for this check.
#
# @global REQUIRE_MIN_BASH_VERSION Minimum required Bash version (e.g., "4.0") or "none".
# @global BASH_VERSINFO Array containing the major and minor versions of the running Bash.
#
# @return None
# @exit 1 If the Bash version is below the required version.
#
# @example
# check_sh_ver debug
# -----------------------------------------------------------------------------
check_sh_ver() {
    local debug_enabled="false"
    [[ "${1:-}" == "debug" ]] && debug_enabled="true"

    local required_version="${REQUIRE_MIN_BASH_VERSION:-none}"

    $debug_enabled && logD "Minimum required Bash version is set to '$required_version'."

    if [[ "$required_version" == "none" ]]; then
        $debug_enabled && logD "Bash version check is disabled (REQUIRE_MIN_BASH_VERSION='none')."
        return 0
    fi

    local required_major="${required_version%%.*}"
    local required_minor="${required_version##*.}"

    $debug_enabled && logD "Current Bash version is ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}."

    if (( BASH_VERSINFO[0] < required_major || 
          (BASH_VERSINFO[0] == required_major && 
           BASH_VERSINFO[1] < required_minor) )); then
        $debug_enabled && logD "Current Bash version does not meet the requirement."
        die 1 "This script requires Bash version $required_version or newer."
    fi

    $debug_enabled && logD "Current Bash version meets the requirement."
}

# -----------------------------------------------------------------------------
# @brief Check system bitness compatibility.
# @details Validates whether the current system's bitness matches the supported 
#          configuration specified in `REQUIRE_BITNESS`.
#
# @param $1 [Optional] "debug" to enable verbose output for the check.
#
# @global REQUIRE_BITNESS Specifies the bitness supported by the script ("32", "64", or "both").
#
# @return None
# @exit 1 If the system bitness is unsupported.
#
# @example
# check_bitness debug
# -----------------------------------------------------------------------------
check_bitness() {
    local debug_enabled="false"
    [[ "${1:-}" == "debug" ]] && debug_enabled="true"

    local bitness
    bitness=$(getconf LONG_BIT)
    $debug_enabled && logD "Detected system bitness: $bitness-bit."

    case "$REQUIRE_BITNESS" in
        "32")
            $debug_enabled && logD "Script supports only 32-bit systems."
            if [[ "$bitness" -ne 32 ]]; then
                die 1 "Only 32-bit systems are supported. Detected $bitness-bit system."
            fi
            ;;
        "64")
            $debug_enabled && logD "Script supports only 64-bit systems."
            if [[ "$bitness" -ne 64 ]]; then
                die 1 "Only 64-bit systems are supported. Detected $bitness-bit system."
            fi
            ;;
        "both")
            $debug_enabled && logD "Script supports both 32-bit and 64-bit systems."
            ;;
        *)
            $debug_enabled && logD "Invalid REQUIRE_BITNESS configuration: '$REQUIRE_BITNESS'."
            die 1 "Configuration error: Invalid value for REQUIRE_BITNESS ('$REQUIRE_BITNESS')."
            ;;
    esac

    $debug_enabled && logD "System bitness check passed for $bitness-bit system."
}

# -----------------------------------------------------------------------------
# @brief Check system bitness compatibility.
# @details Validates whether the current system's bitness matches the supported 
#          configuration specified in `REQUIRE_BITNESS`. Logs an error and exits 
#          if the system's bitness is unsupported.
#
# @param $1 [Optional] "debug" to enable verbose output for the check.
#
# @global REQUIRE_BITNESS Specifies the bitness supported by the script ("32", "64", or "both").
#
# @return None
# @exit 1 If the system bitness is unsupported.
#
# @example
# check_bitness debug
# -----------------------------------------------------------------------------
check_bitness() {
    local debug_enabled="false"
    [[ "${1:-}" == "debug" ]] && debug_enabled="true"

    local bitness
    bitness=$(getconf LONG_BIT)
    $debug_enabled && logD "Detected system bitness: $bitness-bit."

    case "$REQUIRE_BITNESS" in
        "32")
            $debug_enabled && logD "Script supports only 32-bit systems."
            if [[ "$bitness" -ne 32 ]]; then
                die 1 "Only 32-bit systems are supported. Detected $bitness-bit system."
            fi
            ;;
        "64")
            $debug_enabled && logD "Script supports only 64-bit systems."
            if [[ "$bitness" -ne 64 ]]; then
                die 1 "Only 64-bit systems are supported. Detected $bitness-bit system."
            fi
            ;;
        "both")
            $debug_enabled && logD "Script supports both 32-bit and 64-bit systems."
            ;;
        *)
            $debug_enabled && logD "Invalid REQUIRE_BITNESS configuration: '$REQUIRE_BITNESS'."
            die 1 "Configuration error: Invalid value for REQUIRE_BITNESS ('$REQUIRE_BITNESS')."
            ;;
    esac

    $debug_enabled && logD "System bitness check passed for $bitness-bit system."
}

# -----------------------------------------------------------------------------
# @brief Check if the detected Raspberry Pi model is supported.
# @details Reads the Raspberry Pi model from `/proc/device-tree/compatible` and 
#          checks it against a predefined list of supported models stored in the 
#          global `SUPPORTED_MODELS` array. Logs an error if the model is unsupported 
#          or cannot be detected.
#
# @param $1 [Optional] "debug" to enable verbose output for all supported/unsupported models.
#
# @global SUPPORTED_MODELS Associative array of supported and unsupported Raspberry Pi models.
#
# @return None
# @exit 1 If the detected Raspberry Pi model is unsupported or cannot be determined.
#
# @example
# check_arch debug
# -----------------------------------------------------------------------------
check_arch() {
    local detected_model is_supported key full_name model chip
    local debug_enabled="false"
    [[ "${1:-}" == "debug" ]] && debug_enabled="true"

    # Attempt to read and process the compatible string
    if ! detected_model=$(cat /proc/device-tree/compatible 2>/dev/null | tr '\0' '\n' | grep "raspberrypi" | sed 's/raspberrypi,//'); then
        die 1 "Failed to read or process /proc/device-tree/compatible. Ensure compatibility."
    fi

    # Check if the detected model is empty
    if [[ -z "${detected_model:-}" ]]; then
        die 1 "No Raspberry Pi model found in /proc/device-tree/compatible. This system may not be supported."
    fi

    # Initialize is_supported flag
    is_supported=false

    # Iterate through supported models to check compatibility
    for key in "${!SUPPORTED_MODELS[@]}"; do
        IFS='|' read -r full_name model chip <<< "$key"
        if [[ "$model" == "$detected_model" ]]; then
            if [[ "${SUPPORTED_MODELS[$key]}" == "Supported" ]]; then
                is_supported=true
                $debug_enabled && logD "Model: '$full_name' ($chip) is supported."
            else
                die 1 "Model: '$full_name' ($chip) is not supported."
            fi
            break
        fi
    done

    # Debug output of all models if requested
    if [[ "$debug_enabled" == "true" ]]; then
        for key in "${!SUPPORTED_MODELS[@]}"; do
            IFS='|' read -r full_name model chip <<< "$key"
            if [[ "${SUPPORTED_MODELS[$key]}" == "Supported" ]]; then
                logD "Model: '$full_name' ($chip) is supported."
            else
                logW "Model: '$full_name' ($chip) is not supported."
            fi
        done
    fi

    # Log an error if no supported model was found
    if [[ "$is_supported" == false ]]; then
        die 1 "Detected Raspberry Pi model '$detected_model' is not recognized or supported."
    fi
}

# -----------------------------------------------------------------------------
# @brief Validate proxy connectivity by testing a known URL.
# @details Uses the `check_url` function to verify connectivity through the 
#          specified proxy settings. Defaults to using the global `http_proxy` 
#          or `https_proxy` environment variables if no proxy URL is provided.
#
# @param $1 [Optional] Proxy URL to validate. Defaults to `http_proxy` or `https_proxy` if unset.
#
# @global http_proxy The HTTP proxy URL (if set).
# @global https_proxy The HTTPS proxy URL (if set).
#
# @return 0 If the proxy is functional.
# @return 1 If the proxy is unreachable or misconfigured.
#
# @example
# validate_proxy "http://proxy.example.com:8080"
# -----------------------------------------------------------------------------
validate_proxy() {
    local proxy_url="$1"

    # Default to global proxy settings if no proxy is provided
    [[ -z "${proxy_url:-}" ]] && proxy_url="${http_proxy:-$https_proxy}"

    # Validate that a proxy is set
    if [[ -z "${proxy_url:-}" ]]; then
        logW "No proxy URL configured for validation."
        return 1
    fi

    logI "Validating proxy: $proxy_url"

    # Test the proxy connectivity using check_url
    if check_url "http://example.com" "curl" "--silent --head --max-time 10 --proxy $proxy_url"; then
        logI "Proxy $proxy_url is functional."
        return 0
    else
        logE "Proxy $proxy_url is unreachable or misconfigured."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# @brief Check connectivity to a URL using a specified tool.
# @details Attempts to connect to the provided URL using either `curl` or `wget` 
#          based on the specified arguments. Handles timeouts and validates tool 
#          availability before performing the test.
#
# @param $1 The URL to test.
# @param $2 The tool to use for the test (`curl` or `wget`).
# @param $3 Options to pass to the testing tool (e.g., `--silent --head` for `curl`).
#
# @return 0 If the URL is reachable.
# @return 1 If the URL is unreachable or the tool is unavailable.
#
# @example
# check_url "http://example.com" "curl" "--silent --head"
# -----------------------------------------------------------------------------
check_url() {
    local url="$1"
    local tool="$2"
    local options="$3"

    # Validate inputs
    if [[ -z "${url:-}" || -z "${tool:-}" ]]; then
        logE "URL and tool parameters are required for check_url."
        return 1
    fi

    # Check tool availability
    if ! command -v "$tool" &>/dev/null; then
        logE "Tool '$tool' is not installed or unavailable."
        return 1
    fi

    # Perform the connectivity check
    if $tool $options "$url" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# @brief Comprehensive internet and proxy connectivity check.
# @details Validates proxy configuration and tests internet connectivity using 
#          both proxies (if available) and direct connections. Supports both `curl` 
#          and `wget` for the connectivity tests.
#
# @param $1 [Optional] "debug" to enable verbose output for all checks.
#
# @global http_proxy Proxy URL for HTTP (if set).
# @global https_proxy Proxy URL for HTTPS (if set).
# @global no_proxy Proxy exclusions (if set).
#
# @return 0 If all connectivity tests pass.
# @return 1 If any connectivity test fails.
#
# @example
# check_internet debug
# -----------------------------------------------------------------------------
check_internet() {
    local debug_enabled="false"
    [[ "${1:-}" == "debug" ]] && debug_enabled="true"

    local primary_url="http://google.com"
    local secondary_url="http://1.1.1.1"
    local proxy_valid=false

    # Debug mode message
    $debug_enabled && logD "Starting internet connectivity checks."

    # Validate proxy settings
    if [[ -n "${http_proxy:-}" || -n "${https_proxy:-}" ]]; then
        $debug_enabled && logD "Proxy detected. Validating proxy configuration."
        if validate_proxy; then
            proxy_valid=true
            $debug_enabled && logD "Proxy validation succeeded."
        else
            logW "Proxy validation failed. Proceeding with direct connectivity checks."
        fi
    fi

    # Check connectivity using curl
    if command -v curl &>/dev/null; then
        $debug_enabled && logD "curl is available. Testing internet connectivity using curl."

        # Check with proxy
        if $proxy_valid && curl --silent --head --max-time 10 --proxy "${http_proxy:-${https_proxy:-}}" "$primary_url" &>/dev/null; then
            logI "Internet is available using curl with proxy."
            return 0
        fi

        # Check without proxy
        if curl --silent --head --max-time 10 "$primary_url" &>/dev/null; then
            logI "Internet is available using curl without proxy."
            return 0
        fi
    fi

    # Check connectivity using wget
    if command -v wget &>/dev/null; then
        $debug_enabled && logD "wget is available. Testing internet connectivity using wget."

        # Check with proxy
        if $proxy_valid && wget --spider --quiet --timeout=10 --proxy="${http_proxy:-${https_proxy:-}}" "$primary_url" &>/dev/null; then
            logI "Internet is available using wget with proxy."
            return 0
        fi

        # Check without proxy
        if wget --spider --quiet --timeout=10 "$secondary_url" &>/dev/null; then
            logI "Internet is available using wget without proxy."
            return 0
        fi
    fi

    # Final failure message
    logE "No internet connection detected after all checks."
    return 1
}

############
### Logging Functions
############

# -----------------------------------------------------------------------------
# @brief Print a formatted log entry to the appropriate destinations.
# @details Handles logging to the console, a file, or both based on the global 
#          `LOG_OUTPUT` configuration. Formats log messages with a timestamp, 
#          log level, script name, and optional details.
#
# @param $1 Timestamp of the log entry.
# @param $2 Log level (e.g., DEBUG, INFO, WARNING, ERROR, CRITICAL).
# @param $3 Color code for console output.
# @param $4 Line number from the calling context.
# @param $5 Main log message.
# @param $6 [Optional] Additional details for the log entry.
#
# @global LOG_OUTPUT Specifies where to log messages ("file", "console", "both").
# @global LOG_FILE Path to the log file (if configured).
# @global THIS_SCRIPT The name of the script being executed.
#
# @return None
# -----------------------------------------------------------------------------
print_log_entry() {
    local timestamp="$1"
    local level="$2"
    local color="$3"
    local lineno="$4"
    local message="$5"
    local details="$6"

    # Log to file if required
    if [[ "$LOG_OUTPUT" == "file" || "$LOG_OUTPUT" == "both" ]]; then
        printf "[%s] [%s] [%s:%d] %s\n" "$timestamp" "$level" "$THIS_SCRIPT" "$lineno" "$message" >> "$LOG_FILE"
        [[ -n "$details" ]] && printf "[%s] [%s] [%s:%d] Details: %s\n" "$timestamp" "$level" "$THIS_SCRIPT" "$lineno" "$details" >> "$LOG_FILE"
    fi

    # Log to console if required
    if [[ "$LOG_OUTPUT" == "console" || "$LOG_OUTPUT" == "both" ]]; then
        printf "%b[%s] [%s:%d] %s%b\n" "$color" "$level" "$THIS_SCRIPT" "$lineno" "$message" "$RESET"
        [[ -n "$details" ]] && printf "%bDetails: %s%b\n" "$color" "$details" "$RESET"
    fi
}

# -----------------------------------------------------------------------------
# @brief Generate a timestamp and line number for log entries.
# @details Retrieves the current timestamp and the line number from the calling 
#          script's context. Formats them into a pipe-separated string for easy parsing.
#
# @return A pipe-separated string in the format: "timestamp|line_number".
#
# @example
# prepare_log_context
# Output: "2024-01-01 12:00:00|42"
# -----------------------------------------------------------------------------
prepare_log_context() {
    local timestamp lineno

    # Generate the current timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Retrieve the line number of the caller
    lineno="${BASH_LINENO[2]}"
    lineno=$(pad_with_spaces "$lineno") # Pad with spaces for consistent formatting

    # Return the pipe-separated timestamp and line number
    printf "%s|%s\n" "$timestamp" "$lineno"
}

# -----------------------------------------------------------------------------
# @brief Log a message with the specified log level.
# @details Logs messages to a file, the console, or both depending on the 
#          global `LOG_OUTPUT` configuration. Filters messages based on their 
#          severity relative to the configured log level.
#
# @param $1 Log level (e.g., DEBUG, INFO, WARNING, ERROR, CRITICAL).
# @param $2 Main log message.
# @param $3 [Optional] Extended details for the log entry.
#
# @global LOG_LEVEL The current logging verbosity level.
# @global LOG_PROPERTIES Associative array defining log level properties.
# @global LOG_FILE Path to the log file (if configured).
# @global USE_CONSOLE Boolean flag to enable or disable console output.
# @global LOG_OUTPUT Specifies where to log messages ("file", "console", "both").
# @global THIS_SCRIPT The name of the script being executed.
#
# @return None
#
# @note
# - The severity of the log level must meet or exceed the configured threshold to be logged.
# - Details are included if provided as an optional parameter.
# -----------------------------------------------------------------------------
log_message() {
    local level="${1:-DEBUG}"  # Default to "DEBUG" if $1 is unset
    local message="${2:-<no message>}"  # Default to "<no message>" if $2 is unset
    local details="${3:-}"  # Default to an empty string if $3 is unset
    local context timestamp lineno custom_level color severity config_severity

    # Prepare log context (timestamp and line number)
    context=$(prepare_log_context)
    IFS="|" read -r timestamp lineno <<< "$context"

    # Validate the provided log level and message
    if [[ -z "${message:-}" || -z "${LOG_PROPERTIES[$level]:-}" ]]; then
        printf "Invalid log level or empty message in log_message.\n" >&2
        return 1
    fi

    # Extract log properties for the specified level
    IFS="|" read -r custom_level color severity <<< "${LOG_PROPERTIES[$level]}"
    severity="${severity:-0}"  # Default severity to 0 if not defined
    color="${color:-$RESET}"   # Default to reset color if not defined

    # Extract severity threshold for the configured log level
    IFS="|" read -r _ _ config_severity <<< "${LOG_PROPERTIES[$LOG_LEVEL]}"

    # Skip logging if the message's severity is below the configured threshold
    if (( severity < config_severity )); then
        return 0
    fi

    # Print the log entry
    print_log_entry "$timestamp" "$custom_level" "$color" "$lineno" "$message" "$details"
}

# -----------------------------------------------------------------------------
# @brief Ensure the log file exists and is writable, with fallback to `/tmp` if necessary.
# @details Validates the specified log file's directory to ensure it exists and is writable. 
#          If the directory is invalid or inaccessible, attempts to create it. If all else fails, 
#          the log file is redirected to `/tmp`. Logs a warning if the fallback is used.
#
# @global LOG_FILE Path to the log file (modifiable to fallback location).
# @global THIS_SCRIPT The name of the script (used to derive fallback log file name).
#
# @return None
#
# @example
# init_log
# -----------------------------------------------------------------------------
init_log() {
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
    if [[ -d "$log_dir" && -w "$log_dir" ]]; then
        # Attempt to create the log file
        if ! touch "$LOG_FILE" &>/dev/null; then
            logW "Cannot create log file: $LOG_FILE"
            log_dir="/tmp"
        fi
    else
        log_dir="/tmp"
    fi

    # Fallback to /tmp if the directory is invalid
    if [[ "$log_dir" == "/tmp" ]]; then
        fallback_log="/tmp/$scriptname.log"
        LOG_FILE="$fallback_log"
        logW "Falling back to log file in /tmp: $LOG_FILE"
    fi

    # Attempt to create the log file in the fallback location
    if ! touch "$LOG_FILE" &>/dev/null; then
        die 1 "Unable to create log file even in fallback location: $LOG_FILE"
    fi

    readonly LOG_FILE
    export LOG_FILE
}

# -----------------------------------------------------------------------------
# @brief Logging functions for different severity levels.
# @details These functions wrap around `log_message` to simplify logging at 
#          predefined severity levels. Each function logs a message with the 
#          corresponding log level:
#          - `logD`: DEBUG (detailed debugging information).
#          - `logI`: INFO (normal operational information).
#          - `logW`: WARNING (non-critical issues).
#          - `logE`: ERROR (significant issues impacting functionality).
#          - `logC`: CRITICAL (severe issues requiring immediate attention).
#
# @param $1 Main log message.
# @param $2 [Optional] Extended details for the log entry.
#
# @global LOG_LEVEL The current logging verbosity level.
# @global LOG_PROPERTIES Associative array defining log level properties.
# @global LOG_FILE Path to the log file (if configured).
# @global USE_CONSOLE Boolean flag to enable or disable console output.
# @global LOG_OUTPUT Specifies where to log messages ("file", "console", "both").
# @global THIS_SCRIPT The name of the script being executed.
#
# @return None
#
# @example
# logD "Debugging initialization process."
# logI "Service started successfully."
# logW "Configuration file not found, using defaults."
# logE "Failed to connect to the database."
# logC "System resources exhausted. Immediate action required."
# -----------------------------------------------------------------------------
logD() { log_message "DEBUG" "${1:-}" "${2:-}"; }
logI() { log_message "INFO" "${1:-}" "${2:-}"; }
logW() { log_message "WARNING" "${1:-}" "${2:-}"; }
logE() { log_message "ERROR" "${1:-}" "${2:-}"; }
logC() { log_message "CRITICAL" "${1:-}" "${2:-}"; }

# -----------------------------------------------------------------------------
# @brief Validate the logging configuration, including `LOG_LEVEL`.
# @details Ensures that the global `LOG_LEVEL` is defined and valid based on the 
#          `LOG_PROPERTIES` associative array. If `LOG_LEVEL` is not valid, it 
#          defaults to "INFO" and logs a warning message.
#
# @global LOG_LEVEL Current logging verbosity level.
# @global LOG_PROPERTIES Associative array defining log level properties.
#
# @return None
#
# @example
# LOG_LEVEL="DEBUG"
# validate_log_level
# -----------------------------------------------------------------------------
validate_log_level() {
    # Ensure LOG_LEVEL is a valid key in LOG_PROPERTIES
    if [[ -z "${LOG_PROPERTIES[$LOG_LEVEL]:-}" ]]; then
        logW "Invalid LOG_LEVEL '$LOG_LEVEL'. Defaulting to 'INFO'."
        LOG_LEVEL="INFO"
    fi
}

# -----------------------------------------------------------------------------
# @brief Sets up the logging environment for the script.
# @details Initializes terminal colors, configures the logging environment, 
#          defines log properties, and validates the `LOG_LEVEL`. This function 
#          must be called before any logging functions are used.
#
# @global LOG_LEVEL Current logging verbosity level.
# @global LOG_PROPERTIES Associative array defining log level properties.
# @global LOG_FILE Path to the log file.
# @global THIS_SCRIPT Name of the script being executed.
#
# @note
# - Initializes terminal colors using `init_colors`.
# - Configures the log file location and directory with `init_log`.
# - Defines global log properties, including severity levels, colors, and labels.
# - Validates the configured log level to ensure compatibility.
#
# @return None
#
# @example
# setup_log
# logD "Debugging log setup."
# -----------------------------------------------------------------------------
setup_log() {
    # Initialize terminal colors
    init_colors

    # Initialize logging environment
    init_log

    # Define log properties (severity, colors, and labels)
    declare -gA LOG_PROPERTIES=(
        ["DEBUG"]="DEBUG|${FGCYN}|0"
        ["INFO"]="INFO |${FGGRN}|1"
        ["WARNING"]="WARN |${FGYLW}|2"
        ["ERROR"]="ERROR|${FGRED}|3"
        ["CRITICAL"]="CRIT |${FGMAG}|4"
        ["EXTENDED"]="EXTD |${FGCYN}|0"
    )

    # Validate the log level and log properties
    validate_log_level
}

# -----------------------------------------------------------------------------
# @brief Retrieve the terminal color code or attribute.
# @details Uses `tput` to retrieve a terminal color code or attribute (e.g., 
#          `sgr0` for reset, `bold` for bold text). If the attribute is unsupported 
#          by the terminal, the function returns an empty string.
#
# @param $1 The terminal color code or attribute to retrieve (e.g., `bold`, `smso`).
#
# @return The corresponding terminal value or an empty string if unsupported.
#
# @example
# RESET=$(default_color sgr0)
# -----------------------------------------------------------------------------
default_color() {
    tput "$@" 2>/dev/null || printf "\n"  # Fallback to an empty string on error
}

# -----------------------------------------------------------------------------
# @brief Execute and combine complex terminal control sequences.
# @details Executes `tput` commands or other shell commands to create complex 
#          terminal control sequences. Supports operations like cursor movement, 
#          clearing lines, and resetting attributes.
#
# @param $@ Commands and arguments to evaluate (supports multiple commands).
#
# @return The resulting terminal control sequence or an empty string if unsupported.
#
# @example
# printf "%s" "$(generate_terminal_sequence tput bold)"
# -----------------------------------------------------------------------------
generate_terminal_sequence() {
    local result
    # Execute the command and capture its output, suppressing errors.
    result=$("$@" 2>/dev/null || printf "\n")
    printf "%s" "$result"
}

# -----------------------------------------------------------------------------
# @brief Initialize terminal colors and text formatting.
# @details Sets up variables for foreground colors, background colors, and text 
#          formatting styles. Checks terminal capabilities and provides fallback 
#          values for unsupported or non-interactive environments. All variables 
#          are marked as `readonly`.
#
# @global RESET General reset for terminal formatting.
# @global BOLD Bold text formatting.
# @global UNDERLINE Underline text formatting.
# @global FGBLK, FGRED, FGGRN, etc. Foreground color variables.
# @global BGBLK, BGRED, BGGRN, etc. Background color variables.
#
# @return None
#
# @example
# init_colors
# printf "%sBold and red text%s\n" "$BOLD$FGRED" "$RESET"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2034
init_colors() {
    # General text attributes
    RESET=$(default_color sgr0)
    BOLD=$(default_color bold)
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
    FGBLU=$(default_color setaf 4)
    FGMAG=$(default_color setaf 5)
    FGCYN=$(default_color setaf 6)
    FGWHT=$(default_color setaf 7)
    FGRST=$(default_color setaf 9)
    FGGLD=$(default_color setaf 220)

    # Background colors
    BGBLK=$(default_color setab 0)
    BGRED=$(default_color setab 1)
    BGGRN=$(default_color setab 2)
    BGYLW=$(default_color setab 3)
    BGBLU=$(default_color setab 4)
    BGMAG=$(default_color setab 5)
    BGCYN=$(default_color setab 6)
    BGWHT=$(default_color setab 7)
    BGRST=$(default_color setab 9)

    # Set variables as readonly
    readonly RESET BOLD SMSO RMSO UNDERLINE NO_UNDERLINE
    readonly BLINK NO_BLINK ITALIC NO_ITALIC MOVE_UP CLEAR_LINE
    readonly FGBLK FGRED FGGRN FGYLW FGBLU FGMAG FGCYN FGWHT FGRST FGGLD
    readonly BGBLK BGRED BGGRN BGYLW BGBLU BGMAG BGCYN BGWHT BGRST
    readonly DOT HHR LHR
}

# -----------------------------------------------------------------------------
# @brief Generate a separator string for terminal output.
# @details Creates heavy or light horizontal rules based on the terminal width. 
#          Uses characters `═` for heavy rules and `─` for light rules.
#
# @param $1 Type of rule: "heavy" or "light".
#
# @return The generated rule string or an error message for invalid types.
#
# @example
# generate_separator heavy
# generate_separator light
# -----------------------------------------------------------------------------
generate_separator() {
    local type="${1,,}"  # Normalize to lowercase
    local width="${COLUMNS:-80}"  # Default width if COLUMNS is unavailable
    case "$type" in
        heavy) printf '═%.0s' $(seq 1 "$width") ;;
        light) printf '─%.0s' $(seq 1 "$width") ;;
        *) printf "Invalid separator type: %s\n" "$type" >&2; return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# @brief Toggle the `USE_CONSOLE` variable on or off.
# @details Updates the global `USE_CONSOLE` variable to control whether log messages 
#          are displayed in the console. Accepts "on" (to enable console logging) or 
#          "off" (to disable console logging).
#
# @param $1 The desired state: 
#           - "on": Enable console logging (`USE_CONSOLE="true"`).
#           - "off": Disable console logging (`USE_CONSOLE="false"`).
#
# @global USE_CONSOLE Controls whether log messages are displayed in the console.
#
# @return 0 If the input argument is valid and the state is updated.
# @return 1 If the input argument is invalid.
#
# @example
# toggle_console_log on
# toggle_console_log off
# -----------------------------------------------------------------------------
toggle_console_log() {
    local state="${1,,}"  # Convert input to lowercase for consistency

    case "$state" in
        on)
            logD "Console logging enabled."
            USE_CONSOLE="true"
            ;;
        off)
            USE_CONSOLE="false"
            logD "Console logging disabled."
            ;;
        *)
            logW "Invalid argument for toggle_console_log: '$state'. Expected 'on' or 'off'." >&2
            return 1
            ;;
    esac

    return 0
}

############
### Get Project Parameters (Git) Functions
############

# -----------------------------------------------------------------------------
# @brief Retrieve the Git owner or organization name from the remote URL.
# @details Extracts the owner or organization name from the remote URL of the 
#          current Git repository. The owner or organization is the first path 
#          segment after the domain in the URL. Supports both HTTPS and SSH 
#          Git URLs. If not inside a Git repository or no remote URL is configured, 
#          the function logs an error and exits with a non-zero status.
#
# @return Prints the owner or organization name to standard output if successful.
# @retval 0 Success: The owner or organization name is printed.
# @retval 1 Failure: Logs an error message and exits.
#
# @example
# get_repo_org
# Output: "organization-name"
# -----------------------------------------------------------------------------
get_repo_org() {
    local url organization

    # Retrieve the remote URL from Git configuration.
    url=$(git config --get remote.origin.url)

    # Check if the URL is non-empty.
    if [[ -n "$url" ]]; then
        # Extract the owner or organization name (supports HTTPS and SSH Git URLs).
        organization=$(printf "%s" "$url" | sed -E 's#(git@|https://)([^:/]+)[:/]([^/]+)/.*#\3#')
        printf "%s\n" "$organization"
    else
        die 1 "Not inside a Git repository or no remote URL configured."
    fi
}

# -----------------------------------------------------------------------------
# @brief Retrieve the Git project name from the remote URL.
# @details Extracts the repository name from the remote URL of the current 
#          Git repository, removing the `.git` suffix if present. If not inside 
#          a Git repository or no remote URL is configured, the function logs 
#          an error and exits with a non-zero status.
#
# @return Prints the project name to standard output if successful.
# @retval 0 Success: The project name is printed.
# @retval 1 Failure: Logs an error message and exits.
#
# @example
# get_repo_name
# Output: "repository-name"
# -----------------------------------------------------------------------------
get_repo_name() {
    local url repo_name

    # Retrieve the remote URL from Git configuration.
    url=$(git config --get remote.origin.url)

    # Check if the URL is non-empty.
    if [[ -n "$url" ]]; then
        # Extract the repository name and remove the `.git` suffix if present.
        repo_name="${url##*/}"       # Remove everything up to the last `/`.
        repo_name="${repo_name%.git}" # Remove the `.git` suffix.
        printf "%s\n" "$repo_name"
    else
        die 1 "Not inside a Git repository or no remote URL configured."
    fi
}

# -----------------------------------------------------------------------------
# @brief Convert a Git repository name to title case.
# @details Transforms a Git repository name by replacing underscores (`_`) and 
#          hyphens (`-`) with spaces and converting each word to title case. 
#          Ensures the first letter of each word is capitalized.
#
# @param $1 The Git repository name (e.g., "my_repo-name").
#
# @return Prints the repository name in title case (e.g., "My Repo Name").
# @retval 0 Success: The title-cased name is printed.
# @retval 1 Failure: Logs an error message and exits if the input is empty.
#
# @example
# repo_to_title_case "my_repo-name"
# Output: "My Repo Name"
# -----------------------------------------------------------------------------
repo_to_title_case() {
    local repo_name="$1"  # Input repository name
    local title_case      # Variable to hold the formatted name

    # Validate input
    if [[ -z "${repo_name:-}" ]]; then
        die 1 "Error: Repository name cannot be empty."
    fi

    # Replace underscores and hyphens with spaces and convert to title case
    title_case=$(printf "%s" "$repo_name" | tr '_-' ' ' | awk '{for (i=1; i<=NF; i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

    # Output the result
    printf "%s\n" "$title_case"
}

# -----------------------------------------------------------------------------
# @brief Retrieve the current Git branch name or the branch this was detached from.
# @details Fetches the name of the currently checked-out branch in a Git repository. 
#          If the repository is in a detached HEAD state, it attempts to determine 
#          the branch or tag the HEAD was detached from. Logs an error and exits 
#          if the repository is not inside a Git repository or the source branch 
#          cannot be determined.
#
# @return Prints the current branch name or the source of the detached HEAD.
# @retval 0 Success: The branch or detached source name is printed.
# @retval 1 Failure: Logs an error message and exits.
#
# @example
# get_git_branch
# Output: "main" or "Detached from branch: develop"
# -----------------------------------------------------------------------------
get_git_branch() {
    local branch detached_from

    # Retrieve the current branch name using `git rev-parse`.
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
        # Print the branch name if available and not in a detached HEAD state.
        printf "%s\n" "$branch"
    elif [[ "$branch" == "HEAD" ]]; then
        # Handle the detached HEAD state: attempt to determine the source.
        detached_from=$(git reflog show --pretty='%gs' | grep -oE 'checkout: moving from [^ ]+' | head -n 1 | awk '{print $NF}')
        if [[ -n "$detached_from" ]]; then
            printf "Detached from branch: %s\n" "$detached_from"
        else
            die 1 "Detached HEAD state: Cannot determine the source branch."
        fi
    else
        die 1 "Not inside a Git repository."
    fi
}

# -----------------------------------------------------------------------------
# @brief Get the most recent Git tag.
# @details Retrieves the most recent tag in the current Git repository using 
#          `git describe --tags --abbrev=0`. If no tags are available or the 
#          command fails, it returns an empty string.
#
# @return Prints the most recent Git tag, or an empty string if no tags exist.
# @retval 0 Success: The most recent Git tag is printed.
# @retval 1 Failure: Logs an error message and exits if not inside a Git repository.
#
# @example
# get_last_tag
# Output: "v1.2.3" or an empty line if no tags exist.
# -----------------------------------------------------------------------------
get_last_tag() {
    local tag

    # Retrieve the most recent Git tag
    tag=$(git describe --tags --abbrev=0 2>/dev/null)

    if [[ -z "$tag" ]]; then
        die 1 "No tags found or not inside a Git repository."
    fi

    printf "%s\n" "$tag"
}

# -----------------------------------------------------------------------------
# @brief Check if a tag follows semantic versioning.
# @details Validates if the given Git tag adheres to the semantic versioning 
#          format: `major.minor.patch` (e.g., "1.0.0").
#
# @param $1 The Git tag to validate.
#
# @return Prints "true" if the tag follows semantic versioning, otherwise "false".
# @retval 0 Success: Validation result is printed.
# @retval 1 Failure: If the input is invalid or the function encounters an error.
#
# @example
# is_sem_ver "1.0.0"
# Output: "true"
# -----------------------------------------------------------------------------
is_sem_ver() {
    local tag="$1"

    # Validate if the tag follows the semantic versioning format (major.minor.patch)
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf "true\n"
    else
        printf "false\n"
    fi
}

# -----------------------------------------------------------------------------
# @brief Get the number of commits since the last tag.
# @details Counts the number of commits made in the current Git repository since 
#          the specified tag. If the tag does not exist, the function returns 0.
#
# @param $1 The Git tag to count commits from.
#
# @return Prints the number of commits since the specified tag, or 0 if the tag 
#         does not exist or is invalid.
# @retval 0 Success: The commit count is printed.
# @retval 1 Failure: If the repository is invalid or inaccessible.
#
# @example
# get_num_commits "v1.0.0"
# Output: "42"
# -----------------------------------------------------------------------------
get_num_commits() {
    local tag="$1" commit_count

    # Count the number of commits since the given tag
    commit_count=$(git rev-list --count "${tag}..HEAD" 2>/dev/null || printf "0\n")

    printf "%s\n" "$commit_count"
}

# -----------------------------------------------------------------------------
# @brief Get the short hash of the current Git commit.
# @details Retrieves the short hash (typically 7 characters) of the current 
#          commit in the current Git repository. If the repository is invalid 
#          or inaccessible, the function returns an empty string.
#
# @return Prints the short hash of the current Git commit.
# @retval 0 Success: The short hash is printed.
# @retval 1 Failure: If the repository is invalid or inaccessible.
#
# @example
# get_short_hash
# Output: "abc1234"
# -----------------------------------------------------------------------------
get_short_hash() {
    local short_hash

    # Retrieve the short hash of the current Git commit
    short_hash=$(git rev-parse --short HEAD 2>/dev/null)

    printf "%s\n" "$short_hash"
}

# -----------------------------------------------------------------------------
# @brief Check if there are uncommitted changes in the working directory.
# @details Verifies whether the current Git repository has any uncommitted 
#          changes, including staged, unstaged, or untracked files. If the 
#          repository is invalid or inaccessible, it returns "false".
#
# @return Prints "true" if there are uncommitted changes, otherwise "false".
# @retval 0 Success: The status is printed.
# @retval 1 Failure: If the repository is invalid or inaccessible.
#
# @example
# get_dirty
# Output: "true" (if there are uncommitted changes)
# -----------------------------------------------------------------------------
get_dirty() {
    local changes

    # Check for uncommitted changes in the repository
    changes=$(git status --porcelain 2>/dev/null)

    if [[ -n "$changes" ]]; then
        printf "true\n"
    else
        printf "false\n"
    fi
}

# -----------------------------------------------------------------------------
# @brief Generate a semantic version string based on the state of the Git repository.
# @details Constructs a semantic version string using the following components:
#          - The latest Git tag (if it follows semantic versioning).
#          - The current branch name.
#          - The number of commits since the last tag.
#          - The short hash of the current commit.
#          - A "dirty" suffix if there are uncommitted changes in the working directory.
#
# @return Prints the generated semantic version string.
# @retval 0 Success: The semantic version string is printed.
# @retval 1 Failure: Logs an error and exits if the Git repository is invalid or inaccessible.
#
# @example
# get_sem_ver
# Output: "1.0.0-main+42.abc1234-dirty"
# -----------------------------------------------------------------------------
get_sem_ver() {
    local branch_name num_commits short_hash dirty version_string tag

    # Determine if the latest tag is a semantic version
    tag=$(get_last_tag)
    if [[ "$(is_sem_ver "$tag")" == "true" ]]; then
        version_string="$tag"
    else
        version_string="1.0.0" # Use default version if no valid tag exists
    fi

    # Retrieve the current branch name
    branch_name=$(get_git_branch)
    version_string="$version_string-$branch_name"

    # Get the number of commits since the last tag and append it to the tag
    num_commits=$(get_num_commits "$tag")
    if [[ "$num_commits" -gt 0 ]]; then
        version_string="$version_string+$num_commits"
    fi

    # Get the short hash and append it to the tag
    short_hash=$(get_short_hash)
    if [[ -n "$short_hash" ]]; then
        version_string="$version_string.$short_hash"
    fi

    # Check for a dirty working directory
    dirty=$(get_dirty)
    if [[ "$dirty" == "true" ]]; then
        version_string="$version_string-dirty"
    fi

    printf "%s\n" "$version_string"
}

# -----------------------------------------------------------------------------
# @brief Configure local or remote mode based on the Git repository context.
# @details Determines the script's operating mode (local or remote) based on the 
#          `USE_LOCAL` and `IS_GITHUB_REPO` variables. In local mode, retrieves 
#          Git repository parameters such as organization, name, branch, semantic 
#          version, and relevant paths. In remote mode, sets URLs for accessing 
#          the repository's raw content and API.
#
# @global USE_LOCAL           Indicates whether local mode is enabled.
# @global IS_GITHUB_REPO      Indicates whether the script resides in a GitHub repository.
# @global THIS_SCRIPT         Name of the current script.
# @global REPO_ORG            Git organization or owner name.
# @global REPO_NAME           Git repository name.
# @global GIT_BRCH            Current Git branch name.
# @global SEM_VER             Generated semantic version string.
# @global LOCAL_SOURCE_DIR    Path to the root of the local repository.
# @global LOCAL_WWW_DIR       Path to the `data` directory in the repository.
# @global LOCAL_SCRIPTS_DIR   Path to the `scripts` directory in the repository.
# @global GIT_RAW             URL for accessing raw files remotely.
# @global GIT_API             URL for accessing the repository API.
#
# @throws Exits with a critical error if:
#         - Local mode is enabled but the repository context is invalid.
#         - Remote mode is enabled but `REPO_ORG` or `REPO_NAME` are unset.
#
# @return None
#
# @example
# get_proj_params
# echo "Repository: $REPO_ORG/$REPO_NAME"
# -----------------------------------------------------------------------------
get_proj_params() {
    if [[ "$USE_LOCAL" == "true" && "$IS_GITHUB_REPO" == "true" ]]; then
        THIS_SCRIPT=$(basename "$0")
        REPO_ORG=$(get_repo_org) || die 1 "Failed to retrieve repository organization."
        REPO_NAME=$(get_repo_name) || die 1 "Failed to retrieve repository name."
        GIT_BRCH=$(get_git_branch) || die 1 "Failed to retrieve current branch name."
        SEM_VER=$(get_sem_ver) || die 1 "Failed to generate semantic version."

        # Get the root directory of the repository
        LOCAL_SOURCE_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
        if [[ -z "${LOCAL_SOURCE_DIR:-}" ]]; then
            die 1 "Not inside a valid Git repository. Ensure the repository is properly initialized."
        fi

        # Set local paths based on repository structure
        LOCAL_WWW_DIR="$LOCAL_SOURCE_DIR/data"
        LOCAL_SCRIPTS_DIR="$LOCAL_SOURCE_DIR/scripts"
    else
        # Configure remote access URLs
        if [[ -z "${REPO_ORG:-}" || -z "${REPO_NAME:-}" ]]; then
            die 1 "Remote mode requires REPO_ORG and REPO_NAME to be set."
        fi
        GIT_RAW="https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"
        GIT_API="https://api.github.com/repos/$REPO_ORG/$REPO_NAME"
    fi

    # Export global variables for further use
    export THIS_SCRIPT REPO_ORG REPO_NAME GIT_BRCH SEM_VER LOCAL_SOURCE_DIR
    export LOCAL_WWW_DIR LOCAL_SCRIPTS_DIR GIT_RAW GIT_API
}

############
### Get Git File Functions
############

# -----------------------------------------------------------------------------
# @brief Fetch the file tree of the repository from the GitHub API.
# @details Retrieves a recursive tree view of the specified branch.
#
# @global REPO_ORG   The GitHub organization or user owning the repository.
# @global REPO_NAME  The name of the GitHub repository.
# @global REPO_BRANCH The branch to fetch the tree from.
#
# @return JSON representation of the repository's file tree.
# -----------------------------------------------------------------------------
fetch_tree() {
    local branch_sha
    branch_sha=$(curl -s \
        "https://api.github.com/repos/$REPO_ORG/$REPO_NAME/git/ref/heads/$REPO_BRANCH" \
        | jq -r '.object.sha')

    curl -s \
        "https://api.github.com/repos/$REPO_ORG/$REPO_NAME/git/trees/$branch_sha?recursive=1"
}

# -----------------------------------------------------------------------------
# @brief Download a single file from the repository.
# @details Downloads the specified file from the repository to the given destination directory.
#
# @param $1 The file path in the repository.
# @param $2 The destination directory.
# @return None
# -----------------------------------------------------------------------------
download_file() {
    local file_path="$1"
    local dest_dir="$2"

    mkdir -p "$dest_dir"
    curl -s \
        -o "$dest_dir/$(basename "$file_path")" \
        "https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME/$REPO_BRANCH/$file_path"
}

# -----------------------------------------------------------------------------
# @brief Download files from specified directories in the repository.
# @details Fetches and downloads all files from the specified directories in the repository.
#
# @global DIRECTORIES  An array of directories to process.
# @global USER_HOME    The user's home directory.
# @return None
# -----------------------------------------------------------------------------
download_files_from_directories() {
    local dest_root="$USER_HOME/apppop" # Destination root directory
    logI "Fetching repository tree."
    local tree=$(fetch_tree)

    if [[ $(printf "%s" "$tree" | jq '.tree | length') -eq 0 ]]; then
        die 1 "Failed to fetch repository tree. Check repository details or ensure it is public."
    fi

    for dir in "${DIRECTORIES[@]}"; do
        logI "Processing directory: $dir"

        local files
        files=$(printf "%s" "$tree" | jq -r --arg TARGET_DIR "$dir/" \
            '.tree[] | select(.type=="blob" and (.path | startswith($TARGET_DIR))) | .path')

        if [[ -z "$files" ]]; then
            logI "No files found in directory: $dir"
            continue
        fi

        local dest_dir="$dest_root/$dir"
        mkdir -p "$dest_dir"

        printf "%s\n" "$files" | while read -r file; do
            logI "Downloading: $file"
            download_file "$file" "$dest_dir"
        done

        logI "Files from $dir downloaded to: $dest_dir"
    done

    logI "Files saved in: $dest_root"
    update_directory_and_files "$dest_root"
}

# -----------------------------------------------------------------------------
# @brief Update ownership and permissions for a single file.
# @details Sets appropriate ownership and permissions for the given file.
#
# @param $1 The file path.
# @param $2 The root directory for determining ownership.
# @return 0 on success, 1 on failure.
# -----------------------------------------------------------------------------
update_file() {
    local file="$1"
    local home_root="$2"

    if [[ -z "$file" || -z "$home_root" ]]; then
        logE "Usage: update_file <file> <home_root>"
        return 1
    fi

    if [[ ! -d "$home_root" ]]; then
        logE "Home root '$home_root' is not a valid directory."
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        logE "File '$file' does not exist."
        return 1
    fi

    local owner
    owner=$(stat -c '%U' "$home_root")
    if [[ -z "$owner" ]]; then
        logE "Unable to determine the owner of the home root."
        return 1
    fi

    logI "Changing ownership of '$file' to '$owner'..."
    chown "$owner":"$owner" "$file" || { logE "Failed to change ownership."; return 1; }

    if [[ "$file" == *.sh ]]; then
        logI "Setting permissions of '$file' to 700 (executable)."
        chmod 700 "$file" || { logE "Failed to set permissions to 700."; return 1; }
    else
        logI "Setting permissions of '$file' to 600."
        chmod 600 "$file" || { logE "Failed to set permissions to 600."; return 1; }
    fi

    logI "Ownership and permissions updated successfully for '$file'."
    return 0
}

# -----------------------------------------------------------------------------
# @brief Update ownership and permissions for a directory and its files.
# @details Recursively updates ownership and permissions for a directory.
#
# @param $1 The directory path.
# @global USER_HOME The user's home directory for determining ownership.
# @return 0 on success, 1 on failure.
# -----------------------------------------------------------------------------
update_directory_and_files() {
    local directory="$1"
    local home_root="$USER_HOME"

    if [[ -z "$directory" ]]; then
        logE "Usage: update_directory_and_files <directory>"
        return 1
    fi

    if [[ ! -d "$directory" ]]; then
        logE "Directory '$directory' does not exist."
        return 1
    fi

    if [[ -z "$home_root" || ! -d "$home_root" ]]; then
        logE "USER_HOME environment variable is not set or points to an invalid directory."
        return 1
    fi

    local owner
    owner=$(stat -c '%U' "$home_root")
    if [[ -z "$owner" ]]; then
        logE "Unable to determine the owner of the home root."
        return 1
    fi

    logI "Changing ownership and permissions of '$directory' tree."
    find "$directory" -type d -exec chown "$owner":"$owner" {} \; -exec chmod 700 {} \; || {
        logE "Failed to update ownership or permissions of directories."
        return 1
    }

    logI "Setting permissions of non-.sh files to 600 in '$directory'."
    find "$directory" -type f ! -name "*.sh" -exec chown "$owner":"$owner" {} \; -exec chmod 600 {} \; || {
        logE "Failed to update permissions of non-.sh files."
        return 1
    }

    logI "Setting permissions of .sh files to 700 in '$directory'."
    find "$directory" -type f -name "*.sh" -exec chown "$owner":"$owner" {} \; -exec chmod 700 {} \; || {
        logE "Failed to update permissions of .sh files."
        return 1
    }

    logI "Ownership and permissions applied to all files and directories in '$directory'."
    return 0
}

############
### Start/Stop Script Functions
############

# -----------------------------------------------------------------------------
# @brief Start the script, with optional timeout for non-interactive environments.
# @details Provides an interactive start to the script, prompting the user to 
#          press a key to proceed. If no input is received within 10 seconds, 
#          the script defaults to continuing. In terse mode, this prompt is skipped.
#
# @global TERSE Indicates whether terse mode is enabled (skips interactive messages).
# @global REPO_NAME Name of the repository, used for display purposes.
#
# @return None
#
# @example
# start_script
# Output: "Press any key to continue or 'Q' to quit (defaulting in 10 seconds)."
# -----------------------------------------------------------------------------
start_script() {
    if [[ "${TERSE:-false}" == "true" ]]; then
        logI "$(repo_to_title_case "${REPO_NAME:-Unknown}") installation beginning."
        return
    fi

    # Prompt user for input
    clear
    printf "\nStarting installation for: %s.\n" "$(repo_to_title_case "${REPO_NAME:-Unknown}")"
    printf "Press any key to continue or 'Q' to quit (defaulting in 10 seconds).\n"

    # Read a single key with a 10-second timeout
    if ! read -n 1 -sr -t 10 key < /dev/tty; then
        key=""  # Assign a default value on timeout
    fi

    # Handle user input
    case "${key}" in
        [Qq])  # Quit
            logD "Installation canceled by user."
            exit_script 0
            ;;
        "")  # Timeout or Enter
            logI "No key pressed (timeout or Enter). Proceeding with installation."
            ;;
        *)  # Any other key
            logI "Key pressed: '${key}'. Proceeding with installation."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# @brief End the script with an optional completion message.
# @details Provides feedback to indicate that the script completed successfully. 
#          If `TERSE` mode is enabled, logs the completion message without console output.
#
# @global TERSE Controls whether terse mode is enabled (affects console output).
# @global REPO_NAME Name of the repository, used for display purposes.
# @global USE_CONSOLE Controls whether console output is enabled.
#
# @return None
#
# @example
# finish_script
# Output: "Installation complete: Repository Name."
# -----------------------------------------------------------------------------
finish_script() {
    if [[ "${TERSE:-false}" == "true" ]]; then
        logI "Installation complete: $(repo_to_title_case "$REPO_NAME")."
        return
    fi

    clear
    printf "Installation complete: %s.\n" "$(repo_to_title_case "$REPO_NAME")"
}

############
### Command Execution Functions
############

# -----------------------------------------------------------------------------
# @brief Execute a command and return its success or failure.
# @details Executes a given command, logs its status, and optionally displays 
#          status messages on the console based on the value of `USE_CONSOLE`. 
#          If `DRY_RUN` is enabled, the command is not executed, and the function 
#          simulates success with a delay.
#
# @param $1 The name or description of the operation (e.g., "Installing package").
# @param $2 The command or process to execute (e.g., "apt-get install -y package").
#
# @global DRY_RUN Indicates whether the script is in dry run mode.
# @global USE_CONSOLE Controls whether log messages are displayed in the console.
# @global FGGLD, FGGRN, FGRED Foreground color codes for status messages.
# @global RESET Terminal reset code.
# @global MOVE_UP Terminal control sequence to move the cursor up.
#
# @return 0 (true) if the command succeeds.
# @return 1 (false) if the command fails.
#
# @example
# exec_command "Installing package" "apt-get install -y package"
# -----------------------------------------------------------------------------
exec_command() {
    local exec_name="$1"            # The name/message for the operation
    local exec_process="$2"         # The command/process to execute
    local result                    # To store the exit status of the command

    local running_pre="Running"    # Prefix for running message
    local complete_pre="Complete"  # Prefix for success message
    local failed_pre="Failed"      # Prefix for failure message
    if [[ "${DRY_RUN}" == "true" ]]; then
        local dry=" (dry)"
        running_pre+="$dry"
        complete_pre+="$dry"
        failed_pre+="$dry"
    fi
    running_pre+=":"
    complete_pre+=":"
    failed_pre+=":"

    logI "$running_pre '$exec_name'."

    # Log the running line
    if [[ "${USE_CONSOLE}" == "false" ]]; then
        printf "%b[-]%b\t%s %s.\n" "${FGGLD}${BOLD}" "$RESET" "$running_pre" "$exec_name"
    fi

    # If it's a DRY_RUN just use sleep
    if [[ "${DRY_RUN}" == "true" ]]; then
        sleep 1  # Simulate execution delay
        result=0 # Simulate success
    else
        # Execute the task command, suppress output, and capture result
        result=$(
            {
                result=0
                eval "$exec_process" > /dev/null 2>&1 || result=$?
                printf "%s" "$?"
            }
        )
    fi

    # Move the cursor up and clear the entire line if USE_CONSOLE is false
    if [[ "${USE_CONSOLE}" == "false" ]]; then
        printf "%s" "$MOVE_UP"
    fi

    # Handle success or failure
    if [ "$result" -eq 0 ]; then
        # Success case
        if [[ "${USE_CONSOLE}" == "false" ]]; then
            printf "%b[✔]%b\t %s.\n" "${FGGRN}${BOLD}" "${RESET}" "$complete_pre" "$exec_name"
        fi
        logI "$complete_pre $exec_name"
        return 0 # Success (true)
    else
        # Failure case
        if [[ "${USE_CONSOLE}" == "false" ]]; then
            printf "%b[✘]%b\t%s %s (%s).\n" "${FGRED}${BOLD}" "${RESET}" "$failed_pre" "$exec_name" "$result"
        fi
        logE "$failed_pre $exec_name"
        return 1 # Failure (false)
    fi
}

# -----------------------------------------------------------------------------
# @brief Execute a command, replacing the current shell process.
# @details This function replaces the current shell process with the specified 
#          command. If `DRY_RUN` is enabled, the command is simulated, and the 
#          current process does not exit. Logs the operation status and ensures 
#          proper validation of the executable command.
#
# @param $1 The name or description of the operation (e.g., "Restart Service").
#           Defaults to "Unnamed Operation" if not provided.
# @param $2 The command or process to execute. Defaults to `true` (a no-op command) 
#           if not provided.
#
# @global DRY_RUN Indicates whether the script is in dry run mode.
# @global MOVE_UP Moves the cursor up one line in the terminal.
# @global CLEAR_LINE Clears the current line in the terminal.
# @global FGGLD Foreground color for gold text.
# @global FGGRN Foreground color for green text.
# @global RESET Terminal reset code.
#
# @throws Exits with an error if the command is not executable or not found 
#         when `DRY_RUN` is disabled.
#
# @return None
#
# @example
# exec_new_shell "Re-run Script" "/usr/local/bin/my_script.sh"
# Output:
# [✔] Running: Re-run Script.
# -----------------------------------------------------------------------------
exec_new_shell() {
    local exec_name="${1:-Unnamed Operation}"   # Default to "Unnamed Operation" if $1 is unset
    local exec_process="${2:-true}"             # Default to "true" if $2 is unset (a no-op command)
    local start_prefix="Running"
    local sim_prefix="Simulating"
    local script_path="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

    exec_process="$(remove_dot "$exec_process")"   # Remove trailing period
    exec_name="$(remove_dot "$exec_name")"         # Remove trailing period

    if [ "${DRY_RUN:-false}" = "true" ]; then
        # Simulate execution during a dry run
        printf "%b[-]%b %s: %s. Command: \"%s\".\n" "$BOLD$FGGLD" "$RESET" "$sim_prefix" "$exec_name" "$exec_process"
        sleep 3
        # Move the cursor up and clear the line
        printf "%b" "${MOVE_UP}${CLEAR_LINE}"
        # Log the operation as completed
        printf "%b[✔]%b %s: %s.\n" "$BOLD$FGGRN" "$RESET" "$start_prefix" "$exec_name"
        logI "Exiting after simulating re-spawn."
    else
        # Validate exec_process
        if [[ -z "$exec_process" || ! -x "$exec_process" ]]; then
            echo "ERROR: $exec_process is not executable or not found!"
            exit 1
        fi

        # Execute the command, replacing the current shell process
        printf "%b[✔]%b %s: %s.\n" "$BOLD$FGGRN" "$RESET" "$start_prefix" "$exec_name"
        exec env SOURCE_DIR="$script_path" RE_RUN=true "$exec_process"
    fi
}

############
### Instal/Uninstall Functions
############

# -----------------------------------------------------------------------------
# @brief Installs or upgrades all packages in the `APT_PACKAGES` list.
# @details Updates the package list and resolves broken dependencies before proceeding 
#          with the installation or upgrade of packages in the `APT_PACKAGES` array. 
#          Skips execution if the `APT_PACKAGES` array is empty.
#
# @global APT_PACKAGES Array containing the list of required APT packages.
#
# @return Logs the success or failure of each operation.
# @retval 0 All packages were successfully handled.
# @retval >0 Indicates the number of errors encountered during package handling.
#
# @example
# APT_PACKAGES=("curl" "wget" "git")
# handle_apt_packages
# -----------------------------------------------------------------------------
handle_apt_packages() {
    # Check if APT_PACKAGES is empty
    if [[ ${#APT_PACKAGES[@]} -eq 0 ]]; then
        logI "No packages specified in APT_PACKAGES. Skipping package handling."
        return 0
    fi

    local package error_count=0  # Counter for failed operations

    logI "Updating and managing required packages (this may take a few minutes)."

    # Update package list and fix broken installs
    if ! exec_command "Update local package index" "sudo apt-get update -y"; then
        logE "Failed to update package list."
        ((error_count++))
    fi
    if ! exec_command "Fixing broken or incomplete package installations" "sudo apt-get install -f -y"; then
        logE "Failed to fix broken installs."
        ((error_count++))
    fi

    # Install or upgrade each package in the list
    for package in "${APT_PACKAGES[@]}"; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
            if ! exec_command "Upgrade $package" "sudo apt-get install --only-upgrade -y $package"; then
                logW "Failed to upgrade package: $package."
                ((error_count++))
            fi
        else
            if ! exec_command "Install $package" "sudo apt-get install -y $package"; then
                logW "Failed to install package: $package."
                ((error_count++))
            fi
        fi
    done

    # Log summary of errors
    if ((error_count > 0)); then
        logE "APT package handling completed with $error_count errors."
    else
        logI "APT package handling completed successfully."
    fi

    return $error_count
}

# -----------------------------------------------------------------------------
# @brief Install the controller script if not already installed.
# @details Installs the current script to the specified `CONTROLLER_PATH` if it 
#          meets the required conditions:
#          - The script is not running from an already installed path.
#          - The script is not being re-run (`RE_RUN` is not set to `true`).
#
#          After installation, the script replaces itself in memory with the 
#          newly installed version using `exec_new_shell`.
#
# @global RE_RUN            Indicates if the script is being re-run.
# @global CONTROLLER_PATH   The target path where the controller script should be installed.
# @global THIS_SCRIPT       The name of the current script.
#
# @return None
#
# @throws Exits the script if any installation or permission change command fails.
#
# @example
# install_controller_script
# Output:
#   Installing this tool as /usr/local/sbin/controller_name.
# -----------------------------------------------------------------------------
install_controller_script() {
    # Call is_running_from_installed_path once and store the result
    local is_installed
    if is_running_from_installed_path; then
        is_installed=true
    else
        is_installed=false
    fi

    # Evaluate the conditions
    condition1=$([[ "${RE_RUN:-false}" != "true" ]] && echo true || echo false)
    condition2=$([[ "$is_installed" == "false" ]] && echo true || echo false)

    if [[ "$condition1" == "true" && "$condition2" == "true" ]]; then
        logI "Installing this tool as $CONTROLLER_PATH."

        # Get the directory of the current script
        local script_path
        script_path="$(dirname "$(readlink -f "$0")")"

        exec_command "Installing controller" "cp -f \"$script_path/$THIS_SCRIPT\" \"$CONTROLLER_PATH\""
        exec_command "Change permissions on controller" "chmod +x \"$CONTROLLER_PATH\""
    fi

    # Replace the current running script in memory with the installed version
    exec_new_shell "Re-spawning (1) from $CONTROLLER_PATH" "$CONTROLLER_PATH"
}

# -----------------------------------------------------------------------------
# @brief Install and configure man pages for the script.
# @details Copies the man page files specified in the `MAN_PAGES` array to their 
#          respective directories under `/usr/share/man`. Updates the man page 
#          database after installation.
#
# @global MAN_PAGES Array containing the names of the man pages to install.
#
# @return None
# @throws Exits with an error if any command fails during the process.
#
# @example
# install_man_pages
# Output:
#   Creating directory: /usr/share/man/man1/
#   Installing man page apconfig.1
#   Installing man page appop.1
#   Updating man page database.
# -----------------------------------------------------------------------------
install_man_pages() {
    # Base directory for man pages
    return # TODO: DEBUG: Commented to speed things up
    man_base_dir="/usr/share/man"

    # Loop through the man pages
    for man_page in "${MAN_PAGES[@]}"; do
        # Extract the section number from the file name
        section="${man_page##*.}"

        # Target directory based on the section number
        target_dir="${man_base_dir}/man${section}"

        # Ensure the target directory exists
        if [[ ! -d "$target_dir" ]]; then
            exec_command "Creating directory: $target_dir/" "mkdir -p '$target_dir'"
        fi

        # Install the man page
        exec_command "Installing man page $man_page" "sudo cp '$man_page' '$target_dir'"
    done

    # Update the man page database
    exec_command "Updating man page database." "mandb"

    logI "Man pages installed successfully."
}

# -----------------------------------------------------------------------------
# @brief Install the AP Pop-Up script and its dependencies.
# @details Copies the script to `/usr/bin`, ensures required APT packages are 
#          installed, and configures the necessary systemd services, timers, 
#          and man pages. If the controller script is not installed, it will 
#          be set up and the script will relaunch itself.
#
# @global SOURCE_APP_NAME The name of the script to install.
# @global APP_PATH The target installation path for the script.
#
# @return None
# @throws Exits with an error if the source script is not found or if any step 
#         in the installation process fails.
#
# @example
# install_ap_popup
# Output:
#   Installing apconfig.sh...
#   Installing controller...
# -----------------------------------------------------------------------------
install_ap_popup() {
    local source_dir="${source_dir:-"$(pwd)"}"

    # Verify that the source script exists
    if [ ! -f "$source_dir/$SOURCE_APP_NAME" ]; then
        die 1 "Error: $SOURCE_APP_NAME not found in $source_dir. Cannot continue."
    fi

    # Install the main script to the application path
    exec_command "Installing $SOURCE_APP_NAME" "cp '$source_dir/$SOURCE_APP_NAME' '$APP_PATH'"
    chmod +x "$APP_PATH"

    # Check and install APT packages if needed
    check_apt_packages

    # Ensure the configuration file exists
    check_config_file

    # Create and enable the required systemd service
    create_systemd_service

    # Create and enable the required systemd timer
    create_systemd_timer

    # Install man pages for the application
    install_man_pages

    # Install the controller script and relaunch
    install_controller_script
}

# -----------------------------------------------------------------------------
# @brief Ensure the configuration file exists and is properly configured.
# @details Checks for the presence of the configuration file (`CONFIG_FILE`) 
#          and installs a default configuration if missing. The default 
#          configuration is sourced from the `conf` directory relative to the 
#          script's source directory. Loads the configuration if it exists.
#
# @global CONFIG_FILE The path to the configuration file.
# @global SCRIPT_NAME The name of the script (used for default configuration).
# @global source_dir The base directory for finding the configuration file.
#
# @return None
# @throws Exits with an error if the configuration file cannot be found or installed.
#
# @example
# check_config_file
# Output:
#   Creating default configuration file at /etc/apconfig.conf.
#   Configuration loaded.
# -----------------------------------------------------------------------------
check_config_file() {
    # Ensure the configuration file exists
    local source_dir="${source_dir:-"$(pwd)"}"

    if [[ ! -f "$CONFIG_FILE" && -d "$source_dir" ]]; then
        local conf_path="$source_dir/../conf/$SCRIPT_NAME.conf"
        local expanded_path
        expanded_path=$(eval echo "$conf_path")

        echo "$expanded_path"   # TODO: DEBUG
        pause                   # TODO: DEBUG

        if [[ -f "$expanded_path" ]]; then
            logI "Creating default configuration file at $CONFIG_FILE."
            exec_command "Installing default configuration" "cp \"$expanded_path\" \"$CONFIG_FILE\""
            chown root:root "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
        else
            die 1 "$SCRIPT_NAME.conf not found. Cannot continue."
        fi
    elif [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE" || die 1 "$CONFIG_FILE not found."
        logI "Configuration loaded."
    fi
}

# -----------------------------------------------------------------------------
# @brief Uninstall the AP Pop-Up script and related systemd services and timers.
# @details
# - Stops and disables systemd services and timers associated with AP Pop-Up.
# - Removes configuration files, log directories, and man pages.
# - Ensures complete cleanup of the AP Pop-Up installation.
#
# @global SERVICE_FILE    Name of the systemd service file.
# @global TIMER_FILE      Name of the systemd timer file.
# @global SYSTEMD_PATH    Path to systemd unit files.
# @global LOG_PATH        Directory for log files.
# @global CONFIG_FILE     Path to the configuration file.
# @global APP_PATH        Path to the AP Pop-Up executable script.
# @global CONTROLLER_PATH Path to the controller script.
# @global MAN_PAGES       Array of man page file names.
# @global SCRIPT_NAME     Name of the script being uninstalled.
# @return None
# -----------------------------------------------------------------------------
uninstall_ap_popup() {
    # clear
    logI "Uninstalling AP Pop-Up."

    # Remove the systemd service
    if systemctl -all list-unit-files "$SERVICE_FILE" | grep -q "$SERVICE_FILE"; then
        logI "Removing systemd service: $SERVICE_FILE"
        exec_command "Stopping $SERVICE_FILE" "systemctl stop $SERVICE_FILE"
        exec_command "Disabling $SERVICE_FILE" "systemctl disable $SERVICE_FILE"
        exec_command "Unmasking $SERVICE_FILE" "systemctl unmask $SERVICE_FILE"
        exec_command "Removing $SERVICE_FILE" "rm -f $SYSTEMD_PATH/$SERVICE_FILE"
        exec_command "Reloading systemd" "systemctl daemon-reload"
        exec_command "Removing log target" "rm -fr $LOG_PATH/"
    fi

    # Remove the systemd timer
    if systemctl -all list-unit-files "$TIMER_FILE" | grep -q "$TIMER_FILE"; then
        logI "Removing systemd timer: $TIMER_FILE"
        exec_command "Stopping $TIMER_FILE" "systemctl stop $TIMER_FILE"
        exec_command "Disabling $TIMER_FILE" "systemctl disable $TIMER_FILE"
        exec_command "Unmasking $TIMER_FILE" "systemctl unmask $TIMER_FILE"
        exec_command "Removing $TIMER_FILE" "rm -f $SYSTEMD_PATH/$TIMER_FILE"
        exec_command "Reloading systemd" "systemctl daemon-reload"
    fi

    # Remove the configuration file
    if [ -f "$CONFIG_FILE" ]; then
        exec_command "Removing $SCRIPT_NAME.conf" "rm -f $CONFIG_FILE"
    fi

    # Remove the AP Pop-Up script
    if [ -f "$APP_PATH" ]; then
        logD "Removing the script: $SCRIPT_NAME"
        rm -f "$APP_PATH"
    fi

    # Remove the controller script
    if [ -f "$CONTROLLER_PATH" ]; then
        logD "Removing the script: $CONTROLLER_PATH"
        rm -f "$CONTROLLER_PATH"
    fi

    # Base directory for man pages
    local man_base_dir="/usr/share/man"

    # Remove associated man pages
    exit_controller "AP Pop-Up uninstallation complete."
    return # TODO: DEBUG: Commented to speed things up

    for man_page in "${MAN_PAGES[@]}"; do
        # Extract the section number from the file name
        local section="${man_page##*.}"

        # Target directory based on the section number
        local target_dir="${man_base_dir}/man${section}"

        # Remove the man page if it exists
        if [ -f "$target_dir/$man_page" ]; then
            exec_command "Removing man page $man_page." "rm '$target_dir/$man_page'"
        fi
        pause # DEBUG: TODO
    done

    # Update the man page database
    pause # DEBUG: TODO
    exec_command "Updating man page database." "mandb"
    logI "Man pages removed successfully."

    exit_controller "AP Pop-Up uninstallation complete."
}

############
### Arguments Functions
############

# -----------------------------------------------------------------------------
# @brief Define script options and their properties.
# @details The `OPTIONS` associative array maps each script option to its 
#          description. Options include both short and long forms, and some 
#          options accept arguments.
#
# @global OPTIONS Associative array of script options and their properties.
#
# @example
# echo "${OPTIONS["--log-level|-l <level>"]}"
# Output: "Set the logging verbosity level (DEBUG, INFO, WARNING, ERROR, CRITICAL)."
# -----------------------------------------------------------------------------
declare -A OPTIONS=(
    ["--dry-run|-d"]="Enable dry-run mode (no actions performed)."
    ["--version|-v"]="Display script version and exit."
    ["--help|-h"]="Show this help message and exit."
    ["--log-file|-f <path>"]="Specify the log file location."
    ["--log-level|-l <level>"]="Set the logging verbosity level (DEBUG, INFO, WARNING, ERROR, CRITICAL)."
    ["--terse|-t"]="Enable terse output mode."
    ["--console|-c"]="Enable console logging."
)

# -----------------------------------------------------------------------------
# @brief Display script usage information.
# @details Dynamically generates a usage message based on the `OPTIONS` 
#          associative array, listing each available option and its description.
#
# @global OPTIONS Associative array of script options and their properties.
# @global THIS_SCRIPT Name of the current script.
#
# @return None
#
# @example
# usage
# Output:
#   Usage: script_name [options]
#
#   Options:
#     --dry-run|-d: Enable dry-run mode (no actions performed).
#     --version|-v: Display script version and exit.
#     ...
# -----------------------------------------------------------------------------
usage() {
    printf "Usage: %s [options]\n\n" "$THIS_SCRIPT"
    printf "Options:\n"
    for key in "${!OPTIONS[@]}"; do
        printf "  %s: %s\n" "$key" "${OPTIONS[$key]}"
    done
}

# -----------------------------------------------------------------------------
# @brief Parse command-line arguments.
# @details Validates and handles script options using the `OPTIONS` array. Updates 
#          global variables such as `DRY_RUN`, `LOG_FILE`, `LOG_LEVEL`, `TERSE`, 
#          and `USE_CONSOLE` based on the input arguments.
#
# @param "$@" The command-line arguments passed to the script.
#
# @global DRY_RUN          Enables dry-run mode if specified.
# @global LOG_FILE         Specifies the path to the log file.
# @global LOG_LEVEL        Sets the logging verbosity level.
# @global TERSE            Enables terse output mode if specified.
# @global USE_CONSOLE      Enables console logging if specified.
#
# @return None
#
# @throws Exits with code 1 if an unknown option is encountered.
#
# @example
# parse_args --log-level DEBUG --dry-run
# echo $LOG_LEVEL
# Output: "DEBUG"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2034
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run|-d)
                DRY_RUN=true
                ;;
            --version|-v)
                print_version
                exit 0
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --log-file|-f)
                LOG_FILE=$(realpath -m "$2" 2>/dev/null)
                shift
                ;;
            --log-level|-l)
                LOG_LEVEL="$2"
                shift
                ;;
            --terse|-t)
                TERSE="true"
                ;;
            --console|-c)
                USE_CONSOLE="true"
                ;;
            *)
                printf "Unknown option: %s\n" "$1" >&2
                usage
                exit 1
                ;;
        esac
        shift
    done
}

############
### Systemd Files
############

# -----------------------------------------------------------------------------
# @brief Create or update the systemd service unit for AP Pop-Up.
# @details Ensures the systemd service unit file is created or updated in 
#          the designated systemd directory. Handles unmasking, enabling, 
#          and reloading the service to reflect any changes.
#
# @global SYSTEMD_PATH The path to the systemd directory.
# @global SERVICE_FILE The name of the systemd service file.
# @global APP_PATH The path to the application executable.
# @global LOG_PATH The path for storing log files.
#
# @return None
# @throws Logs an error if systemd commands fail or permissions are insufficient.
# -----------------------------------------------------------------------------
create_systemd_service() {
    local service_file_path="$SYSTEMD_PATH/$SERVICE_FILE"

    # Check if the systemd service already exists
    if ! systemctl -all list-unit-files "$SERVICE_FILE" | grep -q "$SERVICE_FILE"; then
        logI "Creating systemd service: $SCRIPT_NAME."
    else
        logI "Updating systemd service: $SCRIPT_NAME."
        exec_command "Disabling $SERVICE_FILE" "systemctl disable $SERVICE_FILE"
        exec_command "Stopping $SERVICE_FILE" "systemctl stop $SERVICE_FILE"
        exec_command "Unmasking $SERVICE_FILE" "systemctl unmask $SERVICE_FILE"
    fi

    # Write the systemd service file
    cat > "$service_file_path" <<EOF
[Unit]
Description=Automatically toggles WiFi Access Point based on network availability ($SCRIPT_NAME)
After=multi-user.target
Requires=network-online.target

[Service]
Type=simple
ExecStart=${APP_PATH}
StandardOutput=file:$LOG_PATH/output.log
StandardError=file:$LOG_PATH/error.log

[Install]
WantedBy=multi-user.target
EOF

    exec_command "Creating log target: $LOG_PATH" "mkdir -p $LOG_PATH"
    exec_command "Unmasking $SERVICE_FILE" "systemctl unmask $SERVICE_FILE"
    exec_command "Enabling $SERVICE_FILE" "systemctl enable $SERVICE_FILE"
    exec_command "Reloading systemd" "systemctl daemon-reload"
    logI "Systemd service $SERVICE_FILE created."
}

# -----------------------------------------------------------------------------
# @brief Create or update the systemd timer unit for AP Pop-Up.
# @details Ensures the systemd timer unit file is created or updated in the 
#          designated systemd directory. Handles unmasking, enabling, and 
#          starting the timer to ensure periodic execution.
#
# @global SYSTEMD_PATH The path to the systemd directory.
# @global TIMER_FILE The name of the systemd timer file.
# @global SCRIPT_NAME The name of the script managed by the timer.
#
# @return None
# @throws Logs an error if systemd commands fail or permissions are insufficient.
# -----------------------------------------------------------------------------
create_systemd_timer() {
    local timer_file_path="$SYSTEMD_PATH/$TIMER_FILE"

    # Check if the systemd timer already exists
    if ! systemctl -all list-unit-files "$TIMER_FILE" | grep -q "$TIMER_FILE"; then
        logI "Creating systemd timer: $SCRIPT_NAME."
    else
        logI "Updating systemd timer: $SCRIPT_NAME."
        exec_command "Disabling $TIMER_FILE" "systemctl disable $TIMER_FILE"
        exec_command "Stopping $TIMER_FILE" "systemctl stop $TIMER_FILE"
        exec_command "Unmasking $TIMER_FILE" "systemctl unmask $TIMER_FILE"
    fi

    # Write the systemd timer file
    cat > "$timer_file_path" <<EOF
[Unit]
Description=Runs $SCRIPT_NAME every 2 minutes to check network status (appop)

[Timer]
OnBootSec=0min
OnCalendar=*:0/2

[Install]
WantedBy=timers.target
EOF

    exec_command "Unmasking $TIMER_FILE" "systemctl unmask $TIMER_FILE"
    exec_command "Enabling $TIMER_FILE" "systemctl enable $TIMER_FILE"
    exec_command "Reloading systemd" "systemctl daemon-reload"
    exec_command "Starting $TIMER_FILE" "systemctl start $TIMER_FILE"
    logI "Systemd service $TIMER_FILE started."
}


############
### Prerequisite Functions Here
############

# -----------------------------------------------------------------------------
# @brief Check if NetworkManager (nmcli) is running and active.
# @details Ensures that NetworkManager is active and running. If it is not, the 
#          script terminates with an error message.
#
# @global None
#
# @return None
# @throws Exits with code 1 if NetworkManager is not active.
#
# @example
# check_network_manager
# Output: "Network Manager is required but not active."
# -----------------------------------------------------------------------------
check_network_manager() {
    if ! nmcli -t -f RUNNING general | grep -q "running"; then
        die 1 "Network Manager is required but not active."
    fi
}

# -----------------------------------------------------------------------------
# @brief Check the status of hostapd to prevent conflicts with NetworkManager.
# @details Verifies if `hostapd` is installed and enabled, which may conflict 
#          with NetworkManager's ability to manage Access Points. Provides 
#          appropriate warnings or exits the script if conflicts are detected.
#
# @global None
#
# @return None
# @throws Exits with code 1 if `hostapd` is installed and enabled.
#
# @example
# check_hostapd_status
# Output: "Hostapd is installed and enabled, conflicting with NetworkManager's AP."
# -----------------------------------------------------------------------------
check_hostapd_status() {
    local installed="n"
    local enabled="disabled"

    if dpkg -s "hostapd" >/dev/null 2>&1; then
        installed="y"
        if systemctl -all list-unit-files hostapd.service | grep -q "hostapd.service enabled"; then
            enabled="enabled"
        fi
    fi

    if [ "$enabled" = "enabled" ]; then
        die 1 "Hostapd is installed and enabled, conflicting with NetworkManager's AP." \
        "Disable or uninstall hostapd to proceed: 'sudo systemctl disable hostapd'"
    elif [ "$installed" = "y" ]; then
        warn "Hostapd is installed but not enabled. Consider uninstalling if issues arise."
        printf "Press any key (or wait 5 seconds) to continue.\n"
        read -n 1 -t 5 -r || true
    fi
}

############
### Program Flow Functions
############

# -----------------------------------------------------------------------------
# @brief Configure a new WiFi network or modify an existing one.
# @details Scans for available WiFi networks, allowing the user to add a new 
#          network or change the password for an existing one. Handles retries 
#          if the WiFi device is busy and validates user input for network selection.
#
# @global CONFIG_FILE Path to the configuration file for WiFi settings.
# @global WIFI_INTERFACE The network interface used for WiFi scanning.
# @global FGYLW Terminal formatting for yellow foreground.
# @global BOLD Terminal formatting for bold text.
# @global RESET Terminal formatting reset sequence.
#
# @return None
# @throws Logs an error and returns if the WiFi device is unavailable or no 
#         networks are detected.
#
# @example
# setup_wifi_network
# Output:
#   Detected WiFi networks:
#   1) Network_A
#   2) Network_B
#   ...
#   Enter the number corresponding to the network you wish to configure:
# -----------------------------------------------------------------------------
setup_wifi_network() {
    local wifi_list=()
    local selection=""
    local attempts=0
    local max_attempts=5

    if [ ! -f "$CONFIG_FILE" ]; then
        logW "Config file not yet present, install script from menu first."
        return
    fi

    printf "${FGYLW}${BOLD}Add or modify a WiFi Network${RESET}\n"
    printf "\nScanning for available WiFi networks.\n"

    # Scan for WiFi networks, retrying if the device is busy
    while [ "$attempts" -lt "$max_attempts" ]; do
        IFS=$'\n' wifi_list=($(iw dev "$WIFI_INTERFACE" scan ap-force | grep -E "SSID:" | sed 's/SSID: //'))
        if [ "${#wifi_list[@]}" -gt 0 ]; then
            break
        elif [ "$attempts" -ge "$((max_attempts - 1))" ]; then
            logE "WiFi device is unavailable. Unable to scan for networks at this time." \
                "Please check your device and try again later."
            return
        else
            printf "WiFi device is busy or temporarily unavailable. Retrying in 2 seconds.\n"
            attempts=$((attempts + 1))
            sleep 2
        fi
    done

    # Display scanned networks
    if [ "${#wifi_list[@]}" -eq 0 ]; then
        printf "No WiFi networks detected. There may be a temporary issue with the device or signal.\n"
        printf "Press any key (or wait 5 seconds) to continue.\n"
        read -n 1 -t 5 -sr < /dev/tty || true
        return
    fi

    printf "\nDetected WiFi networks:\n"
    for i in "${!wifi_list[@]}"; do
        local trimmed_entry=$(printf "%s" "${wifi_list[i]}" | xargs)
        printf "%d)\t%s\n" $((i + 1)) "$trimmed_entry"
    done
    printf "%d)\tCancel\n" "$(( ${#wifi_list[@]} + 1 ))"

    # User selection
    while true; do
        printf "\nEnter the number corresponding to the network you wish to configure:\n"
        read -n 1 -sr selection < /dev/tty || true

        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$(( ${#wifi_list[@]} + 1 ))" ]; then
            if [ "$selection" -eq "$(( ${#wifi_list[@]} + 1 ))" ]; then
                printf "\nOperation canceled.\n"
                return
            else
                update_wifi_profile "${wifi_list[$((selection - 1))]}"
                return
            fi
        elif [[ -z "$selection" ]]; then
            printf "No selection, exiting to menu.\n"
            return
        else
            logW "Invalid selection. Please try again."
        fi
    done
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
#   Password updated. Attempting to connect to MyNetwork...
#   Successfully connected to MyNetwork.
# -----------------------------------------------------------------------------
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
        read -r password < /dev/tty

        if [ -n "$password" ] && [ "${#password}" -ge 8 ]; then
            nmcli connection modify "$existing_profile" wifi-sec.psk "$password"
            printf "Password updated. Attempting to connect to %s...\n" "$existing_profile"
            connection_status=$(nmcli device wifi connect "$existing_profile" 2>&1)
            if [ $? -eq 0 ]; then
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
        printf "No existing profile found for %s.\n" "$ssid"
        printf "%sEnter the password for the network (minimum 8 characters):%s\n" "${FGYLW}" "${RESET}"
        read -r password < /dev/tty

        if [ -n "$password" ] && [ "${#password}" -ge 8 ]; then
            printf "Creating a new profile and attempting to connect to %s.\n" "$ssid"
            connection_status=$(nmcli device wifi connect "$ssid" password "$password" 2>&1)
            if [ $? -eq 0 ]; then
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
update_access_point_ssid() {
    # clear

    cat << EOF

>> ${FGYLW}Current AP SSID:${RESET} ${FGGRN}$AP_SSID${RESET}

Enter new SSID (1-32 characters, no leading/trailing spaces, Enter to keep current):
EOF
    read -r new_ssid < /dev/tty

    # Trim and validate SSID
    new_ssid=$(printf "%s" "$new_ssid" | xargs | sed -e 's/^"//' -e 's/"$//')
    if [[ -n "$new_ssid" ]]; then
        if [[ ${#new_ssid} -ge 1 && ${#new_ssid} -le 32 && "$new_ssid" =~ ^[[:print:]]+$ && "$new_ssid" != *" "* ]]; then
            AP_SSID="$new_ssid"
            sed -i "s/^AP_SSID=.*/AP_SSID=\"$new_ssid\"/" "$CONFIG_FILE"
            printf "\n${FGYLW}<< AP SSID updated to:${RESET} ${FGGRN}$new_ssid${RESET}\n"
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
    read -r new_pw < /dev/tty

    # Trim and validate password
    new_pw=$(printf "%s" "$new_pw" | xargs)
    if [[ -n "$new_pw" ]]; then
        if [[ ${#new_pw} -ge 8 && ${#new_pw} -le 63 && "$new_pw" =~ ^[[:print:]]+$ ]]; then
            AP_PASSWORD="$new_pw"
            sed -i "s/^AP_PASSWORD=.*/AP_PASSWORD=\"$new_pw\"/" "$CONFIG_FILE"
            printf "\n${FGYLW}<< AP Password updated to:${RESET} ${FGGRN}$new_pw${RESET}\n"
        else
            logE "Invalid password. Must be 8-63 printable characters with no leading/trailing spaces."
        fi
    else
        printf "Keeping the current password.\n"
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
update_access_point_ip() {
    if [ ! -f "$CONFIG_FILE" ]; then
        # clear
        logW "Config file not yet present, install script from menu first."
        return
    fi
    # clear

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

    read -n 1 -t 5 -sr choice < /dev/tty || true
    printf "\n"
    case "$choice" in
        1) base="192.168." ;;
        2) base="10.0." ;;
        3) return ;;
        *) logW "Invalid selection." ; return ;;
    esac

    printf "\nEnter the third octet (0-255):\n"
    read -r third_octet < /dev/tty
    if ! validate_host_number "$third_octet" 255; then return; fi

    printf "\nEnter the fourth octet (0-253):\n"
    read -r fourth_octet < /dev/tty
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
    read -n 1 -t 5 -sr confirm < /dev/tty || true
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
# @brief Validate that a given number is within a specific range.
# @details Ensures the input is a non-negative integer within the range 0 to the specified maximum value.
#
# @param $1 The number to validate.
# @param $2 The maximum allowed value.
# @return Outputs "true" if valid, logs a warning and outputs nothing if invalid.
# -----------------------------------------------------------------------------
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
# @brief Validate a subnet and its gateway.
# @details Checks if the subnet follows the CIDR format and the gateway is a valid IP address.
#
# @param $1 The subnet in CIDR format (e.g., "192.168.0.1/24").
# @param $2 The gateway IP address (e.g., "192.168.0.254").
# @return 0 if valid, 1 if invalid.
# -----------------------------------------------------------------------------
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
# @brief Validate a proposed Access Point (AP) configuration.
# @details Ensures there are no network conflicts, the gateway is not in use, 
#          and the subnet and gateway are valid.
#
# @param $1 The new subnet in CIDR format (e.g., "192.168.0.1/24").
# @param $2 The new gateway IP address (e.g., "192.168.0.254").
# @return 0 if valid, 1 if invalid.
# -----------------------------------------------------------------------------
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
# @brief Check for conflicts between a new subnet and active networks.
# @details Compares the new subnet with active subnets on the system and logs 
#          any conflicts.
#
# @param $1 The new AP subnet in CIDR format (e.g., "192.168.0.1/24").
# @return 0 if no conflicts, 1 if conflicts are detected.
# -----------------------------------------------------------------------------
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
update_hostname() {
    # clear
    local current_hostname
    current_hostname=$(nmcli general hostname)

    cat << EOF

>> ${FGYLW}Current hostname:${RESET} ${FGGRN}$current_hostname${RESET}

Enter a new hostname (Enter to keep current):
EOF

    read -r new_hostname < /dev/tty || true

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

            printf "\n${FGYLW}<< Hostname updated to:${RESET} ${FGGRN}$new_hostname${RESET}\n"
        else
            printf "Invalid hostname. Please follow the hostname rules.\n" >&2
        fi
    else
        printf "Hostname unchanged.\n"
    fi
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
# @brief Execute the AP Pop-Up script to manage WiFi and Access Point switching.
# @details
# - Runs the AP Pop-Up script if it is installed and available in the system's PATH.
# - Logs the operation and handles errors if the script is not found.
#
# @global SCRIPT_NAME The name of the AP Pop-Up script.
# @global APP_PATH    The full path to the AP Pop-Up script.
# @return None
# -----------------------------------------------------------------------------
run_ap_popup() {
    # clear
    logI "Running AP Pop-Up."

    # Check if the script is available and execute it
    if which "$SCRIPT_NAME" &>/dev/null; then
        exec_command "Calling $SCRIPT_NAME" "$APP_PATH"
    else
        warn "$SCRIPT_NAME not available. Install first."
    fi
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
switch_between_wifi_and_ap() {
    # clear
    logI "Switching between WiFi and Access Point."

    # Check if the script is available and execute it
    if which "$SCRIPT_NAME" &>/dev/null; then
        exec_command "Calling $SCRIPT_NAME" "$APP_PATH"
    else
        warn "$SCRIPT_NAME not available. Install first."
    fi
}

############
### Menu Functions
############

# -----------------------------------------------------------------------------
# @brief Displays and handles the main menu for user interaction.
# @details Continuously displays the main menu and waits for user input to execute 
#          corresponding options. Includes a timeout mechanism for user inactivity.
#
# @global OPTIONS_MAP Associative array mapping menu options to their corresponding functions.
#
# @return None
# @throws Exits the script if the user does not provide input within 30 seconds.
#
# @example
# menu
# Output: Displays the menu, waits for user input, and executes the selected option.
# -----------------------------------------------------------------------------
menu() {
    while true; do
        display_main_menu
        printf "Enter your choice:\n"

        # Read user input with timeout
        if ! read -n 1 -t 30 -sr user_choice < /dev/tty; then
            # Handle timeout or error
            exit_controller "User timeout."
        fi

        execute_menu_option "$user_choice"
    done
}

# -----------------------------------------------------------------------------
# @brief Displays the main menu for configuration and maintenance tasks.
# @details Dynamically generates the menu options based on the script's running context 
#          (installed or not installed). Options are stored in the `OPTIONS_MAP` array 
#          and associated with corresponding functions.
#
# @global OPTIONS_MAP Associative array mapping menu options to their corresponding functions.
# @global SEM_VER The current version of the script.
#
# @return None
#
# @example
# display_main_menu
# Output: Displays the menu options and instructions.
# -----------------------------------------------------------------------------
display_main_menu() {
    # clear

    local menu_number=1

    # Clear the OPTIONS_MAP before rebuilding it
    OPTIONS_MAP=()

    printf "%s\n" "${FGYLW}${BOLD}AP Pop-Up Installation and Setup, ver: $SEM_VER ${RESET}"
    printf "\n"
    printf "%s\n" "AP Pop-Up raises an access point when no configured WiFi networks"
    printf "%s\n" "are in range."
    printf "\n"

    if ! is_running_from_installed_path; then
        printf " %d = Install AP Pop-Up Script\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="install_ap_popup"
        menu_number=$((menu_number + 1))

        printf " %d = Setup a New WiFi Network or Change Password\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="setup_wifi_network"
        menu_number=$((menu_number + 1))

        printf " %d = Change Hostname\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="update_hostname"
        menu_number=$((menu_number + 1))

        printf " %d = Exit\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="exit_controller"
        menu_number=$((menu_number + 1))

    elif is_running_from_installed_path; then
        printf " %d = Change the Access Point SSID or Password\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="update_access_point_ssid"
        menu_number=$((menu_number + 1))

        printf " %d = Setup a New WiFi Network or Change Password\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="setup_wifi_network"
        menu_number=$((menu_number + 1))

        printf " %d = Change Hostname\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="update_hostname"
        menu_number=$((menu_number + 1))

        printf " %d = Update access point IP\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="update_access_point_ip"
        menu_number=$((menu_number + 1))

        printf " %d = Live Switch between Network WiFi and Access Point\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="switch_between_wifi_and_ap"
        menu_number=$((menu_number + 1))

        printf " %d = Run appop now\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="run_ap_popup"
        menu_number=$((menu_number + 1))

        printf " %d = Uninstall appop\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="uninstall_ap_popup"
        menu_number=$((menu_number + 1))

        printf " %d = Exit\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="exit_controller"
    fi

    # Add an additional line break after the menu
    printf "\n"
}

# -----------------------------------------------------------------------------
# @brief Executes the function associated with a menu option.
# @details Validates the selected option against the `OPTIONS_MAP` array, 
#          ensuring it is valid and maps to an existing function. Executes 
#          the corresponding function if validation passes.
#
# @param $1 The selected menu option.
#
# @global OPTIONS_MAP Associative array mapping menu options to their corresponding functions.
#
# @return None
# @throws Prints an error message if the option is invalid or the function does not exist.
#
# @example
# execute_menu_option 1
# Output: Executes the function associated with option 1.
# -----------------------------------------------------------------------------
execute_menu_option() {
    local option="$1"

    # Check if an option was passed (i.e., $option is not empty)
    if [[ -z "$option" ]]; then
        printf "No option provided.\n"
        return
    fi

    # Check if the option exists in the associative array
    if [[ -z "${OPTIONS_MAP[$option]+_}" ]]; then
        printf "Invalid option.\n"
        return
    fi

    # Execute the corresponding function
    local function_name="${OPTIONS_MAP[$option]}"
    
    # Ensure the function exists and is callable
    if declare -f "$function_name" > /dev/null; then
        "$function_name"
    else
        printf "Function %s does not exist.\n" "$function_name"
        return
    fi

    # Prompt to continue
    printf "\nPress any key (or wait 5 seconds) to continue.\n"
    read -n 1 -t 5 -sr < /dev/tty || true
}

############
### Debug Functions
############

pause() {
    printf "Press any key to continue.\n"
    read -n 1 -sr < /dev/tty || true
}

############
### Main Functions
############

# Main function
main() {
    ############
    ### Check Environment Functions
    ############

    # Get execution context of the script and sets relevant environment variables.
    handle_execution_context # Pass "debug" to enable debug output

    # Get Project Parameters Functions
    get_proj_params     # Get project and git parameters

    # Arguments Functions
    parse_args "$@"     # Parse command-line arguments

    # Check Environment Functions
    enforce_sudo        # Ensure proper privileges for script execution
    validate_depends    # Ensure required dependencies are installed
    validate_sys_accs   # Verify critical system files are accessible
    validate_env_vars   # Check for required environment variables

    # Logging Functions
    setup_log           # Setup logging environment

    # Check Environment Functions with debug available, pass "debug" to enable debug output.
    check_bash          # Ensure the script is executed in a Bash shell
    check_sh_ver        # Verify the current Bash version meets minimum requirements
    check_bitness       # Validate system bitness compatibility
    check_release       # Check Raspbian OS version compatibility

    check_arch          # Validate Raspberry Pi model compatibility, pass "debug" to enable debug output.
    check_internet      # Verify internet connectivity if required, pass "debug" to enable debug output.

    # Print/Display Environment Functions
    print_system        # Log system information, pass "debug" to enable debug output.
    print_version       # Log the script version

    ############
    ### Installer Functions
    ############
    start_script
    handle_apt_packages

    #########################################################################
    # Previous Program Flow:

    # Check if NetworkManager (nmcli) is running and active.
    check_network_manager
    # Check hostapd status to ensure it does not conflict with NetworkManager's AP.
    check_hostapd_status

    # If we are piped, make sure we are not re-running the script in a new shell
    if is_this_piped && is_this_curled; then
        # Curl installer to local temp_dir
        download_files_from_directories

        # Resolve the real path of the script
        # TODO: local dest_root="$USER_HOME/$REPO_NAME"       # Replace with your desired destination root directory
        readonly USER_HOME=$(eval printf "~%s" "$(printf "%s" "$SUDO_USER")")
        local dest_root="$USER_HOME/apppop"       # Replace with your desired destination root directory
        local new_script_path=$(readlink -f "$dest_root/src/$THIS_SCRIPT")
        
        # Replace the current running script with downloaded script
        exec_new_shell "Re-spawning from $new_script_path" "$new_script_path"
    elif is_this_piped; then
        install_ap_popup
    fi

    # Load config
    check_config_file

    menu

    # Previous Program Flow^
    #########################################################################
}

# Run the main function and exit with its return status
main "$@"
exit $?
