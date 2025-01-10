#!/bin/bash

# -----------------------------------------------------------------------------
# @brief Test script for validating the installation process.
# -----------------------------------------------------------------------------

MODE="${1:-install}" # Default mode is "install"

# -----------------------------------------------------------------------------
# Source the installer script to access its functions and variables
# -----------------------------------------------------------------------------
echo "Running installation validation tests..."
if [[ -f ./install.sh ]]; then
    # Attempt to source the installer script
    source ./install.sh || {
        printf "❌ Error: Failed to source 'install.sh'. Ensure the file exists and is accessible.\n"
        exit 1
    }

    # Debug message after successful sourcing
    if declare -f debug_print >/dev/null 2>&1; then
        printf "✅ Successfully sourced 'install.sh' in test.sh\n"
    fi
else
    printf "❌ Error: 'install.sh' not found in the current directory.\n"
    exit 1
fi

# Check functions
check_file_not_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        echo "❌ Error: File '$file' should not exist."
        return 1
    fi
    echo "✅ File '$file' does not exist."
}

check_dir_not_exists() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        echo "❌ Error: Directory '$dir' should not exist."
        return 1
    fi
    echo "✅ Directory '$dir' does not exist."
}

check_service_removed() {
    local service_path="$1"

    # Extract the service name from the provided path
    local service_name
    service_name="$(basename "$service_path")"

    # Check if the service file is removed
    if [[ -f "$service_path" ]]; then
        echo "❌ Error: Service file '$service_path' should not exist."
        return 1
    fi
    echo "✅ Service file '$service_path' is removed."

    # Check if the service is disabled and not active
    if systemctl is-active --quiet "$service_name" || systemctl is-enabled --quiet "$service_name"; then
        echo "❌ Error: Service '$service_name' is still active or enabled."
        return 1
    fi
    echo "✅ Service '$service_name' is disabled and inactive."
}

# Check functions
check_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "❌ Error: File '$file' not found."
        return 1
    fi
    echo "✅ File '$file' exists."
}

check_dir_exists() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "❌ Error: Directory '$dir' not found."
        return 1
    fi
    echo "✅ Directory '$dir' exists."
}

check_file_permissions() {
    local file="$1"
    local expected_permissions="$2"

    if [[ ! -e "$file" ]]; then
        echo "❌ Error: File '$file' does not exist for permissions check."
        return 1
    fi

    local actual_permissions
    actual_permissions=$(stat -c "%a" "$file")
    if [[ "$actual_permissions" != "$expected_permissions" ]]; then
        echo "❌ Error: File '$file' permissions are '$actual_permissions', expected '$expected_permissions'."
        return 1
    fi
    echo "✅ File '$file' has correct permissions ($actual_permissions)."
}

check_ownership() {
    local path="$1"
    local expected_user="$2"
    local expected_group="$3"

    if [[ ! -e "$path" ]]; then
        echo "❌Error: Path '$path' does not exist for ownership check."
        return 1
    fi

    local actual_user actual_group
    actual_user=$(stat -c "%U" "$path")
    actual_group=$(stat -c "%G" "$path")

    if [[ "$actual_user" != "$expected_user" || "$actual_group" != "$expected_group" ]]; then
        echo "❌ Error: Ownership of '$path' is '$actual_user:$actual_group', expected '$expected_user:$expected_group'."
        return 1
    fi
    echo "✅ Ownership of '$path' is correct ($actual_user:$actual_group)."
}

check_dir_permissions() {
    local dir="$1"
    local expected_permissions="$2"

    if [[ ! -d "$dir" ]]; then
        echo "❌ Error: Directory '$dir' does not exist for permissions check."
        return 1
    fi

    local actual_permissions
    actual_permissions=$(stat -c "%a" "$dir")
    if [[ "$actual_permissions" != "$expected_permissions" ]]; then
        echo "❌ Error: Directory '$dir' permissions are '$actual_permissions', expected '$expected_permissions'."
        return 1
    fi
    echo "✅ Directory '$dir' has correct permissions ($actual_permissions)."
}

# Check if a package exists
check_if_package_exists() {
    local package="$1"
    if command -v dpkg >/dev/null 2>&1; then
        if ! dpkg -l "$package" >/dev/null 2>&1; then
            echo "❌ Error: Package '$package' is not installed."
            return 1
        fi
    elif command -v rpm >/dev/null 2>&1; then
        if ! rpm -q "$package" >/dev/null 2>&1; then
            echo "❌ Error: Package '$package' is not installed."
            return 1
        fi
    else
        echo "❌ Error: Package manager not supported. Cannot check '$package'."
        return 1
    fi
    echo "✅ Package '$package' is installed."
}

# Check if a man page exists and is accessible
check_man_page() {
    local man_file="$1"  # Man file path relative to MAN_BASE_DIR
    local section="$2"   # Section number for man command
    local man_path="${MAN_BASE_DIR}/man${section}/${man_file}"

    # Check if the man file exists
    if [[ ! -f "$man_path" && ! -f "$man_path.gz" ]]; then
        echo "❌ Error: Man page file '$man_path' does not exist."
        return 1
    fi
    echo "✅ Man page file '$man_path' exists."

    # Check if the man page is accessible
    local man_name="${man_file%%.*}"  # Strip the file extension for man command
    if ! man -w -s "$section" "$man_name" >/dev/null 2>&1; then
        echo "❌ Error: Man page '$man_name' (section $section) is not accessible."
        return 1
    fi
    echo "✅ Man page '$man_name' (section $section) is accessible."
}

check_service_status() {
    local service_path="$1"
    local allow_enabled_inactive="${2:-false}" # Optional second parameter

    # Extract the service name from the provided path
    local service_name
    service_name="$(basename "$service_path")"

    # Check if the service file exists
    if [[ ! -f "$service_path" ]]; then
        echo "❌ Error: Service file '$service_path' does not exist."
        return 1
    fi
    echo "✅ Service file '$service_path' exists."

    # Check if the service is active
    if systemctl is-active --quiet "$service_name"; then
        echo "✅ Service '$service_name' is active."
        return 0
    fi

    # If allow_enabled_inactive is true, check if the service is enabled but not active
    if [[ "$allow_enabled_inactive" == "true" ]] && systemctl is-enabled --quiet "$service_name"; then
        echo "✅ Service '$service_name' is enabled but inactive."
        return 0
    fi

    # If the service is neither active nor enabled (and inactive), it's an error
    echo "❌ Error: Service '$service_name' is not active."
    return 1
}

test_uninstall() {
    local debug; debug=$(debug_start "$@"); eval set -- "$(debug_filter "$@")"
    local errors=0

    echo "Running uninstallation validation tests..."

    # Validate that the service is not running and has been removed
    if systemctl list-unit-files | grep -q "^$APP_NAME"; then
        if systemctl is-active --quiet "$APP_NAME"; then
            logE "Service $APP_NAME is still active."
            errors=$((errors + 1))
        else
            debug_print "Service $APP_NAME is not active. ✅" "$debug"
        fi

        if systemctl is-enabled --quiet "$SYSTEMD_PATH"; then
            logE "Service $APP_NAME is still enabled."
            errors=$((errors + 1))
        else
            debug_print "Service $APP_NAME is not enabled. ✅" "$debug"
        fi
    else
        debug_print "Service unit file for $APP_NAME does not exist. ✅" "$debug"
    fi

    # Validate that the service file has been removed
    if [[ -f "$SERVICE_FILE" ]]; then
        logE "Service file $SERVICE_FILE still exists."
        errors=$((errors + 1))
    else
        debug_print "Service file $SERVICE_FILE has been removed. ✅" "$debug"
    fi

    # Validate that the timer is not running and has been removed
    if systemctl list-unit-files | grep -q "^$APP_NAME.timer"; then
        if systemctl is-active --quiet "$APP_NAME.timer"; then
            logE "Timer $APP_NAME.timer is still active."
            errors=$((errors + 1))
        else
            debug_print "Timer $APP_NAME.timer is not active. ✅" "$debug"
        fi

        if systemctl is-enabled --quiet "$APP_NAME.timer"; then
            logE "Timer $APP_NAME.timer is still enabled."
            errors=$((errors + 1))
        else
            debug_print "Timer $APP_NAME.timer is not enabled. ✅" "$debug"
        fi
    else
        debug_print "Timer unit file for $APP_NAME.timer does not exist. ✅" "$debug"
    fi

    # Validate that the timer file has been removed
    if [[ -f "$TIMER_FILE" ]]; then
        logE "Timer file $TIMER_FILE still exists."
        errors=$((errors + 1))
    else
        debug_print "Timer file $TIMER_FILE has been removed. ✅" "$debug"
    fi

    # Validate that the log directory has been removed
    if [[ -d "$APP_LOG_PATH" ]]; then
        logE "Log directory $APP_LOG_PATH still exists."
        errors=$((errors + 1))
    else
        debug_print "Log directory $APP_LOG_PATH has been removed. ✅" "$debug"
    fi

    # Validate other files and directories as needed
    if [[ -f "$CONFIG_FILE" ]]; then
        logE "Configuration file $CONFIG_FILE still exists."
        errors=$((errors + 1))
    else
        debug_print "Configuration file $CONFIG_FILE has been removed. ✅" "$debug"
    fi

    # Final results
    if (( errors > 0 )); then
        echo "❌ Uninstallation validation failed with $errors errors."
        debug_end "$debug"
        exit 1
    fi

    echo "✅ Uninstallation validation passed successfully!"
}

# Main test function for installation checks
test_install() {
    local errors=0

    # Validate required packages
    for package in "${APT_PACKAGES[@]}"; do
        check_if_package_exists "$package" || errors=$((errors + 1))
    done

    # Validate controller files
    check_file_exists "$CONTROLLER_PATH" || errors=$((errors + 1))
    check_file_permissions "$CONTROLLER_PATH" "755" || errors=$((errors + 1))
    check_ownership "$CONTROLLER_PATH" "root" "root" || errors=$((errors + 1))

    # Validate service
    check_file_exists "$SERVICE_FILE" || errors=$((errors + 1))
    check_file_permissions "$SERVICE_FILE" "644" || errors=$((errors + 1))
    check_ownership "$SERVICE_FILE" "root" "root" || errors=$((errors + 1))
    check_service_status "$SERVICE_FILE" true || errors=$((errors + 1))

    # Validate timer
    check_file_exists "$TIMER_FILE" || errors=$((errors + 1))
    check_file_permissions "$TIMER_FILE" "644" || errors=$((errors + 1))
    check_ownership "$TIMER_FILE" "root" "root" || errors=$((errors + 1))
    check_service_status "$TIMER_FILE" || errors=$((errors + 1))

    # Validate configuration file
    check_file_exists "$CONFIG_FILE" || errors=$((errors + 1))
    check_file_permissions "$CONFIG_FILE" "644" || errors=$((errors + 1))
    check_ownership "$CONFIG_FILE" "root" "root" || errors=$((errors + 1))

    # Validate directories and logs
    check_dir_exists "$APP_LOG_PATH" || errors=$((errors + 1))
    check_dir_permissions "$APP_LOG_PATH" "755" || errors=$((errors + 1))
    check_ownership "$APP_LOG_PATH" "root" "root" || errors=$((errors + 1))

    check_file_exists "$APP_LOG_PATH/output.log" || errors=$((errors + 1))
    check_file_permissions "$APP_LOG_PATH/output.log" "644" || errors=$((errors + 1))
    check_ownership "$APP_LOG_PATH/output.log" "root" "root" || errors=$((errors + 1))

    check_file_exists "$APP_LOG_PATH/error.log" || errors=$((errors + 1))
    check_file_permissions "$APP_LOG_PATH/error.log" "644" || errors=$((errors + 1))
    check_ownership "$APP_LOG_PATH/error.log" "root" "root" || errors=$((errors + 1))

    # Validate man pages
    check_man_page "apconfig.1" 1 || errors=$((errors + 1))
    check_man_page "appop.1" 1 || errors=$((errors + 1))
    check_man_page "appop.5" 5 || errors=$((errors + 1))

    # Final results
    if (( errors > 0 )); then
        echo "❌❌❌ Validation failed with $errors errors."
        exit 1
    fi

    echo "✅✅✅ All installation validation tests passed successfully! 🎉"
}

# Main script logic
if [[ "$MODE" == "uninstall" ]]; then
    test_uninstall
else
    test_install
fi
