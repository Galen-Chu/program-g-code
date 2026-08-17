#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Health Check Utilities
# =============================================================================
# Perform health checks on services via HTTP endpoints and TCP ports.
#
# Usage:
#   ./scripts/utils/health-check.sh <url|host:port> [options]
#
# Options:
#   --tcp               Use TCP check instead of HTTP
#   --retry N           Number of retries (default: 30)
#   --interval N        Interval between retries in seconds (default: 10)
#   --timeout N         Timeout for each check in seconds (default: 5)
#   --expected-code N   Expected HTTP status code (default: 200)
#   --expected-text TEXT Expected text in response body
#   --headers FILE      File with request headers (key: value format)
#   --help, -h          Show help message
#
# Environment Variables:
#   HEALTH_CHECK_TIMEOUT    Default timeout (default: 300)
#   HEALTH_CHECK_INTERVAL   Default interval (default: 10)
#   HEALTH_CHECK_RETRIES    Default retries (default: 30)
################################################################################

set -euo pipefail

# Source dependencies (use own dir; don't overwrite caller's SCRIPT_DIR)
_HC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_HC_DIR}/common.sh"
source "${_HC_DIR}/logger.sh"

# =============================================================================
# Configuration
# =============================================================================
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-30}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-5}"
EXPECTED_STATUS_CODE="${EXPECTED_STATUS_CODE:-200}"
EXPECTED_TEXT="${EXPECTED_TEXT:-}"

# =============================================================================
# HTTP Health Check
# =============================================================================

# Perform HTTP health check
# Usage: http_health_check url [retry_count] [interval] [timeout]
http_health_check() {
    local url="$1"
    local max_retries="${2:-${HEALTH_CHECK_RETRIES}}"
    local interval="${3:-${HEALTH_CHECK_INTERVAL}}"
    local timeout="${4:-${CHECK_TIMEOUT}}"
    local expected_code="${5:-${EXPECTED_STATUS_CODE}}"
    local expected_text="${6:-${EXPECTED_TEXT:-}}"
    local headers_file="${7:-}"

    local retries=0
    local last_status=""
    local last_response=""

    log_info "Starting health check for: ${url}"
    log_debug "Max retries: ${max_retries}, Interval: ${interval}s, Timeout: ${timeout}s"

    while [[ ${retries} -lt ${max_retries} ]]; do
        retries=$((retries + 1))

        # Build curl command
        local curl_cmd=("curl" "-s" "-o" "-" "-w" "%{http_code}" "--max-time" "${timeout}")

        # Add headers if file provided
        if [[ -n "${headers_file}" ]] && [[ -f "${headers_file}" ]]; then
            while IFS=':' read -r key value; do
                # Skip empty lines and comments
                [[ -z "${key}" ]] || [[ "${key}" =~ ^#.*$ ]] && continue
                curl_cmd+=("-H" "${key}: ${value}")
            done < "${headers_file}"
        fi

        curl_cmd+=("${url}")

        # Execute curl
        local response
        response="$("${curl_cmd[@]}" 2>&1)"
        local status_code="${response: -3}"
        local body="${response%???}"

        log_debug "Attempt ${retries}/${max_retries}: HTTP ${status_code}"

        # Check status code
        if [[ "${status_code}" == "${expected_code}" ]]; then
            # Check expected text if provided
            if [[ -n "${expected_text}" ]]; then
                if [[ "${body}" == *"${expected_text}"* ]]; then
                    log_success "Health check passed (HTTP ${status_code}, text matched)"
                    return 0
                else
                    log_debug "Status code OK but expected text not found: ${expected_text}"
                fi
            else
                log_success "Health check passed (HTTP ${status_code})"
                return 0
            fi
        else
            last_status="${status_code}"
            last_response="${body}"
        fi

        # Wait before retry
        if [[ ${retries} -lt ${max_retries} ]]; then
            sleep "${interval}"
        fi
    done

    # Health check failed
    log_error "Health check failed after ${max_retries} attempts"
    log_error "Last status: HTTP ${last_status}"
    if [[ -n "${last_response}" ]]; then
        log_error "Response: ${last_response}"
    fi

    return 1
}

# Perform HTTP health check with JSON response validation
# Usage: http_health_check_json url json_path expected_value
http_health_check_json() {
    local url="$1"
    local json_path="$2"
    local expected_value="$3"
    local max_retries="${4:-${HEALTH_CHECK_RETRIES}}"
    local interval="${5:-${HEALTH_CHECK_INTERVAL}}"

    if ! check_command jq; then
        log_error "jq is required for JSON health checks"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    local retries=0

    log_info "Starting JSON health check for: ${url}"
    log_debug "JSON path: ${json_path}, Expected value: ${expected_value}"

    while [[ ${retries} -lt ${max_retries} ]]; do
        retries=$((retries + 1))

        # Get JSON response
        local response
        response=$(curl -s "${url}" 2>/dev/null || echo "")

        # Check if response is valid JSON
        if ! echo "${response}" | jq empty 2>/dev/null; then
            log_debug "Attempt ${retries}/${max_retries}: Invalid JSON response"
            sleep "${interval}"
            continue
        fi

        # Extract value using JSON path
        local actual_value
        actual_value=$(echo "${response}" | jq -r "${json_path}" 2>/dev/null || echo "")

        if [[ "${actual_value}" == "${expected_value}" ]]; then
            log_success "JSON health check passed"
            log_debug "Value at ${json_path}: ${actual_value}"
            return 0
        fi

        log_debug "Attempt ${retries}/${max_retries}: Value mismatch (got: ${actual_value}, expected: ${expected_value})"
        sleep "${interval}"
    done

    log_error "JSON health check failed after ${max_retries} attempts"
    return 1
}

# =============================================================================
# TCP Health Check
# =============================================================================

# Perform TCP port health check
# Usage: tcp_health_check host port [retry_count] [interval] [timeout]
tcp_health_check() {
    local host="$1"
    local port="$2"
    local max_retries="${3:-${HEALTH_CHECK_RETRIES}}"
    local interval="${4:-${HEALTH_CHECK_INTERVAL}}"
    local timeout="${5:-${CHECK_TIMEOUT}}"

    local retries=0

    log_info "Starting TCP health check for: ${host}:${port}"
    log_debug "Max retries: ${max_retries}, Interval: ${interval}s"

    while [[ ${retries} -lt ${max_retries} ]]; do
        retries=$((retries + 1))

        # Try to connect using timeout
        if timeout "${timeout}" bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null; then
            log_success "TCP health check passed (${host}:${port} is reachable)"
            return 0
        fi

        log_debug "Attempt ${retries}/${max_retries}: ${host}:${port} not reachable"

        # Wait before retry
        if [[ ${retries} -lt ${max_retries} ]]; then
            sleep "${interval}"
        fi
    done

    log_error "TCP health check failed after ${max_retries} attempts"
    log_error "Could not connect to ${host}:${port}"

    return 1
}

# =============================================================================
# Database Health Check
# =============================================================================

# Perform database health check
# Usage: db_health_check connection_string
db_health_check() {
    local connection_string="$1"
    local db_type="${2:-auto}"

    log_info "Starting database health check..."

    case "${db_type}" in
        postgres|postgresql|psql)
            if ! check_command psql; then
                log_error "psql not found"
                return "${EXIT_ERROR_MISSING_DEPS}"
            fi

            if psql "${connection_string}" -c "SELECT 1" &>/dev/null; then
                log_success "PostgreSQL health check passed"
                return 0
            else
                log_error "PostgreSQL health check failed"
                return 1
            fi
            ;;

        mysql)
            if ! check_command mysql; then
                log_error "mysql not found"
                return "${EXIT_ERROR_MISSING_DEPS}"
            fi

            if mysql "${connection_string}" -e "SELECT 1" &>/dev/null; then
                log_success "MySQL health check passed"
                return 0
            else
                log_error "MySQL health check failed"
                return 1
            fi
            ;;

        redis)
            if ! check_command redis-cli; then
                log_error "redis-cli not found"
                return "${EXIT_ERROR_MISSING_DEPS}"
            fi

            if redis-cli -u "${connection_string}" ping 2>/dev/null | grep -q PONG; then
                log_success "Redis health check passed"
                return 0
            else
                log_error "Redis health check failed"
                return 1
            fi
            ;;

        mongo|mongodb)
            if ! check_command mongosh; then
                log_error "mongosh not found"
                return "${EXIT_ERROR_MISSING_DEPS}"
            fi

            if mongosh "${connection_string}" --eval "db.adminCommand('ping')" &>/dev/null; then
                log_success "MongoDB health check passed"
                return 0
            else
                log_error "MongoDB health check failed"
                return 1
            fi
            ;;

        *)
            log_error "Unsupported database type: ${db_type}"
            return "${EXIT_ERROR_CONFIG}"
            ;;
    esac
}

# =============================================================================
# Container Health Check
# =============================================================================

# Perform Docker container health check
# Usage: container_health_check container_name
container_health_check() {
    local container_name="$1"

    if ! check_command docker; then
        log_error "Docker not found"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    log_info "Checking container health: ${container_name}"

    # Check if container exists
    local container_id
    container_id=$(docker ps -q -f name="${container_name}" 2>/dev/null || echo "")

    if [[ -z "${container_id}" ]]; then
        log_error "Container not found: ${container_name}"
        return 1
    fi

    # Get container health status
    local health_status
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "${container_id}" 2>/dev/null || echo "")

    if [[ "${health_status}" == "healthy" ]]; then
        log_success "Container is healthy: ${container_name}"
        return 0
    elif [[ "${health_status}" == "unhealthy" ]]; then
        log_error "Container is unhealthy: ${container_name}"
        return 1
    elif [[ -z "${health_status}" ]]; then
        # No health check configured, check if container is running
        local running
        running=$(docker inspect --format='{{.State.Running}}' "${container_id}" 2>/dev/null || echo "false")

        if [[ "${running}" == "true" ]]; then
            log_success "Container is running: ${container_name}"
            return 0
        else
            log_error "Container is not running: ${container_name}"
            return 1
        fi
    else
        log_debug "Container health status: ${health_status}"
        log_error "Container health check failed: ${container_name}"
        return 1
    fi
}

# =============================================================================
# Kubernetes Health Check
# =============================================================================

# Perform Kubernetes pod health check
# Usage: k8s_pod_health_check pod_name [namespace]
k8s_pod_health_check() {
    local pod_name="$1"
    local namespace="${2:-default}"

    if ! check_command kubectl; then
        log_error "kubectl not found"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    log_info "Checking Kubernetes pod health: ${pod_name} (namespace: ${namespace})"

    # Get pod status
    local pod_status
    pod_status=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

    if [[ "${pod_status}" == "Running" ]]; then
        # Check if all containers are ready
        local ready
        ready=$(kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

        if [[ "${ready}" == "True" ]]; then
            log_success "Pod is healthy: ${pod_name}"
            return 0
        else
            log_error "Pod containers not ready: ${pod_name}"
            return 1
        fi
    else
        log_error "Pod status is not Running: ${pod_name} (${pod_status})"
        return 1
    fi
}

# =============================================================================
# Composite Health Check
# =============================================================================

# Run multiple health checks
# Usage: run_health_checks config_file
run_health_checks() {
    local config_file="$1"

    if [[ ! -f "${config_file}" ]]; then
        log_error "Health check config file not found: ${config_file}"
        return "${EXIT_ERROR_CONFIG}"
    fi

    log_info "Running health checks from config: ${config_file}"

    local all_passed=true

    # Parse config file (simple key=value format)
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ -z "${key}" ]] || [[ "${key}" =~ ^#.*$ ]] && continue

        case "${key}" in
            http_url|url)
                log_debug "HTTP health check: ${value}"
                if ! http_health_check "${value}"; then
                    all_passed=false
                fi
                ;;
            tcp_host)
                tcp_host="${value}"
                ;;
            tcp_port)
                tcp_port="${value}"
                if [[ -n "${tcp_host:-}" ]] && [[ -n "${tcp_port}" ]]; then
                    log_debug "TCP health check: ${tcp_host}:${tcp_port}"
                    if ! tcp_health_check "${tcp_host}" "${tcp_port}"; then
                        all_passed=false
                    fi
                    tcp_host=""
                    tcp_port=""
                fi
                ;;
            container_name)
                log_debug "Container health check: ${value}"
                if ! container_health_check "${value}"; then
                    all_passed=false
                fi
                ;;
            *)
                log_warn "Unknown config key: ${key}"
                ;;
        esac
    done < "${config_file}"

    if [[ "${all_passed}" == "true" ]]; then
        log_success "All health checks passed"
        return 0
    else
        log_error "Some health checks failed"
        return 1
    fi
}

# =============================================================================
# Main Health Check Function
# =============================================================================

# Main health check logic (wrapper for use by other scripts)
# Usage: run_health_check url [type]
run_health_check() {
    local target="$1"
    local type="${2:-http}"

    case "${type}" in
        http|https)
            http_health_check "${target}"
            ;;
        tcp)
            # Parse host:port
            local host="${target%:*}"
            local port="${target##*:}"
            tcp_health_check "${host}" "${port}"
            ;;
        *)
            log_error "Unknown health check type: ${type}"
            return "${EXIT_ERROR_CONFIG}"
            ;;
    esac
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 <url|host:port> [options]

Perform health checks on services.

Arguments:
  url|host:port    Target URL or host:port combination

Options:
  --tcp                Use TCP check instead of HTTP
  --retry N            Number of retries (default: 30)
  --interval N         Interval between retries in seconds (default: 10)
  --timeout N          Timeout for each check in seconds (default: 5)
  --expected-code N    Expected HTTP status code (default: 200)
  --expected-text TEXT Expected text in response body
  --json-path PATH     JSON path to validate (for JSON checks)
  --json-value VALUE   Expected value at JSON path
  --headers FILE       File with request headers (key: value format)
  --container NAME     Check Docker container health
  --k8s-pod NAME       Check Kubernetes pod health
  --config FILE        Run health checks from config file
  --help, -h           Show this help message

Environment Variables:
  HEALTH_CHECK_TIMEOUT    Overall timeout (default: 300)
  HEALTH_CHECK_INTERVAL   Interval between retries (default: 10)
  HEALTH_CHECK_RETRIES    Number of retries (default: 30)

Examples:
  # HTTP health check
  $0 https://api.example.com/health

  # TCP health check
  $0 localhost:8080 --tcp

  # With custom retry settings
  $0 https://api.example.com/health --retry 10 --interval 5

  # Check for expected text
  $0 https://api.example.com/health --expected-text "OK"

  # Check Docker container
  $0 --container myapp

  # Check Kubernetes pod
  $0 --k8s-pod myapp-pod --namespace production

EOF
}

# =============================================================================
# Main Script Entry Point
# =============================================================================

main() {
    local target=""
    local use_tcp=false
    local max_retries="${HEALTH_CHECK_RETRIES}"
    local interval="${HEALTH_CHECK_INTERVAL}"
    local timeout="${CHECK_TIMEOUT}"
    local expected_code="${EXPECTED_STATUS_CODE}"
    local expected_text=""
    local json_path=""
    local json_value=""
    local headers_file=""
    local container_name=""
    local k8s_pod=""
    local k8s_namespace="default"
    local config_file=""
    local show_help=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help=true
                shift
                ;;
            --tcp)
                use_tcp=true
                shift
                ;;
            --retry)
                max_retries="$2"
                shift 2
                ;;
            --interval)
                interval="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --expected-code)
                expected_code="$2"
                shift 2
                ;;
            --expected-text)
                expected_text="$2"
                shift 2
                ;;
            --json-path)
                json_path="$2"
                shift 2
                ;;
            --json-value)
                json_value="$2"
                shift 2
                ;;
            --headers)
                headers_file="$2"
                shift 2
                ;;
            --container)
                container_name="$2"
                shift 2
                ;;
            --k8s-pod)
                k8s_pod="$2"
                shift 2
                ;;
            --namespace)
                k8s_namespace="$2"
                shift 2
                ;;
            --config)
                config_file="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                exit "${EXIT_ERROR_GENERAL}"
                ;;
            *)
                if [[ -z "${target}" ]]; then
                    target="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ "${show_help}" == "true" ]]; then
        show_help
        exit "${EXIT_SUCCESS}"
    fi

    # Handle special modes
    if [[ -n "${container_name}" ]]; then
        container_health_check "${container_name}"
        exit $?
    fi

    if [[ -n "${k8s_pod}" ]]; then
        k8s_pod_health_check "${k8s_pod}" "${k8s_namespace}"
        exit $?
    fi

    if [[ -n "${config_file}" ]]; then
        run_health_checks "${config_file}"
        exit $?
    fi

    # Validate target
    if [[ -z "${target}" ]]; then
        log_error "Target URL or host:port is required"
        echo ""
        show_help
        exit "${EXIT_ERROR_GENERAL}"
    fi

    # Perform health check
    if [[ "${use_tcp}" == "true" ]]; then
        # Parse host:port
        local host="${target%:*}"
        local port="${target##*:}"
        tcp_health_check "${host}" "${port}" "${max_retries}" "${interval}" "${timeout}"
    else
        if [[ -n "${json_path}" ]] && [[ -n "${json_value}" ]]; then
            http_health_check_json "${target}" "${json_path}" "${json_value}" "${max_retries}" "${interval}"
        else
            http_health_check "${target}" "${max_retries}" "${interval}" "${timeout}" "${expected_code}" "${expected_text}" "${headers_file}"
        fi
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Export functions for use in other scripts
export -f run_health_check
export -f http_health_check
export -f http_health_check_json
export -f tcp_health_check
export -f db_health_check
export -f container_health_check
export -f k8s_pod_health_check
