#!/usr/bin/env bash
set -uo pipefail # Setting -e is far too much work here
IFS=$'\n\t'
set +o noclobber

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
# @brief Trap unexpected errors during script execution.
# @details Captures any errors (via the ERR signal) that occur during script execution.
# Logs the function name and line number where the error occurred and exits the script.
# The trap calls an error-handling function for better flexibility.
#
# @global FUNCNAME Array containing function names in the call stack.
# @global LINENO Line number where the error occurred.
# @global THIS_SCRIPT Name of the script.
#
# @return None (exits the script with an error code).
# -----------------------------------------------------------------------------
# shellcheck disable=2329
trap_error() {
    # Capture function name, line number, and script name
    local func="${FUNCNAME[1]:-main}"  # Get the calling function name (default: "main")
    local line="${1:-}"                # Line number where the error occurred
    local script="${THIS_SCRIPT:-$(basename "$0")}"  # Script name (fallback to current script)

    # Validate that the line number is set
    if [[ -z "$line" ]]; then
        line="unknown"
    fi

    # Log the error message to stderr
    printf "\n[ERROR] An unexpected error occurred in function '%s()' at line %s of script '%s'. Exiting.\n" \
        "$func" "$line" "$script" >&2

    # Exit with a non-zero status code
    exit 1
}

# Set the trap to call trap_error on any error
# Uncomment the next line to help with script debugging
# trap 'trap_error "$LINENO"' ERR

############
### Global Script Declarations
############

# -----------------------------------------------------------------------------
# @var RE_RUN
# @brief Optional environment variable to control re-execution behavior.
# @details Ensures that the `RE_RUN` variable is declared to prevent unbound 
#          variable errors. Defaults to "false" if not explicitly set.
# @default false
# -----------------------------------------------------------------------------
declare RE_RUN="${RE_RUN:-false}" # Use existing value, or default to "false".

# -----------------------------------------------------------------------------
# @var THIS_SCRIPT
# @brief The name of the script being executed.
# @details This variable is initialized to the name of the script (e.g.,
#          `install.sh`) if not already set. It dynamically defaults to the
#          basename of the executing script at runtime.
#
# @example
# echo "Executing script: $THIS_SCRIPT"
# -----------------------------------------------------------------------------
declare THIS_SCRIPT="${THIS_SCRIPT:-$(basename "$0")}"  # Default to the script's name if not set.

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
readonly DIRECTORIES=("man" "scripts" "conf")           # Relevant directories for installation.

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
readonly DEST_APP_NAME="${SOURCE_APP_NAME%.*}"          # The final installed name of the main script (no extension).
readonly APP_PATH="/usr/bin/$DEST_APP_NAME"             # Path to where the main script (appop) will be installed.
readonly SYSTEMD_PATH="/etc/systemd/system/"            # Path to the systemd directory for services/timers.
readonly SERVICE_FILE="$DEST_APP_NAME.service"          # Name of the systemd service file to be created/managed.
readonly TIMER_FILE="$DEST_APP_NAME.timer"              # Name of the systemd timer file to be created/managed.
readonly CONFIG_FILE="/etc/$DEST_APP_NAME.conf"         # Path to the AP Pop-Up configuration file.
declare LOG_PATH="${LOG_PATH:-/var/log/$DEST_APP_NAME}" # Path to the logs for the application.

# -----------------------------------------------------------------------------
# @var DRY_RUN
# @brief Enables simulated execution of certain commands.
# @details When set to `true`, commands are not actually executed but are
#          simulated to allow testing or validation without side effects.
#          If set to `false`, commands execute normally.
#
# @example
# DRY_RUN=true ./apconfig.sh  # Run the script in dry-run mode.
# -----------------------------------------------------------------------------
declare DRY_RUN="${DRY_RUN:-false}"  # Use existing value, or default to "false".

# -----------------------------------------------------------------------------
# @var IS_PATH
# @brief Indicates whether the script was executed from a `PATH` location.
# @details This variable is initialized to `false` by default. During execution,
#          it is dynamically set to `true` if the script is determined to have
#          been executed from a directory listed in the `PATH` environment variable.
#
# @example
# if [[ "$IS_PATH" == "true" ]]; then
#     echo "Script was executed from a PATH directory."
# else
#     echo "Script was executed from a non-PATH directory."
# fi
# -----------------------------------------------------------------------------
declare IS_PATH="${IS_PATH:-false}"  # Default to "false".

# -----------------------------------------------------------------------------
# @var IS_GITHUB_REPO
# @brief Indicates whether the script resides in a GitHub repository or subdirectory.
# @details This variable is initialized to `false` by default. During execution, it
#          is dynamically set to `true` if the script is detected to be within a
#          GitHub repository (i.e., if a `.git` directory exists in the directory
#          hierarchy of the script's location).
#
# @example
# if [[ "$IS_GITHUB_REPO" == "true" ]]; then
#     echo "This script resides within a GitHub repository."
# else
#     echo "This script is not located within a GitHub repository."
# fi
# -----------------------------------------------------------------------------
declare IS_GITHUB_REPO="${IS_GITHUB_REPO:-false}"  # Default to "false".

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
# - @var GIT_BRCH The current Git branch name (default: "main").
# - @var GIT_TAG The current Git tag (default: "0.0.1").
# - @var SEM_VER The semantic version of the project (default: "0.0.1").
# - @var LOCAL_SOURCE_DIR The local source directory path (default: unset).
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
# echo "Branch: $GIT_BRCH, Tag: $GIT_TAG, Version: $SEM_VER"
# echo "Source Directory: ${LOCAL_SOURCE_DIR:-Not Set}"
# echo "WWW Directory: ${LOCAL_WWW_DIR:-Not Set}"
# echo "Scripts Directory: ${LOCAL_SCRIPTS_DIR:-Not Set}"
# echo "Raw URL: $GIT_RAW"
# echo "API URL: $GIT_API"
# -----------------------------------------------------------------------------
declare REPO_ORG="${REPO_ORG:-lbussy}"
declare REPO_NAME="${REPO_NAME:-ap-popup}"
declare GIT_BRCH="${GIT_BRCH:-main}"
declare GIT_TAG="${GIT_TAG:-0.0.1}"
declare SEM_VER="${GIT_TAG:-0.0.1}"
declare LOCAL_SOURCE_DIR="${LOCAL_SOURCE_DIR:-}"
declare LOCAL_WWW_DIR="${LOCAL_WWW_DIR:-}"
declare LOCAL_SCRIPTS_DIR="${LOCAL_SCRIPTS_DIR:-}"
declare GIT_RAW="${GIT_RAW:-"https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"}"
declare GIT_API="${GIT_API:-"https://api.github.com/repos/$REPO_ORG/$REPO_NAME"}"
declare GIT_CLONE="${GIT_CLONE:-"https://github.com/$REPO_ORG/$REPO_NAME.git"}"

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
# @var CONSOLE_STATE
# @brief Tracks the original console logging state.
# @details This variable mirrors the value of USE_CONSOLE and provides a
#          consistent reference for toggling or querying the state of console
#          logging.
#
# @example
# - CONSOLE_STATE="USE_CONSOLE": Console logging matches USE_CONSOLE.
# -----------------------------------------------------------------------------
declare CONSOLE_STATE="${CONSOLE_STATE:-$USE_CONSOLE}"

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
# ./apconfig.sh
#
# TERSE=false # Enables verbose logging mode.
# ./apconfig.sh
# -----------------------------------------------------------------------------
declare TERSE="${TERSE:-false}"  # Default to "false" (verbose logging).

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
# REQUIRE_SUDO=false ./apconfig.sh  # Run the script without enforcing root privileges.
# -----------------------------------------------------------------------------
readonly REQUIRE_SUDO="${REQUIRE_SUDO:-true}"  # Default to "true" if not specified.

# -----------------------------------------------------------------------------
# @var REQUIRE_INTERNET
# @type string
# @brief Flag indicating if internet connectivity is required.
# @details Controls whether the script should verify internet connectivity
#          during initialization. This variable can be overridden by setting
#          the `REQUIRE_INTERNET` environment variable before running the script.
#
# @values
# - `"true"`: Internet connectivity is required.
# - `"false"`: Internet connectivity is not required.
#
# @default "true"
#
# @example
# REQUIRE_INTERNET=false ./apconfig.sh  # Run the script without verifying internet connectivity.
# -----------------------------------------------------------------------------
readonly REQUIRE_INTERNET="${REQUIRE_INTERNET:-true}"   # Default to "true" if not set.

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
# MIN_BASH_VERSION="none" ./apconfig.sh  # Disable Bash version checks.
# MIN_BASH_VERSION="5.0" ./apconfig.sh   # Require at least Bash 5.0.
# -----------------------------------------------------------------------------
readonly MIN_BASH_VERSION="${MIN_BASH_VERSION:-4.0}"  # Default to "4.0" if not specified.

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
readonly MIN_OS=11  # Minimum supported OS version.

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
readonly MAX_OS=15  # Maximum supported OS version (use -1 for no upper limit).

# -----------------------------------------------------------------------------
# @var SUPPORTED_BITNESS
# @brief Specifies the supported system bitness.
# @details Defines the system architectures that the script supports. Acceptable
#          values are:
#          - `"32"`: Only supports 32-bit systems.
#          - `"64"`: Only supports 64-bit systems.
#          - `"both"`: Supports both 32-bit and 64-bit systems.
#          This variable ensures compatibility with the intended system architecture.
#          It defaults to `"32"` if not explicitly set.
#
# @default "32"
#
# @example
# if [[ "$SYSTEM_BITNESS" != "$SUPPORTED_BITNESS" && "$SUPPORTED_BITNESS" != "both" ]]; then
#     echo "This script supports $SUPPORTED_BITNESS-bit systems only."
#     exit 1
# fi
# -----------------------------------------------------------------------------
readonly SUPPORTED_BITNESS="both"  # Supported bitness ("32", "64", or "both").

# -----------------------------------------------------------------------------
# @var SUPPORTED_MODELS
# @brief Associative array of Raspberry Pi models and their support statuses.
# @details This associative array maps Raspberry Pi model identifiers to their
#          corresponding support statuses. Each key is a pipe-delimited string
#          containing:
#          - The model name (e.g., "Raspberry Pi 4 Model B").
#          - A simplified identifier (e.g., "4-model-b").
#          - The chipset identifier (e.g., "bcm2711").
#
#          The value is the support status, which can be:
#          - `"Supported"`: Indicates the model is fully supported by the script.
#          - `"Not Supported"`: Indicates the model is not supported.
#
#          This array is marked as `readonly` to ensure it remains immutable at runtime.
#
# @example
# for model in "${!SUPPORTED_MODELS[@]}"; do
#     IFS="|" read -r full_name short_name chipset <<< "$model"
#     echo "Model: $full_name ($short_name, $chipset) - Status: ${SUPPORTED_MODELS[$model]}"
# done
# -----------------------------------------------------------------------------
declare -A SUPPORTED_MODELS=(
    # Unsupported Models
    ["Raspberry Pi 400|400|bcm2711"]="Not Supported"                            # Raspberry Pi 400
    ["Raspberry Pi Compute Module 4|4-compute-module|bcm2711"]="Not Supported"  # Compute Module 4
    ["Raspberry Pi Compute Module 3|3-compute-module|bcm2837"]="Not Supported"  # Compute Module 3
    ["Raspberry Pi Compute Module|compute-module|bcm2835"]="Not Supported"      # Original Compute Module

    # Supported Models
    ["Raspberry Pi 5|5-model-b|bcm2712"]="Supported"                # Raspberry Pi 5 Model B
    ["Raspberry Pi 4 Model B|4-model-b|bcm2711"]="Supported"        # Raspberry Pi 4 Model B
    ["Raspberry Pi 3 Model A+|3-model-a-plus|bcm2837"]="Supported"  # Raspberry Pi 3 Model A+
    ["Raspberry Pi 3 Model B+|3-model-b-plus|bcm2837"]="Supported"  # Raspberry Pi 3 Model B+
    ["Raspberry Pi 3 Model B|3-model-b|bcm2837"]="Supported"        # Raspberry Pi 3 Model B
    ["Raspberry Pi 2 Model B|2-model-b|bcm2836"]="Supported"        # Raspberry Pi 2 Model B
    ["Raspberry Pi Model A+|model-a-plus|bcm2835"]="Supported"      # Raspberry Pi Model A+
    ["Raspberry Pi Model B+|model-b-plus|bcm2835"]="Supported"      # Raspberry Pi Model B+
    ["Raspberry Pi Model B Rev 2|model-b-rev2|bcm2835"]="Supported" # Raspberry Pi Model B Rev 2
    ["Raspberry Pi Model A|model-a|bcm2835"]="Supported"            # Raspberry Pi Model A
    ["Raspberry Pi Model B|model-b|bcm2835"]="Supported"            # Raspberry Pi Model B
    ["Raspberry Pi Zero 2 W|model-zero-2-w|bcm2837"]="Supported"    # Raspberry Pi Zero 2 W
    ["Raspberry Pi Zero|model-zero|bcm2835"]="Supported"            # Raspberry Pi Zero
    ["Raspberry Pi Zero W|model-zero-w|bcm2835"]="Supported"        # Raspberry Pi Zero W
)
readonly SUPPORTED_MODELS

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
# LOG_OUTPUT="file" ./apconfig.sh      # Logs to a file only.
# LOG_OUTPUT="console" ./apconfig.sh   # Logs to the console only.
# LOG_OUTPUT="both" ./apconfig.sh      # Logs to both destinations.
# -----------------------------------------------------------------------------
declare LOG_OUTPUT="${LOG_OUTPUT:-both}"  # Default to logging to both console and file.

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
# LOG_FILE="/var/log/my_script.log" ./apconfig.sh  # Use a custom log file.
# -----------------------------------------------------------------------------
declare LOG_FILE="${LOG_FILE:-}"  # Use the provided LOG_FILE or default to blank.

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
# LOG_LEVEL="INFO" ./apconfig.sh  # Set the log level to INFO.
# -----------------------------------------------------------------------------
declare LOG_LEVEL="${LOG_LEVEL:-DEBUG}"  # Default log level is DEBUG if not set.

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
#   `"dpkg"`, `"git"`, `"dpkg-reconfigure"`, `"curl"`, `"wget"`, `"realpath"`.
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
COLUMNS="${COLUMNS:-80}"  # Default to 80 columns if unset.

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
#          - `git`: Version control system.
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
# WARN_STACK_TRACE=true ./apconfig.sh  # Enable stack traces for warnings.
# WARN_STACK_TRACE=false ./apconfig.sh # Disable stack traces for warnings.
# -----------------------------------------------------------------------------
readonly WARN_STACK_TRACE="${WARN_STACK_TRACE:-false}"  # Default to false if not set.

############
### Common Functions
############

# -----------------------------------------------------------------------------
# @brief Pads a number with spaces.
# @details Pads the input number with spaces to the left. Defaults to 4 characters wide but accepts an optional width.
#          Also accepts an optional debug flag, which, when set to "debug", enables debug output.
#
# @param $1 The number to pad (e.g., "7").
# @param $2 (Optional) The width of the output (default is 4). If debug is provided here, it will be considered the debug flag.
# @param $3 (Optional) The debug flag. Pass "debug" to enable debug output.
#
# @return The padded number with spaces as a string.
# -----------------------------------------------------------------------------
pad_with_spaces() {
    local number="$1"       # Input number (mandatory)
    local width="${2:-4}"   # Optional width (default is 4)
    # Debug setup
    local debug="${3:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"

    # If the second parameter is "debug", adjust the arguments
    if [[ "$width" == "debug" ]]; then
        debug="$width"
        width=4  # Default width to 4 if "debug" was passed in place of width
    fi

    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

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

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    # Format the number with leading spaces and return it as a string
    printf "%${width}d\n" "$number"
}

##
# @brief Print a detailed stack trace of the call hierarchy.
# @details Outputs the sequence of function calls leading up to the point
#          where this function was invoked. Supports optional error messages
#          and colorized output based on terminal capabilities.
#
# @param $1 Log level (e.g., DEBUG, INFO, WARN, ERROR, CRITICAL).
# @param $2 Optional error message to display at the top of the stack trace.
#
# @global BASH_LINENO Array of line numbers in the call stack.
# @global FUNCNAME Array of function names in the call stack.
# @global BASH_SOURCE Array of source file names in the call stack.
#
# @return None
##
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
    # shellcheck disable=2183
    printf "%b%s%b\n" "$color" "$(printf '%*s' "${#header}" | tr ' ' '-')" "\033[0m" >&2
}

# -----------------------------------------------------------------------------
# @brief Logs a warning or error message with optional details and a stack trace.
# @details This function logs messages at the `WARNING` or `ERROR` level, with
#          support for an optional stack trace for warnings. It appends the error
#          level (numeric) and additional details to the log message if provided.
#
#          Stack traces are included for warnings if `WARN_STACK_TRACE` is set
#          to `true`. The function uses `BASH_LINENO` to identify the call stack.
#
# @param $1 [Optional] Numeric error level. Defaults to `0` if not provided.
# @param $2 [Optional] Log level. Acceptable values are `WARNING` or `ERROR`. Defaults to `WARNING`.
# @param $3 [Optional] Main log message. Defaults to "A warning was raised on this line."
# @param $4 [Optional] Additional details to include in the log.
#
# @global WARN_STACK_TRACE Enables stack trace logging for warnings when set to `true`.
# @global BASH_LINENO Array of line numbers in the call stack.
# @global SCRIPT_NAME The name of the script being executed.
#
# @example
# warn 2 "WARNING" "Disk space is low" "Available space: 5GB"
# warn 1 "ERROR" "Critical failure detected" "Terminating script"
# -----------------------------------------------------------------------------
warn() {
    # Default values for parameters
    local error_level="${1:-0}"               # Numeric error level
    local level="${2:-WARNING}"               # Log level (WARNING or ERROR)
    local message="${3:-A warning was raised on this line}"  # Default log message
    local details="${4:-}"                    # Additional details (optional)
    local lineno="${BASH_LINENO[1]:-0}"       # Line number where the function was called
    lineno=$(pad_with_spaces "$lineno")       # Format line number with leading spaces

    # Construct the main log message
    message="${message}: (${error_level})"

    # Log the message at the specified level
    if [[ "$level" == "WARNING" ]]; then
        logW "$message" "$details"
    elif [[ "$level" == "ERROR" ]]; then
        logE "$message" "$details"
    fi

    # Include stack trace for warnings if enabled
    if [[ "$WARN_STACK_TRACE" == "true" && "$level" == "WARNING" ]]; then
        stack_trace "$level" "Stack trace for $level at line $lineno: $message"
    fi
}

# -----------------------------------------------------------------------------
# @brief Log a critical error, print a stack trace, and exit the script.
# @details This function logs a critical error message, optionally prints additional
#          details and a stack trace, and then exits the script with a specified
#          or default exit status.
#
# @param $1 [Optional] Exit status code. Defaults to `1` if not numeric.
# @param $2 [Optional] Main error message. Defaults to "Unrecoverable error."
# @param $@ [Optional] Additional details for the error.
#
# @global BASH_LINENO Array of line numbers in the call stack.
# @global THIS_SCRIPT The name of the current script.
#
# @return Exits the script with the provided or default exit status.
#
# @example
# die 2 "Configuration file missing" "Expected file: /etc/config.cfg"
# die "An unexpected error occurred"
# -----------------------------------------------------------------------------
die() {
    # Local variables
    local exit_status="$1"              # First parameter as exit status
    local message                       # Main error message
    local details                       # Additional details
    local lineno="${BASH_LINENO[0]}"    # Line number where the error occurred
    local script="${THIS_SCRIPT:-$(basename "$0")}"  # Script name
    local level="CRITICAL"              # Error level
    local tag="CRIT "                   # Log tag
    lineno=$(pad_with_spaces "$lineno") # Pad line number with spaces for consistency

    # Determine exit status and message
    if ! [[ "$exit_status" =~ ^[0-9]+$ ]]; then
        exit_status=1
        message="$1"
        shift
    else
        shift
        message="${1:-Unrecoverable error.}"
        shift
    fi
    details="$*" # Remaining parameters as additional details

    # Log the critical error
    printf "[%s]\t[%s:%s]\t%s\n" "$tag" "$script" "$lineno" "${message:-Unrecoverable error.}" >&2
    if [[ -n "$details" ]]; then
        printf "[%s]\t[%s:%s]\tDetails: %s\n" "$tag" "$script" "$lineno" "$details" >&2
    fi

    # Log an unrecoverable error message with exit status
    printf "[%s]\t[%s:%s]\tUnrecoverable error (exit status: %d).\n" \
        "$tag" "$script" "$lineno" "$exit_status" >&2

    # Call stack_trace with processed message and error level
    stack_trace "$level" "Stack trace from line $lineno: ${message:-Unrecoverable error.}"

    # Exit with the determined status
    exit "$exit_status"
}

# -----------------------------------------------------------------------------
# @brief Add a dot (`.`) at the beginning of a string if it's missing.
# @details This function ensures the input string starts with a leading dot.
#          If the input string is empty, the function logs a warning and returns
#          an error code.
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
add_dot() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "Input to add_dot cannot be empty." "No string provided for processing."
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
# @details This function processes the input string and removes a leading dot
#          if it exists. If the input string is empty, the function logs an error
#          and returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string without a leading dot if one was present.
# @retval 1 If the input string is empty.
#
# @example
# remove_dot ".example"  # Outputs "example"
# remove_dot "example"   # Outputs "example"
# remove_dot ""          # Logs an error and returns an error code.
# -----------------------------------------------------------------------------
remove_dot() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to remove_dot cannot be empty." "No string provided for processing."
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
# @details This function ensures that the input string ends with a trailing slash.
#          If the input string is empty, the function logs an error and returns
#          an error code.
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
add_slash() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to add_slash cannot be empty." "No string provided for processing."
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
# @details This function ensures that the input string does not end with a trailing
#          slash. If the input string is empty, the function logs an error and
#          returns an error code.
#
# @param $1 The input string to process.
#
# @return Outputs the modified string without a trailing slash if one was present.
# @retval 1 If the input string is empty.
#
# @example
# remove_slash "/path/to/directory/"  # Outputs "/path/to/directory"
# remove_slash "/path/to/directory"   # Outputs "/path/to/directory"
# remove_slash ""                     # Logs an error and returns an error code.
# -----------------------------------------------------------------------------
remove_slash() {
    local input="$1"  # Input string to process

    # Validate input
    if [[ -z "${input:-}" ]]; then
        warn "ERROR" "Input to remove_slash cannot be empty." "No string provided for processing."
        return 1
    fi

    # Remove the trailing slash if present
    if [[ "$input" == */ ]]; then
        input="${input%/}"
    fi

    printf "%s\n" "$input"
}

# -----------------------------------------------------------------------------
# @brief Pauses execution and waits for user input to continue.
# @details This function displays a message prompting the user to press any key
#          to continue. It waits for a single key press, then resumes execution.
#
# @example
# pause
# -----------------------------------------------------------------------------
pause() {
    printf "Press any key to continue.\n"
    read -n 1 -sr < /dev/tty || true
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Declare local variables
    local system_name

    # Extract system name and version from /etc/os-release
    system_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d '=' -f2 | tr -d '"')

    # Debug: Log extracted system name
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Extracted system name: %s\n" "${system_name:-<empty>}" >&2

    # Check if system_name is empty and log accordingly
    if [[ -z "${system_name:-}" ]]; then
        logW "System: Unknown (could not extract system information)."  # Log warning if system information is unavailable
        [[ "$debug" == "debug" ]] && printf "[DEBUG] System information could not be extracted.\n" >&2
    else
        logI "System: $system_name."  # Log the system information
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Logged system information: %s\n" "$system_name" >&2
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Print the script version and optionally log it.
# @details This function displays the version of the script stored in the global
#          variable `SEM_VER`. If called by `parse_args`, it uses `printf` to
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Check the name of the calling function
    local caller="${FUNCNAME[1]}"

    if [[ "$caller" == "parse_args" ]]; then
        printf "%s: version %s\n" "$THIS_SCRIPT" "$SEM_VER" # Display the script name and version
    else
        logI "Running $(repo_to_title_case "$REPO_NAME")'s '$THIS_SCRIPT', version $SEM_VER" # Log the script name and version
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Print the system information to the log.
# @details Extracts and logs the system's name and version using information
#          from `/etc/os-release`. Includes debug output when the `debug`
#          argument is provided.
#
# @param $1 [Optional] Debug flag to enable detailed output (debug).
#
# @global None
#
# @return None
#
# @example
# print_system debug
# Outputs system information with debug logs enabled.
# -----------------------------------------------------------------------------
# shellcheck disable=2120
print_system() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Declare local variables
    local system_name

    # Extract system name and version from /etc/os-release
    system_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d '=' -f2 | tr -d '"')

    # Check if system_name is empty and log accordingly
    if [[ -z "${system_name:-}" ]]; then
        logW "System: Unknown (could not extract system information)."  # Warning if system information is unavailable
        [[ "$debug" == "debug" ]] && printf "[DEBUG] System information could not be extracted.\n" >&2
    else
        logI "System: $system_name."  # Log the system information
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Logged system information: %s\n" "$system_name" >&2
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

############
### Check Environment Functions
############

# -----------------------------------------------------------------------------
# @brief Determine the script's execution context.
# @details Identifies how the script was executed, returning one of the
#          predefined context codes. Handles errors gracefully and outputs
#          additional debugging information when the "debug" argument is passed.
#
# Context Codes:
#   - `0`: Script executed via pipe.
#   - `1`: Script executed with `bash` in an unusual way.
#   - `2`: Script executed directly (local or from PATH).
#   - `3`: Script executed from within a GitHub repository.
#   - `4`: Script executed from a PATH location.
#
# @param $1 [Optional] Pass "debug" to enable verbose logging for debugging purposes.
#
# @throws Exits with an error if the script path cannot be resolved or
#         directory traversal exceeds the maximum depth.
#
# @return Returns a context code (described above) indicating the script's
#         execution context.
# -----------------------------------------------------------------------------
determine_execution_context() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local script_path   # Full path of the script
    local current_dir   # Temporary variable to traverse directories
    local max_depth=10  # Limit for directory traversal depth
    local depth=0       # Counter for directory traversal

    # Debug: Start context determination
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Determining script execution context.\n" >&2

    # Check if the script is executed via pipe
    if [[ "$0" == "bash" ]]; then
        if [[ -p /dev/stdin ]]; then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Execution context: Script executed via pipe.\n" >&2
            return 0  # Execution via pipe
        else
            printf "[WARN] Unusual bash execution detected.\n" >&2
            return 1  # Unusual bash execution
        fi
    fi

    # Get the script path
    script_path=$(realpath "$0" 2>/dev/null) || script_path=$(pwd)/$(basename "$0")
    if [[ ! -f "$script_path" ]]; then
        printf "[ERROR] Unable to resolve script path: %s\n" "$script_path" >&2
        exit 1
    fi
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Resolved script path: %s.\n" "$script_path" >&2

    # Initialize current_dir with the directory part of script_path
    current_dir="${script_path%/*}"
    current_dir="${current_dir:-.}"

    # Safeguard against invalid current_dir during initialization
    if [[ ! -d "$current_dir" ]]; then
        printf "[ERROR] Invalid starting directory: %s\n" "$current_dir" >&2
        exit 1
    fi

    # Traverse upwards to detect a GitHub repository
    while [[ "$current_dir" != "/" && $depth -lt $max_depth ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] GitHub repository detected at depth %d: %s.\n" "$depth" "$current_dir" >&2
            return 3  # Execution within a GitHub repository
        fi
        current_dir=$(dirname "$current_dir") # Move up one directory
        ((depth++))
    done

    # Handle loop termination conditions
    if [[ $depth -ge $max_depth ]]; then
        printf "[ERROR] Directory traversal exceeded maximum depth (%d).\n" "$max_depth" >&2
        exit 1
    fi

    # Check if the script is executed from a PATH location
    local resolved_path
    resolved_path=$(command -v "$(basename "$0")" 2>/dev/null)
    if [[ "$resolved_path" == "$script_path" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Script executed from a PATH location: %s.\n" "$resolved_path" >&2
        return 4  # Execution from a PATH location
    fi

    # Default: Direct execution from the local filesystem
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Default context: Script executed directly.\n" >&2
    return 2
}

# -----------------------------------------------------------------------------
# @brief Handle the execution context of the script.
# @details Determines the script's execution context by invoking
#          `determine_execution_context` and sets global variables based on
#          the context. Outputs debug information if the "debug" argument is
#          passed. Provides safeguards for unknown or invalid context codes.
#
# @param $1 [Optional] Pass "debug" to enable verbose logging for debugging purposes.
#
# @throws Exits with an error if an invalid context code is returned.
#
# @return None
# -----------------------------------------------------------------------------
handle_execution_context() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Call determine_execution_context and capture its output
    determine_execution_context "${1:-}"
    local context=$?  # Capture the return code to determine context

    # Validate the context
    if ! [[ "$context" =~ ^[0-4]$ ]]; then
        printf "[ERROR] Invalid context code returned: %d\n" "$context" >&2
        exit 1
    fi

    # Initialize and set global variables based on the context
    case $context in
        0)
            THIS_SCRIPT="piped_script"
            USE_LOCAL=false
            IS_GITHUB_REPO=false
            IS_PATH=false
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Execution context: Script was piped (e.g., 'curl url | sudo bash').\n" >&2
            ;;
        1)
            THIS_SCRIPT="piped_script"
            USE_LOCAL=false
            IS_GITHUB_REPO=false
            IS_PATH=false
            printf "[WARN] Execution context: Script run with 'bash' in an unusual way.\n" >&2
            ;;
        2)
            THIS_SCRIPT=$(basename "$0")
            USE_LOCAL=true
            IS_GITHUB_REPO=false
            IS_PATH=false
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Execution context: Script executed directly from %s.\n" "$THIS_SCRIPT" >&2
            ;;
        3)
            THIS_SCRIPT=$(basename "$0")
            USE_LOCAL=true
            IS_GITHUB_REPO=true
            IS_PATH=false
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Execution context: Script is within a GitHub repository.\n" >&2
            ;;
        4)
            THIS_SCRIPT=$(basename "$0")
            USE_LOCAL=true
            IS_GITHUB_REPO=false
            IS_PATH=true
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Execution context: Script executed from a PATH location (%s).\n" "$(command -v "$THIS_SCRIPT")" >&2
            ;;
        *)
            printf "[ERROR] Unknown execution context.\n" >&2
            exit 99
            ;;
    esac
}

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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function parameters:\n\t- REQUIRE_SUDO='%s'\n\t- EUID='%s'\n\t- SUDO_USER='%s'\n\t- SUDO_COMMAND='%s'\n" \
            "$REQUIRE_SUDO" "$EUID" "$SUDO_USER" "$SUDO_COMMAND" >&2

    if [[ "$REQUIRE_SUDO" == true ]]; then
        if [[ "$EUID" -eq 0 && -n "$SUDO_USER" && "$SUDO_COMMAND" == *"$0"* ]]; then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Sudo conditions met. Proceeding.\n" >&2
            # Script is properly executed with `sudo`
        elif [[ "$EUID" -eq 0 && -n "$SUDO_USER" ]]; then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Script run from a root shell. Exiting.\n" >&2
            die 1 "This script should not be run from a root shell." \
                  "Run it with 'sudo $THIS_SCRIPT' as a regular user."
        elif [[ "$EUID" -eq 0 ]]; then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Script run as root. Exiting.\n" >&2
            die 1 "This script should not be run as the root user." \
                  "Run it with 'sudo $THIS_SCRIPT' as a regular user."
        else
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Script not run with sudo. Exiting.\n" >&2
            die 1 "This script requires 'sudo' privileges." \
                  "Please re-run it using 'sudo $THIS_SCRIPT'."
        fi
    fi
    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Declare local variables
    local missing=0  # Counter for missing dependencies
    local dep        # Iterator for dependencies

    # Iterate through dependencies
    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            logE "Missing dependency: $dep"
            ((missing++))
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Missing dependency: %s\n" "$dep" >&2
        else
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Found dependency: %s\n" "$dep" >&2
        fi
    done

    # Handle missing dependencies
    if ((missing > 0)); then
        logE "Missing $missing dependencies. Install them and re-run the script."
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting due to missing dependencies.\n" >&2
        exit_script 1
    fi

    [[ "$debug" == "debug" ]] && printf "[DEBUG] All dependencies are present.\n" >&2

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Declare local variables
    local missing=0  # Counter for missing or unreadable files
    local file       # Iterator for files

    # Iterate through system files
    for file in "${SYSTEM_READS[@]}"; do
        if [[ ! -r "$file" ]]; then
            logE "Missing or unreadable file: $file"
            ((missing++))
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Missing or unreadable file: %s\n" "$file" >&2
        else
            [[ "$debug" == "debug" ]] && printf "[DEBUG] File is accessible: %s\n" "$file" >&2
        fi
    done

    # Handle missing files
    if ((missing > 0)); then
        logE "Missing or unreadable $missing critical system files."
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting due to missing or unreadable files.\n" >&2
        die 1 "Ensure all required files are accessible and re-run the script."
    fi

    [[ "$debug" == "debug" ]] && printf "[DEBUG] All critical system files are accessible.\n" >&2

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Declare local variables
    local missing=0  # Counter for missing environment variables
    local var        # Iterator for environment variables

    # Iterate through environment variables
    for var in "${ENV_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            printf "ERROR: Missing environment variable: %s\n" "$var" >&2
            ((missing++))
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Missing environment variable: %s\n" "$var" >&2
        else
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Environment variable is set: %s=%s\n" "$var" "${!var}" >&2
        fi
    done

    # Handle missing variables
    if ((missing > 0)); then
        printf "ERROR: Missing %d required environment variables. Ensure all required environment variables are set and re-run the script.\n" "$missing" >&2
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting due to missing environment variables.\n" >&2
        exit 1
    fi

    [[ "$debug" == "debug" ]] && printf "[DEBUG] All required environment variables are set.\n" >&2

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Ensure the script is running in a Bash shell
    if [[ -z "${BASH_VERSION:-}" ]]; then
        logE "This script requires Bash. Please run it with Bash."
        [[ "$debug" == "debug" ]] && printf "BASH_VERSION is empty or undefined.\n" >&2
        exit_script 1 "BASH_VERSION is empty or undefined"
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local required_version="${MIN_BASH_VERSION:-none}"

    # If MIN_BASH_VERSION is "none", skip version check
    if [[ "$required_version" == "none" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Bash version check is disabled (MIN_BASH_VERSION='none').\n" >&2
    else
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Minimum required Bash version is set to '%s'.\n" "$required_version" >&2

        # Extract the major and minor version components from the required version
        local required_major="${required_version%%.*}"
        local required_minor="${required_version#*.}"
        required_minor="${required_minor%%.*}"

        # Log current Bash version for debugging
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Current Bash version is %d.%d.\n" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" >&2

        # Compare the current Bash version with the required version
        if (( BASH_VERSINFO[0] < required_major ||
              (BASH_VERSINFO[0] == required_major && BASH_VERSINFO[1] < required_minor) )); then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Current Bash version does not meet the requirement.\n" >&2
            die 1 "This script requires Bash version $required_version or newer."
        fi
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Check system bitness compatibility.
# @details Validates whether the current system's bitness matches the supported
#          configuration. Outputs debug information if debug mode is enabled.
#
# @param $1 [Optional] "debug" to enable verbose output for the check.
#
# @global SUPPORTED_BITNESS Specifies the bitness supported by the script ("32", "64", or "both").
#
# @return None
# @exit 1 if the system bitness is unsupported.
#
# @example
# check_bitness
# check_bitness debug
# -----------------------------------------------------------------------------
check_bitness() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local bitness  # Stores the detected bitness of the system.

    # Detect the system bitness
    bitness=$(getconf LONG_BIT)

    # Debugging: Detected system bitness
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Detected system bitness: %s-bit.\n" "$bitness" >&2

    case "$SUPPORTED_BITNESS" in
        "32")
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Script supports only 32-bit systems.\n" >&2
            if [[ "$bitness" -ne 32 ]]; then
                die 1 "Only 32-bit systems are supported. Detected $bitness-bit system."
            fi
            ;;
        "64")
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Script supports only 64-bit systems.\n" >&2
            if [[ "$bitness" -ne 64 ]]; then
                die 1 "Only 64-bit systems are supported. Detected $bitness-bit system."
            fi
            ;;
        "both")
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Script supports both 32-bit and 64-bit systems.\n" >&2
            ;;
        *)
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Invalid SUPPORTED_BITNESS configuration: '%s'.\n" "$SUPPORTED_BITNESS" >&2
            die 1 "Configuration error: Invalid value for SUPPORTED_BITNESS ('$SUPPORTED_BITNESS')."
            ;;
    esac

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local ver  # Holds the extracted version ID from /etc/os-release.

    # Ensure the file exists and is readable.
    if [[ ! -f /etc/os-release || ! -r /etc/os-release ]]; then
        die 1 "Unable to read /etc/os-release. Ensure this script is run on a compatible system."
    fi

    # Extract the VERSION_ID from /etc/os-release.
    if [[ -f /etc/os-release ]]; then
        ver=$(grep "VERSION_ID" /etc/os-release | awk -F "=" '{print $2}' | tr -d '"')
    else
        logE "File /etc/os-release not found."
        ver="unknown"
    fi
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Raspbian version '%d' detected.\n" "$ver" >&2

    # Ensure the extracted version is not empty.
    if [[ -z "${ver:-}" ]]; then
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

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Check if the detected Raspberry Pi model is supported.
# @details Reads the Raspberry Pi model from /proc/device-tree/compatible and checks
#          it against a predefined list of supported models. Logs an error if the
#          model is unsupported or cannot be detected. Optionally outputs debug information
#          about all models if `debug` is set to `true`.
#
# @param $1 [Optional] "debug" to enable verbose output for all supported/unsupported models.
#
# @global SUPPORTED_MODELS Associative array of supported and unsupported Raspberry Pi models.
# @global log_message Function for logging messages.
# @global die Function to handle critical errors and terminate the script.
#
# @return None Exits the script with an error code if the architecture is unsupported.
#
# @example
# check_arch
# check_arch debug
# -----------------------------------------------------------------------------
check_arch() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local detected_model is_supported key full_name model chip this_model this_chip

    # Read and process the compatible string
    if ! detected_model=$(cat /proc/device-tree/compatible 2>/dev/null | tr '\0' '\n' | grep "raspberrypi" | sed 's/raspberrypi,//'); then
        die 1 "Failed to read or process /proc/device-tree/compatible. Ensure compatibility."
    fi

    # Check if the detected model is empty
    if [[ -z "${detected_model:-}" ]]; then
        die 1 "No Raspberry Pi model found in /proc/device-tree/compatible. This system may not be supported."
    fi
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Detected model: %s.\n" "$detected_model" >&2

    # Initialize is_supported flag
    is_supported=false

    # Iterate through supported models to check compatibility
    for key in "${!SUPPORTED_MODELS[@]}"; do
        IFS='|' read -r full_name model chip <<< "$key"
        if [[ "$model" == "$detected_model" ]]; then
            if [[ "${SUPPORTED_MODELS[$key]}" == "Supported" ]]; then
                is_supported=true
                this_model="$full_name"
                this_chip="$chip"
                [[ "$debug" == "debug" ]] && printf "[DEBUG] Model: '%s' (%s) is supported.\n" "$full_name" "$chip" >&2
            else
                die 1 "Model: '$full_name' ($chip) is not supported."
            fi
            break
        fi
    done

    # Debug output of all models if requested
    if [[ "$debug" == "debug" ]]; then
        # Arrays to hold supported and unsupported models
        declare -a supported_models=()
        declare -a unsupported_models=()

        # Group the models into supported and unsupported
        for key in "${!SUPPORTED_MODELS[@]}"; do
            IFS='|' read -r full_name model chip <<< "$key"
            if [[ "${SUPPORTED_MODELS[$key]}" == "Supported" ]]; then
                supported_models+=("$full_name ($chip)")
            else
                unsupported_models+=("$full_name ($chip)")
            fi
        done

        # Sort and print supported models
        if [[ ${#supported_models[@]} -gt 0 ]]; then
            printf "[DEBUG] Supported models:\n" >&2
            for model in $(printf "%s\n" "${supported_models[@]}" | sort); do
                printf "\t- %s\n" "$model" >&2
            done
        fi

        # Sort and print unsupported models
        if [[ ${#unsupported_models[@]} -gt 0 ]]; then
            printf "[DEBUG] Unsupported models:\n" >&2
            for model in $(printf "%s\n" "${unsupported_models[@]}" | sort); do
                printf "\t- %s\n" "$model" >&2
            done
        fi
    fi

    # Log an error if no supported model was found
    if [[ "$is_supported" == false ]]; then
        die 1 "Detected Raspberry Pi model '$detected_model' is not recognized or supported."
    fi


    [[ "$debug" == "debug" ]] && printf "[DEBUG] Model: '%s' (%s) is supported.\n" "$this_model" "$this_chip" >&2
    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Validate proxy connectivity by testing a known URL.
# @details Uses `check_url` to verify connectivity through the provided proxy settings.
#
# @param $1 [Optional] Proxy URL to validate (defaults to `http_proxy` or `https_proxy` if not provided).
# @param $2 [Optional] "debug" to enable verbose output for the proxy validation.
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
    # Check if debug flag or proxy_url is passed
    local debug=""
    local proxy_url=""
    # Check if proxy_url is the first argument (if set)
    if [[ -n "$1" && "$1" =~ ^https?:// ]]; then
        # First argument is proxy_url
        proxy_url="$1"
        shift  # Move to the next argument
    fi
    # Check if debug is the first argument
    if [[ "$1" == "debug" ]]; then
        debug="debug"
    fi
    # Debug setup
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Default to global proxy settings if no proxy is provided
    [[ -z "${proxy_url:-}" ]] && proxy_url="${http_proxy:-$https_proxy}"

    # Validate that a proxy is set
    if [[ -z "${proxy_url:-}" ]]; then
        logW "No proxy URL configured for validation."
        return 1
    fi

    logI "Validating proxy: $proxy_url"

    # Test the proxy connectivity using check_url (passing the debug flag)
    if check_url "$proxy_url" "curl" "--silent --head --max-time 10 --proxy $proxy_url" "$debug"; then
        logI "Proxy $proxy_url is functional."
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Proxy %s is functional.\n" "$proxy_url" >&2
        return 0
    else
        logE "Proxy $proxy_url is unreachable or misconfigured."
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Proxy %s failed validation.\n" "$proxy_url" >&2
        return 1
    fi
}

# -----------------------------------------------------------------------------
# @brief Check connectivity to a URL using a specified tool.
# @details Attempts to connect to a given URL with `curl` or `wget` based on the
#          provided arguments. Ensures that the tool's availability is checked
#          and handles timeouts gracefully. Optionally prints debug information
#          if the "debug" flag is set.
#
# @param $1 The URL to test.
# @param $2 The tool to use for the test (`curl` or `wget`).
# @param $3 Options to pass to the testing tool (e.g., `--silent --head` for `curl`).
# @param $4 [Optional] "debug" to enable verbose output during the check.
#
# @return 0 if the URL is reachable, 1 otherwise.
#
# @example
# check_url "http://example.com" "curl" "--silent --head" debug
# -----------------------------------------------------------------------------
check_url() {
    # Debug setup
    local debug="${4:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local url="$1"
    local tool="$2"
    local options="$3"

    # Validate inputs
    if [[ -z "${url:-}" ]]; then
        printf "ERROR: URL and tool parameters are required for check_url.\n" >&2
        return 1
    fi

    # Check tool availability
    if ! command -v "$tool" &>/dev/null; then
        printf "ERROR: Tool '%s' is not installed or unavailable.\n" "$tool" >&2
        return 1
    fi

    # Perform the connectivity check, allowing SSL and proxy errors
    local retval
    # shellcheck disable=2086
    if $tool $options "$url" &>/dev/null; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Successfully connected to %s using %s.\n" "$url" "$tool" >&2
        retval=0
    else
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Failed to connect to %s using %s.\n" "$url" "$tool" >&2
        retval=1
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Comprehensive internet and proxy connectivity check.
# @details Combines proxy validation and direct internet connectivity tests
#          using `check_url`. Validates proxy configuration first, then
#          tests connectivity with and without proxies. Outputs debug information if enabled.
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local primary_url="http://google.com"
    local secondary_url="http://1.1.1.1"
    local proxy_valid=false

    # Validate proxy settings
    if [[ -n "${http_proxy:-}" || -n "${https_proxy:-}" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Proxy detected. Validating proxy configuration.\n" >&2
        if validate_proxy "$debug"; then  # Pass debug flag to validate_proxy
            proxy_valid=true
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Proxy validation succeeded.\n" >&2
        else
            logW "Proxy validation failed. Proceeding with direct connectivity checks."
        fi
    fi

    # Check connectivity using curl
    if command -v curl &>/dev/null; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] curl is available. Testing internet connectivity using curl.\n" >&2

        # Check with proxy
        if $proxy_valid && curl --silent --head --max-time 10 --proxy "${http_proxy:-${https_proxy:-}}" "$primary_url" &>/dev/null; then
            logI "Internet is available using curl with proxy."
            [[ "$debug" == "debug" ]] && printf "[DEBUG] curl successfully connected via proxy.\n" >&2
            return 0
        fi

        # Check without proxy
        if curl --silent --head --max-time 10 "$primary_url" &>/dev/null; then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] curl successfully connected without proxy.\n" >&2
            return 0
        fi

        [[ "$debug" == "debug" ]] && printf "[DEBUG] curl failed to connect.\n" >&2
    else
        [[ "$debug" == "debug" ]] && printf "[DEBUG] curl is not available.\n" >&2
    fi

    # Check connectivity using wget
    if command -v wget &>/dev/null; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] wget is available. Testing internet connectivity using wget.\n" >&2

        # Check with proxy
        if $proxy_valid && wget --spider --quiet --timeout=10 --proxy="${http_proxy:-${https_proxy:-}}" "$primary_url" &>/dev/null; then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Internet is available using wget with proxy.\n" >&2
            [[ "$debug" == "debug" ]] && printf "[DEBUG] wget successfully connected via proxy.\n" >&2
            return 0
        fi

        # Check without proxy
        if wget --spider --quiet --timeout=10 "$secondary_url" &>/dev/null; then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Internet is available using wget without proxy.\n" >&2
            [[ "$debug" == "debug" ]] && printf "[DEBUG] wget successfully connected without proxy.\n" >&2
            return 0
        fi

        [[ "$debug" == "debug" ]] && printf "[DEBUG] wget failed to connect.\n" >&2
    else
        [[ "$debug" == "debug" ]] && printf "[DEBUG] wget is not available.\n" >&2
    fi

    # Final failure message
    logE "No internet connection detected after all checks."
    [[ "$debug" == "debug" ]] && printf "[DEBUG] All internet connectivity tests failed.\n" >&2
    return 1
}

# ############
# ### Logging Functions
# ############

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
    # Declare local variables at the start of the function
    local timestamp="$1"
    local level="$2"
    local color="$3"
    local lineno="$4"
    local message="$5"
    # Debug setup
    local debug="${5:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Skip logging if the message is empty
    if [[ -z "$message" ]]; then
        return
    fi

    # Log to file if required
    if [[ "$LOG_OUTPUT" == "file" || "$LOG_OUTPUT" == "both" ]]; then
        printf "%s [%s] [%s:%d] %s\\n" "$timestamp" "$level" "$THIS_SCRIPT" "$lineno" "$message" >> "$LOG_FILE"
    fi

    # Log to console if required and USE_CONSOLE is true
    if [[ "$USE_CONSOLE" == "true" && ("$LOG_OUTPUT" == "console" || "$LOG_OUTPUT" == "both") ]]; then
        printf "%b[%s] %s%b\\n" "$color" "$level" "$message" "$RESET"
    fi
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local timestamp
    local lineno

    # Generate the current timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Retrieve the line number of the caller
    lineno="${BASH_LINENO[2]}"

    # Pass debug flag to pad_with_spaces
    lineno=$(pad_with_spaces "$lineno" "$debug") # Pass debug flag

    # Debug message if debug flag is set, print to stderr
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Return the pipe-separated timestamp and line number
    printf "%s|%s\n" "$timestamp" "$lineno"
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
    # Ensure the calling function is log_message_with_severity()
    if [[ "${FUNCNAME[1]}" != "log_message_with_severity" ]]; then
        echo "[ERROR]: log_message() can only be called from log_message_with_severity()." >&2
        exit 1
    fi

    local level="UNSET"          # Default to "UNSET" if no level is provided
    local message="<no message>" # Default to "<no message>" if no message is provided
    local debug=""               # Default to empty string for debug

    local context timestamp lineno custom_level color severity config_severity
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"

    # Get level if it exists (must be one of the predefined values)
    if [[ -n "$1" && "$1" =~ ^(DEBUG|INFO|WARNING|ERROR|CRITICAL|EXTENDED)$ ]]; then
        level="$1"
        shift  # Move to the next argument
    fi

    # Get message if it exists and is not "debug"
    if [[ -n "$1" && "$1" != "debug" ]]; then
        message="$1"
        shift  # Move to the next argument
    fi

    # Get debug if it is specifically "debug"
    if [[ -n "$1" && "$1" == "debug" ]]; then
        debug="debug"
        shift  # Move to the next argument
    fi

    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Validate the log level and message if needed
    if [[ "$level" == "UNSET" || -z "${LOG_PROPERTIES[$level]:-}" || "$message" == "<no message>" ]]; then
        logE "Invalid log level '$level' or empty message."
        return 1
    fi

    # Prepare log context (timestamp and line number)
    context=$(prepare_log_context "$debug")  # Pass debug flag to sub-function
    IFS="|" read -r timestamp lineno <<< "$context"

    # Extract log properties for the specified level
    IFS="|" read -r custom_level color severity <<< "${LOG_PROPERTIES[$level]}"

    # Check if all three values (custom_level, color, severity) were successfully parsed
    if [[ -z "$custom_level" || -z "$color" || -z "$severity" ]]; then
        logE "Malformed log properties for level '$level'. Using default values."
        custom_level="UNSET"
        color="$RESET"
        severity=0
    fi

    # Extract severity threshold for the configured log level
    IFS="|" read -r _ _ config_severity <<< "${LOG_PROPERTIES[$LOG_LEVEL]}"

    # Check for valid severity level
    if [[ -z "$config_severity" || ! "$config_severity" =~ ^[0-9]+$ ]]; then
        logE "Malformed severity value for level '$LOG_LEVEL'."
        return 1
    fi

    # Skip logging if the message's severity is below the configured threshold
    if (( severity < config_severity )); then
        return 0
    fi

    # Call print_log_entry to handle actual logging (to file and console)
    print_log_entry "$timestamp" "$custom_level" "$color" "$lineno" "$message" "$debug"

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
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
    # Exit if the calling function is not one of the allowed ones.
    # shellcheck disable=2076
    if [[ ! "logD logI logW logE logC logX" =~ "${FUNCNAME[1]}" ]]; then
        echo "[ERROR]: Invalid calling function: ${FUNCNAME[1]}" >&2
        exit 1
    fi

    # Initialize variables
    local severity="$1"   # Level is always passed as the first argument to log_message_with_severity
    local message=""
    local extended_message=""
    local debug=""
    local func_name="${FUNCNAME[1]}"
    local caller_name="${FUNCNAME[2]}"
    local caller_line="${BASH_LINENO[1]}"

    # Process arguments
    if [[ -n "$2" ]]; then
        if [[ "$2" == "debug" ]]; then
            echo "[ERROR]: Empty message. The first argument cannot be 'debug'." >&2
            exit 1
        else
            message="$2"
        fi
    else
        echo "[ERROR]: Message is required." >&2
        exit 1
    fi

    if [[ -n "$3" ]]; then
        if [[ "$3" == "debug" ]]; then
            debug="debug"
        else
            extended_message="$3"
        fi
    fi

    if [[ -n "$4" && "$4" == "debug" ]]; then
        debug="debug"
    fi

    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Logging message at severity '%s' with message='%s'.\n" "$severity" "$message" >&2
    [[ "$debug" == "debug" ]] && [[ -n "$extended_message" ]] && printf "[DEBUG] Extended message: '%s'.\n" "$extended_message" >&2

    # Log the primary message
    log_message "$severity" "$message" "$debug"

    # Log the extended message if present
    if [[ -n "$extended_message" ]]; then
        logX "$extended_message" "$debug"
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
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
logI() { log_message_with_severity "INFO" "$1" "${2:-}" "${3:-}"; }
logW() { log_message_with_severity "WARNING" "$1" "${2:-}" "${3:-}"; }
logE() { log_message_with_severity "ERROR" "$1" "${2:-}" "${3:-}"; }
# shellcheck disable=2329
logC() { log_message_with_severity "CRITICAL" "$1" "${2:-}" "${3:-}"; }
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
    local scriptname="${THIS_SCRIPT%%.*}"  # Extract script name without extension
    local homepath log_dir fallback_log
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

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
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Checking if log directory '%s' exists and is writable.\n" "$log_dir" >&2

    if [[ -d "$log_dir" && -w "$log_dir" ]]; then
        # Attempt to create the log file
        if ! touch "$LOG_FILE" &>/dev/null; then
            logW "Cannot create log file: $LOG_FILE"
            log_dir="/tmp"
        else
            # Change ownership of the log file if possible
            if [[ -n "${SUDO_USER:-}" && "${REQUIRE_SUDO:-true}" == "true" ]]; then
                chown "$SUDO_USER:$SUDO_USER" "$LOG_FILE" &>/dev/null || logW "Failed to set ownership to SUDO_USER: $SUDO_USER"
            else
                chown "$(whoami):$(whoami)" "$LOG_FILE" &>/dev/null || logW "Failed to set ownership to current user: $(whoami)"
            fi
        fi
    else
        log_dir="/tmp"
    fi

    # Fallback to /tmp if the directory is invalid
    if [[ "$log_dir" == "/tmp" ]]; then
        fallback_log="/tmp/$scriptname.log"
        LOG_FILE="$fallback_log"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Falling back to log file in /tmp: %s\n" "$LOG_FILE" >&2
        logW "Falling back to log file in /tmp: $LOG_FILE"
    fi

    # Attempt to create the log file in the fallback location
    if ! touch "$LOG_FILE" &>/dev/null; then
        die 1 "Unable to create log file even in fallback location: $LOG_FILE"
    fi

    # Final debug message after successful log file setup
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Log file successfully created at: %s\n" "$LOG_FILE" >&2

    readonly LOG_FILE
    export LOG_FILE

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
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
    tput "$@" 2>/dev/null || printf "\n"  # Fallback to an empty string on error
}

# -----------------------------------------------------------------------------
# @brief Execute and combine complex terminal control sequences.
#
# @details This function executes `tput` commands and other shell commands
#          to create complex terminal control sequences. It supports commands
#          like moving the cursor, clearing lines, and resetting attributes.
#
# @param $@ Commands and arguments to evaluate (supports multiple commands).
#
# @return The resulting terminal control sequence or an empty string if unsupported.
# -----------------------------------------------------------------------------
# shellcheck disable=2329
generate_terminal_sequence() {
    local result
    # Execute the command and capture its output, suppressing errors.
    result=$("$@" 2>/dev/null || printf "\n")
    printf "%s" "$result"
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

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
    # shellcheck disable=2303
    readonly RESET BOLD SMSO RMSO UNDERLINE NO_UNDERLINE
    readonly BLINK NO_BLINK ITALIC NO_ITALIC MOVE_UP CLEAR_LINE
    readonly FGBLK FGRED FGGRN FGYLW FGBLU FGMAG FGCYN FGWHT FGRST FGGLD
    readonly BGBLK BGRED BGGRN BGYLW BGBLU BGMAG BGCYN BGWHT BGRST

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Generate a separator string for terminal output.
# @details Creates heavy or light horizontal rules based on terminal width.
#          Optionally outputs debug information if the debug flag is set.
#
# @param $1 Type of rule: "heavy" or "light".
# @param $2 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return The generated rule string or error message if an invalid type is provided.
#
# @example
# generate_separator "heavy"
# -----------------------------------------------------------------------------
generate_separator() {
    # Debug setup
    local debug="${2:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Normalize separator type to lowercase
    local type="${1,,}"
    local width="${COLUMNS:-80}"  # Default to 80 columns if $COLUMNS is not set

    # Validate separator type
    if [[ "$type" != "heavy" && "$type" != "light" ]]; then
        echo "[ERROR] Invalid separator type: '$1'. Must be 'heavy' or 'light'." >&2
        exit 1
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
            printf "[ERROR] Invalid separator type: %s\n" "$type" >&2
            return 1
            ;;
    esac

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Ensure LOG_LEVEL is a valid key in LOG_PROPERTIES
    if [[ -z "${LOG_PROPERTIES[$LOG_LEVEL]:-}" ]]; then
        # Print error message if LOG_LEVEL is invalid
        printf "[ERROR] Invalid LOG_LEVEL '%s'. Defaulting to 'INFO'.\n" "$LOG_LEVEL" >&2
        LOG_LEVEL="INFO"  # Default to "INFO"
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()', log level is %s.\n" "$func_name""$LOG_LEVEL" >&2
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
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Initialize terminal colors
    init_colors "$debug"

    # Initialize logging environment
    init_log "$debug"

    # Define log properties (severity, colors, and labels)
    declare -gA LOG_PROPERTIES=(
        ["DEBUG"]="DEBUG|${FGCYN}|0"
        ["INFO"]="INFO |${FGGRN}|1"
        ["WARNING"]="WARN |${FGYLW}|2"
        ["ERROR"]="ERROR|${FGMAG}|3"
        ["CRITICAL"]="CRIT |${FGRED}|4"
        ["EXTENDED"]="EXTD |${FGCYN}|0"
    )

    # Debug message for log properties initialization
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG] Log properties initialized:\n" >&2

        # Iterate through LOG_PROPERTIES to print each level with its color
        for level in "${!LOG_PROPERTIES[@]}"; do
            IFS="|" read -r custom_level color severity <<< "${LOG_PROPERTIES[$level]}"
            printf "[DEBUG] %s: %b%s%b\n" "$level" "$color" "$custom_level" "$RESET" >&2
        done
    fi

    # Validate the log level and log properties
    validate_log_level "$debug"

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Toggle the USE_CONSOLE variable on or off.
# @details This function updates the global USE_CONSOLE variable to either "true" (on)
#          or "false" (off) based on the input argument. It also prints debug messages
#          when the debug flag is passed.
#
# @param $1 The desired state: "on" (to enable console logging) or "off" (to disable console logging).
# @param $2 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global USE_CONSOLE The flag to control console logging.
#
# @return 0 on success, 1 on invalid input.
# -----------------------------------------------------------------------------
toggle_console_log() {
    # Declare local variables
    local state="${1,,}"      # Convert input to lowercase for consistency
    # Debug setup
    local debug="${2:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Validate $state
    if [[ "$state" != "on" && "$state" != "off" ]]; then
        warn "Invalid state: '$state'. Must be 'on' or 'off'." >&2
        return 1
    fi

    # Process the desired state
    case "$state" in
        on)
            USE_CONSOLE="true"
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Console logging enabled. USE_CONSOLE='%s', CONSOLE_STATE='%s'\n" "$USE_CONSOLE" "$CONSOLE_STATE" >&2
            ;;
        off)
            USE_CONSOLE="false"
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Console logging disabled. USE_CONSOLE='%s', CONSOLE_STATE='%s'\n" "$USE_CONSOLE" "$CONSOLE_STATE" >&2
            ;;
        *)
            printf "[ERROR] Invalid argument for toggle_console_log: %s\n" "$state" >&2
            return 1
            ;;
    esac

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

############
### Get Project Parameters Functions
############

# -----------------------------------------------------------------------------
# @brief Retrieve the Git owner or organization name from the remote URL.
# @details Attempts to dynamically fetch the Git repository's organization
#          name from the current Git process. If not available, uses the global
#          `$REPO_ORG` if set. If neither is available, returns "unknown".
#          Provides debugging output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global REPO_ORG If set, uses this as the repository organization.
#
# @return Prints the organization name if available, otherwise "unknown".
# @retval 0 Success: the organization name is printed.
# @retval 1 Failure: prints an error message to standard error if the organization cannot be determined.
# -----------------------------------------------------------------------------
get_repo_org() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local repo_org
    local url

    # Attempt to retrieve organization dynamically from local Git environment
    url=$(git config --get remote.origin.url 2>/dev/null)
    if [[ -n "$url" ]]; then
        # Extract the owner or organization name from the Git URL
        repo_org=$(printf "%s" "$url" | sed -E 's#(git@|https://)([^:/]+)[:/]([^/]+)/.*#\3#')
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Retrieved organization from local Git remote URL: %s\n" "$repo_org" >&2
    else
        printf "[ERROR] No remote origin URL retrieved.\n"
    fi

    # If the organization is still empty, use $REPO_ORG (if set)
    if [[ -z "$repo_org" && -n "$REPO_ORG" ]]; then
        repo_org="$REPO_ORG"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Using global REPO_ORG: %s\n" "$repo_org" >&2
    fi

    # If organization is still empty, return "unknown"
    if [[ -z "$repo_org" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Unable to determine organization. Returning 'unknown'.\n" >&2
        repo_org="unknown"
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    # Output the determined or fallback organization
    printf "%s\n" "$repo_org"
}

# -----------------------------------------------------------------------------
# @brief Retrieve the Git project name from the remote URL.
# @details Attempts to dynamically fetch the Git repository's name from the
#          current Git process. If not available, uses the global `$REPO_NAME`
#          if set. If neither is available, returns "unknown". Provides debugging
#          output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global REPO_NAME If set, uses this as the repository name.
#
# @return Prints the repository name if available, otherwise "unknown".
# @retval 0 Success: the repository name is printed.
# @retval 1 Failure: prints an error message to standard error if the repository name cannot be determined.
# -----------------------------------------------------------------------------
get_repo_name() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local repo_name="${REPO_NAME:-}"  # Use existing $REPO_NAME if set
    local url

    # Attempt to retrieve repository name dynamically from Git
    if [[ -z "$repo_name" ]]; then
        url=$(git config --get remote.origin.url 2>/dev/null)
        if [[ -n "$url" ]]; then
            # Extract the repository name and remove the ".git" suffix if present
            repo_name="${url##*/}"        # Remove everything up to the last `/`
            repo_name="${repo_name%.git}" # Remove the `.git` suffix
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Retrieved repository name from remote URL: %s\n" "$repo_name"
        fi
    fi

    # Use "unknown" if no repository name could be determined
    if [[ -z "$repo_name" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Unable to determine repository name. Returning 'unknown'.\n" >&2
        repo_name="unknown"
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    # Output the determined or fallback repository name
    printf "%s\n" "$repo_name"
}

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
    local repo_name="${1:-}"  # Input repository name
    # Debug setup
    local debug="${2:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local title_case  # Variable to hold the formatted name

    # Validate input
    if [[ -z "${repo_name:-}" ]]; then
        printf "[ERROR] Repository name cannot be empty.\n" >&2
        return 1
    fi
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Received repository name: %s\n" "$repo_name" >&2

    # Replace underscores and hyphens with spaces and convert to title case
    title_case=$(printf "%s" "$repo_name" | tr '_-' ' ' | awk '{for (i=1; i<=NF; i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

    local retval
    if [[ -n "${title_case:-}" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Converted repository name to title case: %s\n" "$title_case" >&2
        printf "%s\n" "$title_case"
        retval=0
    else
        printf "[ERROR] Failed to convert repository name to title case.\n" >&2
        retval=1
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2    # Debug log: function exit

    return "$retval"
}

# -----------------------------------------------------------------------------
# @brief Retrieve the current Git branch name or the branch this was detached from.
# @details Attempts to dynamically fetch the branch name from the current Git process.
#          If not available, uses the global `$GIT_BRCH` if set. If neither is available,
#          returns "unknown". Provides debugging output when the "debug" argument
#          is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global GIT_BRCH If set, uses this as the current Git branch name.
#
# @return Prints the branch name if available, otherwise "unknown".
# @retval 0 Success: the branch name is printed.
# @retval 1 Failure: prints an error message to standard error if the branch name cannot
#           be determined.
# -----------------------------------------------------------------------------
get_git_branch() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local branch="${GIT_BRCH:-}"  # Use existing $GIT_BRCH if set
    local detached_from

    # Attempt to retrieve branch name dynamically from Git
    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Retrieved branch name from Git: %s\n" "$branch" >&2
        elif [[ "$branch" == "HEAD" ]]; then
            # Handle detached HEAD state: attempt to determine the source
            detached_from=$(git reflog show --pretty='%gs' | grep -oE 'checkout: moving from [^ ]+' | head -n 1 | awk '{print $NF}')
            if [[ -n "$detached_from" ]]; then
                branch="$detached_from"
                [[ "$debug" == "debug" ]] && printf "[DEBUG] Detached HEAD state. Detached from branch: %s\n" "$branch" >&2
            else
                [[ "$debug" == "debug" ]] && printf "[DEBUG] Detached HEAD state. Cannot determine the source branch.\n" >&2
                branch="unknown"
            fi
        fi
    fi

    # Use "unknown" if no branch name could be determined
    if [[ -z "$branch" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Unable to determine Git branch. Returning 'unknown'.\n" >&2
        branch="unknown"
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    # Output the determined or fallback branch name
    printf "%s\n" "$branch"
    return 0
}

# -----------------------------------------------------------------------------
# @brief Get the most recent Git tag.
# @details Attempts to dynamically fetch the most recent Git tag from the current
#          Git process. If not available, uses the global `$GIT_TAG` if set. If
#          neither is available, returns "0.0.1". Provides debugging output when
#          the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global GIT_TAG If set, uses this as the most recent Git tag.
#
# @return Prints the tag name if available, otherwise "0.0.1".
# @retval 0 Success: the tag name is printed.
# -----------------------------------------------------------------------------
get_last_tag() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local tag

    # Attempt to retrieve the tag dynamically from Git
    tag=$(git describe --tags --abbrev=0 2>/dev/null)
    if [[ -n "$tag" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Retrieved tag from Git: %s\n" "$tag" >&2
    else
        [[ "$debug" == "debug" ]] && printf "[DEBUG] No tag obtained from local repo.\n" >&2
        # Try using GIT_TAG if it is set
        tag="${GIT_TAG:-}"
        # Fall back to "0.0.1" if both the local tag and GIT_TAG are unset
        if [[ -z "$tag" ]]; then
            tag="0.0.1"
            [[ "$debug" == "debug" ]] && printf "[DEBUG] No local tag and GIT_TAG is unset. Using fallback: %s\n" "$tag" >&2
        else
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Using pre-assigned GIT_TAG: %s\n" "$tag" >&2
        fi
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    # Output the tag
    printf "%s\n" "$tag"
}

# -----------------------------------------------------------------------------
# @brief Check if a tag follows semantic versioning.
# @details Validates if a given Git tag follows the semantic versioning format
#          (major.minor.patch). Provides debugging output when the "debug" argument
#          is passed.
#
# @param $1 The Git tag to validate.
# @param $2 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return Prints "true" if the tag follows semantic versioning, otherwise "false".
# @retval 0 Success: the validation result is printed.
# @retval 1 Failure: prints an error message to standard error if no tag is provided.
# -----------------------------------------------------------------------------
is_sem_ver() {
    local tag="${1:-}"

    # Debug setup
    local debug="${2:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Validate input
    if [[ -z "${tag:-}" ]]; then
        printf "[ERROR] Tag cannot be empty.\n" >&2
        return 1
    fi

    [[ "$debug" == "debug" ]] && printf "[DEBUG] Validating tag: %s\n" "$tag" >&2

    # Check if the tag follows the semantic versioning format
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Tag %s follows semantic versioning.\n" "$tag" >&2
        printf "true\n"
    else
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Tag %s does not follow semantic versioning.\n" "$tag" >&2
        printf "false\n"
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Get the number of commits since the last tag.
# @details Counts commits since the provided Git tag using `git rev-list`. If
#          no tag is found, defaults to `0` commits. Debug messages are sent
#          only to `stderr`.
#
# @param $1 The Git tag to count commits from.
# @param $2 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return The number of commits since the tag, or 0 if the tag does not exist.
# -----------------------------------------------------------------------------
get_num_commits() {
    local tag="${1:-}"
    local debug="${2:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    if [[ -z "$tag" || "$tag" == "0.0.1" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] No valid tag provided. Assuming 0 commits.\n" >&2
        printf "0\n"
        return
    fi

    local commit_count
    commit_count=$(git rev-list --count "${tag}..HEAD" 2>/dev/null || echo 0)

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    printf "%s\n" "$commit_count"
}

# -----------------------------------------------------------------------------
# @brief Get the short hash of the current Git commit.
# @details Retrieves the short hash of the current Git commit. Provides debugging
#          output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return Prints the short hash of the current Git commit.
# @retval 0 Success: the short hash is printed.
# @retval 1 Failure: prints an error message to standard error if unable to retrieve the hash.
# -----------------------------------------------------------------------------
get_short_hash() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local short_hash
    short_hash=$(git rev-parse --short HEAD 2>/dev/null)
    if [[ -z "$short_hash" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] No short hash available. Using 'unknown'.\n" >&2
        short_hash="unknown"
    else
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Short hash of the current commit: %s\n" "$short_hash" >&2
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    printf "%s\n" "$short_hash"
}

# -----------------------------------------------------------------------------
# @brief Check if there are uncommitted changes in the working directory.
# @details Checks for uncommitted changes in the current Git repository.
#          Provides debugging output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return Prints "true" if there are uncommitted changes, otherwise "false".
# @retval 0 Success: the dirty state is printed.
# @retval 1 Failure: prints an error message to standard error if unable to determine the repository state.
# -----------------------------------------------------------------------------
get_dirty() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local changes

    # Check for uncommitted changes in the repository
    changes=$(git status --porcelain 2>/dev/null)

    if [[ -n "${changes:-}" ]]; then
        printf "true\n"
    else

        printf "false\n"
    fi

    if [[ -n "$changes" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Changes detected..\n" >&2
    else
        [[ "$debug" == "debug" ]] && printf "[DEBUG] No changes detected.\n" >&2
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Generate a version string based on the state of the Git repository.
# @details Constructs a semantic version string using the most recent Git tag,
#          current branch name, number of commits since the tag, the short hash
#          of the latest commit, and whether the working directory is dirty.
#          Provides debugging output when the "debug" argument is passed.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @return Prints the generated semantic version string.
# @retval 0 Success: the semantic version string is printed.
# @retval 1 Failure: prints an error message to standard error if any required
#         Git information cannot be determined.
# -----------------------------------------------------------------------------
get_sem_ver() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    local tag branch_name num_commits short_hash dirty version_string

    # Retrieve the most recent tag
    tag=$(get_last_tag "$debug")
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Received tag: from get_last_tag().\n" "$tag" >&2
    if [[ -z "$tag" || "$tag" == "0.0.1" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] No semantic version tag found (or version is 0.0.1). Using default: 0.0.1\n" >&2
        version_string="0.0.1"
    else
        version_string="$tag"
    fi

    # Append branch name
    branch_name=$(get_git_branch "$debug")
    version_string="$version_string-$branch_name"
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Appended branch name to version: %s\n" "$branch_name" >&2

    # Append number of commits since the last tag
    num_commits=$(get_num_commits "$tag" "$debug")
    if [[ "$num_commits" -gt 0 ]]; then
        version_string="$version_string+$num_commits"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Appended commit count to version: %s\n" "$num_commits" >&2
    fi

    # Append short hash of the current commit
    short_hash=$(get_short_hash "$debug")
    version_string="$version_string.$short_hash"
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Appended short hash to version: %s\n" "$short_hash" >&2

    # Check if the repository is dirty
    dirty=$(get_dirty "$debug")
    if [[ "$dirty" == "true" ]]; then
        version_string="$version_string-dirty"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Repository is dirty. Appended '-dirty' to version.\n" >&2
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()', SEM_VER is %s.\n" "$func_name" "$version_string" >&2

    printf "%s\n" "$version_string"
}

# -----------------------------------------------------------------------------
# @brief Configure local or remote mode based on the Git repository context.
# @details Sets relevant variables for local mode if `USE_LOCAL` is `true` and
#          the script is being executed from within a GitHub repository
#          (`IS_GITHUB_REPO` is `true`). Defaults to remote configuration if not
#          in local mode or when the combined check fails.
#
# @param $1 [Optional] Pass "debug" to enable verbose debugging output.
#
# @global USE_LOCAL           Indicates whether local mode is enabled.
# @global IS_GITHUB_REPO      Indicates whether the script resides in a GitHub repository.
# @global THIS_SCRIPT         Name of the current script.
# @global REPO_ORG            Git organization or owner name.
# @global REPO_NAME           Git repository name.
# @global GIT_BRCH            Current Git branch name.
# @global GIT_TAG             Generated semantic version string.
# @global LOCAL_SOURCE_DIR    Path to the root of the local repository.
# @global LOCAL_WWW_DIR       Path to the `data` directory in the repository.
# @global LOCAL_SCRIPTS_DIR   Path to the `scripts` directory in the repository.
# @global GIT_RAW             URL for accessing raw files remotely.
# @global GIT_API             URL for accessing the repository API.
#
# @throws Exits with a critical error if the combined check fails in local mode.
#
# @return None
# -----------------------------------------------------------------------------
get_proj_params() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    if [[ "$USE_LOCAL" == "true" && "$IS_GITHUB_REPO" == "true" ]]; then
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Configuring local mode with GitHub repository context.\n" >&2

        # Making sure THIS_SCRIPT is right
        THIS_SCRIPT=$(basename "$0")
        [[ "$debug" == "debug" ]] && printf "[DEBUG] THIS_SCRIPT set to: %s\n" "$THIS_SCRIPT" >&2

        # Retrieve repository details
        REPO_ORG=$(get_repo_org "${debug}") || { printf "[ERROR] Failed to retrieve repository organization.\n" >&2; exit 1; }
        [[ "$debug" == "debug" ]] && printf "[DEBUG] REPO_ORG set to: %s\n" "$REPO_ORG" >&2

        REPO_NAME=$(get_repo_name "${debug}") || { printf "[ERROR] Failed to retrieve repository name.\n" >&2; exit 1; }
        [[ "$debug" == "debug" ]] && printf "[DEBUG] REPO_NAME set to: %s\n" "$REPO_NAME" >&2

        GIT_BRCH=$(get_git_branch "${debug}") || { printf "[ERROR] Failed to retrieve current branch name.\n" >&2; exit 1; }
        [[ "$debug" == "debug" ]] && printf "[DEBUG] GIT_BRCH set to: %s\n" "$GIT_BRCH" >&2

        GIT_TAG=$(get_last_tag "${debug}") || { printf "[ERROR] Failed to retrieve current Git tag.\n" >&2; exit 1; }
        [[ "$debug" == "debug" ]] && printf "[DEBUG] GIT_TAG set to: %s\n" "$GIT_TAG" >&2

        SEM_VER=$(get_sem_ver "${debug}") || { printf "[ERROR] Failed to generate semantic version.\n" >&2; exit 1; }
        [[ "$debug" == "debug" ]] && printf "[DEBUG] SEM_VER set to: %s\n" "$SEM_VER" >&2

        # Get the root directory of the repository
        LOCAL_SOURCE_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
        if [[ -z "${LOCAL_SOURCE_DIR:-}" ]]; then
            printf "[ERROR] Not inside a valid Git repository. Ensure the repository is properly initialized.\n" >&2
            exit 1
        fi
        [[ "$debug" == "debug" ]] && printf "[DEBUG] LOCAL_SOURCE_DIR set to: %s\n" "$LOCAL_SOURCE_DIR" >&2

        # Set local script path based on repository structure
        LOCAL_WWW_DIR="$LOCAL_SOURCE_DIR/data"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] LOCAL_WWW_DIR set to: %s\n" "$LOCAL_WWW_DIR" >&2

        # Set local web page path based on repository structure
        LOCAL_SCRIPTS_DIR="$LOCAL_SOURCE_DIR/scripts"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] LOCAL_SCRIPTS_DIR set to: %s\n" "$LOCAL_SCRIPTS_DIR" >&2
    else
        # Configure remote access URLs
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Configuring remote mode.\n" >&2
        if [[ -z "${REPO_ORG:-}" || -z "${REPO_NAME:-}" ]]; then
            printf "[ERROR] Remote mode requires REPO_ORG and REPO_NAME to be set.\n" >&2
            exit 1
        fi
        GIT_RAW="https://raw.githubusercontent.com/$REPO_ORG/$REPO_NAME"
        GIT_API="https://api.github.com/repos/$REPO_ORG/$REPO_NAME"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] GIT_RAW set to: %s\n" "$GIT_RAW" >&2
        [[ "$debug" == "debug" ]] && printf "[DEBUG] GIT_API set to: %s\n" "$GIT_API" >&2
    fi

    # Export global variables for further use
    export THIS_SCRIPT REPO_ORG REPO_NAME GIT_BRCH GIT_TAG LOCAL_SOURCE_DIR
    export LOCAL_WWW_DIR LOCAL_SCRIPTS_DIR GIT_RAW GIT_API

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# ############
# ### Install Functions
# ############

# -----------------------------------------------------------------------------
# @brief Start the script, with optional timeout for non-interactive environments.
# @details Allows users to press a key to proceed, or defaults after 10 seconds.
#          If the debug flag is provided, additional information about the process
#          will be printed.
#
# @param $1 [Optional] Debug flag to enable detailed output (true/false).
#
# @global TERSE Indicates terse mode (skips interactive messages).
# @global REPO_NAME The name of the repository being installed.
#
# @return None
#
# @example
# start_script debug
# -----------------------------------------------------------------------------
start_script() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Check terse mode
    if [[ "${TERSE:-false}" == "true" ]]; then
        logI "$(repo_to_title_case "${REPO_NAME:-Unknown}") installation beginning."
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Skipping interactive message due to terse mode.\n" >&2
        return
    fi

    # Prompt user for input
    printf "\nStarting installation for: %s.\n" "$(repo_to_title_case "${REPO_NAME:-Unknown}")"
    printf "Press any key to continue or 'Q' to quit (defaulting in 10 seconds).\n"

    # Read a single key with a 10-second timeout
    if ! read -n 1 -sr -t 10 key < /dev/tty; then
        key=""  # Assign a default value on timeout
    fi
    printf "\n"

    # Handle user input
    case "${key}" in
        [Qq])  # Quit
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Quit key pressed. Ending installation.\n" "$key" >&2
            logI "Installation canceled by user."
            exit_script "Script canceled"
            ;;
        "")  # Timeout or Enter
            [[ "$debug" == "debug" ]] && printf "[DEBUG] No key pressed, proceeding with installation.\n" >&2
            ;;
        *)  # Any other key
            [[ "$debug" == "debug" ]] && printf "[DEBUG] Key pressed: '%s'. Proceeding with installation.\n" "$key" >&2
            ;;
    esac

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Sets the system timezone interactively or logs if already set.
# @details If the current timezone is not GMT or BST, logs the current date and time,
#          and exits. Otherwise, prompts the user to confirm or reconfigure the timezone.
#          If the debug flag is passed, additional information about the process is logged.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable detailed output.
#
# @global TERSE Indicates terse mode (skips interactive messages).
#
# @return None Logs the current timezone or adjusts it if necessary.
#
# @example
# set_time debug
# -----------------------------------------------------------------------------
set_time() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Declare local variables
    local need_set=false
    local current_date tz yn

    # Get the current date and time
    current_date="$(date)"
    tz="$(date +%Z)"

    # Log and return if the timezone is not GMT or BST
    if [ "$tz" != "GMT" ] && [ "$tz" != "BST" ]; then
        need_set=true
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Timezone is neither GMT nor BST: $tz\n" >&2
        return
    fi

    # Check if the script is in terse mode
    if [[ "$TERSE" == "true" && "$need_set" == "true" ]]; then
        logW "Timezone detected as $tz, which may need to be updated."
        return
    else
        logI "Timezone detected as $tz."
    fi

    # Inform the user about the current date and time
    logI "Timezone detected as $tz, which may need to be updated."

    # Prompt for confirmation or reconfiguration
    while true; do
        read -rp "Is this correct? [y/N]: " yn < /dev/tty
        case "$yn" in
            [Yy]*)
                logI "Timezone confirmed on $current_date"
                [[ "$debug" == "debug" ]] && printf "[DEBUG] Timezone confirmed on: $current_date\n" >&2
                break
                ;;
            [Nn]* | *)
                dpkg-reconfigure tzdata
                logI "Timezone reconfigured on $current_date"
                [[ "$debug" == "debug" ]] && printf "[DEBUG] Timezone reconfigured on: $current_date\n" >&2
                break
                ;;
        esac
    done

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

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
exec_new_shell() {
    local exec_name="${1:-Unnamed Operation}"
    local exec_process="${2:-true}"
    local debug="${3:-}"

    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"

    # Validate debug flag
    if [[ -n "$debug" && "$debug" != "debug" ]]; then
        warn "Invalid debug flag: '$debug'. Use 'debug' or leave blank."
        debug=""
    fi

    # Debug information
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2
    [[ "$debug" == "debug" ]] && printf "[DEBUG] exec_name: %s\n" "$exec_name" >&2
    [[ "$debug" == "debug" ]] && printf "[DEBUG] exec_process: %s\n" "$exec_process" >&2

    # Simulate command execution if DRY_RUN is enabled
    if [[ -n "$DRY_RUN" ]]; then
        printf "[✔] Simulating: '%s'.\n" "$exec_process"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Dry-run simulation complete: '%s'.\n" "$exec_process" >&2
        exit_script
    fi

    # Validate the command
    if [[ "$exec_process" == "true" || "$exec_process" == "" ]]; then
        printf "[✔] Running: '%s'.\n" "$exec_process"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Executing command: '%s' in function '%s()' at line %s.\n" "$exec_process" "$func_name" "$caller_line" >&2
        exec true
    elif ! command -v "${exec_process%% *}" >/dev/null 2>&1; then
        warn "'$exec_process' is not a valid command or executable."
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()' at line %s.\n" "$func_name" "$caller_line" >&2
        die 1 "Invalid command: '$exec_process'"
    else
        # Execute the actual command
        printf "[✔] Running: '%s'.\n" "$exec_process"
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Executing command: '%s' in function '%s()' at line %s.\n" "$exec_process" "$func_name" "$caller_line" >&2
        exec $exec_process || die 1 "Command '${exec_process}' failed"
    fi
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
exec_command() {
    local exec_name="$1"
    local exec_process="$2"
    local debug="${3:-}"

    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"

    # Validate debug flag
    if [[ -n "$debug" && "$debug" != "debug" ]]; then
        warn "Invalid debug flag: '$debug'. Use 'debug' or leave blank."
        debug=""
    fi

    # Debug information
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2
    [[ "$debug" == "debug" ]] && printf "[DEBUG] exec_name: %s\n" "$exec_name" >&2
    [[ "$debug" == "debug" ]] && printf "[DEBUG] exec_process: %s\n" "$exec_process" >&2

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

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    return $status
}

# -----------------------------------------------------------------------------
# @brief Installs or upgrades all packages in the APT_PACKAGES list.
# @details Updates the package list and resolves broken dependencies before proceeding.
#          Accumulates errors for each failed package and logs a summary at the end.
#          Skips execution if the APT_PACKAGES array is empty.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable detailed output.
#
# @global APT_PACKAGES List of packages to install or upgrade.
#
# @return 0 if all operations succeed, 1 if any operation fails.
#
# @example
# handle_apt_packages debug
# -----------------------------------------------------------------------------
handle_apt_packages() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Check if APT_PACKAGES is empty
    if [[ ${#APT_PACKAGES[@]} -eq 0 ]]; then
        logI "No packages specified in APT_PACKAGES. Skipping package handling."
        [[ "$debug" == "debug" ]] && printf "[DEBUG] APT_PACKAGES is empty, skipping execution.\n" >&2
        return 0
    fi

    local package error_count=0  # Counter for failed operations

    logI "Updating and managing required packages (this may take a few minutes)."

    # Update package list and fix broken installs
    if ! exec_command "Update local package index" "sudo apt-get update -y" "$debug"; then
        logE "Failed to update package list."
        ((error_count++))
    fi
    if ! exec_command "Fixing broken or incomplete package installations" "sudo apt-get install -f -y" "$debug"; then
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
        [[ "$debug" == "debug" ]] && printf "[DEBUG] APT package handling completed with $error_count errors.\n" >&2
    else
        logI "APT package handling completed successfully."
        [[ "$debug" == "debug" ]] && printf "[DEBUG] APT package handling completed successfully.\n" >&2
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    return $error_count
}

# -----------------------------------------------------------------------------
# @brief End the script with optional feedback based on logging configuration.
# @details Provides a clear message to indicate the script completed successfully.
#          If the debug flag is passed, additional debug information will be logged.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global REBOOT Indicates if a reboot is required.
# @global USE_CONSOLE Controls whether console output is enabled.
#
# @return None
#
# @example
# finish_script debug
# -----------------------------------------------------------------------------
finish_script() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    if [[ "$TERSE" == "true" || "$TERSE" != "true" ]]; then
        logI "Installation complete: $(repo_to_title_case "$REPO_NAME")."
        [[ "$debug" == "debug" ]] && printf "[DEBUG] Installation complete message logged.\n" >&2
    fi

    # Clear screen (optional if required)
    if [[ "$TERSE" == "true" ]]; then
        # clear
        printf "Installation complete: %s.\n" "$(repo_to_title_case "$REPO_NAME")"
    fi

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Exit the script gracefully.
# @details Logs a provided exit message or uses a default message and exits with
#          a status code of 0. If the debug flag is set to "debug," it outputs
#          additional debug information.
#
# @param $1 [Optional] Message to log before exiting. Defaults to "Exiting."
# @param $2 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @return None
#
# @example
# exit_script "Finished processing successfully." debug
# -----------------------------------------------------------------------------
exit_script() {
    local message
    local debug
    if [[ -z "${1:-}" ]]; then
        message="Exiting"
    elif [[ "${1:-}" == "debug" ]]; then
        debug="debug"
    else
        message="$1"
        debug="${2:-}"  # Optional debug flag, defaults to an empty string if not provided
    fi
    # Debug setup
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    message=$(remove_dot "$message")
    printf "%s\n" "$message"  # Log the provided or default message

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2

    exit 0
}

# ############
# ### Arguments Functions
# ############

# -----------------------------------------------------------------------------
# @brief Define script options and their properties.
# @details Each option includes its long form, short form, and description.
#
# @global OPTIONS Associative array of script options and their properties.
#
# @return None
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
# @brief Display script usage.
# @details Generates usage dynamically based on the `OPTIONS` associative array.
#          If the debug flag is set to "debug," a simple debug message will be printed.
#
# @param $1 [Optional] Debug flag. Pass "debug" to enable debug output.
#
# @global THIS_SCRIPT The name of the script.
# @global OPTIONS Associative array of script options and their properties.
#
# @return None
#
# @example
# usage debug
# -----------------------------------------------------------------------------
usage() {
    # Debug setup
    local debug="${1:-}"  # Optional debug flag, defaults to an empty string if not provided
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Display the script usage
    printf "Usage: %s [options]\n\n" "$THIS_SCRIPT"
    printf "Options:\n"
    for key in "${!OPTIONS[@]}"; do
        printf "  %s: %s\n" "$key" "${OPTIONS[$key]}"
    done

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Parse command-line arguments.
# @details Processes the arguments passed to the script. Uses the `OPTIONS` array
#          for validation and handling. Supports debug mode to log the parsing
#          process and resulting variable values.
#
# @param "$@" The command-line arguments passed to the script.
#
# @global DRY_RUN Updates the dry-run status based on input.
# @global LOG_FILE Updates the log file path based on input.
# @global LOG_LEVEL Updates the log verbosity level based on input.
# @global TERSE Enables terse output mode if specified.
# @global USE_CONSOLE Enables console output if specified.
#
# @return None
#
# @example
# parse_args debug --dry-run --log-file mylog.txt
# parse_args --dry-run --log-file mylog.txt debug
# -----------------------------------------------------------------------------
parse_args() {
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    local debug=""

    # Check for the "debug" argument anywhere
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            break
        fi
    done
    debug="${debug:-}"
    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Process the arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-d)
                DRY_RUN=true
                [[ "$debug" == "debug" ]] && printf "[DEBUG] DRY_RUN set to 'true'\n" >&2
                shift
                ;;
            --version|-v)
                print_version "$debug"
                exit 0
                ;;
            --help|-h)
                usage "$debug"
                exit 0
                ;;
            --log-file|-f)
                if [[ -n "$2" && "$2" != -* ]]; then
                    LOG_FILE=$(realpath -m "$2" 2>/dev/null)
                    [[ "$debug" == "debug" ]] && printf "[DEBUG] LOG_FILE set to '%s'\n" "$LOG_FILE" >&2
                    shift 2 # Shift past the option and its value
                else
                    printf "[ERROR] Option '%s' requires an argument.\n" "$1" >&2
                    exit 1
                fi
                ;;
            --log-level|-l)
                if [[ -n "$2" && "$2" != -* ]]; then
                    LOG_LEVEL="$2"
                    [[ "$debug" == "debug" ]] && printf "[DEBUG] LOG_LEVEL set to '%s'\n" "$LOG_LEVEL" >&2
                    shift 2 # Shift past the option and its value
                else
                    printf "[ERROR] Option '%s' requires an argument.\n" "$1" >&2
                    exit 1
                fi
                ;;
            --terse|-t)
                TERSE="true"
                [[ "$debug" == "debug" ]] && printf "[DEBUG] TERSE set to 'true'\n" >&2
                shift
                ;;
            --console|-c)
                USE_CONSOLE="true"
                [[ "$debug" == "debug" ]] && printf "[DEBUG] USE_CONSOLE set to 'true'\n" >&2
                shift
                ;;
            *)
                if [[ -n "${1-}" ]]; then
                    printf "[ERROR] Unknown option: %s\n" "$1" >&2
                else
                    printf "[ERROR] No option provided.\n" >&2
                fi
                usage "$debug"
                exit 1
                ;;
        esac
    done

    # Debug: Final parsed values
    if [[ "$debug" == "debug" ]]; then
        printf "[DEBUG] Final parsed values:\n" >&2
        printf "\t- DRY_RUN='%s'\n\t- LOG_FILE='%s'\n\t- LOG_LEVEL='%s'\n\t- TERSE='%s'\n\t- USE_CONSOLE='%s'\n" \
            "${DRY_RUN:-false}" "${LOG_FILE:-None}" "${LOG_LEVEL:-None}" "${TERSE:-false}" "${USE_CONSOLE:-false}" >&2
    fi

    # Debug: Function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# ############
# ### AP-Config Functions
# ############

#
# ### AP-Config Core Functions
#

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
#   .
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
            printf "Password updated. Attempting to connect to %s.\n" "$existing_profile"
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

#
# ### AP-Config Menu Functions
#

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

#
# ### AP-Config GitHub Functions
#

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

    logI "Changing ownership of '$file' to '$owner'."
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

# TODO: Git clone

#
# ### AP-Config Install Functions
#



# ############
# ### Main Functions
# ############

# -----------------------------------------------------------------------------
# @brief The main entry point for the script.
# @details This function orchestrates the execution of the script by invoking
#          a series of functions to check the environment, validate dependencies,
#          and perform the main tasks. Debugging can be enabled by passing the
#          `debug` argument.
#
# @param $@ Command-line arguments. If `debug` is included, debug mode is enabled.
#
# @global None
#
# @return None
#
# @example
# ./apconfig.sh              # Run the script normally.
# ./apconfig.sh debug        # Run the script in debug mode.
# -----------------------------------------------------------------------------
main() {
    # Debug setup
    local func_name="${FUNCNAME[0]}"
    local caller_name="${FUNCNAME[1]}"
    local caller_line="${BASH_LINENO[0]}"
    local debug=""  # Debug flag, default to an empty string

    # Check for the "debug" argument
    for arg in "$@"; do
        if [[ "$arg" == "debug" ]]; then
            debug="debug"
            break
        fi
    done

    # Print debug information if the flag is set
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Function '%s()' called by '%s()' at line %s.\n" "$func_name" "$caller_name" "$caller_line" >&2

    # Check and set up the environment
    handle_execution_context "$debug"  # Get execution context and set environment variables
    get_proj_params "$debug"           # Get project and git parameters
    parse_args "$@"                    # Parse command-line arguments
    enforce_sudo "$debug"              # Ensure proper privileges for script execution
    validate_depends "$debug"          # Ensure required dependencies are installed
    validate_sys_accs "$debug"         # Verify critical system files are accessible
    validate_env_vars "$debug"         # Check for required environment variables
    setup_log "$debug"                 # Setup logging environment
    check_bash "$debug"                # Ensure the script is executed in a Bash shell
    check_sh_ver "$debug"              # Verify the Bash version meets minimum requirements
    check_bitness "$debug"             # Validate system bitness compatibility
    check_release "$debug"             # Check Raspbian OS version compatibility
    check_arch "$debug"                # Validate Raspberry Pi model compatibility
    check_internet "$debug"            # Verify internet connectivity if required

    # Print/display the environment
    print_system "$debug"              # Log system information
    print_version "$debug"             # Log the script version

    # Run installer steps
    start_script "$debug"              # Start the script with instructions
    set_time "$debug"                  # Offer to change timezone if default
    handle_apt_packages "$debug"       # Perform APT maintenance and install/update packages


    menu

    #
    # ### AP-Config Functions^
    #

    finish_script "$debug"             # Finish the script with final instructions

    # Debug log: function exit
    [[ "$debug" == "debug" ]] && printf "[DEBUG] Exiting function '%s()'.\n" "$func_name" >&2
}

# -----------------------------------------------------------------------------
# @brief Entry point for the script execution.
# @details Calls the `main` function with all passed command-line arguments.
#          Upon completion, exits with the status returned by `main`.
#
# @param $@ All command-line arguments passed to the script.
#
# @return The exit status code of the `main` function.
#
# @example
# ./apconfig.sh debug
# -----------------------------------------------------------------------------
main "$@"
exit $?
