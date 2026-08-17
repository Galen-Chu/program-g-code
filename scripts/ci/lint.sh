#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Lint Script
# =============================================================================
# Auto-detects project type and runs appropriate linters.
#
# Usage:
#   ./scripts/ci/lint.sh [options] [files...]
#
# Options:
#   --fix          Auto-fix linting issues when possible
#   --dry-run      Show what would be linted without running
#   --config FILE  Use custom configuration file
#   --help, -h     Show help message
#
# Environment Variables:
#   LINT_ENABLED   Enable/disable linting (default: true)
#   AUTO_FIX       Auto-fix issues (default: false)
#   PROJECT_TYPE   Force project type (default: auto-detect)
################################################################################

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "${SCRIPT_DIR}/../utils/common.sh"
source "${SCRIPT_DIR}/../utils/logger.sh"
source "${SCRIPT_DIR}/../utils/validators.sh"

# =============================================================================
# Script Configuration
# =============================================================================
LINT_ENABLED="${LINT_ENABLED:-true}"
AUTO_FIX="${AUTO_FIX:-false}"
FAIL_ON_WARNINGS="${FAIL_ON_WARNINGS:-true}"
MAX_ISSUES="${MAX_ISSUES:-0}"

# Exit codes
EXIT_LINT_FAILED=10
EXIT_TOO_MANY_ISSUES=11

# =============================================================================
# Linter Detection and Execution
# =============================================================================

# Run ESLint for Node.js projects
# Usage: lint_eslint [files...]
lint_eslint() {
    local files=("${@:-.}")
    local eslint_cmd="eslint"
    local args=()

    # Check for ESLint configuration
    if [[ ! -f "${PROJECT_ROOT}/.eslintrc.js" ]] && \
       [[ ! -f "${PROJECT_ROOT}/.eslintrc.json" ]] && \
       [[ ! -f "${PROJECT_ROOT}/.eslintrc.yml" ]] && \
       [[ ! -f "${PROJECT_ROOT}/.eslintrc.yaml" ]] && \
       [[ ! -f "${PROJECT_ROOT}/eslint.config.js" ]] && \
       ! grep -q '"eslint"' "${PROJECT_ROOT}/package.json" 2>/dev/null; then
        log_warn "No ESLint configuration found, attempting to run anyway"
    fi

    # Check if eslint is installed
    if ! check_command "${eslint_cmd}"; then
        # Try npx eslint
        if check_command npx; then
            eslint_cmd="npx eslint"
        else
            log_error "ESLint not found. Install it with: npm install -D eslint"
            return "${EXIT_ERROR_MISSING_DEPS}"
        fi
    fi

    # Build arguments
    if [[ "${AUTO_FIX}" == "true" ]]; then
        args+=("--fix")
    fi

    args+=("--format=compact")

    # Only enforce zero warnings when explicitly requested (default: off,
    # so warnings are shown but don't fail the build)
    if [[ "${FAIL_ON_WARNINGS}" == "true" ]]; then
        args+=("--max-warnings=0")
    fi

    # Run ESLint
    log_info "Running ESLint..."
    log_cmd "${eslint_cmd}" "${args[@]}" "${files[@]}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${eslint_cmd} ${args[*]} ${files[*]}"
        return 0
    fi

    # Run ESLint and capture output
    local output
    local exit_code

    output="$(${eslint_cmd} "${args[@]}" "${files[@]}" 2>&1)" || exit_code=$?
    output_exit_code="${exit_code:-0}"

    # Print output
    if [[ -n "${output}" ]]; then
        echo "${output}"
    fi

    if [[ ${output_exit_code} -ne 0 ]]; then
        log_error "ESLint found issues"
        return "${EXIT_LINT_FAILED}"
    fi

    log_success "ESLint passed"
    return 0
}

# Run flake8 for Python projects
# Usage: lint_flake8 [files...]
lint_flake8() {
    local files=("${@:-.}")
    local flake8_cmd="flake8"
    local args=()

    # Check if flake8 is installed
    if ! check_command "${flake8_cmd}"; then
        log_error "flake8 not found. Install it with: pip install flake8"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    # Build arguments
    if [[ "${AUTO_FIX}" == "true" ]]; then
        log_warn "flake8 does not support auto-fix. Consider using 'autopep8' or 'black'"
    fi

    args+=("--max-line-length=100")
    args+=("--ignore=E203,E266,W503")
    args+=("--exclude=.git,__pycache__,.venv,venv,build,dist")

    # Run flake8
    log_info "Running flake8..."
    log_cmd "${flake8_cmd}" "${args[@]}" "${files[@]}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${flake8_cmd} ${args[*]} ${files[*]}"
        return 0
    fi

    if ! ${flake8_cmd} "${args[@]}" "${files[@]}"; then
        log_error "flake8 found issues"
        return "${EXIT_LINT_FAILED}"
    fi

    log_success "flake8 passed"
    return 0
}

# Run pylint for Python projects
# Usage: lint_pylint [files...]
lint_pylint() {
    local files=("${@:-.}")
    local pylint_cmd="pylint"
    local args=()

    if ! check_command "${pylint_cmd}"; then
        log_error "pylint not found. Install it with: pip install pylint"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    args+=("--errors-only")

    if [[ "${FAIL_ON_WARNINGS}" == "false" ]]; then
        args+=("--disable=all")
        args+=("--enable=E,F")
    fi

    log_info "Running pylint..."
    log_cmd "${pylint_cmd}" "${args[@]}" "${files[@]}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${pylint_cmd} ${args[*]} ${files[*]}"
        return 0
    fi

    if ! ${pylint_cmd} "${args[@]}" "${files[@]}"; then
        log_error "pylint found issues"
        return "${EXIT_LINT_FAILED}"
    fi

    log_success "pylint passed"
    return 0
}

# Run golangci-lint for Go projects
# Usage: lint_golangci [files...]
lint_golangci() {
    local files=("${@:-./...}")
    local golangci_cmd="golangci-lint"
    local args=()

    if ! check_command "${golangci_cmd}"; then
        log_error "golangci-lint not found. Install it from: https://golangci-lint.run/usage/install/"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    args+=("run")

    if [[ "${AUTO_FIX}" == "true" ]]; then
        args+=("--fix")
    fi

    log_info "Running golangci-lint..."
    log_cmd "${golangci_cmd}" "${args[@]}" "--" "${files[@]}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${golangci_cmd} ${args[*]} ${files[*]}"
        return 0
    fi

    if ! ${golangci_cmd} "${args[@]}" -- "${files[@]}"; then
        log_error "golangci-lint found issues"
        return "${EXIT_LINT_FAILED}"
    fi

    log_success "golangci-lint passed"
    return 0
}

# Run gofmt for Go projects
# Usage: lint_gofmt [files...]
lint_gofmt() {
    local files=("${@:-.}")
    local gofmt_cmd="gofmt"

    if ! check_command "${gofmt_cmd}"; then
        log_error "gofmt not found"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    log_info "Running gofmt..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${gofmt_cmd} -l ${files[*]}"
        return 0
    fi

    local unformatted
    unformatted="$(${gofmt_cmd} -l "${files[@]}")"

    if [[ -n "${unformatted}" ]]; then
        log_error "The following files are not formatted:"
        echo "${unformatted}"

        if [[ "${AUTO_FIX}" == "true" ]]; then
            log_info "Running gofmt -w..."
            ${gofmt_cmd} -w "${files[@]}"
        fi

        return "${EXIT_LINT_FAILED}"
    fi

    log_success "gofmt passed"
    return 0
}

# Run mvn checkstyle for Java/Maven projects
# Usage: lint_maven [files...]
lint_maven() {
    local mvn_cmd="mvn"

    if ! check_command "${mvn_cmd}"; then
        log_error "Maven not found"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    log_info "Running Maven checkstyle..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${mvn_cmd} checkstyle:check"
        return 0
    fi

    if ! ${mvn_cmd} checkstyle:check; then
        log_error "Maven checkstyle found issues"
        return "${EXIT_LINT_FAILED}"
    fi

    log_success "Maven checkstyle passed"
    return 0
}

# Run gradle checkstyle for Java/Gradle projects
# Usage: lint_gradle [files...]
lint_gradle() {
    local gradle_cmd="./gradlew"
    local args=("checkstyleMain")

    if [[ ! -f "${gradle_cmd}" ]] && check_command gradle; then
        gradle_cmd="gradle"
    fi

    log_info "Running Gradle checkstyle..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${gradle_cmd} ${args[*]}"
        return 0
    fi

    if ! ${gradle_cmd} "${args[@]}"; then
        log_error "Gradle checkstyle found issues"
        return "${EXIT_LINT_FAILED}"
    fi

    log_success "Gradle checkstyle passed"
    return 0
}

# Run hadolint for Dockerfiles
# Usage: lint_docker [files...]
lint_docker() {
    local files=("${@:-Dockerfile}")
    local hadolint_cmd="hadolint"

    if ! check_command "${hadolint_cmd}"; then
        log_warn "hadolint not found. Install it from: https://github.com/hadolint/hadolint"
        log_warn "Skipping Dockerfile linting"
        return 0
    fi

    log_info "Running hadolint..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${hadolint_cmd} ${files[*]}"
        return 0
    fi

    for file in "${files[@]}"; do
        if [[ -f "${file}" ]]; then
            if ! ${hadolint_cmd} "${file}"; then
                log_error "hadolint found issues in ${file}"
                return "${EXIT_LINT_FAILED}"
            fi
        fi
    done

    log_success "hadolint passed"
    return 0
}

# =============================================================================
# Main Lint Function
# =============================================================================

# Main linting logic
# Usage: main_lint [files...]
main_lint() {
    local files=("$@")

    log_section "Starting Lint"

    # Check if linting is enabled
    if [[ "${LINT_ENABLED}" != "true" ]]; then
        log_info "Linting is disabled (LINT_ENABLED=${LINT_ENABLED})"
        return 0
    fi

    # Detect project type
    local project_type
    project_type="$(get_project_type)"

    log_info "Project type: ${project_type}"
    log_debug "Files to lint: ${files[*]:-.}"

    # Run appropriate linter based on project type
    local exit_code=0

    case "${project_type}" in
        nodejs)
            lint_eslint "${files[@]:-.}" || exit_code=$?
            ;;

        python)
            # Try flake8 first, fall back to pylint
            if check_command flake8; then
                lint_flake8 "${files[@]:-.}" || exit_code=$?
            elif check_command pylint; then
                lint_pylint "${files[@]:-.}" || exit_code=$?
            else
                log_error "No Python linter found. Install flake8 or pylint"
                exit_code="${EXIT_ERROR_MISSING_DEPS}"
            fi
            ;;

        go)
            # Try golangci-lint first, fall back to gofmt
            if check_command golangci-lint; then
                lint_golangci "${files[@]:-./...}" || exit_code=$?
            else
                lint_gofmt "${files[@]:-.}" || exit_code=$?
            fi
            ;;

        maven)
            lint_maven || exit_code=$?
            ;;

        gradle)
            lint_gradle || exit_code=$?
            ;;

        docker)
            lint_docker "${files[@]:-Dockerfile}" || exit_code=$?
            ;;

        unknown)
            log_warn "Could not detect project type"
            log_warn "Please set PROJECT_TYPE environment variable"
            return "${EXIT_ERROR_CONFIG}"
            ;;

        *)
            log_error "Unsupported project type: ${project_type}"
            return "${EXIT_ERROR_CONFIG}"
            ;;
    esac

    if [[ ${exit_code} -eq 0 ]]; then
        log_section "Lint Complete"
        return 0
    else
        return ${exit_code}
    fi
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 [options] [files...]

Auto-detects project type and runs appropriate linters.

Options:
  --fix          Auto-fix linting issues when possible
  --dry-run      Show what would be linted without running
  --config FILE  Use custom configuration file
  --help, -h     Show this help message

Supported Languages:
  - Node.js/JavaScript: ESLint
  - Python: flake8, pylint
  - Go: golangci-lint, gofmt
  - Java (Maven): Maven checkstyle
  - Java (Gradle): Gradle checkstyle
  - Docker: hadolint

Environment Variables:
  LINT_ENABLED     Enable/disable linting (default: true)
  AUTO_FIX         Auto-fix issues (default: false)
  FAIL_ON_WARNINGS Fail on warnings (default: true)
  PROJECT_TYPE     Force project type (default: auto-detect)

Examples:
  # Lint all files
  $0

  # Lint specific directory
  $0 src/

  # Auto-fix issues
  $0 --fix

  # Dry run
  $0 --dry-run

EOF
}

# =============================================================================
# Main Script Entry Point
# =============================================================================

main() {
    local files=()
    local show_help=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help=true
                shift
                ;;
            --fix)
                export AUTO_FIX="true"
                shift
                ;;
            --dry-run)
                export DRY_RUN="true"
                shift
                ;;
            --config)
                export CONFIG_FILE="$2"
                shift 2
                ;;
            --log-level)
                export LOG_LEVEL="$2"
                shift 2
                ;;
            --)
                shift
                files+=("$@")
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                exit "${EXIT_ERROR_GENERAL}"
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done

    if [[ "${show_help}" == "true" ]]; then
        show_help
        exit "${EXIT_SUCCESS}"
    fi

    # Change to project root
    cd "${PROJECT_ROOT}"

    # Run main lint function
    main_lint "${files[@]:+.}"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
