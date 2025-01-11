#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

# -----------------------------------------------------------------------------
# @file install.sh
# @brief Script for installation or uninstallation of AP Pop-Up scripts.
# @details  This script handles installation and uninstallation of the
#           AP Pop-Up scripts and supporting files. It must be run with sudo
#           privileges.
#
#           It will install any necessary required packages.
#
#           Upon completion, the controller may be executed with:
#               $ sudo apconfig
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
# @optional $1 Mode of operation: Determines the script's behavior. Can be
#           "install" or "uninstall".
# @optional $2 Turn on verbose debug with the argument "debug"
#
# -----------------------------------------------------------------------------
# @section example Example Usage
# @example
# url="https://raw.githubusercontent.com/lbussy/ap-popup/refs/heads/main/scripts/install.sh"
# curl -fsSL "$url" | sudo bash                         # Install normally
# curl -fsSL "$url" | sudo bash -s -- debug             # Install with verbose debug
# curl -fsSL "$url" | sudo bash -s -- uninstall         # Uninstall
# curl -fsSL "$url" | sudo bash -s -- uninstall debug   # Uninstall with verbose debug
#
# curl comamnd line:
#
# `-s`: Silent mode, hides progress.
# `-S`: Shows errors if they occur.
# `-L`: Follows redirects if the URL is redirected.
# `| bash`: Pipes the downloaded script into bash for execution.
# `-s`: A flag for bash, telling it to process arguments passed to the script.
# `--`: Separates the script arguments from bash options.
# `<ARGUMENTS>`: The arguments you want to pass to the downloaded script.
# -----------------------------------------------------------------------------

############
### Global Script Declarations
############

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
#               back to using the value of `SCRIPT_NAME`, which
#               defaults to `debug_print.sh`.
#
# @var SCRIPT_NAME
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
#          to `SCRIPT_NAME`.
# -----------------------------------------------------------------------------
declare SCRIPT_NAME="${SCRIPT_NAME:-installer.sh}"
if [[ -z "${THIS_SCRIPT:-}" ]]; then
    if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]:-}" != "bash" ]]; then
        # Use BASH_SOURCE[0] if it is available and not "bash"
        THIS_SCRIPT=$(basename "${BASH_SOURCE[0]}")
    else
        # If BASH_SOURCE[0] is unbound or equals "bash", use
        # SCRIPT_NAME
        THIS_SCRIPT="${SCRIPT_NAME}"
    fi
fi

# -----------------------------------------------------------------------------
# @var DRY_RUN
# @brief Enables simulated execution of certain commands.
# @details When set to `true`, commands are not actually executed but are
#          simulated to allow testing or validation without side effects.
#          If set to `false`, commands execute normally.
#
# @example
# DRY_RUN=true ./template.sh  # Run the script in dry-run mode.
# -----------------------------------------------------------------------------
declare DRY_RUN="${DRY_RUN:-false}"

# -----------------------------------------------------------------------------
# @var IS_REPO
# @brief Indicates whether the script resides in a GitHub repository or
#        subdirectory.
# @details This variable is initialized to `false` by default. During
#          execution, it is dynamically set to `true` if the script is detected
#          to be within a GitHub repository (i.e., if a `.git` directory exists
#          in the directory hierarchy of the script's location).
#
# @example
# if [[ "$IS_REPO" == "true" ]]; then
#     printf "This script resides within a GitHub repository.\n"
# else
#     printf "This script is not located within a GitHub repository.\n"
# fi
# -----------------------------------------------------------------------------
declare IS_REPO="${IS_REPO:-false}"  # Default to "false".

# -----------------------------------------------------------------------------
# @brief Project metadata constants used throughout the script.
# @details These variables provide metadata about the script, including
#          ownership, versioning, project details, and GitHub URLs. They are
#          initialized with default values or dynamically set during execution
#          to reflect the project's context.
#
# @vars
# - @var REPO_ORG The organization or owner of the repository (default:
#                 "lbussy").
# - @var REPO_NAME The name of the repository (default: "bash-template").
# - @var REPO_BRANCH The current Git branch name (default: "main").
# - @var GIT_TAG The current Git tag (default: "0.0.1").
# - @var SEM_VER The semantic version of the project (default: "0.0.1").
# - @var LOCAL_REPO_DIR The local source directory path (default: unset).
# - @var LOCAL_WWW_DIR The local web directory path (default: unset).
# - @var LOCAL_SCRIPTS_DIR The local scripts directory path (default: unset).
# - @var GIT_RAW The base URL for accessing raw GitHub content
#                (default: "https://raw.githubusercontent.com/$REPO_ORG/
#                $REPO_NAME").
# - @var GIT_API The base URL for the GitHub API for this repository
#                (default: "https://api.github.com/repos/$REPO_ORG/$REPO_NAME")
# - @var GIT_CLONE The clone URL for the GitHub repository
#                  (default: "https://api.github.com/repos/$REPO_ORG/
#                  $REPO_NAME").
#
# @example
# printf "Repository: %s/%s\n" "$REPO_ORG" "$REPO_NAME"
# printf "Branch: %s, Tag: %s, Version: %s\n" "$REPO_BRANCH" "$GIT_TAG" "$SEM_VER"
# printf "Source Directory: %s\n" "${LOCAL_REPO_DIR:-Not Set}"
# printf "WWW Directory: %s\n" "${LOCAL_WWW_DIR:-Not Set}"
# printf "Scripts Directory: %s\n" "${LOCAL_SCRIPTS_DIR:-Not Set}"
# printf "Raw URL: %s\n" "$GIT_RAW"
# printf "API URL: %s\n" "$GIT_API"
# -----------------------------------------------------------------------------
declare REPO_ORG="${REPO_ORG:-lbussy}"
declare REPO_NAME="${REPO_NAME:-ap-popup}"
declare REPO_DISPLAY_NAME="${REPO_DISPLAY_NAME:-AP Pop-Up}"
declare REPO_BRANCH="${REPO_BRANCH:-main}"
declare GIT_TAG="${GIT_TAG:-1.0.0}"
declare SEM_VER="${GIT_TAG:-1.0.0-main}"
declare LOCAL_REPO_DIR="${LOCAL_REPO_DIR:-}"
declare LOCAL_WWW_DIR="${LOCAL_WWW_DIR:-}"
declare LOCAL_SCRIPTS_DIR="${LOCAL_SCRIPTS_DIR:-}"
declare GIT_RAW="${GIT_RAW:-"https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"}"
declare GIT_API="${GIT_API:-"https://api.github.com/repos/$REPO_ORG/$REPO_NAME"}"

# -----------------------------------------------------------------------------
# @var DIRECTORIES
# @brief List of directories used during man page installation and configuration.
# @details These directories are involved in storing and managing files related
#          to the application:
#          - `man`: Contains the man pages for the application.
#          - `src`: Contains source files for the application.
#          - `conf`: Contains configuration files for the application.
# -----------------------------------------------------------------------------
readonly GIT_DIRS=("man" "scripts" "conf" "systemd")

# -----------------------------------------------------------------------------
# @var MAN_BASE_DIR
# @brief Base directory for man pages.
# @details This variable defines the root directory where man pages will be
#          installed or removed. By default, it is set to `/usr/share/man`.
#          It can be overridden by setting the `MAN_BASE_DIR` environment
#          variable before running the script.
# -----------------------------------------------------------------------------
readonly MAN_BASE_DIR="${MAN_BASE_DIR:-/usr/share/man}"

# -----------------------------------------------------------------------------
# @var CONTROLLER_NAME
# @brief The final installed name of the main controller script (without
#        extension).
#
# @var CONTROLLER_PATH
# @brief The path where the controller script will be installed.
# @details Combines `/usr/local/sbin/` with the `CONTROLLER_NAME` to determine
#          the full installation path of the controller script.
# -----------------------------------------------------------------------------
readonly CONTROLLER_SOURCE="apconfig.sh"
readonly CONTROLLER_NAME="${CONTROLLER_SOURCE%%.*}"
readonly CONTROLLER_PATH="/usr/local/sbin/$CONTROLLER_NAME"

# -----------------------------------------------------------------------------
# @brief Configuration and installation details for the bash-based daemon.
# @details This script sets variables and paths required for installing and
#          configuring the `appop` daemon and its supporting files.
#
#          Variables:
#          - APP_SOURCE: Name of the source script that will be installed
#            as `appop`.
#          - AP_NAME: The final installed name of the main script (no
#            extension).
#          - APP_PATH: Path to where the main script (appop) will be installed.
#          - SYSTEMD_PATH: Path to the systemd directory for services/timers.
#          - SERVICE_FILE: Name of the systemd service file to be
#            created/managed.
#          - TIMER_FILE: Name of the systemd timer file to be created/managed.
#          - CONFIG_FILE: Path to the AP Pop-Up configuration file.
#          - LOG_PATH: Path to the directory where logs for the application
#            will be stored.
# -----------------------------------------------------------------------------
readonly APP_SOURCE="appop.sh"
readonly APP_NAME="${APP_SOURCE%%.*}"
readonly APP_PATH="/usr/bin/$APP_NAME"
readonly SYSTEMD_PATH="/etc/systemd/system"
readonly SERVICE_FILE="$SYSTEMD_PATH/$APP_NAME.service"
readonly TIMER_FILE="$SYSTEMD_PATH/$APP_NAME.timer"
readonly CONFIG_FILE="/etc/$APP_NAME.conf"
readonly APP_LOG_PATH="/var/log/$APP_NAME"

# -----------------------------------------------------------------------------
# @brief Determines and assigns the home directory and real user based on sudo
#        privileges and environment variables.
#
# @details This section of the script checks whether the `REQUIRE_SUDO` flag is
#          set to true and whether the `SUDO_USER` environment variable is
#          available. It sets the `USER_HOME` variable based on the following
#          logic:
#          - If `REQUIRE_SUDO` is true and `SUDO_USER` is not set, `USER_HOME`
#            is set to empty values.
#          - If `SUDO_USER` is set, `USER_HOME` is set to the home directory of
#            the sudo user.
#          - If `SUDO_USER` is not set, it falls back to using the current
#            user's home directory (`HOME`).
#
# @variables
# @var USER_HOME The home directory of the user. It is set to the value of
#                `$HOME` or the sudo user's home directory, depending on the
#                logic.
#
# @example
# This block is typically used in scripts requiring differentiation between the
# current user and a sudo user, especially when running the script with sudo.
# -----------------------------------------------------------------------------
declare USER_HOME
if [[ "$REQUIRE_SUDO" == true && -z "${SUDO_USER-}" ]]; then
    # Fail gracefully if REQUIRE_SUDO is true and SUDO_USER is not set
    USER_HOME=""
elif [[ -n "${SUDO_USER-}" ]]; then
    # Use SUDO_USER's values if it's set
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    # Fallback to HOME and whoami if SUDO_USER is not set
    USER_HOME="$HOME"
fi

# -----------------------------------------------------------------------------
# @var USE_CONSOLE
# @brief Controls whether logging output is directed to the console.
# @details When set to `true`, log messages are displayed on the console in
#          addition to being written to the log file (if enabled). When set
#          to `false`, log messages are written only to the log file, making
#          it suitable for non-interactive or automated environments.
#
# @example
# - USE_CONSOLE=true: Logs to both console and file.
# - USE_CONSOLE=false: Logs only to file.
# -----------------------------------------------------------------------------
declare USE_CONSOLE="${USE_CONSOLE:-true}"

# -----------------------------------------------------------------------------
# @var TERSE
# @brief Enables or disables terse logging mode.
# @details When `TERSE` is set to `true`, log messages are minimal and
#          optimized for automated environments where concise output is
#          preferred. When set to `false`, log messages are verbose, providing
#          detailed information suitable for debugging or manual intervention.
#
# @example
# TERSE=true  # Enables terse logging mode.
# ./template.sh
#
# TERSE=false # Enables verbose logging mode.
# ./template.sh
# -----------------------------------------------------------------------------
declare TERSE="${TERSE:-false}"

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
readonly MIN_BASH_VERSION="4.0"

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
#     printf "This script requires OS version %d or higher.\n" "$MIN_OS"
#     exit 1
# fi
# -----------------------------------------------------------------------------
readonly MIN_OS="11"

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
#     printf "This script supports OS versions up to %d.\n" "$MAX_OS"
#     exit 1
# fi
# -----------------------------------------------------------------------------
readonly MAX_OS="-1"

# -----------------------------------------------------------------------------
# @var LOG_OUTPUT
# @brief Controls where log messages are directed.
# @details Specifies the logging destination(s) for the script's output. This
#          variable can be set to one of the following values:
#          - `"file"`: Log messages are written only to a file.
#          - `"console"`: Log messages are displayed only on the console.
#          - `"both"`: Log messages are written to both the console and a file.
#          - `unset`: Defaults to `"both"`.
#
#          This variable allows flexible logging behavior depending on the
#          environment or use case.
#
# @default "both"
#
# @example
# LOG_OUTPUT="file" ./template.sh      # Logs to a file only.
# LOG_OUTPUT="console" ./template.sh   # Logs to the console only.
# LOG_OUTPUT="both" ./template.sh      # Logs to both destinations.
# -----------------------------------------------------------------------------
declare LOG_OUTPUT="${LOG_OUTPUT:-both}"

# -----------------------------------------------------------------------------
# @var LOG_FILE
# @brief Specifies the path to the log file.
# @details Defines the file path where log messages are written when logging
#          to a file is enabled. If not explicitly set, this variable defaults
#          to blank, meaning no log file will be used unless a specific path
#          is assigned at runtime or through an external environment variable.
#
# @default ""
#
# @example
# LOG_FILE="/var/log/my_script.log" ./template.sh  # Use a custom log file.
# -----------------------------------------------------------------------------
declare LOG_FILE="${LOG_FILE:-}"

# -----------------------------------------------------------------------------
# @var LOG_LEVEL
# @brief Specifies the logging verbosity level.
# @details Defines the verbosity level for logging messages. This variable
#          controls which messages are logged based on their severity. It
#          defaults to `"DEBUG"` if not set. Common log levels include:
#          - `"DEBUG"`: Detailed messages for troubleshooting and development.
#          - `"INFO"`: Informational messages about normal operations.
#          - `"WARN"`: Warning messages indicating potential issues.
#          - `"ERROR"`: Errors that require immediate attention.
#          - `"CRITICAL"`: Critical issues that may cause the script to fail.
#
# @default "DEBUG"
#
# @example
# LOG_LEVEL="INFO" ./template.sh  # Set the log level to INFO.
# -----------------------------------------------------------------------------
declare LOG_LEVEL="${LOG_LEVEL:-DEBUG}"

# -----------------------------------------------------------------------------
# @var DEPENDENCIES
# @type array
# @brief List of required external commands for the script.
# @details This array defines the external commands that the script depends on
#          to function correctly. Each command in this list is checked for
#          availability at runtime. If a required command is missing, the
#          script may fail or display an error message.
#
#          Best practices:
#          - Ensure all required commands are included.
#          - Use a dependency-checking function to verify their presence early
#            in the script.
#
# @default A predefined set of common system utilities:
# - `"awk"`, `"grep"`, `"tput"`, `"cut"`, `"tr"`, `"getconf"`, `"cat"`, `"sed"`,
#   `"basename"`, `"getent"`, `"date"`, `"printf"`, `"whoami"`, `"touch"`,
#   `"dpkg"`, `"dpkg-reconfigure"`, `"curl"`, `"wget"`, `"realpath"`.
#
# @note Update this list as needed to reflect the actual commands used in the
#       script.
#
# @example
# for cmd in "${DEPENDENCIES[@]}"; do
#     if ! command -v "$cmd" &>/dev/null; then
#         printf "Error: Missing required command: $cmd"
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
#
# @example
# for var in "${ENV_VARS_BASE[@]}"; do
#     if [[ -z "${!var}" ]]; then
#         printf "Error: Required environment variable '%s' is not set.\n" "$var"
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
declare -ar ENV_VARS_BASE=(
    "HOME"
    "COLUMNS"
)

# -----------------------------------------------------------------------------
# @var ENV_VARS
# @type array
# @brief Final list of required environment variables.
# @details This array extends `ENV_VARS_BASE` to include additional variables
#          required under specific conditions. If the script requires root
#          privileges (`REQUIRE_SUDO=true`), the `SUDO_USER` variable is added
#          dynamically during runtime. Otherwise, it inherits only the base
#          environment variables.
#
#          - `SUDO_USER`: Identifies the user who invoked the script using
#            `sudo`.
#
# @note Ensure `ENV_VARS_BASE` is properly defined before constructing
#       `ENV_VARS`.
#
# @example
# for var in "${ENV_VARS[@]}"; do
#     if [[ -z "${!var}" ]]; then
#         printf "Error: Required environment variable '%s' is not set.\n" "$var"
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
if [[ "$REQUIRE_SUDO" == true ]]; then
    readonly -a ENV_VARS=("${ENV_VARS_BASE[@]}" "SUDO_USER")
else
    readonly -a ENV_VARS=("${ENV_VARS_BASE[@]}")
fi

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
# printf "The terminal width is set to %d columns.\n" "$COLUMNS"
# -----------------------------------------------------------------------------
COLUMNS="${COLUMNS:-80}"

# -----------------------------------------------------------------------------
# @var SYSTEM_READS
# @type array
# @brief List of critical system files to check.
# @details Defines the absolute paths to system files that the script depends
#          on for its execution. These files must be present and readable to
#          ensure the script operates correctly. The following files are
#          included:
#          - `/etc/os-release`: Contains operating system identification data.
#
# @example
# for file in "${SYSTEM_READS[@]}"; do
#     if [[ ! -r "$file" ]]; then
#         printf "Error: Required system file '%s' is missing or not
#               readable.\n" "$file"
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
declare -ar SYSTEM_READS=(
    "/etc/os-release"
)
readonly SYSTEM_READS

# -----------------------------------------------------------------------------
# @var APT_PACKAGES
# @type array
# @brief List of required APT packages.
# @details Defines the APT packages that the script depends on for its
#          execution. These packages should be available in the system's
#          default package repository. The script will check for their presence
#          and attempt to install any missing packages as needed.
#
#          Packages included:
#          - `jq`: JSON parsing utility.
#
# @example
# for pkg in "${APT_PACKAGES[@]}"; do
#     if ! dpkg -l "$pkg" &>/dev/null; then
#         printf "Error: Required package '%s' is not installed.\n" "$pkg"
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
readonly APT_PACKAGES=(
    "jq"  # JSON parsing utility
)

# -----------------------------------------------------------------------------
# @var WARN_STACK_TRACE
# @type string
# @brief Flag to enable stack trace logging for warnings.
# @details Controls whether stack traces are printed alongside warning messages.
#          This feature is particularly useful for debugging and tracking the
#          script's execution path in complex workflows.
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
# @brief Handles shell exit operations, displaying session statistics.
# @details This function is called automatically when the shell exits. It
#          calculates and displays the number of commands executed during
#          the session and the session's end timestamp. It is intended to
#          provide users with session statistics before the shell terminates.
#
# @global EXIT This signal is trapped to call the `egress` function upon shell
#              termination.
#
# @note The function uses `history | wc -l` to count the commands executed in
#       the current session and `date` to capture the session end time.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
egress() {
    # TODO: Add any cleanup items here
    true
}

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
        printf "[DEBUG in %s] %b from %s():%d.\n" \
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
    header=$(printf "%b%s%b %b%b%s%b %b%s%b" "$color" "$header_l" "$reset" "$color" "$bold" "$header_name" "$reset" "$color" "$header_r" "$reset")
    local footer formatted_line
    formatted_line="$(printf '%*s' "$width" '' | tr ' ' "$char")"
    footer="$(printf '%b%s%b' "$color" "$formatted_line" "$reset")"

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
# printf "%s\n" "$result"  # Output: "Hello."
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
    read -n 1 -sr key < /dev/tty || true
    printf "\n"
    debug_print "$key" "$debug"

    debug_end "$debug"
    return 0
}

############
### Print/Display Environment Functions
############

# -----------------------------------------------------------------------------
# @brief Print the system information to the log.
# @details Extracts and logs the system's name and version using information
#          from `/etc/os-release`. If the information cannot be extracted, logs
#          a warning message. Includes debug output when the `debug` argument is provided.
#
# @param $1 [Optional] Debug flag to enable detailed output (`debug`).
#
# @global None
#
# @return None
#
# @example
# print_system debug
# Outputs system information with debug logs enabled.
# -----------------------------------------------------------------------------
print_system() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Declare local variables
    local system_name

    # Extract system name and version from /etc/os-release
    system_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d '=' -f2 | tr -d '"')

    # Debug: Log extracted system name
    debug_print "Extracted system name: ${system_name:-<empty>}" "$debug"

    # Check if system_name is empty and log accordingly
    if [[ -z "${system_name:-}" ]]; then
        warn "System: Unknown (could not extract system information)."
        debug_print "System information could not be extracted." "$debug"
    else
        logI "System: $system_name."  # Log the system information
        debug_print "Logged system information: $system_name" "$debug"
    fi

    debug_end "$debug"
    return 0
}

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
    else
        logI "Running $REPO_DISPLAY_NAME's '$THIS_SCRIPT', version $SEM_VER"
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

# -----------------------------------------------------------------------------
# @brief Validate proxy connectivity by testing a known URL.
# @details Uses `check_url` to verify connectivity through the provided proxy
#          settings.
#
# @param $1 [Optional] Proxy URL to validate (defaults to `http_proxy` or
#                      `https_proxy` if not provided).
# @param $2 [Optional] "debug" to enable verbose output for the proxy
#                      validation.
#
# @global http_proxy The HTTP proxy URL (if set).
# @global https_proxy The HTTPS proxy URL (if set).
#
# @return 0 if the proxy is functional, 1 otherwise.
#
# @example
# validate_proxy "http://myproxy.com:8080"
# validate_proxy debug
# -----------------------------------------------------------------------------
validate_proxy() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Check if proxy_url is passed
    local proxy_url=""
    # Check if proxy_url is the first argument (if set)
    if [[ -n "$1" && "$1" =~ ^https?:// ]]; then
        # First argument is proxy_url
        proxy_url="$1"
        shift  # Move to the next argument
    fi

    # Default to global proxy settings if no proxy is provided
    [[ -z "${proxy_url:-}" ]] && proxy_url="${http_proxy:-$https_proxy}"

    # Validate that a proxy is set
    if [[ -z "${proxy_url:-}" ]]; then
        warn "No proxy URL configured for validation."
            debug_end "$debug"
        return 1
    fi

    logI "Validating proxy: $proxy_url"

    # Test the proxy connectivity using check_url (passing the debug flag)
    if check_url "$proxy_url" "curl" "--silent --head --max-time 10 --proxy $proxy_url" "$debug"; then
        logI "Proxy $proxy_url is functional."
        debug_print "Proxy $proxy_url is functional." "$debug"
            debug_end "$debug"
        return 0
    else
        warn "Proxy $proxy_url is unreachable or misconfigured."
        debug_print "Proxy $proxy_url failed validation." "$debug"
            debug_end "$debug"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# @brief Check connectivity to a URL using a specified tool.
# @details Attempts to connect to a given URL with `curl` or `wget` based on
#          the provided arguments. Ensures that the tool's availability is
#          checked and handles timeouts gracefully. Optionally prints debug
#          information if the "debug" flag is set.
#
# @param $1 The URL to test.
# @param $2 The tool to use for the test (`curl` or `wget`).
# @param $3 Options to pass to the testing tool (e.g., `--silent --head` for
#           `curl`).
# @param $4 [Optional] "debug" to enable verbose output during the check.
#
# @return 0 if the URL is reachable, 1 otherwise.
#
# @example
# check_url "http://example.com" "curl" "--silent --head" debug
# -----------------------------------------------------------------------------
check_url() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local url="$1"
    local tool="$2"
    local options="$3"

    # Validate inputs
    if [[ -z "${url:-}" ]]; then
        printf "ERROR: URL and tool parameters are required for check_url.\n" >&2
            debug_end "$debug"
        return 1
    fi

    # Check tool availability
    if ! command -v "$tool" &>/dev/null; then
        printf "ERROR: Tool '%s' is not installed or unavailable.\n" "$tool" >&2
            debug_end "$debug"
        return 1
    fi

    # Perform the connectivity check, allowing SSL and proxy errors
    local retval
    if $tool "$options" "$url" &>/dev/null; then
        debug_print "Successfully connected to $#url using $tool." "$debug"
        retval=0
    else
        debug_print "Failed to connect to $url using $tool." "$debug"
        retval=1
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Comprehensive internet and proxy connectivity check.
# @details Combines proxy validation and direct internet connectivity tests
#          using `check_url`. Validates proxy configuration first, then tests
#          connectivity with and without proxies. Outputs debug information if
#          enabled.
#
# @param $1 [Optional] "debug" to enable verbose output for all checks.
#
# @global http_proxy Proxy URL for HTTP (if set).
# @global https_proxy Proxy URL for HTTPS (if set).
# @global no_proxy Proxy exclusions (if set).
#
# @return 0 if all tests pass, 1 if any test fails.
#
# @example
# check_internet debug
# -----------------------------------------------------------------------------
check_internet() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local primary_url="http://google.com"
    local secondary_url="http://1.1.1.1"
    local proxy_valid=false

    # Validate proxy settings
    if [[ -n "${http_proxy:-}" || -n "${https_proxy:-}" ]]; then
        debug_print "Proxy detected. Validating proxy configuration." "$debug"
        if validate_proxy "$debug"; then  # Pass debug flag to validate_proxy
            proxy_valid=true
            debug_print "Proxy validation succeeded." "$debug"
        else
            warn "Proxy validation failed. Proceeding with direct connectivity checks."
        fi
    fi

    # Check connectivity using curl
    if command -v curl &>/dev/null; then
        debug_print "curl is available. Testing internet connectivity using curl." "$debug"

        # Check with proxy
        if $proxy_valid && curl --silent --head --max-time 10 --proxy "${http_proxy:-${https_proxy:-}}" "$primary_url" &>/dev/null; then
            logI "Internet is available using curl with proxy."
            debug_print "curl successfully connected via proxy." "$debug"
            debug_end "$debug"
            return 0
        fi

        # Check without proxy
        if curl --silent --head --max-time 10 "$primary_url" &>/dev/null; then
            debug_print "curl successfully connected without proxy." "$debug"
            debug_end "$debug"
            return 0
        fi

        debug_print "curl failed to connect." "$debug"
    else
        debug_print "curl is not available." "$debug"
    fi

    # Check connectivity using wget
    if command -v wget &>/dev/null; then
        debug_print "wget is available. Testing internet connectivity using wget." "$debug"

        # Check with proxy
        if $proxy_valid && wget --spider --quiet --timeout=10 --proxy="${http_proxy:-${https_proxy:-}}" "$primary_url" &>/dev/null; then
            logI "Internet is available using wget with proxy."
            debug_print "wget successfully connected via proxy." "$debug"
            debug_end "$debug"
            return 0
        fi

        # Check without proxy
        if wget --spider --quiet --timeout=10 "$secondary_url" &>/dev/null; then
            logI "Internet is available using wget without proxy."
            debug_print "wget successfully connected without proxy." "$debug"
            debug_end "$debug"
            return 0
        fi

        debug_print "wget failed to connect." "$debug"
    else
        debug_print "wget is not available." "$debug"
    fi

    # Final failure message
    warn "No internet connection detected after all checks."
    debug_print "All internet connectivity tests failed." "$debug"
    debug_end "$debug"
    return 1
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
# printf "%s\n" "$result" "$wrapped"
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
    if [[ ! "logD logI logW logE logC logX" =~ ${FUNCNAME[1]} ]]; then
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
    [[ -n "$extended_message" ]] && debug_print "Extended message: '$extended_message'" "$debug"

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
# shellcheck disable=SC2317
logD() { log_message_with_severity "DEBUG" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=SC2317
logI() { log_message_with_severity "INFO" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=SC2317
logW() { log_message_with_severity "WARNING" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=SC2317
logE() { log_message_with_severity "ERROR" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=SC2317
logC() { log_message_with_severity "CRITICAL" "${1:-}" "${2:-}" "${3:-}"; }
# shellcheck disable=SC2317
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
### Get Project Parameters Functions
############

# -----------------------------------------------------------------------------
# @brief Convert a Git repository name to title case.
# @details Replaces underscores and hyphens with spaces and converts words to
#          title case.  Provides debugging output when the "debug" argument is
#          passed.
#
# @param $1 The Git repository name (e.g., "my_repo-name").
# @param $2 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return The repository name in title case (e.g., "My Repo Name").
# @retval 0 Success: the converted repository name is printed.
# @retval 1 Failure: prints an error message to standard error.
#
# @throws Exits with an error if the repository name is empty.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
repo_to_title_case() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local repo_name="${1:-}"  # Input repository name
    local title_case  # Variable to hold the formatted name

    # Validate input
    if [[ -z "${repo_name:-}" ]]; then
        warn "Repository name cannot be empty."
            debug_end "$debug"
        return 1
    fi
    debug_print "Received repository name: $repo_name" "$debug"

    # Replace underscores and hyphens with spaces and convert to title case
    title_case=$(printf "%s" "$repo_name" | tr '_-' ' ' | awk '{for (i=1; i<=NF; i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

    local retval
    if [[ -n "${title_case:-}" ]]; then
        debug_print "onverted repository name to title case: $title_case" "$debug"
        printf "%s\n" "$title_case"
        retval=0
    else
        warn "Failed to convert repository name to title case."
        retval=1
    fi

    debug_end "$debug"
    return "$retval"
}

############
### Git Functions
############

# -----------------------------------------------------------------------------
# @brief Downloads a single file from a Git repository's raw URL.
# @details Fetches a file from the raw content URL of the repository and saves
#          it to the specified local directory. Ensures the destination
#          directory exists before downloading.
#
# @param $1 The relative path of the file in the repository.
# @param $2 The local destination directory where the file will be saved.
#
# @global GIT_RAW The base URL for raw content access in the Git repository.
# @global REPO_BRANCH The branch name from which the file will be fetched.
#
# @throws Logs an error and returns non-zero if the file download fails.
#
# @return None. Downloads the file to the specified directory.
#
# @example
# download_file "path/to/file.txt" "/local/dir"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
download_file() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local file_path="$1"
    local dest_dir="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        debug_print "Create dir: $dest_dir (dry)" "$debug"
    else
        debug_print "Exec: mkdir -p $dest_dir" "$debug"
        mkdir -p "$dest_dir"
    fi

    local file_name
    file_name=$(basename "$file_path")
    file_name="${file_name//\'/}"

    debug_print "Downloading from GitHub: /$REPO_BRANCH/$file_path" "$debug"
    debug_print "Downloading to: $dest_dir/$file_name" "$debug"

    if [[ "$DRY_RUN" == "true" ]]; then
        debug_print "Exec:  wget -q -O $dest_dir/$file_name $GIT_RAW/$REPO_BRANCH/$file_path"
    else
        wget -q -O "$dest_dir/$file_name" "$GIT_RAW/$REPO_BRANCH/$file_path" || {
            warn "Failed to download file: $file_path to $dest_dir/$file_name"
            return 1
        }
    fi

    # Sanitize the filename
    local dest_file="$dest_dir/$file_name"
    local sanitized_file="${dest_file//\'/}"
    if [[ "$dest_file" != "$sanitized_file" ]]; then
        mv -f "$dest_file" "$sanitized_file"
    fi
    debug_end "$debug"
    return
}

# -----------------------------------------------------------------------------
# @brief Fetches the Git tree of a specified branch from a repository.
# @details Retrieves the SHA of the specified branch and then fetches the
#          complete tree structure of the repository, allowing recursive access
#          to all files and directories.
#
# @global GIT_API The base URL for the GitHub API, pointing to the repository.
# @global REPO_BRANCH The branch name to fetch the tree from.
#
# @throws Prints an error message and exits if the branch SHA cannot be
#         fetched.
#
# @return Outputs the JSON representation of the repository tree.
#
# @example
# fetch_tree
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
fetch_tree() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local branch_sha
    branch_sha=$(curl -s "$GIT_API/git/ref/heads/$REPO_BRANCH" | jq -r '.object.sha')

    if [[ -z "$branch_sha" || "$branch_sha" == "null" ]]; then
        warn "Failed to fetch branch SHA for branch: $REPO_BRANCH. Check repository details or API access."
        return 1
    fi

    curl -s "$GIT_API/git/trees/$branch_sha?recursive=1"
    debug_end "$debug"
    return
}

# -----------------------------------------------------------------------------
# @brief Downloads files from specified directories in a repository.
# @details This function retrieves a repository tree, identifies files within
#          specified directories, and downloads them to the local system.
#
# @param $1 The target directory to update.
#
# @global USER_HOME The home directory of the user, used as the base for
#         storing files.
# @global GIT_DIRS Array of directories in the repository to process.
#
# @throws Exits the script with an error if the repository tree cannot be
#         fetched.
#
# @return Downloads files to the specified directory structure under
#         $USER_HOME/apppop.
#
# @example
# download_files_in_directories
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
download_files_in_directories() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local dest_root="$USER_HOME/$REPO_NAME"
    debug_print "Fetching repository tree." "$debug"
    local tree; tree=$(fetch_tree "$debug")

    if [[ $(printf "%s" "$tree" | jq '.tree | length') -eq 0 ]]; then
        die 1 "Failed to fetch repository tree. Check repository details or ensure it is public."
    fi

    for dir in "${GIT_DIRS[@]}"; do
        debug_print "Processing directory: $dir" "$debug"

        local files
        files=$(printf "%s" "$tree" | jq -r --arg TARGET_DIR "$dir/" \
            '.tree[] | select(.type=="blob" and (.path | startswith($TARGET_DIR))) | .path')

        if [[ -z "$files" ]]; then
            logI "No files found in directory: $dir"
            continue
        fi

        local dest_dir="$dest_root/$dir"
        debug_print "Exec: mkdir -p $dest_dir" "$debug"
        mkdir -p "$dest_dir"

        printf "%s\n" "$files" | while read -r file; do
            debug_print "Downloading: $file" "$debug"
            download_file "$file" "$dest_dir" "$debug"
        done

        debug_print "Files from $dir downloaded to: $dest_dir" "$debug"
    done

    debug_end "$debug"
    logI "Install files saved in: $dest_root"
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
    debug_print " exec_process: $exec_process" "$debug"

    # Simulate command execution if DRY_RUN is enabled
    if [[ -n "$DRY_RUN" ]]; then
        printf "[✔] Simulating: '%s'.\n" "$exec_process"
            debug_end "$debug"
        exit_script 0 "$debug"
    fi

    # Validate the command
    if [[ "$exec_process" == "true" || "$exec_process" == "" ]]; then
        printf "[✔] Running: '%s'.\n" "$exec_process"
            debug_end "$debug"
        exec true
    elif ! command -v "${exec_process%% *}" >/dev/null 2>&1; then
        warn "'$exec_process' is not a valid command or executable."
            debug_end "$debug"
        die 1 "Invalid command: '$exec_process'"
    else
        # Execute the actual command
        printf "[✔] Running: '%s'.\n" "$exec_process"
        debug_print "Executing command: '$exec_process' in function '$func_name()' at line ${LINENO}." "$debug"
        exec $exec_process || die 1 "Command '${exec_process}' failed"
    fi

    debug_end "$debug"
    return 0
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
# exec_command "Test Command" "printf Hello World\n" "debug"
# -----------------------------------------------------------------------------
# TODO: Move this to template (allow running a function)
exec_command() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

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
        printf "%b%b" "$MOVE_UP" "$CLEAR_LINE"
        printf "%b[✔]%b %s %s.\n" "${FGGRN}" "${RESET}" "$complete_pre" "$exec_name"
        debug_end "$debug"
        return 0
    fi

    # 3) Check if exec_process is a function or a command
    local status=0
    if declare -F "$exec_process" &>/dev/null; then
        # It's a function, pass remaining arguments to the function
        "$exec_process" "$@" "$debug" "$action" || status=$?
    else
        # It's a command, pass remaining arguments to the command
        bash -c "$exec_process" &>/dev/null || status=$?
    fi

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
    return $status
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
### Installer Functions
############

# -----------------------------------------------------------------------------
# @brief Start the script, with optional timeout for non-interactive environments.
# @details Allows users to press a key to proceed, or defaults after 10 seconds.
#          If the debug flag is provided, additional information about the process
#          will be printed. Dynamically handles "install" or "uninstall" actions.
#
# @param $1 [Required] Action to perform ("install" or "uninstall").
# @param $2 [Optional] Debug flag to enable detailed output (true/false).
#
# @global TERSE Indicates terse mode (skips interactive messages).
# @global REPO_NAME The name of the repository being processed.
#
# @return None
#
# @example
# start_script install debug
# -----------------------------------------------------------------------------
start_script() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    # Validate action
    if [[ "$action" != "install" && "$action" != "uninstall" ]]; then
        debug_print "Invalid action: $action. Must be 'install' or 'uninstall'." "$debug"
        logE "Invalid action specified: $action. Use 'install' or 'uninstall'."
        debug_end "$debug"
        return 1
    fi

    # Adjust log and prompt messages based on action
    local action_message
    if [[ "$action" == "install" ]]; then
        action_message="installation"
    else
        action_message="uninstallation"
    fi

    # Check terse mode
    if [[ "${TERSE:-false}" == "true" ]]; then
        logI "$REPO_DISPLAY_NAME $action_message beginning."
        debug_print "Skipping interactive message due to terse mode." "$debug"
        debug_end "$debug"
        return 0
    fi

    # Prompt user for input
    printf "\nStarting %s for: %s.\n" "$action_message" "$REPO_DISPLAY_NAME"
    printf "Press any key to continue or 'Q' to quit (defaulting in 10 seconds).\n"

    # Read a single key with a 10-second timeout
    if ! read -n 1 -sr -t 10 key < /dev/tty; then
        key=""  # Assign a default value on timeout
    fi
    printf "\n"

    # Handle user input
    case "${key}" in
        [Qq])  # Quit
            debug_print "Quit key pressed. Ending $action_message." "$debug"
            logI "$action_message canceled by user."
            exit_script "Script canceled" "$debug"
            ;;
        "")  # Timeout or Enter
            debug_print "No key pressed, proceeding with $action_message." "$debug"
            ;;
        *)  # Any other key
            debug_print "Key pressed: '$key'. Proceeding with $action_message." "$debug"
            ;;
    esac

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check if NetworkManager (nmcli) is running and active.
# @details This function checks if the NetworkManager service is active and
#          running. It uses `nmcli` to query the status of the NetworkManager.
#          If the service is running and active, it prints a success message.
#          Otherwise, it prints an error message.
#
# @param $1 Action to perform: "install" or "uninstall"
#
# @global None
#
# @return 0 if NetworkManager is running and active, 1 if it is not,
#         or returns immediately if action is "uninstall".
#
# @example
# check_network_manager "install"
# check_network_manager "uninstall"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
check_network_manager() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    # Return immediately if action is "uninstall"
    if [[ "$action" == "uninstall" ]]; then
        debug_end "$debug"
        return 0
    fi

    # Check if NetworkManager is active
    if nmcli general status | grep -q "connected"; then
        debug_print "NetworkManager (nmcli) is running and active." "$debug"
    else
        die 1 "NetworkManager is not installed and running."
    fi
    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Check hostapd status to ensure it does not conflict with nmcli.
# @details This function checks whether `hostapd` is installed and running.
#          If `hostapd` is installed and running, it will fail and exit, as
#          it may conflict with NetworkManager. If `hostapd` is installed but
#          not running, a warning is displayed, and the script continues.
#
# @param $1 Action to perform: "install" or "uninstall".
# @param $2 Optional debug flag to print debug information.
#
# @global None
#
# @return Exits with status 1 if hostapd is installed and running, 0 otherwise.
#
# @example
# check_hostapd_status "install" "$debug"
# check_hostapd_status "uninstall" "$debug"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
check_hostapd_status() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    # Return immediately if action is "uninstall"
    if [[ "$action" == "uninstall" ]]; then
        debug_end "$debug"
        return 0
    fi

    # Check if hostapd is installed
    if command -v hostapd &>/dev/null; then
        # Check if hostapd is running
        if systemctl is-active --quiet hostapd; then
            die 1 "hostapd is installed and running." "It may conflict with NetworkManager."
        else
            warn "hostapd is installed but not running." "It may conflict with nmcli, consider uninstalling it."
        fi
    else
        debug_print "hostapd is not installed."
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the specified APT packages.
# @details This function installs or upgrades packages when "install" is passed as an
#          argument, and removes packages when "uninstall" is passed. It updates the
#          package list, resolves broken dependencies, and manages the package list.
#          On error, it logs the warning but continues the process. It returns 0
#          if no errors occurred, and 1 if any errors occurred during the process.
#
# @param $1 Action to perform: "install" to install or upgrade packages,
#           "uninstall" to remove packages.
# @param $2 [Optional] Debug flag. Pass "debug" to enable detailed output.
#
# @global APT_PACKAGES List of packages to install, upgrade, or remove.
#
# @return 0 if all operations succeed, 1 if any operation fails.
#
# @example
# handle_apt_packages "install" debug
# handle_apt_packages "uninstall" debug
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
handle_apt_packages() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Check if APT_PACKAGES is empty
    if [[ ${#APT_PACKAGES[@]} -eq 0 ]]; then
        logI "No packages specified in APT_PACKAGES. Skipping package handling."
        debug_print "APT_PACKAGES is empty, skipping execution." "$debug"
        debug_end "$debug"
        return 0
    fi

    local package error_count=0  # Counter for failed operations

    logI "Updating and managing required packages (this may take a few minutes)."

    # Update package list and fix broken installs
    if ! exec_command "Update local package index" "sudo apt-get update -y" "$debug" "$action"; then
        warn "Failed to update package list."
        ((error_count++))
    fi
    if ! exec_command "Fixing broken or incomplete package installations" "sudo apt-get install -f -y" "$debug" "$action"; then
        warn "Failed to fix broken installs."
        ((error_count++))
    fi

    # Install, upgrade, or remove each package in the list based on the action
    for package in "${APT_PACKAGES[@]}"; do
        if [[ "$action" == "install" ]]; then
            if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
                if ! exec_command "Upgrade $package" "sudo apt-get install --only-upgrade -y $package" "$debug" "$action"; then
                    warn "Failed to upgrade package: $package."
                    ((error_count++))
                fi
            else
                if ! exec_command "Install $package" "sudo apt-get install -y $package" "$debug" "$action"; then
                    warn "Failed to install package: $package."
                    ((error_count++))
                fi
            fi
        elif [[ "$action" == "uninstall" ]]; then
            if ! exec_command "Remove $package" "sudo apt-get remove -y $package" "$debug" "$action"; then
                warn "Failed to remove package: $package."
                ((error_count++))
            fi
        else
            die 1 "Invalid action. Use 'install' or 'uninstall'."
        fi
    done

    # Log summary of errors
    if ((error_count > 0)); then
        logE "APT package handling completed with $error_count errors."
        debug_print "APT package handling completed with $error_count errors." "$debug"
    else
        logI "APT package handling completed successfully."
        debug_print "APT package handling completed successfully." "$debug"
    fi

    debug_end "$debug"
    return "$error_count"
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the specified controller script.
# @details This function installs the controller script by copying it from
#          the source directory to the specified path when "install" is
#          passed as an argument. It also ensures the script has the correct
#          ownership (root:root) and executable permissions. If "uninstall" is
#          passed, the function will remove the controller script and reset
#          the permissions and ownership.
#
# @param $1 Action to perform: "install" to install the controller, "uninstall"
#           to uninstall the controller.
# @param $2 Optional debug flag to print debug information.
#
# @global LOCAL_REPO_DIR Directory where the source scripts are stored.
# @global CONTROLLER_SOURCE The source file for the controller script.
# @global CONTROLLER_PATH The target path for the controller script.
# @global CONTROLLER_NAME The name of the controller being installed or removed.
#
# @return None
#
# @example
# install_controller_script "install"
# install_controller_script "uninstall"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
install_controller_script() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    local source_root source_path
    source_root="$USER_HOME/$REPO_NAME"
    source_path="$source_root/scripts/$CONTROLLER_SOURCE"

    if [[ "$action" == "install" ]]; then
        logI "Installing '$CONTROLLER_NAME'."

        # Install the controller script
        debug_print "Copying controller." "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: sudo cp -f $source_path $CONTROLLER_PATH"
        else
            exec_command "Copy controller script" "sudo cp -f $source_path $CONTROLLER_PATH" || {
                logE "Failed to install controller."
                debug_end "$debug"
                return 1
            }
        fi

        # Change ownership on the controller
        debug_print  "Changing ownership on controller." "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: sudo chown root:root $CONTROLLER_PATH"
        else
            exec_command "Change ownership on controller" "sudo chown root:root $CONTROLLER_PATH" || {
                logE "Failed to change ownership on controller."
                debug_end "$debug"
                return 1
            }
        fi

        # Change permissions on the controller to make it executable
        debug_print  "Change permissions on controller" "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: chmod +x $CONTROLLER_PATH"
        else
            exec_command "Change permissions on controller" "sudo chmod +x $CONTROLLER_PATH" || {
                logE "Failed to change permissions on controller."
                debug_end "$debug"
                return 1
            }
        fi

    elif [[ "$action" == "uninstall" ]]; then
        logI "Removing '$CONTROLLER_NAME'."

        # Remove the controller script
        debug_print "Removing controller" "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: sudo rm -f $CONTROLLER_PATH"
        else
            exec_command "Remove controller" "sudo rm -f $CONTROLLER_PATH" || {
                logE "Failed to remove controller."
                debug_end "$debug"
                return 1
            }
        fi
    else
        die 1 "Invalid action. Use 'install' or 'uninstall'."
    fi

    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the specified application script.
# @details This function installs the application script by copying it from
#          the source directory to the specified target path when "install" is
#          passed as an argument. It also ensures the script has the correct
#          ownership (root:root) and executable permissions. If "uninstall" is
#          passed, the function will remove the application script and reset
#          the permissions and ownership.
#
# @param $1 Action to perform: "install" to install the application, "uninstall"
#           to uninstall the application.
# @param $2 Optional debug flag to print debug information.
#
# @global LOCAL_REPO_DIR Directory where the source scripts are stored.
# @global APP_SOURCE The source file for the application script.
# @global APP_PATH The target path for the application script.
# @global APP_NAME The name of the application being installed or removed.
#
# @return None
#
# @example
# install_application_script "install"
# install_application_script "uninstall"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
install_application_script() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    local source_root
    source_root="$USER_HOME/$REPO_NAME"
    source_path="$source_root/scripts/$APP_SOURCE"

    if [[ "$action" == "install" ]]; then
        logI "Installing '$CONTROLLER_NAME'."

        # Install the application script
        debug_print "Copying application." "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: cp -f $source_path $APP_PATH"
        else
            exec_command "Instal application script" "sudo cp -f $source_path $APP_PATH" "$debug" || {
                logE "Failed to install application."
                debug_end "$debug"
                return 1
            }
        fi

        # Change ownership on the application script
        debug_print "Changing ownership on application." "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: sudo chown root:root $APP_PATH"
        else
            exec_command "Change ownership on app script" "sudo chown root:root $APP_PATH" "$debug" || {
                logE "Failed to change ownership on application."
                debug_end "$debug"
                return 1
            }
        fi

        # Change permissions on the application script to make it executable
        debug_print  "Changing permissions on application."
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: chmod +x $APP_PATH"
        else
            exec_command "Make app script executable" "sudo chmod +x $APP_PATH" "$debug" "$debug" || {
                logE "Failed to change permissions on application."
                debug_end "$debug"
                return 1
            }
        fi

    elif [[ "$action" == "uninstall" ]]; then
        logI "Removing '$CONTROLLER_NAME'."

        # Remove the application script
        debug_print "Removing application."
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: rm -f $APP_PATH"
        else
            exec_command "Remove application script" "sudo rm -f $APP_PATH" "$debug" || {
                logE "Failed to remove application."
                debug_end "$debug"
                return 1
            }
        fi
    else
        die 1 "Invalid action. Use 'install' or 'uninstall'."
    fi

    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the specified configuration file for the application.
# @details This function installs the configuration file for the application
#          by copying it from the source directory to the target configuration
#          path when "install" is passed as an argument. It also ensures the
#          configuration file has the correct ownership (root:root). If "uninstall"
#          is passed, the function will remove the configuration file and reset
#          the permissions and ownership.
#
# @param $1 Action to perform: "install" to install the configuration, "uninstall"
#           to uninstall the configuration.
# @param $2 Optional debug flag to print debug information.
#
# @global LOCAL_REPO_DIR Directory where the configuration files are stored.
# @global APP_NAME The name of the application for which the configuration
#                  is being installed or removed.
# @global CONFIG_FILE The target configuration file path.
#
# @return None
#
# @example
# install_config_file "install"
# install_config_file "uninstall"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
install_config_file() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    local source_root source_path
    source_root="$USER_HOME/$REPO_NAME"
    source_path="$source_root/conf/$APP_NAME.conf"

    if [[ "$action" == "install" ]]; then
        logI "Installing '$APP_NAME' configuration."

        # Install the configuration file
        debug_print "Installing configuration." "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: cp -f $source_path $CONFIG_FILE"
        else
            exec_command "Copy config file" "sudo cp -f $source_path $CONFIG_FILE" "$debug" || {
                logE "Failed to install config file."
                debug_end "$debug"
                return 1
            }
        fi

        # Change ownership on the config file
        debug_print  "Changing ownership on configuration file." "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: chown root:root $CONFIG_FILE"
        else
            exec_command "Change ownership on config file" "sudo chown root:root $CONFIG_FILE" "$debug" || {
                logE "Failed to change ownership on config file."
                debug_end "$debug"
                return 1
            }
        fi

        # Change permissions on the configuration file
        debug_print  "Changing permissions on configuration file" "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: chmod 644 $CONFIG_FILE"
        else
            exec_command "Change permissions on config file" "sudo chmod 644 $CONFIG_FILE" "$debug" || {
                logE "Failed to change permissions on config file."
                debug_end "$debug"
                return 1
            }
        fi

    elif [[ "$action" == "uninstall" ]]; then
        logI "Removing '$APP_NAME' configuration."

        # Remove the configuration file
        debug_print "Removing configuration file." "$debug"
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Exec: rm -f $CONFIG_FILE"
        else
            exec_command "Remove config file" "sudo rm -f $CONFIG_FILE" "$debug" || {
                logE "Failed to remove configuration."
                debug_end "$debug"
                return 1
            }
        fi
    else
        die 1 "Invalid action. Use 'install' or 'uninstall'."
    fi

    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Replaces a specified string in a script with another string.
# @details Searches for a string bracketed by "%" in the specified script file
#          and replaces it with the provided replacement string.
#
# @param $1 The path/name of the script file.
# @param $2 The string to search for (in the format %string_name%).
# @param $3 The string to replace the search string with.
#
# @global None.
#
# @throws If the file does not exist or is not writable.
#
# @return 0 on success, non-zero on failure.
#
# @example
# replace_string_in_script "script.sh" "%placeholder%" "new_value"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
replace_string_in_script() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    local script_file="${1:-}"
    local search_string="${2:-}"
    local replacement_string="${3:-}"

    # Validate the inputs
    if [[ -z "$script_file" || -z "$search_string" || -z "$replacement_string" ]]; then
        warn "Error: Missing required arguments." "$debug"
        debug_end "$debug"
        return 1
    fi

    if [[ ! -f "$script_file" ]]; then
        debug_print "Error: File '$script_file' does not exist." "$debug"
        warn "Error: File '$script_file' does not exist." >&2
        debug_end "$debug"
        return 2
    fi

    if [[ ! -w "$script_file" ]]; then
        warn "Error: File '$script_file' is not writable." >&2
        debug_end "$debug"
        return 3
    fi

    # Add '%' brackets to the search string
    local full_search_string="%${search_string}%"

    # Perform the replacement
    sed -i "s|$full_search_string|$replacement_string|g" "$script_file"
    local retval=$?
    if [[ $retval -eq 0 ]]; then
        debug_print "Replacement succeeded: '$full_search_string' -> '$replacement_string' in $(basename "$script_file")" "$debug"
        debug_end "$debug"
        return 0
    else
        warn "Error: Replacement failed in file '$script_file'." >&2
        debug_end "$debug"
        return 4
    fi
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the systemd service for the application.
# @details This function creates a new systemd service or updates an existing
#          one for the application when "install" is passed as an argument.
#          When "uninstall" is passed, it removes the systemd service, disables
#          it, and stops it. The function also manages the log directory and
#          its permissions.
#
# @param $1 Action to perform: "install" to create or update the systemd service,
#           "uninstall" to remove the systemd service.
# @param $2 Optional debug flag to print debug information.
#
# @global APP_NAME The name of the application for which the service is created.
# @global APP_PATH The path to the application's executable.
# @global SERVICE_FILE The path to the systemd service file.
# @global APP_LOG_PATH The path where log files for the service will be stored.
#
# @return None
#
# @example
# create_systemd_service "install"
# create_systemd_service "uninstall"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
create_systemd_service() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    local source_root source_file service_name
    service_name=$(basename "$SERVICE_FILE")
    source_root="$USER_HOME/$REPO_NAME"
    source_path="$source_root/systemd/$service_name"

    if [[ "$action" == "install" ]]; then
        # Check if the systemd service already exists
        if ! systemctl list-unit-files --type=service | grep -q "$service_name"; then
            logI "Creating systemd service: $service_name."
        else
            logI "Updating systemd service: $service_name." "$debug"
            # Stop and disable service
            if [[ "$DRY_RUN" == "true" ]]; then
                logD "Stop and disable $service_name (dry-run)."
            else
                exec_command "Disable systemd service" "sudo systemctl disable $service_name" "$debug" "$debug" || {
                    logE "Failed to disable systemd service."
                    debug_end "$debug"
                    return 1
                }

                exec_command "Stop systemd service" "sudo systemctl stop $service_name" "$debug" "$debug" || {
                    logE "Failed to install controller."
                    debug_end "$debug"
                    return 1
                }
                # Check if the service is masked and unmask if necessary
                if systemctl is-enabled "$service_name" 2>/dev/null | grep -q "^masked$"; then
                    exec_command "Unmask systemd service" "sudo systemctl unmask $service_name" "$debug" "$debug" || {
                        logE "Failed to unmask systemd service."
                        debug_end "$debug"
                        return 1
                    }
                fi
            fi
        fi

        if [[ ! -f "$source_path" ]]; then
            warn "$source_path not found."
            return 1
        fi

        # Update template
        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Installing $service_name (dry-run)."
        else
            debug_print "Updating $source_path." "$debug"
            replace_string_in_script "$source_path" "APP_NAME" "$APP_NAME" "$debug"
            replace_string_in_script "$source_path" "APP_PATH" "$APP_PATH" "$debug"
            replace_string_in_script "$source_path" "APP_LOG_PATH" "$APP_LOG_PATH" "$debug"
            # Install the systemd service file
            exec_command "Copy systemd file" "sudo cp -f $source_path $SERVICE_FILE" "$debug" || {
                logE "Failed to copy systemd service."
                debug_end "$debug"
                return 1
            }
            # Change ownership on the systemd service|| {
            exec_command "Change ownership on systemd file" "sudo chown root:root $SERVICE_FILE" "$debug" || {
                logE "Failed to change permissions on systemd service."
                debug_end "$debug"
                return 1
            }
            # Change permissions on the systemd service file
            exec_command "Change permissions on systemd file" "sudo chmod 644 $SERVICE_FILE" "$debug" || {
                logE "Failed to change permissions on systemd service."
                debug_end "$debug"
                return 1
            }
            # Create log directory if not exist and ensure correct permissions
            debug_print "Exec: (log path) sudo mkdir -p $APP_LOG_PATH" "$debug"
            exec_command "Create log path" "sudo mkdir -p $APP_LOG_PATH" "$debug" || {
                logE "Failed to create log path."
                debug_end "$debug"
                return 1
            }
            # Change ownership on the log directory
            exec_command "Change ownership on log path" "sudo chown root:root $APP_LOG_PATH" "$debug" || {
                logE "Failed to change ownership on log path."
                debug_end "$debug"
                return 1
            }
            # Change permissions on the log directory
            exec_command "Change permissions on log path" "sudo chmod 755 $APP_LOG_PATH" "$debug" || {
                logE "Failed to change permissions on log path."
                debug_end "$debug"
                return 1
            }
            # Enable the systemd service
            exec_command "Enable systemd service" "sudo systemctl enable $service_name" "$debug" || {
                logE "Failed to enable systemd service."
                debug_end "$debug"
                return 1
            }
            # Reload systemd
            exec_command "Reload systemd" "sudo systemctl daemon-reload" "$debug" || {
                logE "Failed to reload systemd."
                debug_end "$debug"
                return 1
            }
        fi

        logI "Systemd service $service_name created."

    elif [[ "$action" == "uninstall" ]]; then
        logI "Removing systemd service: $service_name."

        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Remove $service_name (dry-run)."
        else
            # Check if the service unit file exists before proceeding
            if systemctl list-unit-files | grep -q "^$service_name"; then
                # Check if the service is active before attempting to stop it
                if systemctl is-active --quiet "$service_name"; then
                    exec_command "Stop systemd service" "sudo systemctl stop $service_name" "$debug" || {
                        logE "Failed to stop systemd service $service_name."
                        debug_end "$debug"
                        return 1
                    }
                else
                    debug_print "Service $service_name is not active. Skipping stop." "$debug"
                fi

                # Check if the service is enabled before attempting to disable it
                if systemctl is-enabled --quiet "$service_name"; then
                    exec_command "Disable systemd service" "sudo systemctl disable $service_name" "$debug" || {
                        logE "Failed to disable systemd service $service_name."
                        debug_end "$debug"
                        return 1
                    }
                else
                    debug_print "Service $service_name is not enabled. Skipping disable." "$debug"
                fi
            else
                debug_print "Service unit file for $service_name does not exist. Skipping stop and disable." "$debug"
            fi

            # Check if the service file exists before attempting to delete it
            if [[ -f "$SERVICE_FILE" ]]; then
                exec_command "Remove service file" "sudo rm -f $SERVICE_FILE" "$debug" || {
                    logE "Failed to remove service file $SERVICE_FILE."
                    debug_end "$debug"
                    return 1
                }
            else
                debug_print "Service file $SERVICE_FILE does not exist. Skipping removal." "$debug"
            fi

            # Check if the log directory exists before attempting to delete it
            if [[ -d "$APP_LOG_PATH" ]]; then
                exec_command "Remove logs" "sudo rm -rf $APP_LOG_PATH" "$debug" || {
                    logE "Failed to remove logs in $APP_LOG_PATH."
                    debug_end "$debug"
                    return 1
                }
            else
                debug_print "Log directory $APP_LOG_PATH does not exist. Skipping removal." "$debug"
            fi
        fi

        logI "Systemd service $service_name removed."
    else
        die 1 "Invalid action. Use 'install' or 'uninstall'."
    fi

    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the systemd timer for the application.
# @details This function creates a new systemd timer or updates an existing
#          one for the application when "install" is passed as an argument.
#          When "uninstall" is passed, it removes the systemd timer, disables
#          it, and stops it. The function also manages the timer file and
#          enables it based on the action.
#
# @param $1 Action to perform: "install" to create or update the systemd timer,
#           "uninstall" to remove the systemd timer.
# @param $2 Optional debug flag to print debug information.
#
# @global APP_NAME The name of the application for which the timer is created.
# @global TIMER_FILE The path to the systemd timer file.
#
# @return None
#
# @example
# create_systemd_timer "install"
# create_systemd_timer "uninstall"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
create_systemd_timer() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    local timer_name timer_root timer_path
    timer_name=$(basename "$TIMER_FILE")
    timer_root="$USER_HOME/$REPO_NAME"
    timer_path="$timer_root/systemd/$timer_name"

    if [[ "$action" == "install" ]]; then
        # Check if the systemd timer already exists
        if ! systemctl list-unit-files --type=timer | grep -q "$timer_name"; then
            logI "Creating systemd timer: $timer_name."
        else
            logI "Updating systemd timer: $timer_name."
            if [[ "$DRY_RUN" == "true" ]]; then
                logD "Stop and disable $timer_name (dry run)."
            else
                exec_command "Disable $timer_name" "sudo systemctl disable $timer_name" "$debug" || {
                    logE "Failed to disable timer."
                    debug_end "$debug"
                    return 1
                }
                exec_command "Stop $timer_name" "sudo systemctl stop $timer_name" "$debug" || {
                    logE "Failed to stop timer"
                    debug_end "$debug"
                    return 1
                }

                # Check if the timer is masked and unmask if necessary
                if systemctl is-enabled --quiet "$timer_name"; then
                    exec_command "Unmask $timer_name" "sudo systemctl unmask $timer_name" "$debug" || {
                        logE "Failed to unmask timer."
                        debug_end "$debug"
                        return 1
                    }
                fi
            fi
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Install $timer_name (dry run)."
        else
            debug_print "Updating $source_path." "$debug"
            replace_string_in_script "$source_path" "APP_NAME" "$APP_NAME" "$debug"
            # Install the systemd service file
            exec_command "Copy $timer_name" "sudo cp -f $timer_path $TIMER_FILE" || {
                logE "Failed to copy timer."
                debug_end "$debug"
                return 1
            }
            # Change ownership on the systemd timer file
            exec_command "Change ownership on timer file" "sudo chown root:root $TIMER_FILE" "$debug" || {
                logE "Failed to change permissions on systemd service."
                debug_end "$debug"
                return 1
            }
            # Change permissions on the systemd timer file
            exec_command "Change permissions on systemd file" "sudo chmod 644 $TIMER_FILE" "$debug" || {
                logE "Failed to change permissions on systemd service."
                debug_end "$debug"
                return 1
            }
            # Enable the timer
            exec_command "Enable $timer_name" "sudo systemctl enable $timer_name" "$debug" || {
                logE "Failed to enable timer."
                debug_end "$debug"
                return 1
            }
            # Reload systemd
            exec_command "Reload systemd" "sudo systemctl daemon-reload" "$debug" || {
                logE "Failed to reload systemd."
                debug_end "$debug"
                return 1
            }
            exec_command "Start $timer_name" "sudo systemctl start $timer_name" "$debug" || {
                logE "Failed to start timer."
                debug_end "$debug"
                return 1
            }
        fi

        logI "Systemd timer $timer_name created."

    elif [[ "$action" == "uninstall" ]]; then
        logI "Removing systemd timer: $timer_name."

        if [[ "$DRY_RUN" == "true" ]]; then
            logD "Stop and disable $timer_name (dry run)."
        else
            # Check if the timer unit file exists before proceeding
            if systemctl list-unit-files | grep -q "^$timer_name"; then
                # Check if the timer is active before attempting to stop it
                if systemctl is-active --quiet "$timer_name"; then
                    exec_command "Stop $timer_name" "sudo systemctl stop $timer_name" "$debug" || {
                        logE "Failed to stop timer $timer_name."
                        debug_end "$debug"
                        return 1
                    }
                else
                    debug_print "Timer $timer_name is not active. Skipping stop." "$debug"
                fi

                # Check if the timer is enabled before attempting to disable it
                if systemctl is-enabled --quiet "$timer_name"; then
                    exec_command "Disable $timer_name" "sudo systemctl disable $timer_name" "$debug" || {
                        logE "Failed to disable timer $timer_name."
                        debug_end "$debug"
                        return 1
                    }
                else
                    debug_print "Timer $timer_name is not enabled. Skipping disable." "$debug"
                fi
            else
                debug_print "Timer unit file for $timer_name does not exist. Skipping stop and disable." "$debug"
            fi

            # Check if the timer file exists before attempting to delete it
            if [[ -f "$TIMER_FILE" ]]; then
                exec_command "Remove $timer_name" "sudo rm -f $TIMER_FILE" "$debug" || {
                    logE "Failed to remove timer file $TIMER_FILE."
                    debug_end "$debug"
                    return 1
                }
            else
                debug_print "Timer file $TIMER_FILE does not exist. Skipping removal." "$debug"
            fi

            logI "Systemd timer $timer_name removed."
        fi
    else
        die 1 "Invalid action. Use 'install' or 'uninstall'."
    fi

    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Fetches an array of man page files from the repository tree.
# @details This function retrieves the repository tree and filters for files
#          located in the "man/" directory.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global None
#
# @return Prints the list of man page file paths to stderr, one per line.
#         Exits with an error code if the repository tree fetch fails.
#
# @throws Exits with code 1 and an error message if the repository tree cannot
#         be fetched or is empty.
#
# @example
# files=$(get_man_file_array)
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
get_man_file_array() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local tree dir="man"
    tree=$(fetch_tree)

    # Check if the repository tree is empty
    if [[ $(printf "%s" "$tree" | jq '.tree | length') -eq 0 ]]; then
        logE "Failed to fetch repository tree. Check repository details or ensure it is public."
        debug_end "$debug"
        die 1 "Repository tree is empty or unavailable."
    fi

    debug_print "Processing directory: $dir" "$debug"

    # Extract basenames of file paths under the "man/" directory
    local files
    files=$(printf "%s" "$tree" | jq -r --arg TARGET_DIR "$dir/" \
        '.tree[] | select(.type=="blob" and (.path | startswith($TARGET_DIR))) | .path' | xargs -n 1 basename)

    debug_print "Extracted files: \n$files\n" "$debug"

    # Use echo to return the extracted files to the caller
    printf "%s\n" "$files"

    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the man pages.
# @details This function installs the man pages by copying them to the target
#          directories when "install" is passed as an argument. When "uninstall"
#          is passed, it removes the man pages. The function ensures the directories
#          exist, sets the correct permissions, and updates the man page database.
#
# @param $1 Action to perform: "install" to install the man pages,
#           "uninstall" to remove the man pages.
# @param $2 Optional debug flag to print debug information.
#
# @global LOCAL_REPO_DIR Directory where the source man pages are stored.
# @global APP_NAME The name of the application for which the man pages are managed.
# @global MAN_BASE_DIR The base directory for man pages on the system.
#
# @return None
#
# @example
# install_man_pages "install"
# install_man_pages "uninstall"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2317
install_man_pages() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    local man_base_dir="/usr/share/man"
    local -a man_files
    local raw_files

    # Fetch the raw files from get_man_file_array
    raw_files=$(get_man_file_array "$debug")
    debug_print "Raw files output: \n$raw_files" "$debug"

    # Populate the array from raw files
    IFS=$'\n' read -r -d '' -a man_files < <(printf "%s\0" "$raw_files")
    debug_print "Populated man_files array: \n${man_files[*]}" "$debug"

    # Guard clause for empty array
    if [[ ${#man_files[@]} -eq 0 ]]; then
        logE "No man files were found for installation."
        debug_end "$debug"
        return 1
    fi

    if [[ "$action" == "install" ]]; then
        logI "Installing man pages."
        for man_file in "${man_files[@]}"; do
            debug_print "Processing $man_file" "$debug"
            [[ -n "$man_file" ]] || continue  # Skip empty entries

            # Extract section and filename
            local section="${man_file##*.}"
            local filename="$man_file"
            local target_dir="${man_base_dir}/man${section}"
            local source_file="$USER_HOME/$REPO_NAME/man/$filename"
            local compressed_file="${source_file}.gz"

            # Verify the source file exists
            debug_print "Checking source file $source_file" "$debug"
            if [[ ! -f "$source_file" ]]; then
                logE "Manual page $filename not found at $source_file"
                continue
            fi

            # Create target directory if it doesn't exist
            debug_print "Creating directory $target_dir if it doesn't exist" "$debug"
            [[ -d "$target_dir" ]] || sudo mkdir -p "$target_dir"

            # Verify the source file exists (compressed or uncompressed)
            if [[ -f "$compressed_file" ]]; then
                debug_print "Compressed file $compressed_file already exists. Using it." "$debug"
            elif [[ -f "$source_file" ]]; then
                debug_print "Compressing $source_file" "$debug"
                gzip -f "$source_file" || {
                    logE "Failed to compress $source_file"
                    continue
                }
            else
                logE "Manual page $filename not found in either $source_file or $compressed_file"
                continue
            fi

            # Copy the compressed file to the target directory
            debug_print "Copying $compressed_file to $target_dir" "$debug"
            sudo cp "$compressed_file" "$target_dir" || {
                logE "Failed to copy $compressed_file to $target_dir"
                continue
            }

        done
    elif [[ "$action" == "uninstall" ]]; then
        logI "Uninstalling man pages."
        for man_file in "${man_files[@]}"; do
            debug_print "Removing $man_file" "$debug"
            local section="${man_file##*.}"
            local filename="$man_file"
            local target_dir="${man_base_dir}/man${section}"
            local compressed_file="${target_dir}/${filename}.gz"
            
            if [[ -f "$compressed_file" ]]; then
                sudo rm "$compressed_file" || {
                    logE "Failed to remove $compressed_file"
                    continue
                }
                debug_print "Removed $compressed_file" "$debug"
            fi
        done
    else
        die 1 "Invalid action. Use 'install' or 'uninstall'."
    fi

    # Update the man database
    exec_command "Run mandb" "sudo mandb > /dev/null 2>&1" "$debug" || {
        logE "Failed to refresh mandb."
        debug_end "$debug"
        return 1
    }

    # Final success log
    logI "Man pages ${action}ed successfully."

    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Cleans up files in the specified directories.
# @details This function deletes the repository tree when "install" is passed
#          as an argument. When "uninstall" is passed, the function exits
#          immediately without performing any cleanup.
#
# @param $1 Action to perform: "install" to clean up, "uninstall" to skip cleanup.
#
# @global USER_HOME The home directory of the user, used as the base for storing files.
# @global REPO_NAME The repository name used to form the target directory path.
#
# @return 0 if the operation completes successfully, or 1 if an error occurs.
#
# @example
# cleanup_files_in_directories "install"
# cleanup_files_in_directories "uninstall"
# -----------------------------------------------------------------------------
cleanup_files_in_directories() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    local dest_root="$USER_HOME/$REPO_NAME"
    logI "Deleting local repository tree."

    if [[ "$DRY_RUN" == "true" ]]; then
        logD "Delete local repo files (dry-run)."
    else
        # Delete the repository directory
        exec_command "Delete local repository" " sudo rm -fr $dest_root" "$debug" || {
            logE "Failed to delete local install files."
            debug_end "$debug"
            return 1
        }
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief End the script with optional feedback based on logging configuration.
# @details Provides a clear message to indicate the script completed successfully.
#          Dynamically adjusts for "install" or "uninstall" actions. If the debug
#          flag is passed, additional debug information will be logged.
#
# @param $1 [Required] Action performed ("install" or "uninstall").
# @param $2 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global REBOOT Indicates if a reboot is required.
# @global USE_CONSOLE Controls whether console output is enabled.
# @global REPO_NAME The name of the repository being processed.
#
# @return None
#
# @example
# finish_script install debug
# -----------------------------------------------------------------------------
finish_script() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    # Validate action
    if [[ "$action" != "install" && "$action" != "uninstall" ]]; then
        debug_print "Invalid action: $action. Must be 'install' or 'uninstall'." "$debug"
        logE "Invalid action specified: $action. Use 'install' or 'uninstall'."
        debug_end "$debug"
        return 1
    fi

    # Adjust log and output messages based on action
    local action_message
    if [[ "$action" == "install" ]]; then
        action_message="Installation"
    else
        action_message="Uninstallation"
    fi

    # Log completion message
    logI "$action_message complete: $REPO_DISPLAY_NAME."
    debug_print "$action_message complete message logged." "$debug"

    # Optionally clear the screen or display a message
    printf "%s complete: %s.\n" "$action_message" "$REPO_DISPLAY_NAME"

    if [[ "$action" == "install" ]]; then
    # Display follow-up instructions after install
    cat << EOF
TODO:  Provide follow-up instructions after install
EOF
    else
    # Display follow-up instructions after uninstall
    cat << EOF
TODO:  Provide follow-up instructions after uninstall
EOF
    fi

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Installs or uninstalls the application components.
# @details This function handles the installation and uninstallation of various
#          application components. It iterates through a predefined list of
#          functions (controller script, application script, configuration file,
#          systemd service, systemd timer, and man pages) and calls each with
#          the action (`install` or `uninstall`) and a debug flag. It captures
#          the status of each function and, if any function fails, it will stop
#          the process and exit with an error.
#
# @param $1 Action to perform: "install" to install the components,
#           "uninstall" to remove the components.
# @param $2 Optional debug flag to print debug information.
#
# @global install_group Array containing the list of functions to install/uninstall.
#
# @return None
#
# @example
# install_ap_popup "install"
# install_ap_popup "uninstall"
# -----------------------------------------------------------------------------
install_ap_popup() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    # Get action argument
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    # Define the group of functions to install/uninstall
    local install_group=(
        "check_network_manager"
        "check_hostapd_status"
        "handle_apt_packages"
        "download_files_in_directories"
        "install_controller_script"
        "install_application_script"
        "install_config_file"
        "create_systemd_service"
        "create_systemd_timer"
        "install_man_pages"
    )

    local skip_on_uninstall=(
        "check_network_manager"
        "check_hostapd_status"
        "handle_apt_packages"
        "download_files_in_directories"
    )

    # Start the script
    start_script "$action" "$debug"

    # Iterate over the group of functions and call them with the action and debug flag
    if [[ "$action" == "install" ]]; then
        local group_to_execute=()
        group_to_execute=("${install_group[@]}")

        for func in "${group_to_execute[@]}"; do
            debug_print "Running $func() with action: '$action'" "$debug"
            # Call the function with action and debug flag
            "$func" "$action" "$debug"
            local status=$?

            # Check if the function failed
            if [[ $status -ne 0 ]]; then
                logE "$func failed with status $status"
                debug_end "$debug"
                return 1
            else
                debug_print "$func succeeded." "$debug"
            fi
        done
    elif [[ "$action" == "uninstall" ]]; then
        # Reverse the array for uninstall
        local group_to_execute=()
        mapfile -t group_to_execute < <(printf "%s\n" "${install_group[@]}" | tac)

        for func in "${group_to_execute[@]}"; do
            # Skip functions listed in skip_on_uninstall
            local skip=false
            for skip_func in "${skip_on_uninstall[@]}"; do
                if [[ "$func" == "$skip_func" ]]; then
                    skip=true
                    break
                fi
            done

            if [[ "$skip" == true ]]; then
                debug_print "Skipping $func during uninstall." "$debug"
                continue
            fi

            # Call the function with action and debug flag
            "$func" "$action" "$debug"
            local status=$?

            # Check if the function failed
            if [[ $status -ne 0 ]]; then
                logE "$func failed with status $status"
                debug_end "$debug"
                return 1
            else
                debug_print "$func succeeded." "$debug"
            fi
        done
    else
        die 1 "Invalid action. Use 'install' or 'uninstall'."
    fi

    # File cleanup
    cleanup_files_in_directories "$debug"

    # Finish the script
    finish_script "$action" "$debug"

    debug_end "$debug"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Parses and separates an action (install/uninstall) and additional arguments.
# @details This function iterates over the provided arguments to identify the
#          action (either "install" or "uninstall") and separates any remaining
#          arguments into a filtered list.
#
# @param $@ The list of arguments to parse.
#
# @global None.
#
# @throws None.
#
# @return Outputs the action as the first part followed by a pipe (`|`) and the
#         remaining arguments (if any).
#
# @example
# parse_action_and_args install arg1 arg2
# # Output: install|arg1 arg2
#
# parse_action_and_args uninstall
# # Output: uninstall|
# -----------------------------------------------------------------------------
parse_action_and_args() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local action=""  # To capture the action ("install" or "uninstall").
    local args=()    # Array to hold the filtered (non-action) arguments.

    # Iterate over the argument list.
    for arg in "$@"; do
        case "$arg" in
            install|uninstall)
                action="$arg"  # Set the action if "install" or "uninstall".
                ;;
            *)
                args+=("$arg")  # Add non-matching arguments to the args array.
                ;;
        esac
    done

    # Output the action and the remaining arguments as separate values.
    printf "%s|" "$action"       # Action as the first part (e.g., "install|").
    printf "%q " "${args[@]}"    # Filtered arguments as the second part.
    printf "\n"                  # Ensure a newline at the end of output.

    debug_end "$debug"
}

############
### Main Functions
############

_main() {
    # Get debug flag
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    # Extract/remove action and reset remaining arguments
    local parse_result=""; parse_result=$(parse_action_and_args "$@")
    # Get action argument
    local action=""; action="${parse_result%%|*}"  # $action = before the '|'
    # Convert the string after '|' into an array
    local -a args=()  # Ensure `args` is an array
    IFS=' ' read -r -a args <<< "${parse_result#*|}"  # Split into an array
    # Reset the positional arguments to the parsed array
    set -- "${args[@]}"

    # Check and set up the environment
    enforce_sudo "$debug"              # Ensure proper privileges for script execution
    validate_depends "$debug"          # Ensure required dependencies are installed
    validate_sys_accs "$debug"         # Verify critical system files are accessible
    validate_env_vars "$debug"         # Check for required environment variables
    setup_log "$debug"                 # Setup logging environment
    check_bash "$debug"                # Ensure the script is executed in a Bash shell
    check_sh_ver "$debug"              # Verify the Bash version meets minimum requirements
    check_release "$debug"             # Check Raspbian OS version compatibility
    check_internet "$debug"            # Verify internet connectivity if required

    # Print/display the environment
    print_system "$debug"              # Log system information
    print_version "$debug"             # Log the script version

    # Run installer steps
    install_ap_popup "$action" "$debug"

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

# -----------------------------------------------------------------------------
# @brief Traps the `EXIT` signal to invoke the `egress` function.
# @details Ensures the `egress` function is called automatically when the shell
#          exits. This enables proper session cleanup and displays session
#          statistics to the user.
# -----------------------------------------------------------------------------
trap egress EXIT

debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
main "$@" "$debug"
debug_end "$debug"
exit $?
