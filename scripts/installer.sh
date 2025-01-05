#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'
set +o noclobber

############
### Global Script Declarations
############

# -----------------------------------------------------------------------------
# @var REQUIRE_SUDO
# @brief Indicates whether root privileges are required to run the script.
# @details This variable determines if the script requires execution with root
#          privileges. It defaults to `true`, meaning the script will enforce
#          that it is run with `sudo` or as a root user. This behavior can be
#          overridden by setting the `REQUIRE_SUDO` environment variable to `false`.
#
# @default true
#
# @example
# REQUIRE_SUDO=false ./template.sh  # Run the script without enforcing root privileges.
# -----------------------------------------------------------------------------
readonly REQUIRE_SUDO="${REQUIRE_SUDO:-true}"  # Default to "true" if not specified.

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
declare DRY_RUN="${DRY_RUN:-false}"  # Use existing value, or default to "false".

# -----------------------------------------------------------------------------
# @var IS_REPO
# @brief Indicates whether the script resides in a GitHub repository or subdirectory.
# @details This variable is initialized to `false` by default. During execution, it
#          is dynamically set to `true` if the script is detected to be within a
#          GitHub repository (i.e., if a `.git` directory exists in the directory
#          hierarchy of the script's location).
#
# @example
# if [[ "$IS_REPO" == "true" ]]; then
#     echo "This script resides within a GitHub repository."
# else
#     echo "This script is not located within a GitHub repository."
# fi
# -----------------------------------------------------------------------------
declare IS_REPO="${IS_REPO:-false}"  # Default to "false".

# -----------------------------------------------------------------------------
# @brief Project metadata constants used throughout the script.
# @details These variables provide metadata about the script, including ownership,
#          versioning, project details, and GitHub URLs. They are initialized with
#          default values or dynamically set during execution to reflect the project's
#          context.
#
# @vars
# - @var REPO_ORG The organization or owner of the repository (default: "lbussy").
# - @var REPO_NAME The name of the repository (default: "bash-template").
# - @var REPO_BRANCH The current Git branch name (default: "main").
# - @var GIT_TAG The current Git tag (default: "0.0.1").
# - @var SEM_VER The semantic version of the project (default: "0.0.1").
# - @var LOCAL_REPO_DIR The local source directory path (default: unset).
# - @var LOCAL_WWW_DIR The local web directory path (default: unset).
# - @var LOCAL_SCRIPTS_DIR The local scripts directory path (default: unset).
# - @var GIT_RAW The base URL for accessing raw GitHub content
#                (default: "https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME").
# - @var GIT_API The base URL for the GitHub API for this repository
#                (default: "https://api.github.com/repos/$REPO_ORG/$REPO_NAME").
# - @var GIT_CLONE The clone URL for the GitHub repository
#                (default: "https://api.github.com/repos/$REPO_ORG/$REPO_NAME").
#
# @example
# echo "Repository: $REPO_ORG/$REPO_NAME"
# echo "Branch: $REPO_BRANCH, Tag: $GIT_TAG, Version: $SEM_VER"
# echo "Source Directory: ${LOCAL_REPO_DIR:-Not Set}"
# echo "WWW Directory: ${LOCAL_WWW_DIR:-Not Set}"
# echo "Scripts Directory: ${LOCAL_SCRIPTS_DIR:-Not Set}"
# echo "Raw URL: $GIT_RAW"
# echo "API URL: $GIT_API"
# -----------------------------------------------------------------------------
declare REPO_ORG="${REPO_ORG:-lbussy}"
declare REPO_NAME="${REPO_NAME:-ap-popup}"
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
readonly GIT_DIRS=("man" "scripts" "conf")

# -----------------------------------------------------------------------------
# @var CONTROLLER_NAME
# @brief The final installed name of the main controller script (without extension).
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
# @brief        Configuration and installation details for the bash-based daemon.
# @details      This script sets variables and paths required for installing
#               and configuring the `appop` daemon and its supporting files.
#
#               Variables:
#               - APP_SOURCE: Name of the source script that will be installed as `appop`.
#               - AP_NAME: The final installed name of the main script (no extension).
#               - APP_PATH: Path to where the main script (appop) will be installed.
#               - SYSTEMD_PATH: Path to the systemd directory for services/timers.
#               - SERVICE_FILE: Name of the systemd service file to be created/managed.
#               - TIMER_FILE: Name of the systemd timer file to be created/managed.
#               - CONFIG_FILE: Path to the AP Pop-Up configuration file.
#               - LOG_PATH: Path to the directory where logs for the application will be stored.
# -----------------------------------------------------------------------------
readonly APP_SOURCE="appop.sh"
readonly APP_NAME="${APP_SOURCE%%.*}"
readonly APP_PATH="/usr/bin/$APP_NAME"
readonly SYSTEMD_PATH="/etc/systemd/system/"
readonly SERVICE_FILE="$SYSTEMD_PATH/$APP_NAME.service"
readonly TIMER_FILE="$SYSTEMD_PATH/$APP_NAME.timer"
readonly CONFIG_FILE="/etc/$APP_NAME.conf"
readonly APP_LOG_PATH="/var/log/$APP_NAME"

# -----------------------------------------------------------------------------
# @brief Determines and assigns the home directory and real user based on sudo
#        privileges and environment variables.
#
# @details This section of the script checks whether the `REQUIRE_SUDO` flag
#          is set to true and whether the `SUDO_USER` environment variable is
#          available. It sets the `USER_HOME` variable based on the following
#          logic:
#          - If `REQUIRE_SUDO` is true and `SUDO_USER` is not set, `USER_HOME`
#            is set to empty values.
#          - If `SUDO_USER` is set, `USER_HOME` is set to the home directory of the
#            sudo user.
#          - If `SUDO_USER` is not set, it falls back to using the current user's
#            home directory (`HOME`).
#
# @variables
# @var USER_HOME The home directory of the user. It is set to the value of `$HOME`
#                or the sudo user's home directory, depending on the logic.
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
    USER_HOME=$(eval echo "~$SUDO_USER")
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
# @details When `TERSE` is set to `true`, log messages are minimal and optimized
#          for automated environments where concise output is preferred. When
#          set to `false`, log messages are verbose, providing detailed
#          information suitable for debugging or manual intervention.
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
#          the `MIN_BASH_VERSION` environment variable before running the script.
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
#     echo "This script requires OS version $MIN_OS or higher."
#     exit 1
# fi
# -----------------------------------------------------------------------------
readonly MIN_OS="11"

# -----------------------------------------------------------------------------
# @var MAX_OS
# @brief Specifies the maximum supported OS version.
# @details Defines the highest OS version that the script supports. If the script
#          is executed on a system with an OS version higher than this value,
#          it may not function as intended. Set this to `-1` to indicate no upper
#          limit on supported OS versions.
#
# @default 15
#
# @example
# if [[ "$CURRENT_OS_VERSION" -gt "$MAX_OS" && "$MAX_OS" -ne -1 ]]; then
#     echo "This script supports OS versions up to $MAX_OS."
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
#          availability at runtime. If a required command is missing, the script
#          may fail or display an error message.
#
#          Best practices:
#          - Ensure all required commands are included.
#          - Use a dependency-checking function to verify their presence early in the script.
#
# @default
# A predefined set of common system utilities:
# - `"awk"`, `"grep"`, `"tput"`, `"cut"`, `"tr"`, `"getconf"`, `"cat"`, `"sed"`,
#   `"basename"`, `"getent"`, `"date"`, `"printf"`, `"whoami"`, `"touch"`,
#   `"dpkg"`, `"dpkg-reconfigure"`, `"curl"`, `"wget"`, `"realpath"`.
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
#         echo "Error: Required environment variable '$var' is not set."
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
declare -ar ENV_VARS_BASE=(
    "HOME"       # Home directory of the current user
    "COLUMNS"    # Terminal width for formatting
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
#          - `SUDO_USER`: Identifies the user who invoked the script using `sudo`.
#
# @note Ensure `ENV_VARS_BASE` is properly defined before constructing `ENV_VARS`.
#
# @example
# for var in "${ENV_VARS[@]}"; do
#     if [[ -z "${!var}" ]]; then
#         echo "Error: Required environment variable '$var' is not set."
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
    "/etc/os-release"    # OS identification file
)
readonly SYSTEM_READS

# -----------------------------------------------------------------------------
# @var APT_PACKAGES
# @type array
# @brief List of required APT packages.
# @details Defines the APT packages that the script depends on for its execution.
#          These packages should be available in the system's default package
#          repository. The script will check for their presence and attempt to
#          install any missing packages as needed.
#
#          Packages included:
#          - `jq`: JSON parsing utility.
#
# @example
# for pkg in "${APT_PACKAGES[@]}"; do
#     if ! dpkg -l "$pkg" &>/dev/null; then
#         echo "Error: Required package '$pkg' is not installed."
#         exit 1
#     fi
# done
# -----------------------------------------------------------------------------
readonly APT_PACKAGES=(
    "jq"   # JSON parsing utility
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
readonly WARN_STACK_TRACE="${WARN_STACK_TRACE:-false}"  # Default to false if not set.

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
    local level="${1:-INFO}"  # Default to INFO if $1 is not provided
    local message=""

    # Check if $1 is a valid level, otherwise treat it as the message
    case "$level" in
        DEBUG|INFO|WARN|WARNING|ERROR|CRIT|CRITICAL)
            shift
            ;;
        *)
            # If $1 is not valid, treat it as the beginning of the message
            message="$level"
            level="INFO"
            shift
            ;;
    esac

    # Concatenate all remaining arguments into $message
    for arg in "$@"; do
        message+="$arg "
    done
    # Trim trailing space
    message="${message% }"

    # Block width and character for header/footer
    local width=60
    local char="-"

    # Define functions to skip
    local skip_functions=("die" "warn" "stack_trace")
    local encountered_main=0 # Track the first occurrence of main()

    # Get the current function name in title case
    local raw_function_name="${FUNCNAME[0]}"
    local function_name
    function_name="$(printf "%s" "$raw_function_name" | sed -E 's/_/ /g; s/\b(.)/\U\1/g; s/(\b[A-Za-z])([A-Za-z]*)/\1\L\2/g')"

    # -------------------------------------------------------------------------
    # @brief Determines if a function should be skipped in the stack trace.
    # @details Skips functions specified in the `skip_functions` list and
    #          ignores duplicate `main()` entries.
    #
    # @param $1 Function name to evaluate.
    #
    # @return 0 if the function should be skipped, 1 otherwise.
    #
    # @example
    # should_skip "main" && continue
    # -------------------------------------------------------------------------
    should_skip() {
        local func="$1"
        for skip in "${skip_functions[@]}"; do
            if [[ "$func" == "$skip" ]]; then
                return 0 # Skip this function
            fi
        done
        # Skip duplicate main()
        if [[ "$func" == "main" ]]; then
            if (( encountered_main > 0 )); then
                return 0 # Skip subsequent occurrences of main
            fi
            ((encountered_main++))
        fi
        return 1 # Do not skip
    }

    # Iterate through the stack to build the displayed stack
    local displayed_stack=()
    local longest_length=0  # Track the longest function name length

    # Handle a piped script calling stack_trace from main
    if [[ -p /dev/stdin && ${#FUNCNAME[@]} == 1 ]]; then
        displayed_stack+=("$(printf "%s|%s" "main()" "${BASH_LINENO[0]}")")
    fi

    # Handle the rest of the stack
    for ((i = 1; i < ${#FUNCNAME[@]}; i++)); do
        local func="${FUNCNAME[i]}"
        local line="${BASH_LINENO[i - 1]}"
        local current_length=${#func}

        # Skip ignored functions
        if should_skip "$func"; then
            continue
        elif (( current_length > longest_length )); then
            longest_length=$current_length
        fi

        # Prepend the formatted stack entry to reverse the order
        displayed_stack=("$(printf "%s|%s" \
            "$func()" \
            "$line")" \
            "${displayed_stack[@]}")
    done

    # -------------------------------------------------------------------------
    # @brief Provides a fallback for `tput` commands when errors occur.
    # @details Returns an empty string if `tput` fails, ensuring no errors
    #          propagate during color or formatting setup.
    #
    # @param $@ Command-line arguments passed directly to `tput`.
    #
    # @return Output of `tput` if successful, or an empty string if it fails.
    #
    # @example
    # local bold=$(safe_tput bold)
    # -------------------------------------------------------------------------
    safe_tput() { tput "$@" 2>/dev/null || printf ""; }

    # General text attributes
    local reset bold
    reset=$(safe_tput sgr0)
    bold=$(safe_tput bold)

    # Foreground colors
    local fgred fggrn fgylw fgylw fgblu fgmag fgmag fgcyn fggld
    fgred=$(safe_tput setaf 1)  # Red text
    fggrn=$(safe_tput setaf 2)  # Green text
    fgylw=$(safe_tput setaf 3)  # Yellow text
    fgblu=$(safe_tput setaf 4)  # Blue text
    fgmag=$(safe_tput setaf 5)  # Magenta text
    fgcyn=$(safe_tput setaf 6)  # Cyan text
    fggld=$(safe_tput setaf 220)  # Gold text
    [[ -z "$fggld" ]] && fggld="$fgylw"  # Fallback to yellow

    # Determine color and label based on the log level
    local color label
    case "$level" in
        DEBUG) color=${fgcyn}; label="[DEBUG]";;
        INFO) color=${fggrn}; label="[INFO ]";;
        WARN|WARNING) color=${fggld}; label="[WARN ]";;
        ERROR) color=${fgmag}; label="[ERROR]";;
        CRIT|CRITICAL) color=${fgred}; label="[CRIT ]";;
    esac

    # Create header
    local dash_count=$(( (width - ${#function_name} - 2) / 2 ))
    local header_l header_r
    header_l="$(printf '%*s' "$dash_count" '' | tr ' ' "$char")"
    header_r="$header_l"
    [[ $(( (width - ${#function_name}) % 2 )) -eq 1 ]] && header_r="${header_r}${char}"
    local header
    header=$(printf "%b%s%b %b%b%s%b %b%s%b" \
        "${color}" \
        "${header_l}" \
        "${reset}" \
        "${color}" \
        "${bold}" \
        "${function_name}" \
        "${reset}" \
        "${color}" \
        "${header_r}" \
        "${reset}")

    # Create footer
    local footer
    footer="$(printf '%*s' "$width" "" | tr ' ' "$char")"
    [[ -n "$color" ]] && footer="${color}${footer}${reset}"

    # Print header
    printf "%s\n" "$header"

    # Print the message, if provided
    if [[ -n "$message" ]]; then
        # Extract the first word and preserve the rest
        local first="${message%% *}"    # Extract up to the first space
        local remainder="${message#* }" # Remove the first word and the space

        # Format the message
        message="$(printf "%b%b%s%b %b%s%b" \
            "${bold}" "${color}" "$first" \
            "${reset}" "${color}" "$remainder" \
            "${reset}")"

        # Print the formatted message
        printf "%b\n" "$message"
    fi

    # Calculate indent for proper alignment
    local indent
    indent=$(( (width / 2) - ((longest_length + 28) / 2) ))

    # Print the displayed stack in reverse order
    for ((i = ${#displayed_stack[@]} - 1, idx = 0; i >= 0; i--, idx++)); do
        IFS='|' read -r func line <<< "${displayed_stack[i]}"
        printf "%b%*s [%d] Function: %-*s Line: %4s%b\n" \
            "${color}" \
            "$indent" \
            ">" \
            "$idx" \
            "$((longest_length + 2))" \
            "$func" \
            "$line" \
            "${reset}"
    done

    # Print footer
    printf "%b%s%b\n\n" "${color}" "$footer" "${reset}"
}

# -----------------------------------------------------------------------------
# @brief Logs a warning message with optional additional details and
#        formatting.
# @details This function outputs a formatted warning message with color and
#          positional information (script name, function, and line number).
#          If additional details are provided, they are included in the
#          message. The function also supports including an error code and
#          handling stack traces if enabled.
#
# @param $1 [optional] The primary message to log. Defaults to "A warning was
#                      raised on this line" if not provided.
# @param $@ [optional] Additional details to include in the warning message.
#
# @return None.
#
# @example
# warn "File not found" "Please check the file path."
# -----------------------------------------------------------------------------
warn() {
    # Initialize variables
    local script="${THIS_SCRIPT:-unknown}"       # This script's name
    local func_name="${FUNCNAME[1]:-main}"       # Calling function
    local caller_line=${BASH_LINENO[0]:-0}       # Calling line
    local error_code=""                          # Error code, default blank
    local message=""                             # Primary message
    local details=""                             # Additional details
    local width=${COLUMNS:-80}                   # Max console width
    local delimiter="␞"                          # Delimiter for wrapped parts

    # -------------------------------------------------------------------------
    # @brief Provides a fallback for `tput` commands when errors occur.
    # @details Returns an empty string if `tput` fails, ensuring no errors
    #          propagate during color or formatting setup.
    #
    # @param $@ Command-line arguments passed directly to `tput`.
    #
    # @return Output of `tput` if successful, or an empty string if it fails.
    #
    # @example
    #     local bold=$(safe_tput bold)
    # -------------------------------------------------------------------------
    safe_tput() { tput "$@" 2>/dev/null || printf ""; }

    # General text attributes
    local reset bold
    reset=$(safe_tput sgr0)
    bold=$(safe_tput bold)

    # Foreground colors
    local fgred fggrn fgylw fgylw fgblu fgmag fgmag fgcyn fggld
    fgred=$(safe_tput setaf 1)  # Red text
    fggrn=$(safe_tput setaf 2)  # Green text
    fgylw=$(safe_tput setaf 3)  # Yellow text
    fgblu=$(safe_tput setaf 4)  # Blue text
    fgmag=$(safe_tput setaf 5)  # Magenta text
    fgcyn=$(safe_tput setaf 6)  # Cyan text
    fggld=$(safe_tput setaf 220)  # Gold text
    [[ -z "$fggld" ]] && fggld="$fgylw"  # Fallback to yellow

    # -------------------------------------------------------------------------
    # @brief Creates a formatted prefix for logging messages.
    # @details Combines color, labels, and positional information into a
    #          prefix.
    #
    # @param $1 [required] Color for the prefix.
    # @param $2 [required] Label for the message (e.g., "[WARN ]").
    #
    # @return [string] Formatted prefix as a string.
    #
    # @example
    # local warn_prefix=$(format_prefix "$fggld" "[WARN ]")
    # -------------------------------------------------------------------------
    format_prefix() {
        local color=$1
        local label=$2
        printf "%b%s%b %b[%s:%s:%s]%b " \
            "${bold}${color}" "$label" "${reset}" \
            "${bold}" "$script" "$func_name" "$caller_line" "${reset}"
    }

    # Generate prefixes
    local warn_prefix extd_prefix dets_prefix
    warn_prefix=$(format_prefix "$fggld" "[WARN ]")
    extd_prefix=$(format_prefix "$fgcyn" "[EXTND]")
    dets_prefix=$(format_prefix "$fgblu" "[DETLS]")

    # Strip ANSI escape sequences for length calculation
    local plain_warn_prefix prefix_length adjusted_width
    plain_warn_prefix=$(echo -e "$warn_prefix" | sed 's/\x1b\[[0-9;]*m//g')
    prefix_length=${#plain_warn_prefix}
    adjusted_width=$((width - prefix_length))

    # Parse error code if the first parameter is numeric
    if [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
        error_code=$((10#$1))  # Convert to numeric
        shift
    fi

    # Process primary message
    message=$(add_period "${1:-A warning was raised on this line}")
    if [[ -n "$error_code" ]]; then
        message=$(printf "%s Code: (%d)" "$message" "$error_code")
    fi
    shift

    # Process additional details
    details="${1:-}"
    shift
    for arg in "$@"; do
        details+=" $arg"
    done
    if [[ -n $details ]]; then
        details=$(add_period "$details")
    fi

    # Call wrap_and_combine_messages
    local result
    result=$(wrap_messages "$adjusted_width" "$message" "$details")

    # Parse wrapped parts
    # shellcheck disable=SC2295
    local primary="${result%%${delimiter}*}"
    # shellcheck disable=SC2295
    result="${result#*${delimiter}}"
    # shellcheck disable=SC2295
    local overflow="${result%%${delimiter}*}"
    # shellcheck disable=SC2295
    local secondary="${result#*${delimiter}}"

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

    # Include stack trace for warnings if enabled
    if [[ "${WARN_STACK_TRACE:-false}" == "true" ]]; then
        stack_trace "WARNING" "$message"
    fi
}

# -----------------------------------------------------------------------------
# @brief Terminates the script with a critical error message and details.
# @details This function prints a critical error message along with optional
#          details, formats them with color and indentation, and includes a
#          stack trace for debugging. It then exits with the specified error
#          code.
#
# @param $1 [optional] Numeric error code. Defaults to 1 if not provided.
# @param $2 [optional] Primary error message. Defaults to "Critical error"
#                      if not provided.
# @param $@ [optional] Additional details or context for the error.
#
# @global THIS_SCRIPT The script's name, used for logging.
# @global COLUMNS Console width, used to calculate message formatting.
#
# @throws Exits the script with the provided error code or the default
#         value (1).
#
# @return None. Outputs formatted error messages and terminates the script.
#
# @example
# die 127 "File not found" "The specified file is missing or inaccessible."
# -----------------------------------------------------------------------------
die() {
    # Initialize variables
    local script="${THIS_SCRIPT:-unknown}"       # This script's name
    local func_name="${FUNCNAME[1]:-main}"       # Calling function
    local caller_line=${BASH_LINENO[0]:-0}       # Calling line
    local error_code=""                          # Error code, default blank
    local message=""                             # Primary message
    local details=""                             # Additional details
    local width=${COLUMNS:-80}                   # Max console width
    local delimiter="␞"                          # Delimiter for wrapped parts

    # -------------------------------------------------------------------------
    # @brief Provides a fallback for `tput` commands when errors occur.
    # @details Returns an empty string if `tput` fails, ensuring no errors
    #          propagate during color or formatting setup.
    #
    # @param $@ Command-line arguments passed directly to `tput`.
    #
    # @return Output of `tput` if successful, or an empty string if it fails.
    #
    # @example
    # local bold=$(safe_tput bold)
    # -------------------------------------------------------------------------
    safe_tput() {
        tput "$@" 2>/dev/null || printf ""
    }

    # General text attributes
    local reset bold
    reset=$(safe_tput sgr0)
    bold=$(safe_tput bold)

    # Foreground colors
    local fgred fgblu fgcyn
    fgred=$(safe_tput setaf 1)  # Red text
    fgblu=$(safe_tput setaf 4)  # Blue text
    fgcyn=$(safe_tput setaf 6)  # Cyan text

    # -------------------------------------------------------------------------
    # @brief Formats a log message prefix with a specified label and color.
    # @details Constructs a formatted prefix string that includes the label,
    #          the script name, the calling function name, and the line number.
    #
    # @param $1 [required] Color for the label (e.g., `$fgred` for red text).
    # @param $2 [required] Label for the prefix (e.g., "[CRIT ]").
    #
    # @return A formatted prefix string with color and details.
    #
    # @example
    # local crit_prefix=$(format_prefix "$fgred" "[CRIT ]")
    # -------------------------------------------------------------------------
    format_prefix() {
        local color=$1
        local label=$2
        printf "%b%s%b %b[%s:%s:%s]%b " \
            "${bold}${color}" \
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
    local plain_crit_prefix
    plain_crit_prefix=$(echo -e "$crit_prefix" | sed 's/\x1b\[[0-9;]*m//g')
    local prefix_length=${#plain_crit_prefix}
    local adjusted_width=$((width - prefix_length))

    # Parse error code if the first parameter is numeric, default to 1
    if [[ -n "${1:-}" && "$1" =~ ^[0-9]+$ ]]; then
        error_code=$((10#$1))  # Convert to numeric
        shift
    else
        error_code=1  # Default to 1 if no numeric value is provided
    fi

    # Process primary message
    message=$(add_period "${1:-Critical error}")
    if [[ -n "$error_code" ]]; then
        message=$(printf "%s Code: (%d)" "$message" "$error_code")
    fi
    shift

    # Process additional details
    details="${1:-}"
    shift
    for arg in "$@"; do
        details+=" $arg"
    done
    if [[ -n $details ]]; then
        details=$(add_period "$details")
    fi

    # Call wrap_and_combine_messages
    local result
    result=$(wrap_messages "$adjusted_width" "$message" "$details")

    # Parse wrapped parts
    # shellcheck disable=SC2295
    local primary="${result%%${delimiter}*}"
    # shellcheck disable=SC2295
    result="${result#*${delimiter}}"
    # shellcheck disable=SC2295
    local overflow="${result%%${delimiter}*}"
    # shellcheck disable=SC2295
    local secondary="${result#*${delimiter}}"

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

    # Include stack trace for warnings if enabled
    stack_trace "CRITICAL" "$message"
    exit "$error_code"
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
    local line_width=$1 # Maximum width of each line
    local primary=$2    # Primary message string
    local secondary=$3  # Secondary message string
    local delimiter="␞" # ASCII delimiter (code 30) for separating messages

    # -------------------------------------------------------------------------
    # @brief Wraps a message into lines with ellipses for overflow or
    #        continuation.
    # @details Splits the message into lines, appending an ellipsis for
    #          overflowed lines and prepending it for continuation lines.
    #
    # @param $1 [required] The message string to wrap.
    # @param $2 [required] Maximum width of each line (numeric).
    #
    # @global None.
    #
    # @throws None.
    #
    # @return A single string with wrapped lines, ellipses added as necessary.
    #
    # @example
    # wrapped=$(wrap_message "This is a long message" 50)
    # echo "$wrapped"
    # -------------------------------------------------------------------------
    wrap_message() {
        local message=$1        # Input message to wrap
        local width=$2          # Maximum width of each line
        local result=()         # Array to store wrapped lines
        local adjusted_width=$((width - 2))  # Adjust width for ellipses

        # Process message line-by-line
        while IFS= read -r line; do
            result+=("$line")
        done <<< "$(printf "%s\n" "$message" | fold -s -w "$adjusted_width")"

        # Add ellipses to wrapped lines
        for ((i = 0; i < ${#result[@]}; i++)); do
            if ((i == 0)); then
                # Append ellipsis to the first line
                result[i]="${result[i]% }…"
            elif ((i == ${#result[@]} - 1)); then
                # Prepend ellipsis to the last line
                result[i]="…${result[i]}"
            else
                # Add ellipses to both ends of middle lines
                result[i]="…${result[i]% }…"
            fi
        done

        # Return the wrapped lines as a single string
        printf "%s\n" "${result[@]}"
    }

    # Process the primary message
    local overflow=""          # Stores overflow lines from the primary message
    if [[ ${#primary} -gt $line_width ]]; then
        local wrapped_primary  # Temporarily stores the wrapped primary message
        wrapped_primary=$(wrap_message "$primary" "$line_width")
        overflow=$(printf "%s\n" "$wrapped_primary" | tail -n +2)
        primary=$(printf "%s\n" "$wrapped_primary" | head -n 1)
    fi

    # Process the secondary message
    if [[ ${#secondary} -gt $line_width ]]; then
        secondary=$(wrap_message "$secondary" "$line_width")
    fi

    # Return the combined messages
    printf "%s%b%s%b%s" \
        "$primary" \
        "$delimiter" \
        "$overflow" \
        "$delimiter" \
        "$secondary"
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
# @details This function processes the input string and removes a trailing period
#          if it exists. If the input string is empty, the function logs an error
#          and returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string without a trailing period if one was present.
# @retval 1 If the input string is empty.
#
# @example
# remove_period "example."  # Outputs "example"
# remove_period "example"   # Outputs "example"
# remove_period ""          # Logs an error and returns an error code.
# -----------------------------------------------------------------------------
# shellcheck disable=SC2329
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
# shellcheck disable=2329
print_system() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    # Declare local variables
    local system_name

    # Extract system name and version from /etc/os-release
    system_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d '=' -f2 | tr -d '"')

    # Debug: Log extracted system name
    debug_print "Extracted system name: ${system_name:-<empty>}\n" "$debug"

    # Check if system_name is empty and log accordingly
    if [[ -z "${system_name:-}" ]]; then
        warn "System: Unknown (could not extract system information)."  # Log warning if system information is unavailable
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
        logI "Running $(repo_to_title_case "$REPO_NAME")'s '$THIS_SCRIPT', version $SEM_VER" # Log the script name and version
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
# @details Iterates through the dependencies listed in the global array `DEPENDENCIES`,
#          checking if each one is installed. Logs missing dependencies and exits
#          the script with an error code if any are missing.
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
# @details Verifies that each file listed in the `SYSTEM_READS` array exists and is readable.
#          Logs an error for any missing or unreadable files and exits the script if any issues are found.
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
# @details Checks if the environment variables specified in the `ENV_VARS` array
#          are set. Logs any missing variables and exits the script if any are missing.
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
# @details Ensures the script is executed with Bash, as it may use Bash-specific features.
#          If the "debug" argument is passed, detailed logging will be displayed for each check.
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
# @details Compares the current Bash version against a required version specified
#          in the global variable `MIN_BASH_VERSION`. If `MIN_BASH_VERSION` is "none",
#          the check is skipped. Outputs debug information if enabled.
#
# @param $1 [Optional] "debug" to enable verbose output for this check.
#
# @global MIN_BASH_VERSION Minimum required Bash version (e.g., "4.0") or "none".
# @global BASH_VERSINFO Array containing the major and minor versions of the running Bash.
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
# @details This function ensures that the Raspbian version is within the supported
#          range and logs an error if the compatibility check fails.
#
# @param $1 [Optional] "debug" to enable verbose output for this check.
#
# @global MIN_OS Minimum supported OS version.
# @global MAX_OS Maximum supported OS version (-1 indicates no upper limit).
# @global log_message Function for logging messages.
# @global die Function to handle critical errors and terminate the script.
#
# @return None Exits the script with an error code if the OS version is incompatible.
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
# @brief Comprehensive internet and proxy connectivity check.
# @details Combines proxy validation and direct internet connectivity tests;
#          Validates proxy configuration first, then tests connectivity with
#          and without proxies. Outputs debug information if enabled.
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
# @brief Log a message with optional details to the console and/or file.
# @details Handles combined logic for logging to console and/or file, supporting
#          optional details. If details are provided, they are logged with an
#          "[EXTENDED]" tag.
#
# @param $1 Timestamp of the log entry.
# @param $2 Log level (e.g., DEBUG, INFO, WARN, ERROR).
# @param $3 Color code for the log level.
# @param $4 Line number where the log entry originated.
# @param $5 The main log message.
# @param $6 [Optional] Additional details for the log entry.
#
# @global LOG_OUTPUT Specifies where to output logs ("console", "file", or "both").
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
# @details Logs messages to both the console and/or a log file, depending on the
#          configured log output. The function uses the `LOG_PROPERTIES` associative
#          array to determine the log level, color, and severity. If the "debug"
#          argument is provided, debug logging is enabled for additional details.
#
# @param $1 Log level (e.g., DEBUG, INFO, ERROR). The log level controls the message severity.
# @param $2 Main log message to log.
# @param $3 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global LOG_LEVEL The current logging verbosity level.
# @global LOG_PROPERTIES Associative array defining log level properties, such as severity and color.
# @global LOG_FILE Path to the log file (if configured).
# @global USE_CONSOLE Boolean flag to enable or disable console output.
# @global LOG_OUTPUT Specifies where to log messages ("file", "console", "both").
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

    local level="UNSET"          # Default to "UNSET" if no level is provided
    local message="<no message>" # Default to "<no message>" if no message is provided

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
# log_message_with_severity "ERROR" "This is an error message" "Additional details" "debug"
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
    local severity="$1"   # Level is always passed as the first argument to log_message_with_severity
    local message=""
    local extended_message=""

    # Process arguments
    if [[ -n "$2" ]]; then
        message="$2"
    else
        warn "Message is required."
            debug_end "$debug"
        exit 1
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
# @details These functions provide shorthand access to `log_message_with_severity()`
#          with a predefined severity level. They standardize the logging process
#          by ensuring consistent severity labels and argument handling.
#
# @param $1 [string] The primary log message. Must not be empty.
# @param $2 [optional, string] The extended message for additional details (optional), sent to logX.
# @param $3 [optional, string] The debug flag. If set to "debug", enables debug-level logging.
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
# shellcheck disable=2329
logD() { log_message_with_severity "DEBUG" "$1" "${2:-}" "${3:-}"; }
# shellcheck disable=2329
logI() { log_message_with_severity "INFO" "$1" "${2:-}" "${3:-}"; }
# shellcheck disable=2329
logW() { log_message_with_severity "WARNING" "$1" "${2:-}" "${3:-}"; }
# shellcheck disable=2329
logE() { log_message_with_severity "ERROR" "$1" "${2:-}" "${3:-}"; }
# shellcheck disable=2329
logC() { log_message_with_severity "CRITICAL" "$1" "${2:-}" "${3:-}"; }
# shellcheck disable=2329
logX() { log_message_with_severity "EXTENDED" "$1" "${2:-}" "${3:-}"; }

# -----------------------------------------------------------------------------
# @brief Ensure the log file exists and is writable, with fallback to `/tmp` if necessary.
# @details This function validates the specified log file's directory to ensure it exists and is writable.
#          If the directory is invalid or inaccessible, it attempts to create it. If all else fails,
#          the log file is redirected to `/tmp`. A warning message is logged if fallback is used.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global LOG_FILE Path to the log file (modifiable to fallback location).
# @global THIS_SCRIPT The name of the script (used to derive fallback log file name).
#
# @return None
#
# @example
# init_log "debug"  # Ensures log file is created and available for writing with debug output.
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
# @details This function uses `tput` to retrieve a terminal color code or attribute
#          (e.g., sgr0 for reset, bold for bold text). If the attribute is unsupported
#          by the terminal, it returns an empty string.
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
# @details This function sets up variables for foreground colors, background colors,
#          and text formatting styles. It checks terminal capabilities and provides
#          fallback values for unsupported or non-interactive environments.
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
# @brief Validate the logging configuration, including LOG_LEVEL.
# @details This function checks whether the current LOG_LEVEL is valid. If LOG_LEVEL is not
#          defined in the `LOG_PROPERTIES` associative array, it defaults to "INFO" and
#          displays a warning message.
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
# This function initializes terminal colors, configures the logging environment,
# defines log properties, and validates both the log level and properties.
# It must be called before any logging-related functions.
#
# @details
# - Initializes terminal colors using `init_colors`.
# - Sets up the log file and directory using `init_log`.
# - Defines global log properties (`LOG_PROPERTIES`), including severity levels, colors, and labels.
# - Validates the configured log level and ensures all required log properties are defined.
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
# shellcheck disable=SC2329
download_file() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local file_path="$1"
    local dest_dir="$2"

    mkdir -p "$dest_dir"

    local file_name
    file_name=$(basename "$file_path")
    file_name="${file_name//\'/}"

    logI "Downloading from: $GIT_RAW/$REPO_BRANCH/$file_path to $dest_dir/$file_name"

    wget -q -O "$dest_dir/$file_name" "$GIT_RAW/$REPO_BRANCH/$file_path" || {
        warn "Failed to download file: $file_path to $dest_dir/$file_name"
        return 1
    }

    local dest_file="$dest_dir/$file_name"
    mv "$dest_file" "${dest_file//\'/}"
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
# @throws Prints an error message and exits if the branch SHA cannot be fetched.
#
# @return Outputs the JSON representation of the repository tree.
#
# @example
# fetch_tree
# -----------------------------------------------------------------------------
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
# shellcheck disable=SC2329
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
# @details This function manages the execution of a shell command, handling
#          the display of status messages. It supports dry-run mode, where
#          the command is simulated without execution. The function prints
#          success or failure messages and handles the removal of the "Running"
#          line once the command finishes.
#
# @param exec_name The name of the command or task being executed.
# @param exec_process The command string to be executed.
# @param debug Optional flag to enable debug messages. Set to "debug" to enable.
#
# @return Returns 0 if the command was successful, non-zero otherwise.
#
# @note The function supports dry-run mode, controlled by the DRY_RUN variable.
#       When DRY_RUN is true, the command is only simulated without actual execution.
#
# @example
# exec_command "Test Command" "echo Hello World" "debug"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2329
exec_command() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"

    local exec_name="$1"
    # shellcheck disable=SC2154 
    local exec_name=${remove_period $exec_name}
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
# shellcheck disable=SC2329
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
    message=$(remove_period "$message")
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
# shellcheck disable=SC2329
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
        logI "$(repo_to_title_case "${REPO_NAME:-Unknown}") $action_message beginning."
        debug_print "Skipping interactive message due to terse mode." "$debug"
        debug_end "$debug"
        return 0
    fi

    # Prompt user for input
    printf "\nStarting %s for: %s.\n" "$action_message" "$(repo_to_title_case "${REPO_NAME:-Unknown}")"
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
# shellcheck disable=SC2329
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
# shellcheck disable=SC2329
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
# shellcheck disable=SC2329
handle_apt_packages() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

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
    if ! exec_command "Update local package index" "sudo apt-get update -y" "$debug"; then
        warn "Failed to update package list."
        ((error_count++))
    fi
    if ! exec_command "Fixing broken or incomplete package installations" "sudo apt-get install -f -y" "$debug"; then
        warn "Failed to fix broken installs."
        ((error_count++))
    fi

    # Install, upgrade, or remove each package in the list based on the action
    for package in "${APT_PACKAGES[@]}"; do
        if [[ "$action" == "install" ]]; then
            if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
                if ! exec_command "Upgrade $package" "sudo apt-get install --only-upgrade -y $package" "$debug"; then
                    warn "Failed to upgrade package: $package."
                    ((error_count++))
                fi
            else
                if ! exec_command "Install $package" "sudo apt-get install -y $package" "$debug"; then
                    warn "Failed to install package: $package."
                    ((error_count++))
                fi
            fi
        elif [[ "$action" == "uninstall" ]]; then
            if ! exec_command "Remove $package" "sudo apt-get remove -y $package" "$debug"; then
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
# @brief Downloads files from specified directories in a repository.
# @details This function retrieves a repository tree, identifies files within
#          specified directories, and downloads them to the local system.
#
# @param $1 The target directory to update. "install" to download files, "uninstall" to skip.
#
# @global USER_HOME The home directory of the user, used as the base for storing files.
# @global GIT_DIRS Array of directories in the repository to process.
#
# @throws Exits the script with an error if the repository tree cannot be fetched.
#
# @return Downloads files to the specified directory structure under $USER_HOME/apppop.
#
# @example
# download_files_in_directories "install"
# download_files_in_directories "uninstall"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2329
download_files_in_directories() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    # Return immediately if action is "uninstall"
    if [[ "$action" == "uninstall" ]]; then
        debug_end "$debug"
        return 0
    fi

    local dest_root="$USER_HOME/$REPO_NAME"
    logI "Fetching repository tree."
    local tree
    tree=$(fetch_tree "$debug")

    if [[ $(printf "%s" "$tree" | jq '.tree | length') -eq 0 ]]; then
        die 1 "Failed to fetch repository tree. Check repository details or ensure it is public."
    fi

    for dir in "${GIT_DIRS[@]}"; do
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

    debug_end "$debug"
    logI "Files saved in: $dest_root"
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the specified controller script.
# @details This function installs the controller script by copying it from
#          the source directory to the specified path when "install" is
#          passed as an argument. It also ensures the script has the correct
#          ownership (root:root) and executable permissions. If "remove" is
#          passed, the function will remove the controller script and reset
#          the permissions and ownership.
#
# @param $1 Action to perform: "install" to install the controller, "remove"
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
# install_controller_script "remove"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2329
install_controller_script() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    if [[ "$action" == "install" ]]; then
        logI "Installing '$CONTROLLER_NAME'."

        # Install the controller script
        exec_command "Install controller" "cp -f \"$LOCAL_REPO_DIR/scripts/$CONTROLLER_SOURCE\" \"$CONTROLLER_PATH\"" "$debug" || { logE "Failed to install controller."; debug_end "$debug"; return 1; }

        # Change ownership on the controller
        exec_command "Change ownership on controller" "chown root:root \"$CONTROLLER_PATH\"" "$debug" || { logE "Failed to change ownership on controller."; debug_end "$debug"; return 1; }

        # Change permissions on the controller to make it executable
        exec_command "Change permissions on controller" "chmod +x \"$CONTROLLER_PATH\"" "$debug" || { logE "Failed to change permissions on controller."; debug_end "$debug"; return 1; }

    elif [[ "$action" == "remove" ]]; then
        logI "Removing '$CONTROLLER_NAME'."

        # Remove the controller script
        exec_command "Remove controller" "rm -f \"$CONTROLLER_PATH\"" "$debug" || { logE "Failed to remove controller."; debug_end "$debug"; return 1; }
    else
        die 1 "Invalid action. Use 'install' or 'remove'."
    fi

    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the specified application script.
# @details This function installs the application script by copying it from
#          the source directory to the specified target path when "install" is
#          passed as an argument. It also ensures the script has the correct
#          ownership (root:root) and executable permissions. If "remove" is
#          passed, the function will remove the application script and reset
#          the permissions and ownership.
#
# @param $1 Action to perform: "install" to install the application, "remove"
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
# install_application_script "remove"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2329
install_application_script() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    if [[ "$action" == "install" ]]; then
        logI "Installing '$APP_NAME'."

        # Install the application script
        exec_command "Install application" "cp -f \"$LOCAL_REPO_DIR/scripts/$APP_SOURCE\" \"$APP_PATH\"" "$debug" || { logE "Failed to install application."; debug_end "$debug"; return 1; }

        # Change ownership on the application script
        exec_command "Change ownership on application" "chown root:root \"$APP_PATH\"" "$debug" || { logE "Failed to change ownership on application."; debug_end "$debug"; return 1; }

        # Change permissions on the application script to make it executable
        exec_command "Change permissions on application" "chmod +x \"$APP_PATH\"" "$debug" || { logE "Failed to change permissions on application."; debug_end "$debug"; return 1; }

    elif [[ "$action" == "remove" ]]; then
        logI "Removing '$APP_NAME'."

        # Remove the application script
        exec_command "Remove application" "rm -f \"$APP_PATH\"" "$debug" || { logE "Failed to remove application."; debug_end "$debug"; return 1; }
    else
        die 1 "Invalid action. Use 'install' or 'remove'."
    fi

    debug_end "$debug"
}

# -----------------------------------------------------------------------------
# @brief Installs or removes the specified configuration file for the application.
# @details This function installs the configuration file for the application
#          by copying it from the source directory to the target configuration
#          path when "install" is passed as an argument. It also ensures the
#          configuration file has the correct ownership (root:root). If "remove"
#          is passed, the function will remove the configuration file and reset
#          the permissions and ownership.
#
# @param $1 Action to perform: "install" to install the configuration, "remove"
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
# install_config_file "remove"
# -----------------------------------------------------------------------------
# shellcheck disable=SC2329
install_config_file() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    if [[ "$action" == "install" ]]; then
        logI "Installing '$APP_NAME' configuration."

        # Install the configuration file
        exec_command "Installing configuration" "cp -f \"$LOCAL_REPO_DIR/conf/$APP_NAME.conf\" \"$CONFIG_FILE\"" "$debug" || { logE "Failed to install configuration."; debug_end "$debug"; return 1; }

        # Change ownership on the configuration file
        exec_command "Change ownership on configuration file" "chown root:root \"$CONFIG_FILE\"" "$debug" || { logE "Failed to change ownership on configuration file."; debug_end "$debug"; return 1; }

        # Optional: Change permissions on the configuration file (if needed)
        exec_command "Change permissions on configuration file" "chmod 644 \"$CONFIG_FILE\"" "$debug" || { logE "Failed to change permissions on configuration file."; debug_end "$debug"; return 1; }

    elif [[ "$action" == "remove" ]]; then
        logI "Removing '$APP_NAME' configuration."

        # Remove the configuration file
        exec_command "Remove configuration" "rm -f \"$CONFIG_FILE\"" "$debug" || { logE "Failed to remove configuration."; debug_end "$debug"; return 1; }
    else
        die 1 "Invalid action. Use 'install' or 'remove'."
    fi

    debug_end "$debug"
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
# shellcheck disable=SC2329
create_systemd_service() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    local service_name
    service_name=$(basename "$SERVICE_FILE")

    if [[ "$action" == "install" ]]; then
        # Check if the systemd service already exists
        if ! systemctl list-unit-files --type=service | grep -q "$service_name"; then
            logI "Creating systemd service: $service_name."
        else
            logI "Updating systemd service: $service_name."
            exec_command "Disable $service_name" "systemctl disable $service_name" "$debug" || { logE "Failed to disable $service_name."; debug_end "$debug"; return 1; }
            exec_command "Stop $service_name" "systemctl stop $service_name" "$debug" || { logE "Failed to stop $service_name."; debug_end "$debug"; return 1; }

            # Check if the service is masked and unmask if necessary
            if systemctl is-enabled --quiet "$service_name"; then
                exec_command "Unmask $service_name" "systemctl unmask $service_name" "$debug" || { logE "Failed to unmask $service_name."; debug_end "$debug"; return 1; }
            fi
        fi

        # Write the systemd service file
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Automatically toggles WiFi Access Point based on network availability ($APP_NAME)
After=multi-user.target
Requires=network-online.target

[Service]
Type=simple
ExecStart=${APP_PATH}
StandardOutput=file:$APP_LOG_PATH/output.log
StandardError=file:$APP_LOG_PATH/error.log

[Install]
WantedBy=multi-user.target
EOF

        # Create log directory if not exist and ensure correct permissions
        exec_command "Create log target: $APP_LOG_PATH" "mkdir -p $APP_LOG_PATH" "$debug" || { logE "Failed to create log target."; debug_end "$debug"; return 1; }

        # Change ownership/permissions on the log directory
        exec_command "Change ownership on log target: $APP_LOG_PATH" "chown root:root \"$APP_LOG_PATH\"" "$debug" || { logE "Failed to change ownership on log target."; debug_end "$debug"; return 1; }
        exec_command "Change permissions on log target: $APP_LOG_PATH" "chmod 755 \"$APP_LOG_PATH\"" "$debug" || { logE "Failed to change permissions on log target."; debug_end "$debug"; return 1; }

        # Enable the systemd service
        exec_command "Enable $service_name" "systemctl enable $service_name" "$debug" || { logE "Failed to enable $service_name."; debug_end "$debug"; return 1; }
        exec_command "Reload systemd" "systemctl daemon-reload" "$debug" || { logE "Failed to reload systemd."; debug_end "$debug"; return 1; }

        logI "Systemd service $service_name created."

    elif [[ "$action" == "uninstall" ]]; then
        logI "Removing systemd service: $service_name."

        # Disable and stop the systemd service
        exec_command "Stop $service_name" "systemctl stop $service_name" "$debug" || { logE "Failed to stop $service_name."; debug_end "$debug"; return 1; }
        exec_command "Disable $service_name" "systemctl disable $service_name" "$debug" || { logE "Failed to disable $service_name."; debug_end "$debug"; return 1; }

        # Remove the service file
        exec_command "Remove $service_name" "rm -f \"$SERVICE_FILE\"" "$debug" || { logE "Failed to remove $service_name."; debug_end "$debug"; return 1; }

        # Remove the log directory
        exec_command "Remove log target: $APP_LOG_PATH" "rm -rf \"$APP_LOG_PATH\"" "$debug" || { logE "Failed to remove log target."; debug_end "$debug"; return 1; }

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
# shellcheck disable=SC2329
create_systemd_timer() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    local timer_name
    timer_name=$(basename "$TIMER_FILE")

    if [[ "$action" == "install" ]]; then
        # Check if the systemd timer already exists
        if ! systemctl list-unit-files --type=timer | grep -q "$timer_name"; then
            logI "Creating systemd timer: $timer_name."
        else
            logI "Updating systemd timer: $timer_name."
            exec_command "Disable $timer_name" "systemctl disable $timer_name" "$debug" || { logE "Failed to disable $timer_name."; debug_end "$debug"; return 1; }
            exec_command "Stop $timer_name" "systemctl stop $timer_name" "$debug" || { logE "Failed to stop $timer_name."; debug_end "$debug"; return 1; }

            # Check if the timer is masked and unmask if necessary
            if systemctl is-enabled --quiet "$timer_name"; then
                exec_command "Unmask $timer_name" "systemctl unmask $timer_name" "$debug" || { logE "Failed to unmask $timer_name."; debug_end "$debug"; return 1; }
            fi
        fi

        # Write the systemd timer file
        cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Runs $APP_NAME every 2 minutes to check network status (appop)

[Timer]
OnBootSec=0min
OnCalendar=*:0/2

[Install]
WantedBy=timers.target
EOF

        # Enable the timer
        exec_command "Enable $timer_name" "systemctl enable $timer_name" "$debug" || { logE "Failed to enable $timer_name."; debug_end "$debug"; return 1; }
        exec_command "Reload systemd" "systemctl daemon-reload" "$debug" || { logE "Failed to reload systemd."; debug_end "$debug"; return 1; }
        exec_command "Start $timer_name" "systemctl start $timer_name" "$debug" || { logE "Failed to start $timer_name."; debug_end "$debug"; return 1; }

        logI "Systemd timer $timer_name created."

    elif [[ "$action" == "uninstall" ]]; then
        logI "Removing systemd timer: $timer_name."

        # Disable and stop the systemd timer
        exec_command "Stop $timer_name" "systemctl stop $timer_name" "$debug" || { logE "Failed to stop $timer_name."; debug_end "$debug"; return 1; }
        exec_command "Disable $timer_name" "systemctl disable $timer_name" "$debug" || { logE "Failed to disable $timer_name."; debug_end "$debug"; return 1; }

        # Remove the timer file
        exec_command "Remove $timer_name" "rm -f \"$TIMER_FILE\"" "$debug" || { logE "Failed to remove $timer_name."; debug_end "$debug"; return 1; }

        logI "Systemd timer $timer_name removed."
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
get_man_file_array() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local tree
    tree=$(fetch_tree)

    # Check if the repository tree is empty
    if [[ $(printf "%s" "$tree" | jq '.tree | length') -eq 0 ]]; then
        logE "Failed to fetch repository tree. Check repository details or ensure it is public." "$debug"
        debug_end "$debug"
        die 1 "Repository tree is empty or unavailable."
    fi

    local dir="man"
    local files

    # Extract file paths under the "man/" directory
    files=$(printf "%s" "$tree" | jq -r --arg TARGET_DIR "$dir/" \
        '.tree[] | select(.type=="blob" and (.path | startswith($TARGET_DIR))) | .path')

    if [[ -z "$files" ]]; then
        logE "No files found in the 'man/' directory." "$debug"
        debug_end "$debug"
        die 1 "No man page files available."
    fi

    # Print the list of files to stderr
    printf "%s\n" "$files" >&2
    debug_print "Man page files retrieved: $files" "$debug"
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
# shellcheck disable=SC2329
install_man_pages() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    # Base directory for man pages
    local man_base_dir="/usr/share/man"

    if [[ "$action" == "install" ]]; then
        logI "Installing man pages."

        # Ensure the target directory exists
        if [[ ! -d "$man_base_dir" ]]; then
            exec_command "Create directory: $man_base_dir/" "mkdir -p '$man_base_dir'" "$debug" || {
                logE "Failed to create $man_base_dir."
                debug_end "$debug"
                return 1
            }
        fi

        # Loop through all man pages in the local directory
        for man_page in "$LOCAL_REPO_DIR/man/"*.*; do
            [[ -e "$man_page" ]] || continue  # Skip if no files are found

            local section="${man_page##*.}"
            local target_dir="${man_base_dir}/man${section}"

            # Ensure the target directory for the section exists
            if [[ ! -d "$target_dir" ]]; then
                exec_command "Create directory: $target_dir/" "mkdir -p \"$target_dir\"" "$debug" || {
                    logE "Failed to create $target_dir."
                    debug_end "$debug"
                    return 1
                }
            fi

            # Compress and install the man page
            exec_command "Compress man page $man_page" "gzip -f \"$man_page\"" "$debug" || {
                logE "Failed to compress $man_page."
                debug_end "$debug"
                return 1
            }

            local man_page_gz="${man_page}.gz"
            exec_command "Install man page $man_page_gz" "cp \"$man_page_gz\" \"$target_dir/\"" "$debug" || {
                logE "Failed to copy $man_page_gz to $target_dir."
                debug_end "$debug"
                return 1
            }
        done

        # Update the man page database
        exec_command "Update man page database" "mandb" "$debug" || {
            logE "Failed to update man page database."
            debug_end "$debug"
            return 1
        }

        logI "Man pages installed successfully."

    elif [[ "$action" == "uninstall" ]]; then
        logI "Removing man pages."

        # Fetch and iterate over the man pages in the repository
        local files
        files=$(get_man_file_array "$debug")

        while IFS= read -r file; do
            [[ -n "$file" ]] || continue  # Skip empty lines

            local man_page section target_dir
            man_page=$(basename "$file")
            section="${man_page##*.}"
            target_dir="${man_base_dir}/man${section}"

            # Attempt to remove the man page and its compressed version
            exec_command "Remove man page $man_page" "rm -f \"${target_dir}/${man_page}\" \"${target_dir}/${man_page}.gz\"" "$debug" || {
                logE "Failed to remove man page $man_page."
            }
        done <<< "$files"

        # Optionally, clean up empty directories
        exec_command "Remove empty directories" "find $man_base_dir/man* -type d -empty -delete" "$debug" || {
            logE "Failed to remove empty directories."
        }

        # Update the man page database
        exec_command "Update man page database" "mandb" "$debug" || {
            logE "Failed to update man page database."
            debug_end "$debug"
            return 1
        }

        logI "Man pages uninstalled successfully."

    else
        die 1 "Invalid action. Use 'install' or 'uninstall'."
    fi

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
# shellcheck disable=SC2329
cleanup_files_in_directories() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

    # Return immediately if action is "uninstall"
    if [[ "$action" == "uninstall" ]]; then
        debug_end "$debug"
        return 0
    fi

    local dest_root="$USER_HOME/$REPO_NAME"
    logI "Deleting repository tree."

    # Delete the repository directory
    exec_command "Delete source tree" "rm -fr \"$dest_root\"" "$debug" || { logE "Failed to delete repository tree."; debug_end "$debug"; return 1; }

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
# shellcheck disable=SC2329
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
    logI "$action_message complete: $(repo_to_title_case "$REPO_NAME")."
    debug_print "$action_message complete message logged." "$debug"

    # TODO: exec_new_shell() or call out instructions

    # Optionally clear the screen or display a message
    if [[ "${TERSE:-false}" == "true" ]]; then
        printf "%s complete: %s.\n" "$action_message" "$(repo_to_title_case "$REPO_NAME")"
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
# shellcheck disable=SC2329
install_ap_popup() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="${1:-install}"  # Default to "install" if no action is provided

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

    # Validate the action argument
    if [[ "$action" != "install" && "$action" != "uninstall" ]]; then
        die 1 "Invalid action. Use 'install' or 'uninstall'." "$debug"
    fi

    # Determine the order of function execution (reverse for uninstall)
    local group_to_execute=()
    if [[ "$action" == "install" ]]; then
        group_to_execute=("${install_group[@]}")
    else
        mapfile -t group_to_execute < <(printf "%s\n" "${install_group[@]}" | tac)  # Reverse the array
    fi

    # Start the script
    start_script "$action" "$debug"

    # Iterate over the group of functions and call them with the action and debug flag
    for func in "${group_to_execute[@]}"; do
        logI "Running $func with action '$action'" "$debug"

        # Call the function with action and debug flag
        $func "$action" "$debug"
        local status=$?

        # Check if the function failed
        if [[ $status -ne 0 ]]; then
            logE "$func failed with status $status" "$debug"
            debug_end "$debug"
            return 1
        else
            logI "$func succeeded." "$debug"
        fi
    done

    # cleanup files (returns early on uninstall)
    cleanup_files_in_directories "$action" "$debug"

    # Finish the script
    finish_script "$action" "$debug"

    debug_end "$debug"
    return 0
}

############
### Main Functions
############

_main() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local action="$1"

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

    # install_ap_popup "$action" "$debug"
    get_man_file_array

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
