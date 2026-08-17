#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Status Check Utility
# =============================================================================
# Provides CI/CD-focused status checking before operations.
#
# This script wraps git and GitHub CLI commands to check:
#   - CI pipeline status
#   - Git branch status
#   - Uncommitted changes
#   - Recent commits
#
# Usage:
#   bash scripts/utils/status-check.sh [options]
#
# Options:
#   --quick              Skip slower checks (CI status, remote status)
#   --fail-on-dirty      Exit with error if working directory is dirty
#   --fail-on-ci-fail    Exit with error if CI is failing
#   --fail-on-behind     Exit with error if branch is behind main
#   --json               Output status in JSON format
#   --help, -h           Show help message
################################################################################

set -euo pipefail

# Get script directory
_STATUS_CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="_STATUS_CHECK_DIR"
fi

# Source dependencies
source "${_STATUS_CHECK_DIR}/common.sh"
source "${_STATUS_CHECK_DIR}/logger.sh"
source "${_STATUS_CHECK_DIR}/validators.sh"

# =============================================================================
# Script Configuration
# =============================================================================
QUICK_MODE="${QUICK_MODE:-false}"
FAIL_ON_DIRTY="${FAIL_ON_DIRTY:-false}"
FAIL_ON_CI_FAIL="${FAIL_ON_CI_FAIL:-false}"
FAIL_ON_BEHIND="${FAIL_ON_BEHIND:-false}"
JSON_OUTPUT="${JSON_OUTPUT:-false}"

# Status tracking
STATUS_DIRTY=false
STATUS_CI_PASSING=true
STATUS_BEHIND=false
STATUS_AHEAD=0
STATUS_BEHIND_COMMITS=0
BRANCH_NAME=""
MAIN_BRANCH="${MAIN_BRANCH:-main}"

# =============================================================================
# Helper Functions
# =============================================================================

# Check if GitHub CLI is available
# Usage: check_gh_cli
# Returns: 0 if available, 1 if not
check_gh_cli() {
    if check_command gh; then
        # Check if authenticated
        if gh auth status &>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Get the default/main branch name
# Usage: get_main_branch
# Outputs: branch name
get_main_branch() {
    # Try to detect from git remote
    if check_git_repo; then
        local remote_branch
        remote_branch="$(git -C "${PROJECT_ROOT}" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
        if [[ -n "${remote_branch}" ]]; then
            echo "${remote_branch}"
            return
        fi
    fi

    # Fall back to configured default
    echo "${MAIN_BRANCH}"
}

# =============================================================================
# Status Check Functions
# =============================================================================

# Check git working directory status
# Usage: check_git_status
# Returns: 0 if clean, 1 if dirty
check_git_status() {
    if ! check_git_repo; then
        log_debug "Not in a git repository"
        return 0
    fi

    # Get current branch
    BRANCH_NAME="$(git -C "${PROJECT_ROOT}" branch --show-current 2>/dev/null || echo "")"
    log_debug "Current branch: ${BRANCH_NAME}"

    # Check for uncommitted changes
    local status_output
    status_output="$(git -C "${PROJECT_ROOT}" status --porcelain 2>/dev/null || echo "")"

    if [[ -n "${status_output}" ]]; then
        STATUS_DIRTY=true

        if [[ "${JSON_OUTPUT}" == "true" ]]; then
            return 1
        fi

        log_warn "Working directory has uncommitted changes:"
        echo "${status_output}" | head -5 | while read -r line; do
            log_warn "  ${line}"
        done

        local changed_files
        changed_files="$(echo "${status_output}" | wc -l)"
        if [[ ${changed_files} -gt 5 ]]; then
            log_warn "  ... and $((changed_files - 5)) more"
        fi

        if [[ "${FAIL_ON_DIRTY}" == "true" ]]; then
            return "${EXIT_ERROR_VALIDATION}"
        fi
    else
        log_success "Working directory is clean"
    fi

    return 0
}

# Check branch status vs main branch
# Usage: check_branch_status
# Returns: 0 if up to date, 1 if behind
check_branch_status() {
    if ! check_git_repo; then
        log_debug "Not in a git repository"
        return 0
    fi

    if [[ "${QUICK_MODE}" == "true" ]]; then
        log_debug "Skipping branch status check (quick mode)"
        return 0
    fi

    # Get main branch name
    MAIN_BRANCH="$(get_main_branch)"
    log_debug "Main branch: ${MAIN_BRANCH}"

    # Check if we're on main branch
    if [[ "${BRANCH_NAME}" == "${MAIN_BRANCH}" ]]; then
        log_info "On main branch (${MAIN_BRANCH})"
        return 0
    fi

    # Fetch latest from remote (quiet mode)
    log_debug "Fetching remote status..."
    git -C "${PROJECT_ROOT}" fetch -q origin "${BRANCH_NAME}" "${MAIN_BRANCH}" 2>/dev/null || true

    # Check ahead/behind status
    local rev_list
    rev_list="$(git -C "${PROJECT_ROOT}" rev-list --left-right --count "origin/${MAIN_BRANCH}...HEAD" 2>/dev/null || echo "0 0")"

    if [[ "${rev_list}" =~ ^([0-9]+)[[:space:]]([0-9]+)$ ]]; then
        STATUS_BEHIND_COMMITS="${BASH_REMATCH[1]}"
        STATUS_AHEAD="${BASH_REMATCH[2]}"
    fi

    # Report status
    if [[ ${STATUS_BEHIND_COMMITS} -gt 0 ]]; then
        STATUS_BEHIND=true
        log_warn "Branch is behind ${MAIN_BRANCH} by ${STATUS_BEHIND_COMMITS} commit(s)"

        if [[ "${FAIL_ON_BEHIND}" == "true" ]]; then
            return "${EXIT_ERROR_VALIDATION}"
        fi
    elif [[ ${STATUS_AHEAD} -gt 0 ]]; then
        log_info "Branch is ahead of ${MAIN_BRANCH} by ${STATUS_AHEAD} commit(s)"
    else
        log_success "Branch is up to date with ${MAIN_BRANCH}"
    fi

    return 0
}

# Check CI pipeline status
# Usage: check_ci_status
# Returns: 0 if passing, 1 if failing
check_ci_status() {
    if [[ "${QUICK_MODE}" == "true" ]]; then
        log_debug "Skipping CI status check (quick mode)"
        return 0
    fi

    if ! check_gh_cli; then
        log_debug "GitHub CLI not available, skipping CI status check"
        return 0
    fi

    log_debug "Checking CI pipeline status..."

    # Get the status of recent workflow runs
    local ci_status
    ci_status="$(gh run list --json conclusion,databaseId --limit 5 2>/dev/null || echo "")"

    if [[ -z "${ci_status}" ]]; then
        log_debug "No CI runs found"
        return 0
    fi

    # Check if any recent runs failed
    local failed_runs
    failed_runs="$(echo "${ci_status}" | grep -o '"conclusion":"failure"' | wc -l || echo "0")"

    if [[ ${failed_runs} -gt 0 ]]; then
        STATUS_CI_PASSING=false
        log_warn "Recent CI failures detected: ${failed_runs} failed run(s)"

        # Show latest failed run details
        local latest_failure
        latest_failure="$(gh run view --json databaseId,conclusion,createdAt,status --jq '"Run #\(.databaseId): \(.conclusion) - \(.createdAt)"' 2>/dev/null || echo "")"

        if [[ -n "${latest_failure}" ]]; then
            log_warn "Latest failure: ${latest_failure}"
        fi

        if [[ "${FAIL_ON_CI_FAIL}" == "true" ]]; then
            return "${EXIT_ERROR_VALIDATION}"
        fi
    else
        log_success "CI pipeline is passing"
    fi

    return 0
}

# Show recent commits
# Usage: show_recent_commits [count]
show_recent_commits() {
    local count="${1:-5}"

    if ! check_git_repo; then
        return 0
    fi

    log_info "Recent commits (last ${count}):"

    local commits
    commits="$(git -C "${PROJECT_ROOT}" log --oneline -n "${count}" 2>/dev/null || echo "")"

    if [[ -n "${commits}" ]]; then
        echo "${commits}" | while read -r line; do
            log_info "  ${line}"
        done
    else
        log_debug "No commits found"
    fi
}

# Output status in JSON format
# Usage: output_json_status
output_json_status() {
    cat << EOF
{
  "git": {
    "branch": "${BRANCH_NAME}",
    "main_branch": "${MAIN_BRANCH}",
    "dirty": ${STATUS_DIRTY},
    "behind": ${STATUS_BEHIND},
    "behind_commits": ${STATUS_BEHIND_COMMITS},
    "ahead": ${STATUS_AHEAD}
  },
  "ci": {
    "passing": ${STATUS_CI_PASSING},
    "checked": $([[ "${QUICK_MODE}" == "true" ]] && echo "false" || echo "true")
  }
}
EOF
}

# =============================================================================
# Main Status Check Function
# =============================================================================

# Run all status checks
# Usage: run_status_checks
# Returns: 0 if all checks pass, 1 if any fail
run_status_checks() {
    local exit_code=0

    log_section "CI/CD Status Check"

    # Check git status
    check_git_status || exit_code=$?

    # Check branch status
    check_branch_status || exit_code=$?

    # Check CI status
    check_ci_status || exit_code=$?

    # Show recent commits
    if [[ "${JSON_OUTPUT}" != "true" ]] && [[ "${LOG_LEVEL}" == "debug" ]]; then
        show_recent_commits
    fi

    # Output summary
    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        output_json_status
    else
        log_section "Status Summary"
        log_info "Branch: ${BRANCH_NAME:-unknown}"
        log_info "Working dir: $([[ "${STATUS_DIRTY}" == "true" ]] && echo "dirty" || echo "clean")"
        log_info "CI status: $([[ "${STATUS_CI_PASSING}" == "true" ]] && echo "passing" || echo "failing")"
        log_info "Sync state: $([[ "${STATUS_BEHIND}" == "true" ]] && echo "behind by ${STATUS_BEHIND_COMMITS}" || echo "up to date")"
    fi

    return ${exit_code}
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 [options]

Check CI/CD-relevant project status before operations.

Options:
  --quick              Skip slower checks (CI status, remote sync)
  --fail-on-dirty      Exit with error if working directory has uncommitted changes
  --fail-on-ci-fail    Exit with error if CI pipeline is failing
  --fail-on-behind     Exit with error if branch is behind main
  --json               Output status in JSON format
  --help, -h           Show this help message

Environment Variables:
  LOG_LEVEL            Log level (debug|info|warn|error) [default: info]
  MAIN_BRANCH          Main branch name [default: main]
  QUICK_MODE           Enable quick mode [default: false]

Exit Codes:
  0                    All checks passed
  1                    General error
  4                    Validation failed (when using --fail-on-* flags)

Examples:
  # Quick status check
  $0 --quick

  # Full check with fail-fast
  $0 --fail-on-dirty --fail-on-ci-fail

  # JSON output for automation
  $0 --json

  # Check before deployment
  $0 --fail-on-ci-fail --fail-on-behind

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
            --quick)
                export QUICK_MODE="true"
                shift
                ;;
            --fail-on-dirty)
                export FAIL_ON_DIRTY="true"
                shift
                ;;
            --fail-on-ci-fail)
                export FAIL_ON_CI_FAIL="true"
                shift
                ;;
            --fail-on-behind)
                export FAIL_ON_BEHIND="true"
                shift
                ;;
            --json)
                export JSON_OUTPUT="true"
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

    # Run status checks
    run_status_checks
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
