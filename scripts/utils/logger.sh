#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Logging Utilities
# =============================================================================
# Provides structured, configurable logging functions.
# Source this script after common.sh
################################################################################

set -euo pipefail

# Ensure common.sh is loaded (LOG_LEVEL is always set by common.sh)
if [[ -z "${LOG_LEVEL:-}" ]]; then
    echo "ERROR: logger.sh must be sourced after common.sh" >&2
    exit 1
fi

# =============================================================================
# Logging Configuration
# =============================================================================
# Log levels: debug=0, info=1, warn=2, error=3
declare -A LOG_LEVELS=(
    [debug]=0
    [info]=1
    [warn]=2
    [error]=3
)

# Current log level (from environment or default to info)
CURRENT_LOG_LEVEL="${LOG_LEVELS[${LOG_LEVEL}]:-1}"

# Log file path (optional)
LOG_FILE="${LOG_FILE:-}"

# Enable/disable timestamps
LOG_TIMESTAMP="${LOG_TIMESTAMP:-false}"

# =============================================================================
# Logging Functions
# =============================================================================

# Core logging function
# Usage: _log level "message" [color]
_log() {
    local level="$1"
    local message="$2"
    local color="${3:-${COLOR_RESET}}"
    local level_value="${LOG_LEVELS[${level}]}"

    # Check if we should log this level
    if [[ ${level_value} -lt ${CURRENT_LOG_LEVEL} ]]; then
        return
    fi

    # Build the log message
    local timestamp=""
    if [[ "${LOG_TIMESTAMP}" == "true" ]]; then
        timestamp="$(date '+%Y-%m-%d %H:%M:%S') "
    fi

    local level_upper
    level_upper="$(to_upper "${level}")"
    local prefix="${timestamp}[${level_upper}]"

    # Output to console with colors
    if [[ -t 1 ]]; then
        echo -e "${color}${prefix}${COLOR_RESET} ${message}"
    else
        echo "${prefix} ${message}"
    fi

    # Output to file if configured
    if [[ -n "${LOG_FILE}" ]]; then
        echo "${prefix} ${message}" >> "${LOG_FILE}"
    fi
}

# Log info message (blue)
# Usage: log_info "message"
log_info() {
    _log "info" "$1" "${COLOR_BLUE}"
}

# Log success message (green)
# Usage: log_success "message"
log_success() {
    _log "info" "$1" "${COLOR_GREEN}"
}

# Log warning message (yellow)
# Usage: log_warn "message"
log_warn() {
    _log "warn" "$1" "${COLOR_YELLOW}"
}

# Log error message (red)
# Usage: log_error "message"
log_error() {
    _log "error" "$1" "${COLOR_RED}"
}

# Log debug message (gray, only when LOG_LEVEL=debug)
# Usage: log_debug "message"
log_debug() {
    _log "debug" "$1" "${COLOR_GRAY}"
}

# Log section header (cyan, bold)
# Usage: log_section "Section Title"
log_section() {
    local title="$1"
    local separator=""

    # Create separator line
    for ((i=0; i<${#title}+4; i++)); do
        separator="${separator}="
    done

    echo ""
    if [[ -t 1 ]]; then
        echo -e "${COLOR_BOLD}${COLOR_CYAN}${separator}${COLOR_RESET}"
        echo -e "${COLOR_BOLD}${COLOR_CYAN}= ${title} =${COLOR_RESET}"
        echo -e "${COLOR_BOLD}${COLOR_CYAN}${separator}${COLOR_RESET}"
    else
        echo "${separator}"
        echo "= ${title} ="
        echo "${separator}"
    fi
    echo ""
}

# Log command execution
# Usage: log_cmd "command" [args...]
log_cmd() {
    local cmd="$1"
    shift
    log_debug "Executing: ${cmd} $*"
}

# Log start of operation
# Usage: log_start "Operation name"
log_start() {
    log_info "Starting: $1..."
}

# Log completion of operation
# Usage: log_complete "Operation name" [duration]
log_complete() {
    local operation="$1"
    local duration="${2:-}"
    local msg="Completed: ${operation}"

    if [[ -n "${duration}" ]]; then
        msg="${msg} (duration: ${duration})"
    fi

    log_success "${msg}"
}

# Log file operation
# Usage: log_file operation "path/to/file"
log_file() {
    local operation="$1"
    local file="$2"
    local size

    if [[ -f "${file}" ]]; then
        size="$(get_file_size "${file}")"
        log_debug "${operation} file: ${file} (${size})"
    else
        log_debug "${operation} file: ${file}"
    fi
}

# Create a log group for CI/CD platforms
# Usage: log_group_start "Group name"
log_group_start() {
    local title="$1"

    # GitHub Actions
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::group::${title}"
    # GitLab CI
    elif [[ -n "${GITLAB_CI:-}" ]]; then
        echo "section_start:$(date +%s):${title//[[:space:]]/_}[collapsed=true]"
        echo -e "\033[0K\033[1;34m${title}\033[0m"
    fi
}

# End a log group
# Usage: log_group_end
log_group_end() {
    # GitHub Actions
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::endgroup::"
    # GitLab CI
    elif [[ -n "${GITLAB_CI:-}" ]]; then
        echo "section_end:$(date +%s):${title//[[:space:]]/_}"
    fi
}

# Log with annotation for CI/CD platforms
# Usage: log_annotation "message" "type"
# Types: notice|warning|error
log_annotation() {
    local message="$1"
    local type="${2:-notice}"

    # GitHub Actions
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        local file="${3:-}"
        local line="${4:-}"
        local col="${5:-}"
        local annotation="::${type}"

        if [[ -n "${file}" ]]; then
            annotation="${annotation} file=${file}"
            if [[ -n "${line}" ]]; then
                annotation="${annotation},line=${line}"
                if [[ -n "${col}" ]]; then
                    annotation="${annotation},col=${col}"
                fi
            fi
        fi

        echo "${annotation}::${message}"
    fi
}

# Log warning with annotation for GitHub Actions
# Usage: log_warn_annotation "message" ["file" [line [col]]]
log_warn_annotation() {
    log_annotation "$1" "warning" "${2:-}" "${3:-}" "${4:-}"
}

# Log error with annotation for GitHub Actions
# Usage: log_error_annotation "message" ["file" [line [col]]]
log_error_annotation() {
    log_annotation "$1" "error" "${2:-}" "${3:-}" "${4:-}"
}

# Set output parameter for CI/CD platforms
# Usage: log_set_output "name" "value"
log_set_output() {
    local name="$1"
    local value="$2"

    # GitHub Actions
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "${name}=${value}" >> "${GITHUB_OUTPUT:-/dev/null}"
    # GitLab CI
    elif [[ -n "${GITLAB_CI:-}" ]]; then
        echo "${name}=${value}"
    fi
}

# Mask sensitive value in CI/CD logs
# Usage: log_mask_value "sensitive_value"
log_mask_value() {
    local value="$1"

    # GitHub Actions
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::add-mask::${value}"
    fi
}

# Create a summary for GitHub Actions
# Usage: log_summary "content"
log_summary() {
    local content="$1"

    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        echo "${content}" >> "${GITHUB_STEP_SUMMARY}"
    fi
}

# Log table/data
# Usage: log_table "header1,header2" "row1col1,row1col2" "row2col1,row2col2" ...
log_table() {
    local headers="$1"
    shift
    local rows=("$@")

    # Convert to arrays
    IFS=',' read -ra headers_arr <<< "${headers}"

    # Calculate column widths
    local col_widths=()
    local i=0
    for header in "${headers_arr[@]}"; do
        local max_len=${#header}
        for row in "${rows[@]}"; do
            IFS=',' read -ra row_arr <<< "${row}"
            local cell_len=${#row_arr[$i]}
            if [[ ${cell_len} -gt ${max_len} ]]; then
                max_len=${cell_len}
            fi
        done
        col_widths+=($((max_len + 2)))
        ((i++))
    done

    # Print headers
    local header_line=""
    i=0
    for header in "${headers_arr[@]}"; do
        header_line="${header_line}$(printf "%-${col_widths[$i]}s" "${header}")"
        ((i++))
    done
    echo -e "${COLOR_BOLD}${COLOR_CYAN}${header_line}${COLOR_RESET}"

    # Print rows
    for row in "${rows[@]}"; do
        IFS=',' read -ra row_arr <<< "${row}"
        local row_line=""
        i=0
        for cell in "${row_arr[@]}"; do
            row_line="${row_line}$(printf "%-${col_widths[$i]}s" "${cell}")"
            ((i++))
        done
        echo "${row_line}"
    done
}

# Progress indicator (simple spinner for long operations)
# Usage: log_progress_start "message"
#        ... do work ...
#        log_progress_stop
log_progress_start() {
    local message="$1"
    printf "${COLOR_BLUE}${message}... ${COLOR_RESET}"
}

log_progress_stop() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET}"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Enable/disable logging to file
# Usage: log_enable_file "/path/to/logfile.log"
log_enable_file() {
    local file="$1"
    local log_dir

    log_dir="$(dirname "${file}")"
    ensure_dir "${log_dir}"

    LOG_FILE="${file}"
    export LOG_FILE
}

# Disable file logging
# Usage: log_disable_file
log_disable_file() {
    LOG_FILE=""
    export LOG_FILE
}

# Get current log level as string
# Usage: log_get_level
log_get_level() {
    for level in "${!LOG_LEVELS[@]}"; do
        if [[ "${LOG_LEVELS[${level}]}" == "${CURRENT_LOG_LEVEL}" ]]; then
            echo "${level}"
            return
        fi
    done
}

# Set log level
# Usage: log_set_level "debug|info|warn|error"
log_set_level() {
    local new_level="$1"

    if [[ -n "${LOG_LEVELS[${new_level}]:-}" ]]; then
        export LOG_LEVEL="${new_level}"
        export CURRENT_LOG_LEVEL="${LOG_LEVELS[${new_level}]}"
    else
        log_error "Invalid log level: ${new_level}"
        return 1
    fi
}

# =============================================================================
# Export Functions
# =============================================================================
export -f _log
export -f log_info
export -f log_success
export -f log_warn
export -f log_error
export -f log_debug
export -f log_section
export -f log_cmd
export -f log_start
export -f log_complete
export -f log_file
export -f log_group_start
export -f log_group_end
export -f log_annotation
export -f log_warn_annotation
export -f log_error_annotation
export -f log_set_output
export -f log_mask_value
export -f log_summary
export -f log_table
export -f log_progress_start
export -f log_progress_stop
export -f log_enable_file
export -f log_disable_file
export -f log_get_level
export -f log_set_level
