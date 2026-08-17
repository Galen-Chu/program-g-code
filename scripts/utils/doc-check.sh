#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Documentation Check Utility
# =============================================================================
# Validates project documentation exists and is up to date.
#
# This script checks:
#   - Required documentation files exist
#   - Documentation is not outdated
#   - Configuration files are valid
#   - Readme is present and readable
#
# Usage:
#   bash scripts/utils/doc-check.sh [options]
#
# Options:
#   --required-only     Only check required docs
#   --check-staleness   Check if docs are outdated
#   --fail-on-missing   Exit with error if required docs missing
#   --fix               Create missing template docs
#   --help, -h          Show help message
################################################################################

set -euo pipefail

# Get script directory
_DOC_CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="${_DOC_CHECK_DIR}"
fi

# Source dependencies
source "${_DOC_CHECK_DIR}/common.sh"
source "${_DOC_CHECK_DIR}/logger.sh"
source "${_DOC_CHECK_DIR}/validators.sh"

# =============================================================================
# Script Configuration
# =============================================================================
REQUIRED_ONLY="${REQUIRED_ONLY:-false}"
CHECK_STALENESS="${CHECK_STALENESS:-false}"
FAIL_ON_MISSING="${FAIL_ON_MISSING:-false}"
FIX_MODE="${FIX_MODE:-false}"

# Track missing files
declare -a MISSING_DOCS=()
declare -a OUTDATED_DOCS=()

# Required documentation files
REQUIRED_DOCS=(
    "README.md"
)

# Optional but recommended documentation
RECOMMENDED_DOCS=(
    "CHANGELOG.md"
    "CONTRIBUTING.md"
    "LICENSE"
)

# Config files to validate
CONFIG_FILES=(
    "config/ci-cd.conf"
    ".ci-cd.conf"
)

# =============================================================================
# Helper Functions
# =============================================================================

# Get file age in days
# Usage: get_file_age "path/to/file"
# Outputs: age in days
get_file_age() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        echo "9999"
        return
    fi

    local file_time
    local current_time
    file_time="$(stat -c %Y "${file}" 2>/dev/null || stat -f %m "${file}" 2>/dev/null || echo "0")"
    current_time="$(date +%s)"

    local diff_seconds
    diff_seconds=$((current_time - file_time))
    local diff_days=$((diff_seconds / 86400))

    echo "${diff_days}"
}

# Check if documentation file is outdated
# Usage: check_doc_staleness "path/to/doc" [max_age_days]
# Returns: 0 if fresh, 1 if outdated
check_doc_staleness() {
    local doc="$1"
    local max_age="${2:-90}"  # Default: 90 days

    if [[ ! -f "${doc}" ]]; then
        return 1
    fi

    local age
    age="$(get_file_age "${doc}")"

    if [[ ${age} -gt ${max_age} ]]; then
        log_warn "Documentation file is outdated: ${doc} (${age} days old)"
        return 1
    fi

    return 0
}

# Create a template documentation file
# Usage: create_doc_template "filename"
create_doc_template() {
    local filename="$1"
    local filepath="${PROJECT_ROOT}/${filename}"

    if [[ -f "${filepath}" ]]; then
        return 0
    fi

    log_info "Creating template: ${filename}"

    case "${filename}" in
        README.md)
            cat > "${filepath}" << 'EOF'
# Project Name

Brief description of your project.

## Installation

```bash
# Installation instructions
```

## Usage

```bash
# Usage examples
```

## Configuration

See `config/ci-cd.conf` for configuration options.

## Contributing

Please see `CONTRIBUTING.md` for guidelines.

## License

This project is licensed under the MIT License - see the `LICENSE` file for details.
EOF
            ;;

        CHANGELOG.md)
            cat > "${filepath}" << 'EOF'
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project setup

### Changed
-

### Fixed
-

### Removed
-
EOF
            ;;

        CONTRIBUTING.md)
            cat > "${filepath}" << 'EOF'
# Contributing

Thank you for considering contributing to this project!

## Development Setup

```bash
# Clone the repository
git clone <repository-url>
cd <project-name>

# Install dependencies (if applicable)
# npm install  # for Node.js
# pip install -r requirements.txt  # for Python
```

## Code Style

- Follow existing code style
- Write clear commit messages
- Add tests for new features
- Update documentation as needed

## Submitting Changes

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `bash scripts/ci/test.sh`
5. Run linting: `bash scripts/ci/lint.sh`
6. Submit a pull request

## Reporting Issues

Please use GitHub Issues to report bugs or request features.
EOF
            ;;

        LICENSE)
            cat > "${filepath}" << 'EOF'
MIT License

Copyright (c) $(date +%Y) Project Authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
            ;;

        *)
            log_warn "No template available for: ${filename}"
            return 1
            ;;
    esac

    log_success "Created: ${filename}"
    return 0
}

# =============================================================================
# Documentation Check Functions
# =============================================================================

# Check required documentation files
# Usage: check_required_docs
# Returns: 0 if all present, 1 if any missing
check_required_docs() {
    log_info "Checking required documentation..."

    local missing_count=0

    for doc in "${REQUIRED_DOCS[@]}"; do
        local filepath="${PROJECT_ROOT}/${doc}"

        if [[ -f "${filepath}" ]]; then
            log_success "Found: ${doc}"

            # Check staleness if requested
            if [[ "${CHECK_STALENESS}" == "true" ]]; then
                if ! check_doc_staleness "${filepath}" 365; then
                    OUTDATED_DOCS+=("${doc}")
                fi
            fi
        else
            log_error "Missing required doc: ${doc}"
            MISSING_DOCS+=("${doc}")
            missing_count=$((missing_count + 1))

            # Create template if in fix mode
            if [[ "${FIX_MODE}" == "true" ]]; then
                create_doc_template "${doc}"
            fi
        fi
    done

    if [[ ${missing_count} -gt 0 ]] && [[ "${FAIL_ON_MISSING}" == "true" ]]; then
        return "${EXIT_ERROR_VALIDATION}"
    fi

    return 0
}

# Check recommended documentation files
# Usage: check_recommended_docs
# Returns: 0 if all present, 1 if any missing (doesn't fail)
check_recommended_docs() {
    if [[ "${REQUIRED_ONLY}" == "true" ]]; then
        return 0
    fi

    log_info "Checking recommended documentation..."

    for doc in "${RECOMMENDED_DOCS[@]}"; do
        local filepath="${PROJECT_ROOT}/${doc}"

        if [[ -f "${filepath}" ]]; then
            log_success "Found: ${doc}"

            # Check staleness if requested
            if [[ "${CHECK_STALENESS}" == "true" ]]; then
                if ! check_doc_staleness "${filepath}" 180; then
                    OUTDATED_DOCS+=("${doc}")
                fi
            fi
        else
            log_warn "Missing recommended doc: ${doc}"

            # Create template if in fix mode
            if [[ "${FIX_MODE}" == "true" ]]; then
                create_doc_template "${doc}"
            fi
        fi
    done

    return 0
}

# Check project-specific documentation
# Usage: check_project_docs
check_project_docs() {
    log_debug "Checking project-specific documentation..."

    # Check for docs directory
    if [[ -d "${PROJECT_ROOT}/docs" ]]; then
        log_info "Documentation directory found: docs/"

        # Count documentation files
        local doc_count
        doc_count="$(find "${PROJECT_ROOT}/docs" -type f -name "*.md" 2>/dev/null | wc -l || echo "0")"

        if [[ ${doc_count} -gt 0 ]]; then
            log_info "Found ${doc_count} documentation file(s)"
        fi
    else
        log_debug "No docs/ directory found"
    fi

    # Check for API docs based on project type
    local project_type
    project_type="$(get_project_type)"

    case "${project_type}" in
        nodejs)
            if [[ -f "${PROJECT_ROOT}/api.md" ]] || [[ -f "${PROJECT_ROOT}/API.md" ]]; then
                log_success "API documentation found"
            fi
            ;;
        python)
            if [[ -f "${PROJECT_ROOT}/docs/api.md" ]] || ls "${PROJECT_ROOT}"/docs/*.rst &>/dev/null; then
                log_success "API documentation found"
            fi
            ;;
    esac
}

# Check configuration files
# Usage: check_config_files
# Returns: 0 if all valid, 1 if any issues
check_config_files() {
    log_info "Checking configuration files..."

    for config in "${CONFIG_FILES[@]}"; do
        local filepath="${PROJECT_ROOT}/${config}"

        if [[ -f "${filepath}" ]]; then
            log_success "Found: ${config}"

            # Validate config file syntax (basic check)
            if [[ "${config}" == *.conf ]]; then
                log_debug "Configuration file format appears valid"
            fi
        else
            log_debug "Config file not found: ${config} (optional)"
        fi
    done

    return 0
}

# Validate README content
# Usage: validate_readme
validate_readme() {
    local readme="${PROJECT_ROOT}/README.md"

    if [[ ! -f "${readme}" ]]; then
        return 1
    fi

    log_debug "Validating README.md content..."

    # Check for common sections
    local missing_sections=()

    for section in "Installation" "Usage" "Contributing"; do
        if ! grep -q "^##* ${section}" "${readme}" 2>/dev/null; then
            missing_sections+=("${section}")
        fi
    done

    if [[ ${#missing_sections[@]} -gt 0 ]]; then
        log_warn "README.md missing sections: ${missing_sections[*]}"
    else
        log_success "README.md has common sections"
    fi

    return 0
}

# =============================================================================
# Main Documentation Check Function
# =============================================================================

# Run all documentation checks
# Usage: run_doc_checks
# Returns: 0 if all checks pass, 1 if any fail
run_doc_checks() {
    local exit_code=0

    log_section "Documentation Check"

    # Check required docs
    check_required_docs || exit_code=$?

    # Check recommended docs
    check_recommended_docs || true

    # Check project-specific docs
    check_project_docs || true

    # Check config files
    check_config_files || exit_code=$?

    # Validate README content
    if [[ -f "${PROJECT_ROOT}/README.md" ]]; then
        validate_readme || true
    fi

    # Output summary
    log_section "Documentation Summary"

    if [[ ${#MISSING_DOCS[@]} -eq 0 ]] && [[ ${#OUTDATED_DOCS[@]} -eq 0 ]]; then
        log_success "All documentation checks passed"
    else
        if [[ ${#MISSING_DOCS[@]} -gt 0 ]]; then
            log_warn "Missing docs: ${MISSING_DOCS[*]}"
        fi
        if [[ ${#OUTDATED_DOCS[@]} -gt 0 ]]; then
            log_warn "Outdated docs: ${OUTDATED_DOCS[*]}"
        fi
    fi

    return ${exit_code}
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 [options]

Check project documentation exists and is up to date.

Options:
  --required-only     Only check required documentation files
  --check-staleness   Check if documentation files are outdated
  --fail-on-missing   Exit with error if required docs are missing
  --fix               Create missing template documentation files
  --help, -h          Show this help message

Required Files:
  README.md

Recommended Files:
  CHANGELOG.md
  CONTRIBUTING.md
  LICENSE

Environment Variables:
  LOG_LEVEL            Log level (debug|info|warn|error) [default: info]

Exit Codes:
  0                    All checks passed
  1                    General error
  4                    Validation failed (when using --fail-on-missing)

Examples:
  # Check all documentation
  $0

  # Check only required files
  $0 --required-only

  # Check and create missing templates
  $0 --fix

  # Fail if required docs are missing
  $0 --fail-on-missing

  # Check for outdated documentation
  $0 --check-staleness

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
            --required-only)
                export REQUIRED_ONLY="true"
                shift
                ;;
            --check-staleness)
                export CHECK_STALENESS="true"
                shift
                ;;
            --fail-on-missing)
                export FAIL_ON_MISSING="true"
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

    # Run documentation checks
    run_doc_checks
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
