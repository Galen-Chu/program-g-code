#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Test Script
# =============================================================================
# Auto-detects project type and runs appropriate test runners.
#
# Usage:
#   ./scripts/ci/test.sh [options] [test_files...]
#
# Options:
#   --coverage     Generate coverage report
#   --parallel     Run tests in parallel when possible
#   --watch        Watch mode (for development)
#   --dry-run      Show what would be tested without running
#   --filter PATTERN Run tests matching pattern
#   --timeout SECONDS Test timeout
#   --help, -h     Show help message
#
# Environment Variables:
#   TEST_ENABLED   Enable/disable testing (default: true)
#   PARALLEL_TESTS Run tests in parallel (default: true)
#   TEST_TIMEOUT   Default timeout in seconds (default: 300)
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
TEST_ENABLED="${TEST_ENABLED:-true}"
PARALLEL_TESTS="${PARALLEL_TESTS:-true}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"
COVERAGE_ENABLED="${COVERAGE_ENABLED:-true}"

# Test output directories
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-test-results}"
COVERAGE_DIR="${COVERAGE_DIR:-coverage}"

# Exit codes
EXIT_TEST_FAILED=10
EXIT_TIMEOUT=11

# =============================================================================
# Test Runner Detection and Execution
# =============================================================================

# Run Jest for Node.js projects
# Usage: test_jest [test_files...]
test_jest() {
    local test_files=("$@")
    local jest_cmd="jest"
    local args=()

    # Check if Jest is available
    if ! check_command "${jest_cmd}"; then
        # Try npx jest
        if check_command npx; then
            jest_cmd="npx jest"
        else
            log_error "Jest not found. Install it with: npm install -D jest"
            return "${EXIT_ERROR_MISSING_DEPS}"
        fi
    fi

    # Build arguments
    if [[ "${GENERATE_COVERAGE}" == "true" ]]; then
        args+=("--coverage")
        args+=("--coverageDirectory=${COVERAGE_DIR}")
        args+=("--coverageReporters=json lcov text")
    fi

    if [[ "${PARALLEL_TESTS}" == "true" ]]; then
        args+=("--maxWorkers=${PARALLEL_JOBS}")
    fi

    if [[ -n "${TEST_FILTER:-}" ]]; then
        args+=("--testNamePattern='${TEST_FILTER}'")
    fi

    # Add test files if specified
    if [[ ${#test_files[@]} -gt 0 ]]; then
        args+=("${test_files[@]}")
    fi

    # Run Jest
    log_info "Running Jest..."
    log_cmd "${jest_cmd}" "${args[@]}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${jest_cmd} ${args[*]}"
        return 0
    fi

    if ! ${jest_cmd} "${args[@]}"; then
        log_error "Jest tests failed"
        return "${EXIT_TEST_FAILED}"
    fi

    log_success "Jest tests passed"
    return 0
}

# Run Mocha for Node.js projects
# Usage: test_mocha [test_files...]
test_mocha() {
    local test_files=("${@:-test/}")
    local mocha_cmd="mocha"
    local args=()

    if ! check_command "${mocha_cmd}"; then
        if check_command npx; then
            mocha_cmd="npx mocha"
        else
            log_error "Mocha not found. Install it with: npm install -D mocha"
            return "${EXIT_ERROR_MISSING_DEPS}"
        fi
    fi

    args+=("--reporter=json")
    args+=("--reporter-options=output=${TEST_RESULTS_DIR}/mocha-results.json")

    if [[ "${GENERATE_COVERAGE}" == "true" ]]; then
        if check_command nyc; then
            mocha_cmd="nyc ${mocha_cmd}"
            args+=("--reporter=lcov")
            args+=("--reporter=text")
        else
            log_warn "nyc not found. Install with: npm install -D nyc"
        fi
    fi

    args+=("${test_files[@]}")

    log_info "Running Mocha..."
    log_cmd "${mocha_cmd}" "${args[@]}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${mocha_cmd} ${args[*]}"
        return 0
    fi

    if ! bash -c "${mocha_cmd} ${args[*]}"; then
        log_error "Mocha tests failed"
        return "${EXIT_TEST_FAILED}"
    fi

    log_success "Mocha tests passed"
    return 0
}

# Run pytest for Python projects
# Usage: test_pytest [test_files...]
test_pytest() {
    local test_files=("${@:-tests/}")
    local pytest_cmd="pytest"
    local args=()

    if ! check_command "${pytest_cmd}"; then
        log_error "pytest not found. Install it with: pip install pytest"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    # Create test results directory (for tools that need it)
    ensure_dir "${TEST_RESULTS_DIR}"

    if [[ "${GENERATE_COVERAGE}" == "true" ]]; then
        args+=("--cov=.")
        args+=("--cov-report=xml:${COVERAGE_DIR}/coverage.xml")
        args+=("--cov-report=html:${COVERAGE_DIR}")
        args+=("--cov-report=term")
    fi

    if [[ "${PARALLEL_TESTS}" == "true" ]] && check_command pytest-xdist; then
        args+=("-n")
        args+=("${PARALLEL_JOBS}")
    fi

    if [[ -n "${TEST_FILTER:-}" ]]; then
        args+=("-k '${TEST_FILTER}'")
    fi

    args+=("--timeout=${TEST_TIMEOUT}")
    args+=("-v")

    # Add test files if specified
    if [[ ${#test_files[@]} -gt 0 ]]; then
        args+=("${test_files[@]}")
    fi

    log_info "Running pytest..."
    log_cmd "${pytest_cmd}" "${args[@]}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${pytest_cmd} ${args[*]}"
        return 0
    fi

    if ! ${pytest_cmd} "${args[@]}"; then
        log_error "pytest tests failed"
        return "${EXIT_TEST_FAILED}"
    fi

    log_success "pytest tests passed"
    return 0
}

# Run unittest for Python projects
# Usage: test_unittest [test_files...]
test_unittest() {
    local test_files=("${@:-discover}")

    log_info "Running unittest..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: python -m unittest ${test_files[*]}"
        return 0
    fi

    if ! python -m unittest "${test_files[@]}" -v; then
        log_error "unittest tests failed"
        return "${EXIT_TEST_FAILED}"
    fi

    log_success "unittest tests passed"
    return 0
}

# Run go test for Go projects
# Usage: test_go [test_packages...]
test_go() {
    local test_packages=("${@:-./...}")
    local go_cmd="go"
    local args=("test")

    if ! check_command "${go_cmd}"; then
        log_error "Go not found"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    if [[ "${GENERATE_COVERAGE}" == "true" ]]; then
        args+=("-coverprofile=${COVERAGE_DIR}/coverage.out")
        args+=("-covermode=atomic")
    fi

    if [[ "${PARALLEL_TESTS}" == "true" ]]; then
        args+=("-parallel=${PARALLEL_JOBS}")
    fi

    if [[ -n "${TEST_FILTER:-}" ]]; then
        args+=("-run '${TEST_FILTER}'")
    fi

    args+=("-v")
    args+=("-timeout=${TEST_TIMEOUT}s")
    args+=("${test_packages[@]}")

    log_info "Running go test..."
    log_cmd "${go_cmd}" "${args[@]}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${go_cmd} ${args[*]}"
        return 0
    fi

    # Ensure coverage directory exists
    if [[ "${GENERATE_COVERAGE}" == "true" ]]; then
        ensure_dir "${COVERAGE_DIR}"
    fi

    if ! ${go_cmd} "${args[@]}"; then
        log_error "Go tests failed"
        return "${EXIT_TEST_FAILED}"
    fi

    # Generate coverage report
    if [[ "${GENERATE_COVERAGE}" == "true" ]]; then
        if check_command go tool cover; then
            ${go_cmd} tool cover -html="${COVERAGE_DIR}/coverage.out" -o "${COVERAGE_DIR}/coverage.html"
            log_info "Coverage report: ${COVERAGE_DIR}/coverage.html"
        fi
    fi

    log_success "Go tests passed"
    return 0
}

# Run mvn test for Java/Maven projects
# Usage: test_maven [test_classes...]
test_maven() {
    local mvn_cmd="mvn"
    local args=("test")

    if ! check_command "${mvn_cmd}"; then
        log_error "Maven not found"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    # Generate JUnit reports
    args+=("-Dsurefire.reportsFolder=${TEST_RESULTS_DIR}")

    log_info "Running Maven tests..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${mvn_cmd} ${args[*]}"
        return 0
    fi

    ensure_dir "${TEST_RESULTS_DIR}"

    if ! ${mvn_cmd} "${args[@]}"; then
        log_error "Maven tests failed"
        return "${EXIT_TEST_FAILED}"
    fi

    log_success "Maven tests passed"
    return 0
}

# Run gradle test for Java/Gradle projects
# Usage: test_gradle [test_classes...]
test_gradle() {
    local gradle_cmd="./gradlew"

    if [[ ! -f "${gradle_cmd}" ]] && check_command gradle; then
        gradle_cmd="gradle"
    fi

    log_info "Running Gradle tests..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: ${gradle_cmd} test"
        return 0
    fi

    if ! ${gradle_cmd} test; then
        log_error "Gradle tests failed"
        return "${EXIT_TEST_FAILED}"
    fi

    log_success "Gradle tests passed"
    return 0
}

# =============================================================================
# Main Test Function
# =============================================================================

# Main testing logic
# Usage: main_test [test_files...]
main_test() {
    local test_files=("$@")

    log_section "Starting Tests"

    # Check if testing is enabled
    if [[ "${TEST_ENABLED}" != "true" ]]; then
        log_info "Testing is disabled (TEST_ENABLED=${TEST_ENABLED})"
        return 0
    fi

    # Detect project type
    local project_type
    project_type="$(get_project_type)"

    log_info "Project type: ${project_type}"
    log_debug "Test files: ${test_files[*]:-default}"

    # Prepare output directories
    ensure_dir "${TEST_RESULTS_DIR}"
    if [[ "${GENERATE_COVERAGE}" == "true" ]]; then
        ensure_dir "${COVERAGE_DIR}"
    fi

    # Run appropriate test runner based on project type
    local exit_code=0

    case "${project_type}" in
        nodejs)
            # Check for Jest first, then Mocha
            if grep -q '"jest"' "${PROJECT_ROOT}/package.json" 2>/dev/null || \
               [[ -f "${PROJECT_ROOT}/jest.config.js" ]] || \
               [[ -f "${PROJECT_ROOT}/jest.config.ts" ]]; then
                test_jest "${test_files[@]:+.}" || exit_code=$?
            elif grep -q '"mocha"' "${PROJECT_ROOT}/package.json" 2>/dev/null; then
                test_mocha "${test_files[@]:-test/}" || exit_code=$?
            else
                log_warn "Could not detect test runner for Node.js"
                log_warn "Trying Jest as default..."
                test_jest "${test_files[@]:+.}" || exit_code=$?
            fi
            ;;

        python)
            # Try pytest first, fall back to unittest
            if check_command pytest || [[ -f "${PROJECT_ROOT}/pytest.ini" ]] || [[ -f "${PROJECT_ROOT}/pyproject.toml" ]]; then
                test_pytest "${test_files[@]:-tests/}" || exit_code=$?
            elif check_command python; then
                test_unittest "${test_files[@]:-discover}" || exit_code=$?
            else
                log_error "No Python test runner found"
                exit_code="${EXIT_ERROR_MISSING_DEPS}"
            fi
            ;;

        go)
            test_go "${test_files[@]:-./...}" || exit_code=$?
            ;;

        maven)
            test_maven || exit_code=$?
            ;;

        gradle)
            test_gradle || exit_code=$?
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
        log_section "Tests Complete"

        # Print coverage summary if available
        if [[ "${GENERATE_COVERAGE}" == "true" ]]; then
            log_info "Coverage reports generated in: ${COVERAGE_DIR}"
        fi

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
Usage: $0 [options] [test_files...]

Auto-detects project type and runs appropriate test runners.

Options:
  --coverage        Generate coverage report
  --parallel        Run tests in parallel when possible
  --watch           Watch mode (for development)
  --dry-run         Show what would be tested without running
  --filter PATTERN  Run tests matching pattern
  --timeout SECONDS Test timeout (default: 300)
  --help, -h        Show this help message

Supported Test Runners:
  - Node.js: Jest, Mocha, Vitest
  - Python: pytest, unittest
  - Go: go test
  - Java (Maven): mvn test
  - Java (Gradle): gradle test

Environment Variables:
  TEST_ENABLED      Enable/disable testing (default: true)
  PARALLEL_TESTS    Run tests in parallel (default: true)
  TEST_TIMEOUT      Default timeout in seconds (default: 300)
  PARALLEL_JOBS     Number of parallel jobs (default: 4)
  COVERAGE_ENABLED  Generate coverage reports (default: true)

Examples:
  # Run all tests
  $0

  # Run specific test file
  $0 tests/test_api.py

  # Run with coverage
  $0 --coverage

  # Run tests matching pattern
  $0 --filter "user"

EOF
}

# =============================================================================
# Main Script Entry Point
# =============================================================================

main() {
    local test_files=()
    local GENERATE_COVERAGE="${COVERAGE_ENABLED}"
    local show_help=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help=true
                shift
                ;;
            --coverage)
                GENERATE_COVERAGE="true"
                shift
                ;;
            --parallel)
                export PARALLEL_TESTS="true"
                shift
                ;;
            --watch)
                export WATCH_MODE="true"
                shift
                ;;
            --dry-run)
                export DRY_RUN="true"
                shift
                ;;
            --filter)
                export TEST_FILTER="$2"
                shift 2
                ;;
            --timeout)
                export TEST_TIMEOUT="$2"
                shift 2
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
                test_files+=("$@")
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                exit "${EXIT_ERROR_GENERAL}"
                ;;
            *)
                test_files+=("$1")
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

    # Run main test function
    main_test "${test_files[@]}"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
