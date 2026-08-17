#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Pre-flight Check Utility
# =============================================================================
# Orchestrates status and documentation checks before critical operations.
#
# This script runs comprehensive pre-flight checks to ensure the project
# is ready for operations like deployment, release, or major changes.
#
# Usage:
#   bash scripts/utils/pre-flight.sh [options]
#
# Options:
#   --skip-status       Skip status checks
#   --skip-docs         Skip documentation checks
#   --quick             Quick mode (skip slower checks)
#   --strict            Fail on any warning (not just errors)
#   --fix               Auto-fix issues where possible
#   --help, -h          Show this help message
################################################################################

set -euo pipefail

# Get script directory
_PRE_FLIGHT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="_PRE_FLIGHT_DIR"
fi

# Source dependencies
source "${_PRE_FLIGHT_DIR}/common.sh"
source "${_PRE_FLIGHT_DIR}/logger.sh"

# =============================================================================
# Script Configuration
# =============================================================================
SKIP_STATUS="${SKIP_STATUS:-false}"
SKIP_DOCS="${SKIP_DOCS:-false}"
QUICK_MODE="${QUICK_MODE:-false}"
STRICT_MODE="${STRICT_MODE:-false}"
FIX_MODE="${FIX_MODE:-false}"

# Track check results
STATUS_CHECK_PASSED=true
DOC_CHECK_PASSED=true
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# =============================================================================
# Check Functions
# =============================================================================

# Run status check
# Usage: run_status_check
# Returns: 0 if passed, 1 if failed
run_status_check() {
    if [[ "${SKIP_STATUS}" == "true" ]]; then
        log_info "Skipping status checks"
        return 0
    fi

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    log_section "Running Status Checks"

    local status_check_script="${SCRIPT_DIR}/status-check.sh"

    if [[ ! -f "${status_check_script}" ]]; then
        log_error "Status check script not found: ${status_check_script}"
        STATUS_CHECK_PASSED=false
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi

    # Build status check arguments
    local status_args=()
    [[ "${QUICK_MODE}" == "true" ]] && status_args+=(--quick)
    [[ "${STRICT_MODE}" == "true" ]] && status_args+=(--fail-on-dirty --fail-on-ci-fail --fail-on-behind)

    # Run status check
    if bash "${status_check_script}" "${status_args[@]}"; then
        log_success "Status checks passed"
        STATUS_CHECK_PASSED=true
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        local exit_code=$?
        log_error "Status checks failed"
        STATUS_CHECK_PASSED=false
        FAILED_CHECKS=$((FAILED_CHECKS + 1))

        if [[ "${STRICT_MODE}" == "true" ]]; then
            return ${exit_code}
        fi

        return 0
    fi
}

# Run documentation check
# Usage: run_doc_check
# Returns: 0 if passed, 1 if failed
run_doc_check() {
    if [[ "${SKIP_DOCS}" == "true" ]]; then
        log_info "Skipping documentation checks"
        return 0
    fi

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    log_section "Running Documentation Checks"

    local doc_check_script="${SCRIPT_DIR}/doc-check.sh"

    if [[ ! -f "${doc_check_script}" ]]; then
        log_error "Documentation check script not found: ${doc_check_script}"
        DOC_CHECK_PASSED=false
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi

    # Build doc check arguments
    local doc_args=()
    [[ "${FIX_MODE}" == "true" ]] && doc_args+=(--fix)
    [[ "${STRICT_MODE}" == "true" ]] && doc_args+=(--fail-on-missing)

    # Run documentation check
    if bash "${doc_check_script}" "${doc_args[@]}"; then
        log_success "Documentation checks passed"
        DOC_CHECK_PASSED=true
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        local exit_code=$?
        log_warn "Documentation checks found issues"
        DOC_CHECK_PASSED=false
        WARNINGS=$((WARNINGS + 1))

        if [[ "${STRICT_MODE}" == "true" ]]; then
            return ${exit_code}
        fi

        return 0
    fi
}

# Check project dependencies
# Usage: check_dependencies
# Returns: 0 if all available, 1 if any missing
check_dependencies() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    log_info "Checking project dependencies..."

    local missing_deps=()
    local project_type
    project_type="$(get_project_type)"

    case "${project_type}" in
        nodejs)
            if ! check_command npm; then
                missing_deps+=("npm")
            fi
            ;;
        python)
            if ! check_command python3 && ! check_command python; then
                missing_deps+=("python")
            fi
            ;;
        go)
            if ! check_command go; then
                missing_deps+=("go")
            fi
            ;;
        docker)
            if ! check_command docker; then
                missing_deps+=("docker")
            fi
            ;;
    esac

    # Check for git
    if ! check_command git; then
        missing_deps+=("git")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))

        if [[ "${STRICT_MODE}" == "true" ]]; then
            return 1
        fi
    else
        log_success "All dependencies available"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    fi

    return 0
}

# Check configuration validity
# Usage: check_configuration
# Returns: 0 if valid, 1 if invalid
check_configuration() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    log_info "Checking configuration..."

    local config_file="${CONFIG_FILE}"

    if [[ -f "${config_file}" ]]; then
        # Try to load and validate config
        if load_config "${config_file}"; then
            log_success "Configuration is valid"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            return 0
        else
            log_error "Configuration file has errors"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))

            if [[ "${STRICT_MODE}" == "true" ]]; then
                return 1
            fi
        fi
    else
        log_warn "No configuration file found (optional)"
        WARNINGS=$((WARNINGS + 1))
    fi

    return 0
}

# =============================================================================
# Main Pre-flight Function
# =============================================================================

# Run all pre-flight checks
# Usage: run_preflight_checks
# Returns: 0 if all critical checks pass, 1 if any fail
run_preflight_checks() {
    log_section "Pre-flight Check"
    log_info "Project: ${PROJECT_NAME:-$(basename "${PROJECT_ROOT}")}"
    log_info "Type: $(get_project_type)"
    log_info "Time: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"

    # Run checks
    check_dependencies || true
    check_configuration || true
    run_status_check || true
    run_doc_check || true

    # Print summary
    log_section "Pre-flight Summary"
    log_info "Total checks: ${TOTAL_CHECKS}"
    log_success "Passed: ${PASSED_CHECKS}"

    if [[ ${FAILED_CHECKS} -gt 0 ]]; then
        log_error "Failed: ${FAILED_CHECKS}"
    fi

    if [[ ${WARNINGS} -gt 0 ]]; then
        log_warn "Warnings: ${WARNINGS}"
    fi

    # Determine overall result
    if [[ ${FAILED_CHECKS} -eq 0 ]] && [[ ${WARNINGS} -eq 0 ]]; then
        log_success "All pre-flight checks passed"
        return 0
    elif [[ ${FAILED_CHECKS} -eq 0 ]]; then
        log_warn "Pre-flight checks passed with warnings"
        return 0
    else
        log_error "Pre-flight checks failed"
        return 1
    fi
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 [options]

Run comprehensive pre-flight checks before operations.

This script orchestrates status and documentation checks to ensure
your project is ready for deployment, release, or major changes.

Options:
  --skip-status       Skip status checks
  --skip-docs         Skip documentation checks
  --quick             Quick mode (skip slower checks like CI status)
  --strict            Fail on any warning (not just errors)
  --fix               Auto-fix issues where possible (create doc templates)
  --help, -h          Show this help message

Environment Variables:
  LOG_LEVEL            Log level (debug|info|warn|error) [default: info]

Exit Codes:
  0                    All critical checks passed
  1                    Critical checks failed

Examples:
  # Run all pre-flight checks
  $0

  # Quick pre-flight check
  $0 --quick

  # Strict mode (fail on any issues)
  $0 --strict

  # Skip documentation checks
  $0 --skip-docs

  # Auto-fix documentation issues
  $0 --fix

Integration:
  # Use before deployment
  $0 && bash scripts/cd/deploy.sh prod

  # Use in CI/CD pipeline
  $0 --strict --quick

EOF
}

# =============================================================================
# Main Script Entry Point
# =============================================================================

main() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit "${EXIT_SUCCESS}"
                ;;
            --skip-status)
                export SKIP_STATUS="true"
                shift
                ;;
            --skip-docs)
                export SKIP_DOCS="true"
                shift
                ;;
            --quick)
                export QUICK_MODE="true"
                shift
                ;;
            --strict)
                export STRICT_MODE="true"
                shift
                ;;
            --fix)
                export FIX_MODE="true"
                shift
                ;;
            --log-level)
                export LOG_LEVEL="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit "${EXIT_ERROR_GENERAL}"
                ;;
        esac
    done

    # Change to project root
    cd "${PROJECT_ROOT}"

    # Run pre-flight checks
    run_preflight_checks
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
