#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Common Utilities
# =============================================================================
# This script provides core utility functions used by all CI/CD scripts.
# It must be sourced before any other toolkit scripts.
################################################################################

set -euo pipefail

# =============================================================================
# Exit Codes
# =============================================================================
export EXIT_SUCCESS=0
export EXIT_ERROR_GENERAL=1
export EXIT_ERROR_CONFIG=2
export EXIT_ERROR_MISSING_DEPS=3
export EXIT_ERROR_VALIDATION=4
export EXIT_ERROR_BUILD=5
export EXIT_ERROR_DEPLOY=6
export EXIT_ERROR_TEST=7

# =============================================================================
# Color Definitions
# =============================================================================
# Set colors if terminal supports it
if [[ -t 1 ]] && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    export COLOR_RED='\033[0;31m'
    export COLOR_GREEN='\033[0;32m'
    export COLOR_YELLOW='\033[0;33m'
    export COLOR_BLUE='\033[0;34m'
    export COLOR_MAGENTA='\033[0;35m'
    export COLOR_CYAN='\033[0;36m'
    export COLOR_GRAY='\033[0;90m'
    export COLOR_BOLD='\033[1m'
    export COLOR_RESET='\033[0m'
else
    export COLOR_RED=''
    export COLOR_GREEN=''
    export COLOR_YELLOW=''
    export COLOR_BLUE=''
    export COLOR_MAGENTA=''
    export COLOR_CYAN=''
    export COLOR_GRAY=''
    export COLOR_BOLD=''
    export COLOR_RESET=''
fi

# =============================================================================
# Global Variables
# =============================================================================
# TOOLKIT_ROOT: absolute path to the CI/CD toolkit itself (for sourcing
# utils, loading config, finding internal resources)
export SCRIPT_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TOOLKIT_ROOT
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export CONFIG_DIR="${TOOLKIT_ROOT}/config"
export CONFIG_FILE="${CONFIG_DIR}/ci-cd.conf"

# PROJECT_ROOT: the target project directory (defaults to CWD — the
# directory from which the script was invoked). Auto-detection of project
# type, linters, test runners etc. happens HERE, not in the toolkit root.
# Override with: PROJECT_ROOT=/path/to/project bash scripts/ci/lint.sh
export PROJECT_ROOT
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# Default configuration values
export PROJECT_TYPE="${PROJECT_TYPE:-auto}"
export LOG_LEVEL="${LOG_LEVEL:-info}"
export LOG_TIMESTAMP="${LOG_TIMESTAMP:-false}"
export LOG_FILE="${LOG_FILE:-}"
export DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# Utility Functions
# =============================================================================

# Print error message and exit
# Usage: error_exit "Error message" [exit_code]
error_exit() {
    local message="$1"
    local exit_code="${2:-${EXIT_ERROR_GENERAL}}"
    echo -e "${COLOR_RED}ERROR: ${message}${COLOR_RESET}" >&2
    exit "${exit_code}"
}

# Check if a command exists
# Usage: check_command "command_name"
# Returns: 0 if exists, 1 if not
check_command() {
    local cmd="$1"
    command -v "${cmd}" &>/dev/null
}

# Ensure a command exists, exit if not
# Usage: require_command "command_name" [error_message]
require_command() {
    local cmd="$1"
    local error_msg="${2:-Required command '${cmd}' not found. Please install it first.}"

    if ! check_command "${cmd}"; then
        error_exit "${error_msg}" "${EXIT_ERROR_MISSING_DEPS}"
    fi
}

# Detect operating system
# Usage: detect_os
# Outputs: linux|macos|windows|unknown
detect_os() {
    local os_name
    os_name="$(uname -s 2>/dev/null || echo "unknown")"

    case "${os_name}" in
        Linux*)
            echo "linux"
            ;;
        Darwin*)
            echo "macos"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Detect project type based on files present
# Usage: get_project_type
# Outputs: nodejs|python|go|java|docker|unknown
get_project_type() {
    if [[ "${PROJECT_TYPE}" != "auto" ]]; then
        echo "${PROJECT_TYPE}"
        return
    fi

    # Check for project markers in priority order
    if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
        echo "nodejs"
    elif [[ -f "${PROJECT_ROOT}/requirements.txt" ]] || \
         [[ -f "${PROJECT_ROOT}/setup.py" ]] || \
         [[ -f "${PROJECT_ROOT}/pyproject.toml" ]] || \
         [[ -f "${PROJECT_ROOT}/Pipfile" ]] || \
         [[ -f "${PROJECT_ROOT}/poetry.lock" ]]; then
        echo "python"
    elif [[ -f "${PROJECT_ROOT}/go.mod" ]]; then
        echo "go"
    elif [[ -f "${PROJECT_ROOT}/pom.xml" ]]; then
        echo "maven"
    elif [[ -f "${PROJECT_ROOT}/build.gradle" ]] || [[ -f "${PROJECT_ROOT}/build.gradle.kts" ]]; then
        echo "gradle"
    elif [[ -f "${PROJECT_ROOT}/Dockerfile" ]] || [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
        echo "docker"
    else
        echo "unknown"
    fi
}

# Load configuration file
# Usage: load_config [config_file]
# Returns: 0 on success, 1 on error
load_config() {
    local config_file="${1:-${CONFIG_FILE}}"

    if [[ ! -f "${config_file}" ]]; then
        return 1
    fi

    # Source the config file (basic INI parsing for bash)
    # This is a simple implementation - for complex configs, use a dedicated parser
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "${key}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key}" ]] && continue

        # Remove leading/trailing whitespace
        key="$(echo "${key}" | xargs)"
        value="$(echo "${value}" | xargs)"

        # Skip section headers like [general], [ci], [cd], etc.
        [[ "${key}" =~ ^\[.*\]$ ]] && continue

        # Skip if key is empty after trimming
        [[ -z "${key}" ]] && continue

        # Export as environment variable
        export "${key}=${value}"
    done < "${config_file}"

    return 0
}

# Get version from git tag or environment variable
# Usage: get_version
# Outputs: version string
get_version() {
    # If BUILD_VERSION is set, use it
    if [[ -n "${BUILD_VERSION:-}" ]]; then
        echo "${BUILD_VERSION}"
        return
    fi

    # Check if we're in a git repository
    if [[ -d "${PROJECT_ROOT}/.git" ]]; then
        # Try to get the latest tag
        local tag
        tag="$(git -C "${PROJECT_ROOT}" describe --tags --abbrev=0 2>/dev/null || echo "")"

        if [[ -n "${tag}" ]]; then
            echo "${tag}"
            return
        fi

        # Fall back to commit SHA
        local commit
        commit="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
        echo "${commit}"
        return
    fi

    # Default version
    echo "0.0.0"
}

# Check if we're in a git repository
# Usage: check_git_repo
# Returns: 0 if in git repo, 1 if not
check_git_repo() {
    [[ -d "${PROJECT_ROOT}/.git" ]]
}

# Create directory if it doesn't exist
# Usage: ensure_dir "path/to/directory"
ensure_dir() {
    local dir="$1"
    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}"
    fi
}

# Remove directory safely (only if it exists and is within project)
# Usage: safe_rmdir "path/to/directory"
safe_rmdir() {
    local dir="$1"
    local abs_dir

    # Get absolute path
    abs_dir="$(cd "$(dirname "${dir}")" 2>/dev/null && pwd)/$(basename "${dir}")"

    # Safety check: only remove directories within project root
    if [[ "${abs_dir}" == "${PROJECT_ROOT}"* ]]; then
        rm -rf "${abs_dir}"
    else
        error_exit "Refusing to delete directory outside project root: ${dir}" "${EXIT_ERROR_VALIDATION}"
    fi
}

# Get file size in human-readable format
# Usage: get_file_size "path/to/file"
# Outputs: human-readable size (e.g., "1.5M", "512K")
get_file_size() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        echo "unknown"
        return
    fi

    # Try to use GNU stat or BSD stat
    if stat --version &>/dev/null; then
        # GNU stat
        stat -c%s "${file}" 2>/dev/null | numfmt --to=iec --suffix=B 2>/dev/null || echo "unknown"
    else
        # BSD stat (macOS)
        stat -f%z "${file}" 2>/dev/null | numfmt --to=iec --suffix=B 2>/dev/null || echo "unknown"
    fi
}

# Join array elements with delimiter
# Usage: join_by "," "${array[@]}"
join_by() {
    local delimiter="$1"
    shift
    local first="$1"
    shift
    printf "%s" "${first}"
    printf "%s" "${@/#/${delimiter}}"
}

# Convert string to lowercase
# Usage: to_lower "STRING"
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Convert string to uppercase
# Usage: to_upper "string"
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Trim whitespace from string
# Usage: trim "  string  "
trim() {
    echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Check if running in CI/CD environment
# Usage: is_ci_env
# Returns: 0 if in CI, 1 if not
is_ci_env() {
    [[ -n "${CI:-}" ]] || \
    [[ -n "${GITHUB_ACTIONS:-}" ]] || \
    [[ -n "${GITLAB_CI:-}" ]] || \
    [[ -n "${JENKINS_URL:-}" ]] || \
    [[ -n "${TEAMCITY_VERSION:-}" ]] || \
    [[ -n "${TRAVIS:-}" ]] || \
    [[ -n "${CIRCLECI:-}" ]] || \
    [[ -n "${BITBUCKET_BUILD_NUMBER:-}" ]]
}

# Parse command line arguments in standard way
# Usage: parse_args "$@"
# Sets global variables based on arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit "${EXIT_SUCCESS}"
                ;;
            --dry-run)
                export DRY_RUN="true"
                shift
                ;;
            --log-level)
                export LOG_LEVEL="$2"
                shift 2
                ;;
            --config)
                export CONFIG_FILE="$2"
                shift 2
                ;;
            --version|-v)
                show_version
                exit "${EXIT_SUCCESS}"
                ;;
            *)
                # Unknown argument - let caller handle it
                break
                ;;
        esac
    done
}

# Show help message (should be overridden by scripts)
# Usage: show_help
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help, -h         Show this help message"
    echo "  --version, -v      Show version information"
    echo "  --dry-run          Simulate actions without making changes"
    echo "  --log-level LEVEL  Set log level (debug|info|warn|error)"
    echo "  --config FILE      Use custom configuration file"
}

# Show version information
# Usage: show_version
show_version() {
    echo "CI/CD Toolkit v1.0.0"
}

# Execute command or simulate it (if dry-run mode)
# Usage: run_cmd command [args...]
run_cmd() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

# =============================================================================
# Initialization
# =============================================================================

# This function is called when the script is sourced
# Usage: common_init
common_init() {
    # Load configuration if it exists
    if [[ -f "${CONFIG_FILE}" ]]; then
        load_config "${CONFIG_FILE}"
    fi

    # Validate LOG_LEVEL
    case "${LOG_LEVEL}" in
        debug|info|warn|error)
            ;;
        *)
            export LOG_LEVEL="info"
            ;;
    esac
}

# Auto-initialize when sourced
common_init

# Export all functions for use in subshells
export -f error_exit
export -f check_command
export -f require_command
export -f detect_os
export -f get_project_type
export -f load_config
export -f get_version
export -f check_git_repo
export -f ensure_dir
export -f safe_rmdir
export -f get_file_size
export -f join_by
export -f to_lower
export -f to_upper
export -f trim
export -f is_ci_env
export -f parse_args
export -f show_help
export -f show_version
export -f run_cmd
