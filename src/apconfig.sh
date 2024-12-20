#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# TODO:
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
# Uninstall is SUPER short

# Installer name.
declare DRY_RUN="${DRY_RUN:-false}" # Use existing value, or default to "false".

# Semaphore for a re-run after install.
declare RE_RUN="${RE_RUN:-false}" # Use existing value, or default to "false".
declare SOURCE_DIR="${SOURCE_DIR:-}" # Use existing value, or default to "".

# GitHub metadata constants
declare REPO_ORG="${REPO_ORG:-lbussy}"
declare REPO_NAME="${REPO_NAME:-ap-popup}"
declare REPO_BRANCH="${REPO_BRANCH:-main}"
declare SEM_VER="${SEM_VER:-1.0.0}"

# GithHub curl info
readonly DIRECTORIES=("man" "src" "conf")  # Replace with your directories
readonly USER_HOME=$(eval printf "~%s" "$(printf "%s" "$SUDO_USER")")

# Installer name.
declare THIS_SCRIPT="${THIS_SCRIPT:-apconfig.sh}" # Use existing value, or default to "apconfig.sh".
#
# Name of the source script that will be installed as `appop`.
readonly SOURCE_SCRIPT_NAME="${SOURCE_SCRIPT_NAME:-appop.sh}" # Use existing value, or default to "appop.sh".
#
# The final installed name of the main script (no extension).
readonly SCRIPT_NAME="${SOURCE_SCRIPT_NAME%.*}"
#
# The final installed name of the main script (no extension).
readonly CONTROLLER_NAME="${THIS_SCRIPT%.*}"
#
# The final installed name of the main script (no extension).
declare LOG_PATH="${LOG_PATH:-/var/log/$SCRIPT_NAME}"
##
# Determines if script is piped through bash (curl) or executed locally
declare CONTROLLER_IS_INSTALLED="${CONTROLLER_IS_INSTALLED:-false}"
#
# Determines if script is piped through bash (curl) or executed locally
declare DAEMON_IS_INSTALLED="${DAEMON_IS_INSTALLED:-false}"
#
# Determines if script is piped through bash (curl) or executed locally
declare IS_PIPE="${IS_PIPE:-false}"
#
# Path to where the main script (appop) will be installed.
readonly SCRIPT_PATH="/usr/bin/$SCRIPT_NAME"
#
# Path to the systemd directory for services/timers.
readonly SYSTEMD_PATH="/etc/systemd/system/"
#
# Name of the systemd service file to be created/managed.
readonly SERVICE_FILE="$SCRIPT_NAME.service"
#
# Name of the systemd timer file to be created/managed.
readonly TIMER_FILE="$SCRIPT_NAME.timer"
#
# Path to the AP Pop-Up configuration file.
readonly CONFIG_FILE="/etc/$SCRIPT_NAME.conf"
#
# Path where this installer script (apconfig) will be installed.
readonly CONTROLLER_PATH="/usr/local/sbin/$CONTROLLER_NAME"

# Indicates whether root privileges are required to run the script.
readonly REQUIRE_SUDO="${REQUIRE_SUDO:-true}"  # Default to false if not specified.

# Specifies the minimum supported Bash version.
readonly MIN_BASH_VERSION="${MIN_BASH_VERSION:-4.0}"  # Default to "4.0" if not specified.
#
# Specifies the minimum supported OS version.
readonly MIN_OS=11  # Minimum supported OS version.
#
# Specifies the maximum supported OS version.
readonly MAX_OS=15  # Maximum supported OS version (use -1 for no upper limit).
#
# Specifies the logging verbosity level.
declare LOG_LEVEL="${LOG_LEVEL:-DEBUG}"  # Default log level is DEBUG if not set.

# Array containing man page files
MAN_PAGES=("apconfig.1" "appop.1" "appop.5")

# List of required external commands for the script.
declare -ar DEPENDENCIES=(
    "nmcli"
)
readonly DEPENDENCIES

# Base list of required environment variables.
declare -ar ENV_VARS_BASE=(
    "COLUMNS"    # Terminal width for formatting
)

# This array extends `ENV_VARS_BASE` by conditionally including `SUDO_USER`
if [[ "$REQUIRE_SUDO" == true ]]; then
    readonly -a ENV_VARS=("${ENV_VARS_BASE[@]}" "SUDO_USER")
else
    readonly -a ENV_VARS=("${ENV_VARS_BASE[@]}")
fi

# The `COLUMNS` variable represents the width of the terminal in characters. 
COLUMNS="${COLUMNS:-80}"  # Default to 80 columns if unset

# Contains absolute paths to system files that the script depends on. 
declare -ar SYSTEM_READS=(
)
readonly SYSTEM_READS

# Specifies the names of APT packages that the script depends on.
readonly APT_PACKAGES=(
    "jq"
)

# Contains the ndynamic menu items
declare -A OPTIONS_MAP

# Controls whether stack traces are printed alongside warning messages. 
readonly WARN_STACK_TRACE="${WARN_STACK_TRACE:-false}"  # Default to false if not set

# Print a detailed stack trace of the call hierarchy.
stack_trace() {
    local level="$1"
    local message="$2"
    local color=""                   # Default: no color
    local label=""                   # Log level label for display
    local header="------------------ STACK TRACE ------------------"
    local tput_colors_available      # Terminal color support
    local lineno="${BASH_LINENO[0]}" # Line number where the error occurred

    # Check terminal color support
    tput_colors_available=$(tput colors 2>/dev/null || printf "0")

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
        local caller_lineno="${BASH_LINENO[1]}"
        printf "%b%s stack trace called by line: %d%b\n" "$color" "$label" "$caller_lineno" "\033[0m" >&2
    fi

    # Print each function in the stack trace
    for ((i = 2; i < ${#FUNCNAME[@]}; i++)); do
        local script="${BASH_SOURCE[i]##*/}"
        local caller_lineno="${BASH_LINENO[i - 1]}"
        printf "%b[%d] Function: %s called at %s:%d%b\n" \
            "$color" $((i - 1)) "${FUNCNAME[i]}" "$script" "$caller_lineno" "\033[0m" >&2
    done

    # Print stack trace footer (line of "-" matching $header)
    # shellcheck disable=SC2183
    printf "%b%s%b\n" "$color" "$(printf '%*s' "${#header}" | tr ' ' '-')" "\033[0m" >&2
}

# Logs a warning or error message with optional details and a stack trace.
warn() {
    # Initialize default values
    local error_level="${1:-0}"                             # Default error level is 0
    local level="${2:-WARNING}"                             # Default log level is WARNING
    local message="${3:-A warning was raised on this line (${BASH_LINENO[0]})}"  # Default log message
    local details="${4:-}"                                  # Default to no additional details
    local lineno="${BASH_LINENO[1]:-0}"                     # Line number where the function was called
    local script="${THIS_SCRIPT:-Unknown Script}"           # Script name, with default

    # Append error level to the log message
    message="${message}: ($error_level)"

    # Log the message with the appropriate level
    if [[ "$level" == "WARNING" ]]; then
        logW "$message" "$details"
    elif [[ "$level" == "ERROR" ]]; then
        logE "$message" "$details"
    fi

    # Optionally print a stack trace for warnings
    if [[ "$level" == "WARNING" && "${WARN_STACK_TRACE:-false}" == "true" ]]; then
        stack_trace "$level" "Stack trace for $level at line $lineno: $message"
    fi

    return
}

# Log a critical error, print a stack trace, and exit the script.
die() {
    # Local variables
    local exit_status="$1"              # First parameter as exit status
    local message                       # Main error message
    local details                       # Additional details
    local lineno="${BASH_LINENO[0]}"    # Line number where the error occurred
    local script="$THIS_SCRIPT"          # Script name
    local level="CRITICAL"              # Error level
    local tag="${level:0:4}"            # Extracts the first 4 characters (e.g., "CRIT")

    # Determine exit status and message
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

    # Log the error message only if a message is provided
    if [[ -n "$message" ]]; then
        printf "[%s]\t[%s:%d]\t%s\n" "$tag" "$script" "$lineno" "$message" >&2
        if [[ -n "$details" ]]; then
            printf "[%s]\t[%s:%d]\tDetails: %s\n" "$tag" "$script" "$lineno" "$details" >&2
        fi
    fi

    # Log the unrecoverable error
    printf "[%s]\t[%s:%d]\tUnrecoverable error (exit status: %d).\n" \
        "$tag" "$script" "$lineno" "$exit_status" >&2

    # Call stack_trace with processed message and error level
    if [[ -z "$message" ]]; then
        stack_trace "$level" "Stack trace from line $lineno."
    else
        stack_trace "$level" "Stack trace from line $lineno: $message"
    fi

    # Exit with the determined status
    exit "$exit_status"
}

# Add a dot at the beginning of a string if it's missing.
# shellcheck disable=SC2329
add_dot() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "ERROR" "Input to add_dot cannot be empty."
        return 1
    fi

    # Add a leading dot if it's missing
    if [[ "$input" != .* ]]; then
        input=".$input"
    fi

    printf "%s\n" "$input"
}

# Remove a leading dot from a string if present.
# shellcheck disable=SC2329
remove_dot() {
    local input="${1:-}"  # Default to "Unnamed Operation" if $1 is unset

    # Validate input
    if [[ -z "$input" ]]; then
        warn "ERROR" "Input to remove_dot cannot be empty."
        return 1
    fi

    # Remove the leading dot if present
    if [[ "$input" == .* ]]; then
        input="${input#.}"
    fi

    printf "%s\n" "$input"
}

# Add a trailing slash to a string if it's missing.
# shellcheck disable=SC2329
add_slash() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
        warn "ERROR" "Input to add_slash cannot be empty."
        return 1
    fi

    # Add a trailing slash if it's missing
    if [[ "$input" != */ ]]; then
        input="$input/"
    fi

    printf "%s\n" "$input"
}

# Remove a trailing slash from a string if present.
# shellcheck disable=SC2329
remove_slash() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "$input" ]]; then
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

# Print the system information
print_system() {
    # Declare local variables at the start of the function
    local system_name

    # Extract system name and version from /etc/os-release
    system_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d '=' -f2 | tr -d '"')

    # Check if system_name is empty
    if [[ -z "$system_name" ]]; then
        logW "System: Unknown (could not extract system information)." # Warning if system information is unavailable
    else
        logD "System: $system_name." # Log the system information
    fi
}

# Print the script version
print_version() {
    # Declare local variables at the start of the function
    local caller

    # Check the name of the calling function
    caller="${FUNCNAME[1]}"

    if [[ "$caller" == "parse_args" ]]; then
        printf "%s: version %s\n" "$CONTROLLER_NAME" "$SEM_VER"
    else
        logD "Running $CONTROLLER_NAME version $SEM_VER" # Log the script name and version
    fi
}

# Determine how the script was executed.
check_pipe() {
    local this_script  # Local variable for script name

    # Check if stdin is a pipe
    if [ -p /dev/stdin ]; then
        IS_PIPE=true
    else
        IS_PIPE=false
    fi

    # Check if the script is re-run via $RE_RUN:
    if [[ "$RE_RUN" == "true" ]]; then
        IS_PIPE=false
        THIS_SCRIPT=$CONTROLLER_NAME
    fi

    export IS_PIPE
}

# Enforce that the script is run directly with `sudo`.
enforce_sudo() {
    if [[ "$REQUIRE_SUDO" == true ]]; then
        if [[ "$EUID" -eq 0 && -n "$SUDO_USER" && "$SUDO_COMMAND" == *"$0"* ]]; then
            return  # Script is properly executed with `sudo`
        elif [[ "$EUID" -eq 0 && -n "$SUDO_USER" ]]; then
            if [[ "$RE_RUN" == "true" ]]; then
                # We are re-running from the original shell
                return 0
            fi
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

# Check for required dependencies and report any missing ones.
validate_depends() {
    local missing=0  # Counter for missing dependencies
    local dep        # Iterator for dependencies

    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            printf "ERROR: Missing dependency: %s\n" "$dep" >&2
            ((missing++))
        fi
    done

    if ((missing > 0)); then
        die 1 "Missing $missing dependencies. Install them and re-run the script."
    fi
}

# Check the availability of critical system files.
validate_sys_accs() {
    local missing=0  # Counter for missing or unreadable files
    local file       # Iterator for files

    for file in "${SYSTEM_READS[@]}"; do
        if [[ ! -r "$file" ]]; then
            printf "ERROR: Missing or unreadable file: %s\n" "$file" >&2
            ((missing++))
        fi
    done

    if ((missing > 0)); then
        die 1 "Missing or unreadable $missing critical system files. Ensure they are accessible and re-run the script."
    fi
}

# Validate the existence of required environment variables.
validate_env_vars() {
    local missing=0  # Counter for missing environment variables
    local var        # Iterator for environment variables

    for var in "${ENV_VARS[@]}"; do
        if [[ -z "${!var}" ]]; then
            printf "ERROR: Missing environment variable: %s\n" "$var" >&2
            ((missing++))
        fi
    done

    if ((missing > 0)); then
        die 1 "Missing $missing required environment variables." \
              "Ensure they are set and re-run the script."
    fi
}

# Check if the script is running in a Bash shell.
check_bash() {
    if [[ -z "$BASH_VERSION" ]]; then
        printf "ERROR: This script requires Bash. Please run it with Bash.\n" >&2
        exit 1
    fi
}

# Check if the current Bash version meets the minimum required version.
check_sh_ver() {
    local required_version="${MIN_BASH_VERSION:-none}"

    if [[ "$required_version" == "none" ]]; then
        return  # Skip version check
    fi

    if ((BASH_VERSINFO[0] < ${required_version%%.*} || 
         (BASH_VERSINFO[0] == ${required_version%%.*} && 
          BASH_VERSINFO[1] < ${required_version##*.}))); then
        die 1 "This script requires Bash version $required_version or newer."
    fi
}

# Check Raspbian OS version compatibility.
check_release() {
    local ver  # Holds the extracted version ID from /etc/os-release.

    # Ensure the file exists and is readable.
    if [[ ! -f /etc/os-release || ! -r /etc/os-release ]]; then
        die 1 "Unable to read /etc/os-release. Ensure this script is run on a compatible system."
    fi

    # Extract the VERSION_ID from /etc/os-release.
    if ! ver=$(grep "VERSION_ID" /etc/os-release 2>/dev/null | awk -F "=" '{print $2}' | tr -d '"'); then
        die 1 "Failed to extract version information from /etc/os-release."
    fi

    # Ensure the extracted version is not empty.
    if [[ -z "$ver" ]]; then
        die 1 "VERSION_ID is missing or empty in /etc/os-release."
    fi

    # Check if the version is older than the minimum supported version.
    if [[ "$ver" -lt "$MIN_OS" ]]; then
        die 1 "Raspbian version $ver is older than the minimum supported version ($MIN_OS)."
    fi

    # Check if the version is newer than the maximum supported version, if applicable.
    if [[ "$MAX_OS" -ne -1 && "$ver" -gt "$MAX_OS" ]]; then
        die 1 "Raspbian version $ver is newer than the maximum supported version ($MAX_OS)."
    fi
}

print_log_entry() {
    local level="$1"
    local color="$2"
    local message="$3"
    local details="$4"

    # Print the main message: level in bold/color, message in default color
    printf "%b[%s]%b %s\n" \
        "$BOLD$color" "$level" "$RESET" \
        "$message"

    # If details are provided and extended formatting is available, print details
    if [[ -n "$details" && -n "${LOG_PROPERTIES[EXTENDED]}" ]]; then
        IFS="|" read -r extended_label extended_color _ <<< "${LOG_PROPERTIES[EXTENDED]}"
        printf "%b[%s]%b Details: %s\n" \
            "$BOLD$extended_color" "$extended_label" "$RESET" \
            "$details"
    fi
}

# Log a message with the specified log level.
log_message() {
    # Convert log level to uppercase for consistency
    local level="${1^^}"
    local message="$2"
    local details="$3"

    # Context variables for logging
    local context timestamp lineno custom_level color severity config_severity

    # Validate log level and message
    if [[ -z "$message" || -z "${LOG_PROPERTIES[$level]}" ]]; then
        printf "ERROR: Invalid log level or empty message in %s.\n" "${FUNCNAME[0]}" >&2
        exit 1
    fi

    # Extract log properties for the specified level
    IFS="|" read -r level color severity <<< "${LOG_PROPERTIES[$level]}"
    severity="${severity:-0}"  # Default severity to 0 if not defined
    color="${color:-$RESET}"   # Default to reset color if not defined

    # Extract severity threshold for the configured log level
    IFS="|" read -r _ _ config_severity <<< "${LOG_PROPERTIES[$LOG_LEVEL]}"

    # Skip logging if the message's severity is below the configured threshold
    if (( severity < config_severity )); then
        return 0
    fi

    # Print the log entry
    print_log_entry "$level" "$color" "$message" "$details"
}

# Log a message at the DEBUG level.
logD() {
    log_message "DEBUG" "${1:-}" "${2:-}"
}

# Log a message at the INFO level.
logI() {
    log_message "INFO" "${1:-}" "${2:-}"
}

# Log a message at the WARNING level.
logW() {
    log_message "WARNING" "${1:-}" "${2:-}"
}

# Log a message at the ERROR level.
logE() {
    log_message "ERROR" "${1:-}" "${2:-}"
}

# Log a message at the CRITICAL level.
logC() {
    log_message "CRITICAL" "${1:-}" "${2:-}"
}

# Retrieve the terminal color code or attribute.
default_color() {
    tput "$@" 2>/dev/null || printf "\n"  # Fallback to an empty string on error
}

# Execute and combine complex terminal control sequences.
generate_terminal_sequence() {
    local result
    # Execute the command and capture its output, suppressing errors.
    result=$("$@" 2>/dev/null || printf "\n")
    printf "$result"
}

# Initialize terminal colors and text formatting.
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

    # Export variables globally
    export RESET BOLD SMSO RMSO UNDERLINE NO_UNDERLINE
    export BLINK NO_BLINK ITALIC NO_ITALIC MOVE_UP CLEAR_LINE
    export FGBLK FGRED FGGRN FGYLW FGBLU FGMAG FGCYN FGWHT FGRST FGGLD
    export BGBLK BGRED BGGRN BGYLW BGBLU BGMAG BGCYN BGWHT BGRST
    export DOT HHR LHR
}

# Validate the logging configuration, including LOG_LEVEL.
validate_log_level() {
    # Ensure LOG_LEVEL is a valid key in LOG_PROPERTIES
    if [[ -z "${LOG_PROPERTIES[$LOG_LEVEL]}" ]]; then
        printf "ERROR: Invalid LOG_LEVEL '%s'. Defaulting to 'INFO'.\n" "$LOG_LEVEL" >&2
        exit 1
    fi
}

# Sets up the logging environment for the script.
setup_log() {
    # Initialize terminal colors
    init_colors

    # Define log properties (severity, colors, and labels)
    declare -gA LOG_PROPERTIES=(
        ["DEBUG"]="d|${FGCYN}|0"
        ["INFO"]="i|${FGGRN}|1"
        ["WARNING"]="E|${FGYLW}|2"
        ["ERROR"]="E|${FGRED}|3"
        ["CRITICAL"]="C|${FGMAG}|4"
        ["EXTENDED"]="D|${FGCYN}|0"
    )

    # Validate the log level and log properties
    validate_log_level
}

# Execute a command, log its status, and optionally print messages to the console.
exec_command() {
    local exec_name="${1:-Unnamed Operation}"   # Default to "Unnamed Operation" if $1 is unset
    local exec_process="${2:-true}"             # Default to "true" if $2 is unset (a no-op command)
    local result                                # Store the command's exit status
    local start_prefix="Running"
    local sim_prefix="Simulating"
    local fail_prefix="Failed"
    local success_prefix="Finished"

    exec_name="$(remove_dot "$exec_name")"      # Remove tailing perion, we add it

    if [ "${DRY_RUN:-false}" = "true" ]; then
        # Simulate execution during a dry run
        # Log "Running" message
        printf "%b[-]%b %s: %s. Command: \"%s\".\n" "$BOLD$FGGLD" "$RESET" "$sim_prefix" "$exec_name" "$exec_process"
        sleep 3
        result=0
    else
        # Execute the command and capture the exit status
        # Log "Running" message
        printf "%b[-]%b %s: %s.\n" "$BOLD$FGGLD" "$RESET" "$start_prefix" "$exec_name"
        eval "$exec_process" > /dev/null 2>&1
        result=$?
    fi

    # Move the cursor up and clear the line
    printf "%b" "${MOVE_UP}${CLEAR_LINE}"

    # Log success or failure
    if [ "$result" -eq 0 ]; then
        printf "%b[✔]%b %s: %s.\n" "$BOLD$FGGRN" "$RESET" "$success_prefix" "$exec_name"
        return 0
    else
        printf "%b[✘]%b %s: %s. (Exit Code: %d)\n" "$BOLD$FGRED" "$RESET" "$fail_prefix" "$exec_name" "$result"
        return 1
    fi
}

# Execute a command replacing the current shell process.  Current process exits.
exec_newshell() {
    local exec_name="${1:-Unnamed Operation}"   # Default to "Unnamed Operation" if $1 is unset
    local exec_process="${2:-true}"             # Default to "true" if $2 is unset (a no-op command)
    local result                                # Store the command's exit status
    local start_prefix="Running"
    local sim_prefix="Simulating"
    local success_prefix="Finished"
    local script_path=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

    exec_name="$(remove_dot "$exec_name")"      # Remove tailing perion, we add it

    if [ "${DRY_RUN:-false}" = "true" ]; then
        # Simulate execution during a dry run
        # Log "Running" message
        printf "%b[-]%b %s: %s. Command: \"%s\".\n" "$BOLD$FGGLD" "$RESET" "$sim_prefix" "$exec_name" "$exec_process"
        sleep 3
        # Move the cursor up and clear the line
        printf "%b" "${MOVE_UP}${CLEAR_LINE}"
        # Log start_prefix
        printf "%b[✔]%b %s: %s.\n" "$BOLD$FGGRN" "$RESET" "$start_prefix" "$exec_name"
        exit 0
    else
        # Execute the command and capture the exit status
        # Log "Running" message
        printf "%b[✔]%b %s: %s.\n" "$BOLD$FGGRN" "$RESET" "$start_prefix" "$exec_name"
        exec env SOURCE_DIR="$script_path" RE_RUN=true "$exec_process"
        exit 0
    fi
}

# Display installation instructions or log the start of the installation in non-interactive or terse mode.
start_script() {
    logI "$REPO_NAME install beginning."
}

# Sets the system timezone interactively or logs if already set.
set_time() {
    # Declare local variables
    local need_set current_date tz yn

    # Get the current date and time
    current_date="$(date)"
    tz="$(date +%Z)"

    # Log and return if the timezone is not GMT or BST
    if [ "$tz" != "GMT" ] && [ "$tz" != "BST" ]; then
        need_set=true
        return
    fi

    # Check if the script is in terse mode
    if [[ "$need_set" == "true" ]]; then
        logW "Timezone detected as $tz, which may need to be updated."
        return
    fi

    # Inform the user about the current date and time
    logI "Timezone detected as $tz, which may need to be updated."

    # Prompt for confirmation or reconfiguration
    while true; do
        read -rp "Is this correct? [y/N]: " yn < /dev/tty
        case "$yn" in
            [Yy]*) 
                logI "Timezone confirmed on $current_date"
                break
                ;;
            [Nn]* | *) 
                dpkg-reconfigure tzdata
                logI "Timezone reconfigured on $current_date"
                break
                ;;
        esac
    done
}

# Installs or upgrades all packages in the APT_PACKAGES list.
apt_packages() {
    # Declare local variables
    local package

    logI "Updating and managing required packages (this may take a few minutes)."

    # Update package list and fix broken installs
    if ! exec_command "Update local package index" "sudo apt-get update -y"; then
        logE "Failed to update package list."
        return 1
    fi

    # Update package list and fix broken installs
    if ! exec_command "Fixing broken or incomplete package installations" "sudo apt-get install -f -y"; then
        logE "Failed to fix broken installs."
        return 1
    fi

    # Install or upgrade each package in the list
    for package in "${APT_PACKAGES[@]}"; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
            if ! exec_command "Upgrade $package" "sudo apt-get install --only-upgrade -y $package"; then
                logW "Failed to upgrade package: $package. Continuing with the next package."
            fi
        else
            if ! exec_command "Install $package" "sudo apt-get install -y $package"; then
                logW "Failed to install package: $package. Continuing with the next package."
            fi
        fi
    done

    logI "Package Installation Summary: All operations are complete."
    return 0
}

# Display usage information and examples for the script.
usage() {
    cat << EOF
Usage: $THIS_SCRIPT [options]

Options:
  -dr, --dry-run              Enable dry-run mode, where no actions are performed.
                              Useful for testing the script without side effects.
  -v, --version               Display the script version and exit.
  -h, --help                  Display this help message and exit.
  -f, --log-file <path>       Specify the log file location.
                              Default: /var/log
  -l, --log-level <level>     Set the logging verbosity level.
                              Available levels: DEBUG, INFO, WARNING, ERROR, CRITICAL.
                              Default: DEBUG.

Environment Variables:
  LOG_PATH                    Specify the log file path. Overrides the default location.
  LOG_LEVEL                   Set the logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL).

EOF

    # Exit with success
    exit 0
}

# arse command-line arguments and set configuration variables.
parse_args() {
    local arg  # Iterator for arguments

    # If no arguments are provided, return early
    if [[ "$#" -eq 0 ]]; then
        return 0
    fi

    # Iterate through arguments
    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --dry-run|-dr)
                DRY_RUN=true
                ;;
            --version|-v)
                print_version
                exit 0
                ;;
            --help|-h)
                usage
                ;;
            --log-file|-f)
                # Check if the next argument exists and is not another option
                if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                    die 1 "Missing argument for $1. Specify a valid path."
                fi
                LOG_PATH=$(realpath -m "$2" 2>/dev/null || printf "\n")
                if [[ -z "$LOG_PATH" || ! -d "$LOG_PATH" ]]; then
                    die 1 "Invalid or non-existent directory '$2' for --log-file."
                fi
                shift  # Skip the value for this option
                ;;
            --log-level|-l)
                # Check if the next argument exists and is not another option
                if [[ -z "${2:-}" || "${2:-}" =~ ^- ]]; then
                    die 1 "Missing argument for '$1'. Valid options are: DEBUG, INFO, WARNING, ERROR, CRITICAL."
                fi
                LOG_LEVEL="$2"
                case "$LOG_LEVEL" in
                    DEBUG|INFO|WARNING|ERROR|CRITICAL) ;;  # Valid levels
                    *)
                        die 1 "Invalid log level: $LOG_LEVEL. Valid options are: DEBUG, INFO, WARNING, ERROR, CRITICAL."
                        ;;
                esac
                shift  # Skip the value for this option
                ;;
            -*)
                die 1 "Unknown option '$arg'. Use -h or --help to see available options."
                ;;
            *)
                die 1 "Unexpected argument '$arg'."
                exit 1
                ;;
        esac
        shift  # Process the next argument
    done
}

# Check if NetworkManager (nmcli) is running and active.
check_network_manager() {
    if ! nmcli -t -f RUNNING general | grep -q "running"; then
        die 1 "Network Manager is required but not active."
    fi
}

# Check hostapd status to ensure it does not conflict with NetworkManager's AP.
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
        exit 1
    elif [ "$installed" = "y" ]; then
        warn "Hostapd is installed but not enabled. Consider uninstalling if issues arise."
        printf "Press any key (or wait 5 seconds) to continue.\n"
        read -n 1 -t 5 -r || true
        return
    fi
}

install_controller_script() {
    # Declare local variables
    local script_path

    # Check if RE_RUN is not set to "true"
    if [[ "$RE_RUN" != "true" ]]; then
        # Get the directory of the current script
        script_path="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
        # Check if the current script path is not the same as the controller path
        if [[ "$script_path" != "$(dirname "$CONTROLLER_PATH")" ]]; then

            # Check if CONTROLLER_IS_INSTALLED and DAEMON_IS_INSTALLED are true
            if $CONTROLLER_IS_INSTALLED && $DAEMON_IS_INSTALLED; then
                # Source the configuration file
                source "$script_path/$SCRIPT_NAME.conf"
            fi

            # Log the installation action
            logI "Installing this tool as $CONTROLLER_PATH."

            # Execute commands to install the controller
            exec_command "Installing controller" "cp -f \"$script_path/$THIS_SCRIPT\" \"$CONTROLLER_PATH\""
            exec_command "Change permissions on controller" "chmod +x \"$CONTROLLER_PATH\""

            # Execute the controller script in the new location
            exec_newshell "New location: $CONTROLLER_PATH" "$CONTROLLER_PATH"
        fi
    fi
}

menu() {
    while true; do
        display_main_menu
        printf "Enter your choice:\n"

        # Read user input with timeout
        if ! read -n 1 -t 30 -sr user_choice < /dev/tty ; then
            # Handle timeout or error
            exit_controller "User timeout."
        fi

        execute_menu_option "$user_choice"
    done
}

# Display the main menu for configuration and maintenance tasks.
display_main_menu() {
    clear

    local menu_number=1

    # Clear the OPTIONS_MAP before rebuilding it
    OPTIONS_MAP=()

    printf "%s\n" "${FGYLW}${BOLD}AP Pop-Up Installation and Setup, ver: $SEM_VER ${RESET}"
    printf "\n"
    printf "%s\n" "AP Pop-Up raises an access point when no configured WiFi networks"
    printf "%s\n" "are in range."
    printf "\n"

    if ! $CONTROLLER_IS_INSTALLED; then
        printf " %d = Install AP Pop-Up Script\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="install_appop_script"
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
    elif $CONTROLLER_IS_INSTALLED && ! $DAEMON_IS_INSTALLED; then
        printf " %d = Install AP Pop-Up Script\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="install_appop_script"
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
    elif $CONTROLLER_IS_INSTALLED && $DAEMON_IS_INSTALLED; then
        printf " %d = Change the Access Point SSID or Password\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="update_access_point_ssid"
        menu_number=$((menu_number + 1))

        printf " %d = Change the Access Point IP Address\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="update_access_point_ip"
        menu_number=$((menu_number + 1))

        printf " %d = Live Switch between Network WiFi and Access Point\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="switch_between_wifi_and_ap"
        menu_number=$((menu_number + 1))

        printf " %d = Setup a New WiFi Network or Change Password\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="setup_wifi_network"
        menu_number=$((menu_number + 1))

        printf " %d = Change Hostname\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="update_hostname"
        menu_number=$((menu_number + 1))

        printf " %d = Uninstall appop\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="uninstall_ap_popup"
        menu_number=$((menu_number + 1))

        printf " %d = Run appop now\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="run_ap_popup"
        menu_number=$((menu_number + 1))

        printf " %d = Exit\n" "$menu_number"
        OPTIONS_MAP[$menu_number]="exit_controller"
    fi

    # Add an additional line break after the menu
    printf "\n"
}

# Function to execute the selected menu option
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

install_man_pages() {
    # Base directory for man pages
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

## Scans for available WiFi networks, allowing the user to add a new network or change the password for an existing one.
setup_wifi_network() {
    local wifi_list=()
    local selection=""
    local attempts=0
    local max_attempts=5

    if [ ! -f "$CONFIG_FILE" ]; then
        clear
        logW "Config file not yet present, install script from menu first."
        return
    else
        check_config_file
    fi
    clear

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
        read -n 1 -sr < /dev/tty || true

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

## Updates the password for an existing WiFi network or creates a new profile for a selected network.
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

# Install the AP Pop-Up script to /usr/bin and start its systemd services.
install_appop_script() {
    if [ ! "$RE_RUN" == "true" ]; then
        clear
    fi

    install_controller_script   # Install controller and relaunch

    if [ ! -f "$SOURCE_DIR/$SOURCE_SCRIPT_NAME" ]; then
        die 1 "Error: $SOURCE_SCRIPT_NAME not found in $SOURCE_DIR. Cannot continue."
    fi

    if [ ! -f "$SCRIPT_PATH" ]; then
        exec_command "Installing $SOURCE_SCRIPT_NAME" "cp '$SOURCE_DIR/$SOURCE_SCRIPT_NAME' '$SCRIPT_PATH'"
        chmod +x "$SCRIPT_PATH"

        check_config_file       # Install config file if needed
        create_systemd_service  # Install service if needed
        create_systemd_timer    # Install timer if needed
        install_man_pages       # Install man pages

        # Run appop onece
        exec_command "Calling $SCRIPT_NAME" "$SCRIPT_PATH"

        if [ "$RE_RUN" == "true" ]; then
            clear
            RE_RUN="false"
        exit_controller "Installation complete. You can run this script again by executing 'sudo apconfig'."
    fi
    fi
}

# Ensure the main configuration file exists.
check_config_file() {

    if [ ! -f "$CONFIG_FILE" ]; then
        if [ -f "$SOURCE_DIR/$SCRIPT_NAME.conf" ]; then
            logI "Creating default configuration file at $CONFIG_FILE."
            exec_command "Installing default configuration" "cp \"$SCRIPT_NAME.conf\" \"../conf/$CONFIG_FILE\""
            chown root:root "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
        else
            die 1 "$SCRIPT_NAME.conf not found. Cannot continue."
        fi

    fi
    source "$CONFIG_FILE"
    logI "Configuration loaded."
}

# Create the systemd service unit for AP Pop-Up if it doesn't already exist.
create_systemd_service() {
    local service_file_path="$SYSTEMD_PATH/$SERVICE_FILE"

    if ! systemctl -all list-unit-files "$SERVICE_FILE" | grep -q "$SERVICE_FILE"; then
        logI "Creating systemd service: $SCRIPT_NAME."

        cat > "$service_file_path" <<EOF
[Unit]
Description=Automatically toggles WiFi Access Point based on network availability ($SCRIPT_NAME)
After=multi-user.target
Requires=network-online.target

[Service]
Type=simple
ExecStart=${SCRIPT_PATH}
StandardOutput=file:$LOG_PATH/output.log
StandardError=file:$LOG_PATH/error.log

[Install]
WantedBy=multi-user.target
EOF
# TODO: Make sure we have all entries
# TODO: For sure need log paths

        exec_command "Creating log target" "mkdir $LOG_PATH"
        exec_command "Unmasking $SERVICE_FILE" "systemctl unmask $SERVICE_FILE"
        exec_command "Enabling $SERVICE_FILE" "systemctl enable $SERVICE_FILE"
        exec_command "Reloading systemd" "systemctl daemon-reload"
        logI "Systemd service $SERVICE_FILE created."
    else
        logD "Systemd service $SERVICE_FILE already exists. Skipping."
    fi
}

# Create the systemd timer unit for AP Pop-Up if it doesn't already exist.
create_systemd_timer() {
    local timer_file_path="$SYSTEMD_PATH/$TIMER_FILE"

    if ! systemctl -all list-unit-files "$TIMER_FILE" | grep -q "$TIMER_FILE"; then
        logI "Creating systemd timer: $SCRIPT_NAME."

        cat > "$timer_file_path" <<EOF
[Unit]
Description=Runs $SCRIPT_NAME every 2 minutes to check network status (appop)

[Timer]
OnBootSec=0min
OnCalendar=*:0/2

[Install]
WantedBy=timers.target
EOF
# TODO: Make sure we have all entries
# TODO: For sure need log paths

        exec_command "Unmasking $TIMER_FILE" "systemctl unmask $TIMER_FILE"
        exec_command "Enabling $TIMER_FILE" "systemctl enable $TIMER_FILE"
        exec_command "Reloading systemd" "systemctl daemon-reload"
        exec_command "Starting $TIMER_FILE" "systemctl start $TIMER_FILE"
        logI "Systemd service $TIMER_FILE started."
    else
        logD "Systemd timer $TIMER_FILE already exists. Skipping."
    fi
}

# Update the AP SSID and Password in /etc/appop.conf.
update_access_point_ssid() {

    if [ ! -f "$CONFIG_FILE" ]; then
        clear
        logW "Config file not yet present, install script from menu first."
        return
    else
        check_config_file
    fi
    clear

    cat << EOF

>> ${FGYLW}Current AP SSID:${RESET} ${FGGRN}$AP_SSID${RESET}

Enter new SSID (1-32 characters, no leading/trailing spaces, Enter to keep current):
EOF
    read -r new_ssid < /dev/tty

    # Trim leading/trailing spaces and remove any enclosing quotes from new_ssid
    new_ssid=$(printf "%s" "$new_ssid" | xargs | sed -e 's/^"//' -e 's/"$//')

    # Validate the SSID
    if [[ -n "$new_ssid" ]]; then
        if [[ ${#new_ssid} -ge 1 && ${#new_ssid} -le 32 ]]; then
            if [[ "$new_ssid" =~ ^[[:print:]]+$ && "$new_ssid" != *" "* ]]; then
                AP_SSID="$new_ssid"
                # Update the SSID in the config file
                sed -i "s/^AP_SSID=.*/AP_SSID=\"$new_ssid\"/" "$CONFIG_FILE"
                printf "\n${FGYLW}<< AP SSID updated to:${RESET} ${FGGRN}$new_ssid${RESET}\n"
            else
                logE "Invalid SSID. Must be 1-32 printable characters with no leading/trailing spaces."
                return
            fi
        else
            logE "Invalid SSID length. Must be 1-32 characters."
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

    # Trim leading and trailing spaces (if needed)
    new_pw=$(printf "%s" "$new_pw" | xargs)

    # Validate the password
    if [ -n "$new_pw" ]; then
        if [[ ${#new_pw} -ge 8 && ${#new_pw} -le 63 && "$new_pw" =~ ^[[:print:]]+$ ]]; then
            # Update the password if valid
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

# Update the AP IP and Gateway in /etc/appop.conf.
update_access_point_ip() {

    if [ ! -f "$CONFIG_FILE" ]; then
        clear
        logW "Config file not yet present, install script from menu first."
        return
    else
        check_config_file
    fi
    clear

    # Declare all local variables
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

    # Read user's choice
    read -n 1 -t 5 -sr choice < /dev/tty || true
    printf "\n"
    case "$choice" in
        1) base="192.168." ;;
        2) base="10.0." ;;
        3) return ;;
        *) logW "Invalid selection." ; return ;;
    esac

    # Prompt for the third octet
    printf "\nEnter the third octet (0-255):\n"
    read -r third_octet < /dev/tty
    if ! validate_host_number "$third_octet" 255; then return; fi

    # Prompt for the fourth octet
    printf "\nEnter the fourth octet (0-253):\n"
    read -r fourth_octet < /dev/tty
    if ! validate_host_number "$fourth_octet" 253; then return; fi

    # Remove leading zeros from octets
    third_octet=$((10#$third_octet))  # Converts to decimal, removes leading zeros
    fourth_octet=$((10#$fourth_octet))  # Converts to decimal, removes leading zeros

    # Construct the new IP and Gateway
    new_ip="${base}${third_octet}.${fourth_octet}/24"
    new_gateway="${base}${third_octet}.254"

    # Validate the new subnet and gateway
    if ! validate_subnet "$new_ip" "$new_gateway"; then return; fi

    # Validate networks do not conflict
    printf "\nValidating network configuration, this will take a moment.\n"
    if ! validate_ap_configuration "$new_ip" "$new_gateway"; then return; fi

    # Display the proposed new configuration
    cat << EOF

<< ${FGYLW}New AP IP will be:${RESET} ${FGGRN}$new_ip${RESET}
<< ${FGYLW}New AP GW will be:${RESET} ${FGGRN}$new_gateway${RESET}

EOF

    # Confirm the changes
    printf "Apply these changes? (y/N): "
    read -n 1 -t 5 -sr confirm < /dev/tty || true
    printf "\n"
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Apply the changes to the configuration file
        sed -i "s|^AP_CIDR=.*|AP_CIDR=\"$new_ip\"|" "$CONFIG_FILE"
        sed -i "s|^AP_GATEWAY=.*|AP_GATEWAY=\"$new_gateway\"|" "$CONFIG_FILE"
        AP_CIDR="$new_ip"
        AP_GATEWAY="$new_gateway"
        printf "Changes applied successfully.\n"
    else
        logI "Changes canceled."
    fi
}

validate_host_number() {
    local num="$1"
    local max="$2"  # Maximum allowed value

    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 0 ] && [ "$num" -le "$max" ]; then
        return 0  # Valid
    else
        logW "Invalid input. Must be a number between 0 and $max."
        return 1  # Invalid
    fi
}

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

# Change the system hostname using nmcli.
update_hostname() {
    clear
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
            # Update hostname via nmcli
            printf "\n"
            exec_command "Update hostname via nmcli" "nmcli general hostname $new_hostname"

            # Update /etc/hostname
            exec_command "Update /etc/hostname" "printf '%s\n' \"$new_hostname\" | tee /etc/hostname"

            # Update /etc/hosts
            exec_command "Update /etc/hosts" "sed -i 's/$(hostname)/$new_hostname/g' /etc/hosts"

            # Change hostname for the current session
            exec_command "" "hostnamectl set-hostname $new_hostname"

            # Update shell session's HOSTNAME variable
            exec_command "Update shell session's HOSTNAME variable" "export HOSTNAME=$new_hostname"

            # Reload hostname-related services
            exec_command "Reload hostname-related services" "systemctl restart avahi-daemon"

            printf "\n${FGYLW}<< Hostname updated to:${RESET} ${FGGRN}$new_hostname${RESET}\n"
        else
            printf "Invalid hostname. Please follow the hostname rules.\n" >&2
        fi
    else
        printf "Hostname unchanged.\n"
    fi
}

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

# Uninstall the appop script and related services/timers.
uninstall_ap_popup() {
    clear
    logI "Uninstalling AP Pop-Up."

    if systemctl -all list-unit-files "$SERVICE_FILE" | grep -q "$SERVICE_FILE"; then
        logI "Removing systemd service: $SERVICE_FILE"
        exec_command "Stopping $SERVICE_FILE" "systemctl stop $SERVICE_FILE"
        exec_command "Disabling $SERVICE_FILE" "systemctl disable $SERVICE_FILE"
        exec_command "Unmasking $SERVICE_FILE" "systemctl unmask $SERVICE_FILE"
        exec_command "Removing $SERVICE_FILE" "rm -f $SYSTEMD_PATH/$SERVICE_FILE"
        exec_command "Reloading systemd" "systemctl daemon-reload"
        exec_command "Removing log target" "rm -fr $LOG_PATH/"
    fi

    if systemctl -all list-unit-files "$TIMER_FILE" | grep -q "$TIMER_FILE"; then
        logI "Removing systemd service: $TIMER_FILE"
        exec_command "Stopping $TIMER_FILE" "systemctl stop $TIMER_FILE"
        exec_command "Disabling $TIMER_FILE" "systemctl disable $TIMER_FILE"
        exec_command "Unmasking $TIMER_FILE" "systemctl unmask $TIMER_FILE"
        exec_command "Removing $TIMER_FILE" "rm -f $SYSTEMD_PATH/$TIMER_FILE"
        exec_command "Reloading systemd" "systemctl daemon-reload"
    fi

    if [ -f "$CONFIG_FILE" ]; then
        exec_command "Removing $SCRIPT_NAME.conf" "rm -f $CONFIG_FILE"
    fi

    if [ -f "$SCRIPT_PATH" ]; then
        logD "Removing the script: $SCRIPT_NAME"
        rm -f "$SCRIPT_PATH"
    fi

    if [ -f "$CONTROLLER_PATH" ]; then
        logD "Removing the script: $CONTROLLER_PATH"
        rm -f "$CONTROLLER_PATH"
    fi

        # Base directory for man pages
    man_base_dir="/usr/share/man"

    # Loop through the man pages
    for man_page in "${MAN_PAGES[@]}"; do
        # Extract the section number from the file name
        section="${man_page##*.}"

        # Target directory based on the section number
        target_dir="${man_base_dir}/man${section}"

        # Install the man page
        if [ -f "$target_dir/$man_page" ]; then
            exec_command "Removing man page $man_page." "rm '$target_dir/$man_page'"
        fi
    done

    # Update the man page database
    exec_command "Updating man page database." "mandb"
    logI "Man pages removed successfully."

    exit_controller "AP Pop-Up uninstallation complete."
}

# Run the appop script.
run_ap_popup() {
    clear

    logI "Running AP Pop-Up."
    if which "$SCRIPT_NAME" &>/dev/null; then
        exec_command "Calling $SCRIPT_NAME" "$SCRIPT_PATH"
    else
        warn "$SCRIPT_NAME not available. Install first."
    fi
}

# Switch between WiFi and AP by running the appop script directly.
switch_between_wifi_and_ap() {
    clear

    logI "Running AP Pop-Up."
    if which "$SCRIPT_NAME" &>/dev/null; then
        exec_command "Calling $SCRIPT_NAME" "$SCRIPT_PATH"
    else
        warn "$SCRIPT_NAME not available. Install first."
    fi
}

# Check if the script is running from CONTROLLER_PATH and set CONTROLLER_IS_INSTALLED accordingly
# Check if the daemon exists in SCRIPT_PATH and set DAEMON_IS_INSTALLED accordingly
is_running_from_installed_path() {
    local current_script_path

    # Initialize variables
    CONTROLLER_IS_INSTALLED=false
    DAEMON_IS_INSTALLED=false

    # Get the absolute path of the currently running script
    current_script_path=$(readlink -f "${BASH_SOURCE[0]}")

    # Check if the script is running from the installed path
    if [[ "$current_script_path" == "$CONTROLLER_PATH" ]]; then
        CONTROLLER_IS_INSTALLED=true
    fi

    # Check if the file exists in SCRIPT_PATH
    if [[ -f "$SCRIPT_PATH" ]]; then
        DAEMON_IS_INSTALLED=true
    fi
}

# Function to fetch the tree of the repository
fetch_tree() {
    local branch_sha
    branch_sha=$(curl -s \
        "https://api.github.com/repos/$REPO_ORG/$REPO_NAME/git/ref/heads/$REPO_BRANCH" \
        | jq -r '.object.sha')

    curl -s \
        "https://api.github.com/repos/$REPO_ORG/$REPO_NAME/git/trees/$branch_sha?recursive=1"
}

# Function to download a single file
download_file() {
    local file_path="$1"
    local dest_dir="$2"

    mkdir -p "$dest_dir"
    curl -s \
        -o "$dest_dir/$(basename "$file_path")" \
        "https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME/$REPO_BRANCH/$file_path"
}

# Main function to list and download files from specified directories
download_files_from_directories() {
    # TODO: local dest_root="$USER_HOME/$REPO_NAME"       # Replace with your desired destination root directory
    local dest_root="$USER_HOME/apppop"       # Replace with your desired destination root directory
    logI "Fetching repository tree."

    local tree
    tree=$(fetch_tree)

    if [[ $(printf "%s" "$tree" | jq '.tree | length') -eq 0 ]]; then
        die 1 "Failed to fetch repository tree." "Check repository details or ensure it is public."
        exit 1
    fi

    for dir in "${DIRECTORIES[@]}"; do
        logI "Processing directory: $dir"

        local files
        files=$(printf "%s" "$tree" | jq -r --arg TARGET_DIR "$dir/" '.tree[] | select(.type=="blob" and (.path | startswith($TARGET_DIR))) | .path')

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

# Function to update ownership and permissions for a single file
update_file() {
    local file="$1"
    local home_root="$2"

    # Check if both parameters are provided
    if [[ -z "$file" || -z "$home_root" ]]; then
        logE "Usage: update_file <file> <home_root>"
        return 1
    fi

    # Verify if the home root exists and is a directory
    if [[ ! -d "$home_root" ]]; then
        logE "Home root '$home_root' is not a valid directory."
        return 1
    fi

    # Verify if the target file exists
    if [[ ! -f "$file" ]]; then
        logE "File '$file' does not exist."
        return 1
    fi

    # Determine the owner of the home root
    local owner
    owner=$(stat -c '%U' "$home_root")
    if [[ -z "$owner" ]]; then
        logE "Unable to determine the owner of the home root."
        return 1
    fi

    # Change ownership of the file to the determined owner
    logI "Changing ownership of '$file' to '$owner'..."
    chown "$owner":"$owner" "$file" || {
        logE "Failed to change ownership."
        return 1
    }

    # Apply permissions
    if [[ "$file" == *.sh ]]; then
        logI "Setting permissions of '$file' to 700 (executable)."
        chmod 700 "$file" || {
            logE "Failed to set permissions to 700."
            return 1
        }
    else
        logI "Setting permissions of '$file' to 600."
        chmod 600 "$file" || {
            logE "Failed to set permissions to 600."
            return 1
        }
    fi

    logI "Ownership and permissions updated successfully for '$file'."
    return 0
}

# Function to update directories and iterate over files
update_directory_and_files() {
    local directory="$1"
    local home_root="$USER_HOME"

    # Check if the target directory is provided
    if [[ -z "$directory" ]]; then
        logE "Usage: update_directory_and_files <directory>"
        return 1
    fi

    # Verify if the target directory exists
    if [[ ! -d "$directory" ]]; then
        logE "Directory '$directory' does not exist."
        return 1
    fi

    # Verify if USER_HOME is set and valid
    if [[ -z "$home_root" || ! -d "$home_root" ]]; then
        logE "USER_HOME environment variable is not set or points to an invalid directory."
        return 1
    fi

    # Determine the owner of the home root
    local owner
    owner=$(stat -c '%U' "$home_root")
    if [[ -z "$owner" ]]; then
        logE "Unable to determine the owner of the home root."
        return 1
    fi

    # Change ownership and permissions of the target directory and subdirectories
    logI "Changing ownership and permissions of '$directory' tree."
    find "$directory" -type d -exec chown "$owner":"$owner" {} \; -exec chmod 700 {} \; || {
        logE "Failed to update ownership or permissions of directories."
        return 1
    }

    # Update permissions for non-`.sh` files
    logI "Setting permissions of non-.sh files to 600 in '$directory'."
    find "$directory" -type f ! -name "*.sh" -exec chown "$owner":"$owner" {} \; -exec chmod 600 {} \; || {
        logE "Failed to update permissions of non-.sh files."
        return 1
    }

    # Update permissions for `.sh` files
    logI "Setting permissions of .sh files to 700 in '$directory'."
    find "$directory" -type f -name "*.sh" -exec chown "$owner":"$owner" {} \; -exec chmod 700 {} \; || {
        logE "Failed to update permissions of .sh files."
        return 1
    }

    logI "Ownership and permissions applied to all files and directories in '$directory'."
    return 0
}

exit_controller() {
    local message="${1:-Exiting.}"  # Default message if no argument is provided
    clear
    printf "%s\n" "$message"  # Log the provided or default message
    exit 0
}

# DEBUG
pause() {
    printf "Press any key to continue.\n"
    read -n 1 -t 5 -sr < /dev/tty || true
}

# Main function
main() {
    # Check Environment Functions
    check_pipe          # Get fallback name if piped through bash

    # Arguments Functions
    parse_args "$@"     # Parse command-line arguments

    # Check Environment Functions
    enforce_sudo        # Ensure proper privileges for script execution
    validate_depends    # Ensure required dependencies are installed
    validate_sys_accs   # Verify critical system files are accessible
    validate_env_vars   # Check for required environment variables

    # Logging Functions
    setup_log           # Setup logging environment

    # More: Check Environment Functions
    check_bash          # Ensure the script is executed in a Bash shell
    check_sh_ver        # Verify the current Bash version meets minimum requirements
    check_release       # Check Raspbian OS version compatibility

    if [ "$IS_PIPE" = true ]; then
        local real_script_path
        # Curl installer to local temp_dir
        download_files_from_directories

        # Resolve the real path of the script
        # TODO: local dest_root="$USER_HOME/$REPO_NAME"       # Replace with your desired destination root directory
        local dest_root="$USER_HOME/apppop"       # Replace with your desired destination root directory
        real_script_path=$(readlink -f "$dest_root/src/$THIS_SCRIPT")

        logI "Re-spawning from $real_script_path."
        sleep 2
        
        # Replace the current running script
        exec_newshell "Re-spawning after curl" "$real_script_path"
    fi

    # See if we are in the installed path
    is_running_from_installed_path

    # Check if CONTROLLER_IS_INSTALLED and DAEMON_IS_INSTALLED are false
    if ! $CONTROLLER_IS_INSTALLED && ! $DAEMON_IS_INSTALLED; then
        # Get any apt packages needed
        apt_packages
    fi

    # If we are re-spawning after install, go back to install
    if [ "$RE_RUN" == "true" ]; then
        install_appop_script
    else
        # Print/Display Environment Functions
        print_system        # Log system information
        print_version       # Log the script version

        # Check nmcli is running
        check_network_manager
    fi

    # Execute menu
    menu
}

# Run the main function and exit with its return status
main "$@"
exit $?
