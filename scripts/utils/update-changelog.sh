#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - CHANGELOG Update Utility
# =============================================================================
# Automates CHANGELOG.md updates following Keep a Changelog format.
#
# This script helps maintain the changelog by:
#   - Parsing recent commits for context
#   - Interactive prompt for changelog entry
#   - Validating changelog format
#   - Inserting entry in correct location
#
# Usage:
#   bash scripts/utils/update-changelog.sh [options]
#
# Options:
#   --type TYPE         Change type: added, changed, deprecated, removed,
#                       fixed, security (default: added)
#   --message MSG       Changelog message (skip prompt)
#   --issue NUMBER      Reference issue/PR number
#   --auto              Auto-generate from recent commits
#   --dry-run           Show what would be written without writing
#   --help, -h          Show this help message
################################################################################

set -euo pipefail

# Get script directory
_UPDATE_CHANGELOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="_UPDATE_CHANGELOG_DIR"
fi

# Source dependencies
source "${_UPDATE_CHANGELOG_DIR}/common.sh"
source "${_UPDATE_CHANGELOG_DIR}/logger.sh"

# =============================================================================
# Script Configuration
# =============================================================================
CHANGELOG_TYPE="${CHANGELOG_TYPE:-}"
CHANGELOG_MESSAGE="${CHANGELOG_MESSAGE:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
AUTO_MODE="${AUTO_MODE:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Changelog file path
CHANGELOG_FILE="${PROJECT_ROOT}/CHANGELOG.md"

# Valid change types
VALID_TYPES=("added" "changed" "deprecated" "removed" "fixed" "security")

# =============================================================================
# Helper Functions
# =============================================================================

# Validate change type
# Usage: validate_type "type"
# Returns: 0 if valid, 1 if not
validate_type() {
    local type="$1"
    for valid_type in "${VALID_TYPES[@]}"; do
        if [[ "${type}" == "${valid_type}" ]]; then
            return 0
        fi
    done
    return 1
}

# Get recent commits for context
# Usage: get_recent_commits [count]
# Outputs: formatted commit list
get_recent_commits() {
    local count="${1:-5}"

    if ! check_git_repo; then
        return 1
    fi

    log_info "Recent commits (for reference):"
    echo ""

    git -C "${PROJECT_ROOT}" log --oneline -n "${count}" 2>/dev/null | while read -r commit_msg; do
        echo "  ${commit_msg}"
    done
}

# Parse commits for changelog entries
# Usage: parse_commits_for_changelog
# Outputs: suggested entries
parse_commits_for_changelog() {
    if ! check_git_repo; then
        return 1
    fi

    log_info "Analyzing recent commits for changelog suggestions..."

    local commits
    mapfile -t commits < <(git -C "${PROJECT_ROOT}" log --oneline -n 10 2>/dev/null)

    if [[ ${#commits[@]} -eq 0 ]]; then
        log_warn "No recent commits found"
        return 1
    fi

    echo ""
    log_info "Suggested changelog entries from commits:"
    echo ""

    for commit in "${commits[@]}"; do
        local commit_hash
        local commit_msg

        commit_hash="$(echo "${commit}" | cut -d' ' -f1)"
        commit_msg="$(echo "${commit}" | cut -d' ' -f2-)"

        # Skip merge commits and changelog updates
        if [[ "${commit_msg}" =~ ^(Merge|Update CHANGELOG) ]]; then
            continue
        fi

        # Determine type from commit message
        local suggested_type="changed"
        if [[ "${commit_msg}" =~ ^[Aa]dd ]]; then
            suggested_type="added"
        elif [[ "${commit_msg}" =~ ^[Ff]ix ]]; then
            suggested_type="fixed"
        elif [[ "${commit_msg}" =~ ^[Rr]emove ]]; then
            suggested_type="removed"
        fi

        echo "  [${suggested_type}] ${commit_msg}"
    done
}

# Get unreleased section marker
# Usage: get_unreleased_marker
get_unreleased_marker() {
    echo "## [Unreleased]"
}

# Insert entry into CHANGELOG
# Usage: insert_entry "type" "message" ["issue_number"]
insert_entry() {
    local type="$1"
    local message="$2"
    local issue_number="${3:-}"

    # Read current CHANGELOG
    if [[ ! -f "${CHANGELOG_FILE}" ]]; then
        log_error "CHANGELOG.md not found: ${CHANGELOG_FILE}"
        return 1
    fi

    local content
    content="$(cat "${CHANGELOG_FILE}")"

    # Find [Unreleased] section
    if ! echo "${content}" | grep -q "## \[Unreleased\]"; then
        log_error "[Unreleased] section not found in CHANGELOG.md"
        return 1
    fi

    # Build the entry
    local entry="### ${type^}"
    entry="${entry}"$'\n'"- ${message}"

    if [[ -n "${issue_number}" ]]; then
        entry="${entry} (#${issue_number})"
    fi

    # Insert after [Unreleased] heading
    local new_content
    new_content="$(echo "${content}" | sed "/## \[Unreleased\]/a\\
\\
${entry}
")"

    # Write back
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would update CHANGELOG.md:"
        echo ""
        echo "${new_content}" | head -30
        echo ""
        log_info "... (truncated)"
    else
        echo "${new_content}" > "${CHANGELOG_FILE}"
        log_success "CHANGELOG.md updated"
    fi

    return 0
}

# Interactive prompt for changelog entry
# Usage: interactive_prompt
interactive_prompt() {
    log_section "CHANGELOG Entry Creator"

    # Show recent commits for context
    if [[ "${AUTO_MODE}" != "true" ]]; then
        get_recent_commits
        echo ""
    fi

    # Prompt for type
    if [[ -z "${CHANGELOG_TYPE}" ]]; then
        echo ""
        log_info "Select change type:"
        echo "  1) added      - New features"
        echo "  2) changed    - Changes to existing functionality"
        echo "  3) deprecated - Soon-to-be removed features"
        echo "  4) removed    - Removed features"
        echo "  5) fixed      - Bug fixes"
        echo "  6) security   - Security vulnerability fixes"
        echo ""

        local type_choice
        read -rp "Enter choice (1-6): " type_choice

        case "${type_choice}" in
            1) CHANGELOG_TYPE="added" ;;
            2) CHANGELOG_TYPE="changed" ;;
            3) CHANGELOG_TYPE="deprecated" ;;
            4) CHANGELOG_TYPE="removed" ;;
            5) CHANGELOG_TYPE="fixed" ;;
            6) CHANGELOG_TYPE="security" ;;
            *)
                log_error "Invalid choice"
                return 1
                ;;
        esac
    else
        if ! validate_type "${CHANGELOG_TYPE}"; then
            log_error "Invalid change type: ${CHANGELOG_TYPE}"
            return 1
        fi
    fi

    # Prompt for message
    if [[ -z "${CHANGELOG_MESSAGE}" ]]; then
        echo ""
        read -rp "Enter changelog message: " CHANGELOG_MESSAGE

        if [[ -z "${CHANGELOG_MESSAGE}" ]]; then
            log_error "Message cannot be empty"
            return 1
        fi
    fi

    # Prompt for issue number
    if [[ -z "${ISSUE_NUMBER}" ]] && [[ "${AUTO_MODE}" != "true" ]]; then
        echo ""
        read -rp "Enter issue/PR number (optional, press Enter to skip): " ISSUE_NUMBER

        # Allow empty input
        if [[ -z "${ISSUE_NUMBER}" ]]; then
            ISSUE_NUMBER=""
        fi
    fi

    return 0
}

# Auto-generate from commits
# Usage: auto_generate
auto_generate() {
    log_section "Auto-generate CHANGELOG Entry"

    parse_commits_for_changelog

    echo ""
    log_info "Enter the details for your changelog entry:"
    echo ""

    # Prompt for type
    echo "Select change type:"
    echo "  1) added      - New features"
    echo "  2) changed    - Changes to existing functionality"
    echo "  3) deprecated - Soon-to-be removed features"
    echo "  4) removed    - Removed features"
    echo "  5) fixed      - Bug fixes"
    echo "  6) security   - Security vulnerability fixes"
    echo ""

    local type_choice
    read -rp "Enter choice (1-6): " type_choice

    case "${type_choice}" in
        1) CHANGELOG_TYPE="added" ;;
        2) CHANGELOG_TYPE="changed" ;;
        3) CHANGELOG_TYPE="deprecated" ;;
        4) CHANGELOG_TYPE="removed" ;;
        5) CHANGELOG_TYPE="fixed" ;;
        6) CHANGELOG_TYPE="security" ;;
        *)
        log_error "Invalid choice"
        return 1
        ;;
    esac

    # Prompt for message
    echo ""
    read -rp "Enter changelog message (or paste from suggestions above): " CHANGELOG_MESSAGE

    if [[ -z "${CHANGELOG_MESSAGE}" ]]; then
        log_error "Message cannot be empty"
        return 1
    fi

    # Prompt for issue number
    echo ""
    read -rp "Enter issue/PR number (optional, press Enter to skip): " ISSUE_NUMBER

    # Allow empty input
    if [[ -z "${ISSUE_NUMBER}" ]]; then
        ISSUE_NUMBER=""
    fi

    return 0
}

# Validate CHANGELOG format
# Usage: validate_changelog
# Returns: 0 if valid, 1 if issues found
validate_changelog() {
    if [[ ! -f "${CHANGELOG_FILE}" ]]; then
        log_error "CHANGELOG.md not found"
        return 1
    fi

    log_info "Validating CHANGELOG.md format..."

    local issues=0

    # Check for [Unreleased] section
    if ! grep -q "## \[Unreleased\]" "${CHANGELOG_FILE}"; then
        log_error "Missing [Unreleased] section"
        issues=$((issues + 1))
    fi

    # Check for version format
    if ! grep -q "## \[[0-9]" "${CHANGELOG_FILE}"; then
        log_warn "No version sections found"
    fi

    # Check for proper categories
    local categories=("Added" "Changed" "Deprecated" "Removed" "Fixed" "Security")
    for category in "${categories[@]}"; do
        if grep -q "### ${category}" "${CHANGELOG_FILE}"; then
            log_debug "Found category: ${category}"
        fi
    done

    if [[ ${issues} -eq 0 ]]; then
        log_success "CHANGELOG.md format is valid"
        return 0
    else
        log_error "Found ${issues} issue(s) in CHANGELOG.md"
        return 1
    fi
}

# Show existing unreleased entries
# Usage: show_unreleased
show_unreleased() {
    if [[ ! -f "${CHANGELOG_FILE}" ]]; then
        log_error "CHANGELOG.md not found"
        return 1
    fi

    log_info "Current [Unreleased] entries:"
    echo ""

    # Extract and display unreleased section
    awk '/## \[Unreleased\]/,/^## \[/' "${CHANGELOG_FILE}" | head -20
}

# =============================================================================
# Main Functions
# =============================================================================

# Create new changelog entry
# Usage: create_entry
create_entry() {
    if [[ "${AUTO_MODE}" == "true" ]]; then
        auto_generate || return $?
    else
        interactive_prompt || return $?
    fi

    # Show what will be added
    echo ""
    log_info "Preview:"
    echo "  Type: ${CHANGELOG_TYPE}"
    echo "  Message: ${CHANGELOG_MESSAGE}"
    [[ -n "${ISSUE_NUMBER}" ]] && echo "  Issue/PR: #${ISSUE_NUMBER}"
    echo ""

    # Confirm
    if [[ "${DRY_RUN}" != "true" ]] && [[ "${AUTO_MODE}" != "true" ]]; then
        local confirm
        read -rp "Add this entry to CHANGELOG.md? (y/N): " confirm

        if [[ "${confirm}" != "y" ]] && [[ "${confirm}" != "Y" ]]; then
            log_info "Cancelled"
            return 0
        fi
    fi

    # Insert the entry
    insert_entry "${CHANGELOG_TYPE}" "${CHANGELOG_MESSAGE}" "${ISSUE_NUMBER}"
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 [options]

Automate CHANGELOG.md updates following Keep a Changelog format.

Options:
  --type TYPE         Change type: added, changed, deprecated, removed,
                      fixed, security
  --message MSG       Changelog message (bypasses prompt)
  --issue NUMBER      Reference issue/PR number
  --auto              Auto-generate from recent commits (interactive)
  --dry-run           Show what would be written without writing
  --show-unreleased   Show current [Unreleased] entries
  --validate          Validate CHANGELOG.md format
  --help, -h          Show this help message

Environment Variables:
  LOG_LEVEL            Log level (debug|info|warn|error) [default: info]

Examples:
  # Interactive mode
  $0

  # Quick entry
  $0 --type added --message "Add new feature" --issue 123

  # Auto-generate from commits
  $0 --auto

  # Preview without writing
  $0 --type fixed --message "Fix login bug" --dry-run

  # Validate changelog
  $0 --validate

  # Show unreleased entries
  $0 --show-unreleased

CHANGELOG Workflow:
  1. Make changes to code
  2. Run: $0
  3. Commit changes (including CHANGELOG.md)
  4. When releasing: move [Unreleased] items to version section

EOF
}

# =============================================================================
# Main Script Entry Point
# =============================================================================

main() {
    local show_help_flag=false
    local validate_only=false
    local show_unreleased_flag=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help_flag=true
                shift
                ;;
            --type)
                export CHANGELOG_TYPE="$2"
                shift 2
                ;;
            --message)
                export CHANGELOG_MESSAGE="$2"
                shift 2
                ;;
            --issue)
                export ISSUE_NUMBER="$2"
                shift 2
                ;;
            --auto)
                export AUTO_MODE="true"
                shift
                ;;
            --dry-run)
                export DRY_RUN="true"
                shift
                ;;
            --validate)
                validate_only=true
                shift
                ;;
            --show-unreleased)
                show_unreleased_flag=true
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

    if [[ "${show_help_flag}" == "true" ]]; then
        show_help
        exit "${EXIT_SUCCESS}"
    fi

    # Change to project root
    cd "${PROJECT_ROOT}"

    # Handle special modes
    if [[ "${validate_only}" == "true" ]]; then
        validate_changelog
        exit $?
    fi

    if [[ "${show_unreleased_flag}" == "true" ]]; then
        show_unreleased
        exit $?
    fi

    # Create entry
    create_entry
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
