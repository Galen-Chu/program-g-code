#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Rollback Script
# =============================================================================
# Rollback deployments to previous versions.
#
# Usage:
#   ./scripts/cd/rollback.sh <environment> [options]
#
# Arguments:
#   environment      Target environment (dev, staging, prod)
#
# Options:
#   --version VER    Rollback to specific version
#   --list           List available versions
#   --dry-run        Show what would be rolled back without rolling back
#   --help, -h       Show help message
#
# Environment Variables:
#   ROLLBACK_VERSION Version to rollback to
#   KEEP_VERSIONS    Number of versions to keep (default: 5)
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
ROLLBACK_VERSION="${ROLLBACK_VERSION:-}"
LIST_VERSIONS="${LIST_VERSIONS:-false}"
KEEP_VERSIONS="${KEEP_VERSIONS:-5}"
ROLLBACK_TIMEOUT="${ROLLBACK_TIMEOUT:-600}"

# Version storage directory
VERSIONS_DIR="${VERSIONS_DIR:-.versions}"

# =============================================================================
# Version Management
# =============================================================================

# List available versions for environment
# Usage: list_versions environment
list_versions() {
    local environment="$1"
    local env_versions_dir="${VERSIONS_DIR}/${environment}"

    log_info "Available versions for ${environment}:"

    if [[ ! -d "${env_versions_dir}" ]]; then
        log_warn "No versions found for ${environment}"
        return 0
    fi

    # List versions with timestamps
    local versions=()
    mapfile -t versions < <(ls -t "${env_versions_dir}" 2>/dev/null || true)

    if [[ ${#versions[@]} -eq 0 ]]; then
        log_warn "No versions found"
        return 0
    fi

    echo ""
    printf "%-20s %-30s %-15s\n" "Version" "Timestamp" "Status"
    printf "%-20s %-30s %-15s\n" "---" "---" "---"

    for version in "${versions[@]}"; do
        local version_file="${env_versions_dir}/${version}/metadata.json"

        if [[ -f "${version_file}" ]]; then
            local timestamp
            timestamp="$(jq -r '.timestamp' "${version_file}" 2>/dev/null || echo "unknown")"
            local status
            status="$(jq -r '.status' "${version_file}" 2>/dev/null || echo "unknown")"

            printf "%-20s %-30s %-15s\n" "${version}" "${timestamp}" "${status}"
        else
            printf "%-20s %-30s %-15s\n" "${version}" "unknown" "unknown"
        fi
    done

    echo ""
}

# Save current version before rollback
# Usage: save_current_version environment version
save_current_version() {
    local environment="$1"
    local version="${2:-$(get_version)}"
    local env_versions_dir="${VERSIONS_DIR}/${environment}"
    local version_dir="${env_versions_dir}/${version}"

    ensure_dir "${version_dir}"

    log_info "Saving current version: ${version}"

    # Create metadata
    local metadata
    metadata="{
        \"version\": \"${version}\",
        \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
        \"environment\": \"${environment}\",
        \"status\": \"deployed\",
        \"git_commit\": \"$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null || echo "unknown")\",
        \"git_branch\": \"$(git -C "${PROJECT_ROOT}" branch --show-current 2>/dev/null || echo "unknown")\"
    }"

    echo "${metadata}" > "${version_dir}/metadata.json"

    # Copy artifacts if they exist
    if [[ -d "${ARTIFACTS_DIR}" ]]; then
        log_info "Copying artifacts..."
        cp -r "${ARTIFACTS_DIR}" "${version_dir}/artifacts"
    fi

    log_success "Version saved: ${version}"

    # Cleanup old versions
    cleanup_old_versions "${environment}"
}

# Cleanup old versions keeping only N most recent
# Usage: cleanup_old_versions environment
cleanup_old_versions() {
    local environment="$1"
    local env_versions_dir="${VERSIONS_DIR}/${environment}"

    if [[ ! -d "${env_versions_dir}" ]]; then
        return 0
    fi

    local versions=()
    mapfile -t versions < <(ls -t "${env_versions_dir}" 2>/dev/null || true)

    if [[ ${#versions[@]} -gt ${KEEP_VERSIONS} ]]; then
        log_info "Cleaning up old versions (keeping ${KEEP_VERSIONS} most recent)..."

        local old_versions=("${versions[@]:${KEEP_VERSIONS}}")

        for old_version in "${old_versions[@]}"; do
            # 只刪除長得像版本目錄名的條目（非空、無路徑分隔、非隱藏檔），
            # 防止目錄清單解析異常時誤刪不該刪的東西
            if [[ -z "${old_version}" || "${old_version}" == */* || "${old_version}" == .* ]]; then
                log_warn "Skipping suspicious version entry: '${old_version}'"
                continue
            fi
            log_info "Removing old version: ${old_version}"
            rm -rf "${env_versions_dir:?}/${old_version:?}"
        done
    fi
}

# Get previous version
# Usage: get_previous_version environment
get_previous_version() {
    local environment="$1"
    local env_versions_dir="${VERSIONS_DIR}/${environment}"

    if [[ ! -d "${env_versions_dir}" ]]; then
        echo ""
        return 1
    fi

    # Get second most recent version (first is current)
    local versions=()
    mapfile -t versions < <(ls -t "${env_versions_dir}" 2>/dev/null || true)

    if [[ ${#versions[@]} -lt 2 ]]; then
        echo ""
        return 1
    fi

    echo "${versions[1]}"
    return 0
}

# =============================================================================
# Rollback Functions
# =============================================================================

# Rollback Docker deployment
# Usage: rollback_docker version
rollback_docker() {
    local target_version="$1"
    local env_versions_dir="${VERSIONS_DIR}/${DEPLOY_ENVIRONMENT}"
    local version_dir="${env_versions_dir}/${target_version}"

    if [[ ! -d "${version_dir}" ]]; then
        log_error "Version not found: ${target_version}"
        return "${EXIT_ERROR_CONFIG}"
    fi

    log_info "Rolling back Docker deployment to ${target_version}..."

    # Get image name from version metadata
    local image_name
    image_name="$(jq -r '.docker_image' "${version_dir}/metadata.json" 2>/dev/null || echo "")"

    if [[ -z "${image_name}" ]]; then
        # Try to get from artifacts
        local artifacts_dir="${version_dir}/artifacts"
        if [[ -f "${artifacts_dir}/docker-image.txt" ]]; then
            image_name="$(cat "${artifacts_dir}/docker-image.txt")"
        fi
    fi

    if [[ -z "${image_name}" ]]; then
        log_error "Could not determine Docker image for version ${target_version}"
        return "${EXIT_ERROR_CONFIG}"
    fi

    log_info "Target image: ${image_name}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would rollback to: ${image_name}"
        return 0
    fi

    # Kubernetes rollback
    if check_command kubectl && [[ -n "${KUBE_DEPLOYMENT:-}" ]]; then
        local namespace="${KUBE_NAMESPACE:-default}"
        local deployment="${KUBE_DEPLOYMENT}"
        local container="${KUBE_CONTAINER:-app}"

        log_info "Rolling back Kubernetes deployment..."

        if ! kubectl set image "deployment/${deployment}" "${container}=${image_name}" -n "${namespace}"; then
            log_error "Failed to rollback Kubernetes deployment"
            return "${EXIT_ERROR_DEPLOY}"
        fi

        # Wait for rollout
        log_info "Waiting for rollout..."
        if ! kubectl rollout status "deployment/${deployment}" -n "${namespace}" --timeout="${ROLLBACK_TIMEOUT}s"; then
            log_error "Rollback timed out"
            return "${EXIT_ERROR_DEPLOY}"
        fi

        log_success "Kubernetes rollback complete"
        return 0
    fi

    log_info "Docker rollback prepared. Manual deployment may be required."
    log_info "Image: ${image_name}"

    return 0
}

# Rollback generic deployment
# Usage: rollback_generic version
rollback_generic() {
    local target_version="$1"
    local env_versions_dir="${VERSIONS_DIR}/${DEPLOY_ENVIRONMENT}"
    local version_dir="${env_versions_dir}/${target_version}"

    if [[ ! -d "${version_dir}" ]]; then
        log_error "Version not found: ${target_version}"
        return "${EXIT_ERROR_CONFIG}"
    fi

    log_info "Rolling back to ${target_version}..."

    # Restore artifacts
    local artifacts_dir="${version_dir}/artifacts"
    if [[ -d "${artifacts_dir}" ]]; then
        log_info "Restoring artifacts from ${artifacts_dir}..."

        # Backup current artifacts
        if [[ -d "${ARTIFACTS_DIR}" ]]; then
            mv "${ARTIFACTS_DIR}" "${ARTIFACTS_DIR}.backup.$(date +%s)"
        fi

        # Restore version artifacts
        cp -r "${artifacts_dir}" "${ARTIFACTS_DIR}"

        log_success "Artifacts restored"
    fi

    # Get git commit if available
    local git_commit
    git_commit="$(jq -r '.git_commit' "${version_dir}/metadata.json" 2>/dev/null || echo "")"

    if [[ -n "${git_commit}" ]] && [[ "${git_commit}" != "unknown" ]] && check_git_repo; then
        log_info "Restoring git state to commit ${git_commit}..."

        if [[ "${DRY_RUN}" != "true" ]]; then
            git checkout "${git_commit}" || log_warn "Failed to checkout git commit"
        fi
    fi

    log_success "Rollback to ${target_version} complete"
    return 0
}

# =============================================================================
# Notification
# =============================================================================

# Send rollback notification
# Usage: send_rollback_notification status version
send_rollback_notification() {
    local status="$1"
    local version="$2"
    local notifier_script="${SCRIPT_DIR}/../utils/notifiers.sh"

    if [[ ! -f "${notifier_script}" ]]; then
        return 0
    fi

    local message="Rollback to ${version} ${status} for environment ${DEPLOY_ENVIRONMENT}"

    # Source notifier script if available
    source "${notifier_script}" 2>/dev/null || true

    log_info "Sending rollback notification..."

    # Call notification function if available
    if [[ "$(type -t notify_slack)" == "function" ]] && [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        notify_slack "${message}" || true
    fi

    return 0
}

# =============================================================================
# Main Rollback Function
# =============================================================================

# Main rollback logic
# Usage: main_rollback <environment> [--version VERSION]
main_rollback() {
    local environment="$1"
    local target_version="${ROLLBACK_VERSION}"

    log_section "Starting Rollback for ${environment}"

    # Set environment
    export DEPLOY_ENVIRONMENT="${environment}"

    # List versions if requested
    if [[ "${LIST_VERSIONS}" == "true" ]]; then
        list_versions "${environment}"
        return 0
    fi

    # Determine target version
    if [[ -z "${target_version}" ]]; then
        target_version="$(get_previous_version "${environment}")"

        if [[ -z "${target_version}" ]]; then
            log_error "No previous version found for rollback"
            log_error "Use --version to specify a version"
            list_versions "${environment}"
            return "${EXIT_ERROR_CONFIG}"
        fi

        log_info "Auto-detected previous version: ${target_version}"
    fi

    # Validate target version exists
    local env_versions_dir="${VERSIONS_DIR}/${environment}"
    local version_dir="${env_versions_dir}/${target_version}"

    if [[ ! -d "${version_dir}" ]]; then
        log_error "Version not found: ${target_version}"
        list_versions "${environment}"
        return "${EXIT_ERROR_CONFIG}"
    fi

    log_info "Rolling back to version: ${target_version}"

    # Save current version before rollback
    local current_version
    current_version="$(get_version)"
    save_current_version "${environment}" "${current_version}"

    # Determine rollback method based on deployment configuration
    local exit_code=0

    if [[ -n "${KUBE_DEPLOYMENT:-}" ]] || check_command kubectl; then
        # Kubernetes/Docker rollback
        rollback_docker "${target_version}" || exit_code=$?
    else
        # Generic rollback
        rollback_generic "${target_version}" || exit_code=$?
    fi

    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Rollback failed"
        send_rollback_notification "failed" "${target_version}"
        return ${exit_code}
    fi

    # Update version metadata
    if [[ -f "${version_dir}/metadata.json" ]]; then
        local updated_metadata
        updated_metadata="$(jq ".status = \"rolledback\" | .rollback_timestamp = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "${version_dir}/metadata.json")"
        echo "${updated_metadata}" > "${version_dir}/metadata.json"
    fi

    log_section "Rollback Complete"
    send_rollback_notification "succeeded" "${target_version}"

    return 0
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 <environment> [options]

Rollback deployment to a previous version.

Arguments:
  environment          Target environment (dev, staging, prod)

Options:
  --version VER        Rollback to specific version
  --list               List available versions for environment
  --dry-run            Show what would be rolled back without rolling back
  --help, -h           Show this help message

Environment Variables:
  ROLLBACK_VERSION     Version to rollback to (default: previous)
  KEEP_VERSIONS        Number of versions to keep (default: 5)
  ROLLBACK_TIMEOUT     Rollback timeout in seconds (default: 600)
  KUBE_NAMESPACE       Kubernetes namespace
  KUBE_DEPLOYMENT      Kubernetes deployment name
  KUBE_CONTAINER       Kubernetes container name
  VERSIONS_DIR         Directory to store version history (default: .versions)
  SLACK_WEBHOOK        Slack webhook for notifications

Examples:
  # Rollback to previous version
  $0 staging

  # Rollback to specific version
  $0 prod --version 1.0.1

  # List available versions
  $0 dev --list

  # Dry run rollback
  $0 prod --dry-run

EOF
}

# =============================================================================
# Main Script Entry Point
# =============================================================================

main() {
    local environment=""
    local show_help=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help=true
                shift
                ;;
            --version)
                export ROLLBACK_VERSION="$2"
                shift 2
                ;;
            --list)
                export LIST_VERSIONS="true"
                shift
                ;;
            --dry-run)
                export DRY_RUN="true"
                shift
                ;;
            --config)
                export CONFIG_FILE="$2"
                load_config "${CONFIG_FILE}" || true
                shift 2
                ;;
            --log-level)
                export LOG_LEVEL="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                exit "${EXIT_ERROR_GENERAL}"
                ;;
            *)
                if [[ -z "${environment}" ]]; then
                    environment="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ "${show_help}" == "true" ]]; then
        show_help
        exit "${EXIT_SUCCESS}"
    fi

    # Validate environment
    if [[ -z "${environment}" ]]; then
        log_error "Environment argument is required"
        echo ""
        show_help
        exit "${EXIT_ERROR_GENERAL}"
    fi

    # Change to project root
    cd "${PROJECT_ROOT}"

    # Run main rollback function
    main_rollback "${environment}"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
