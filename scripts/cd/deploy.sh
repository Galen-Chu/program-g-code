#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Deploy Script
# =============================================================================
# Multi-environment deployment with health checks and automatic rollback.
#
# Usage:
#   ./scripts/cd/deploy.sh <environment> [options]
#
# Arguments:
#   environment      Target environment (dev, staging, prod)
#
# Options:
#   --skip-build     Skip build step
#   --skip-health    Skip health check
#   --pre-flight     Run pre-flight checks before deployment
#   --force          Force deployment even if checks fail
#   --dry-run        Show what would be deployed without deploying
#   --help, -h       Show help message
#
# Environment Variables:
#   DEPLOY_ENVIRONMENT  Target environment
#   DEPLOY_STRATEGY     Deployment strategy (rolling, blue-green, recreate)
#   AUTO_ROLLBACK       Auto-rollback on failure (default: true)
################################################################################

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "${SCRIPT_DIR}/../utils/common.sh"
source "${SCRIPT_DIR}/../utils/logger.sh"
source "${SCRIPT_DIR}/../utils/validators.sh"

# Source health-check if available
if [[ -f "${SCRIPT_DIR}/../utils/health-check.sh" ]]; then
    source "${SCRIPT_DIR}/../utils/health-check.sh"
fi

# =============================================================================
# Script Configuration
# =============================================================================
DEPLOY_ENVIRONMENT="${DEPLOY_ENVIRONMENT:-}"
DEPLOY_STRATEGY="${DEPLOY_STRATEGY:-rolling}"
AUTO_ROLLBACK="${AUTO_ROLLBACK:-true}"
SKIP_BUILD="${SKIP_BUILD:-false}"
SKIP_HEALTH_CHECK="${SKIP_HEALTH_CHECK:-false}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-dist}"
FORCE_DEPLOY="${FORCE_DEPLOY:-false}"
RUN_PREFLIGHT="${RUN_PREFLIGHT:-false}"

# Health check settings
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-30}"
HEALTH_CHECK_PATH="${HEALTH_CHECK_PATH:-/health}"

# =============================================================================
# Environment Configuration
# =============================================================================

# Load environment-specific settings
# Usage: load_environment_config environment
load_environment_config() {
    local env="$1"

    # Set environment-specific variables
    case "${env}" in
        dev)
            ENV_URL="${ENV_URL:-}"
            ENV_AUTO_DEPLOY="${ENV_AUTO_DEPLOY:-true}"
            ENV_SKIP_HEALTH="${ENV_SKIP_HEALTH:-true}"
            ENV_REQUIRED_APPROVALS="${ENV_REQUIRED_APPROVALS:-0}"
            ;;

        staging)
            ENV_URL="${ENV_URL:-}"
            ENV_AUTO_DEPLOY="${ENV_AUTO_DEPLOY:-true}"
            ENV_SKIP_HEALTH="${ENV_SKIP_HEALTH:-false}"
            ENV_REQUIRED_APPROVALS="${ENV_REQUIRED_APPROVALS:-1}"
            ;;

        prod|production)
            ENV_URL="${ENV_URL:-}"
            ENV_AUTO_DEPLOY="${ENV_AUTO_DEPLOY:-false}"
            ENV_SKIP_HEALTH="${ENV_SKIP_HEALTH:-false}"
            ENV_REQUIRED_APPROVALS="${ENV_REQUIRED_APPROVALS:-2}"
            ;;

        *)
            log_error "Unknown environment: ${env}"
            log_error "Valid environments: dev, staging, prod"
            return "${EXIT_ERROR_CONFIG}"
            ;;
    esac

    log_info "Environment: ${env}"
    log_debug "URL: ${ENV_URL:-not set}"
    log_debug "Auto-deploy: ${ENV_AUTO_DEPLOY}"
    log_debug "Skip health check: ${ENV_SKIP_HEALTH}"
}

# =============================================================================
# Pre-deployment Checks
# =============================================================================

# Run pre-deployment checks
# Usage: pre_deploy_checks
pre_deploy_checks() {
    log_info "Running pre-deployment checks..."

    # Run pre-flight checks if enabled
    if [[ "${RUN_PREFLIGHT}" == "true" ]]; then
        local preflight_script="${SCRIPT_DIR}/../utils/pre-flight.sh"

        if [[ -f "${preflight_script}" ]]; then
            log_info "Running pre-flight checks..."

            local preflight_args=()
            [[ "${DEPLOY_ENVIRONMENT}" == "prod" ]] && preflight_args+=(--strict)

            if ! bash "${preflight_script}" "${preflight_args[@]}"; then
                log_error "Pre-flight checks failed"
                log_error "Use --force to bypass pre-flight checks"
                return "${EXIT_ERROR_VALIDATION}"
            fi
        else
            log_warn "Pre-flight script not found: ${preflight_script}"
        fi
    fi

    # Check if build artifacts exist
    if [[ "${SKIP_BUILD}" != "true" ]]; then
        if [[ ! -d "${ARTIFACTS_DIR}" ]] || [[ -z "$(ls -A ${ARTIFACTS_DIR} 2>/dev/null)" ]]; then
            log_warn "No build artifacts found. Running build..."
            "${SCRIPT_DIR}/build.sh" || return $?
        fi
    fi

    # Check git status (optional)
    if check_git_repo && [[ "${FORCE_DEPLOY}" != "true" ]]; then
        if ! validate_git_clean; then
            log_warn "Working directory has uncommitted changes"
            if [[ "${DEPLOY_ENVIRONMENT}" == "prod" ]]; then
                log_error "Production deployment requires clean working directory"
                log_error "Use --force to override"
                return "${EXIT_ERROR_VALIDATION}"
            fi
        fi
    fi

    # Check required approvals for production
    if [[ "${DEPLOY_ENVIRONMENT}" == "prod" ]] && \
       [[ "${ENV_REQUIRED_APPROVALS:-0}" -gt 0 ]] && \
       [[ ! -n "${APPROVALS:-}" ]]; then
        log_error "Production deployment requires ${ENV_REQUIRED_APPROVALS} approval(s)"
        log_error "Set APPROVALS environment variable to proceed"
        return "${EXIT_ERROR_VALIDATION}"
    fi

    log_success "Pre-deployment checks passed"
    return 0
}

# =============================================================================
# Deployment Functions
# =============================================================================

# Deploy Docker image
# Usage: deploy_docker
deploy_docker() {
    log_info "Deploying Docker image..."

    local image_file="${ARTIFACTS_DIR}/docker-image.txt"

    if [[ ! -f "${image_file}" ]]; then
        log_error "Docker image info not found. Run build first."
        return "${EXIT_ERROR_BUILD}"
    fi

    local image_name
    image_name="$(cat "${image_file}")"

    log_info "Image: ${image_name}"

    # Push to registry if registry is set
    if [[ -n "${DOCKER_REGISTRY:-}" ]]; then
        log_info "Pushing to registry: ${DOCKER_REGISTRY}"

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would push: docker push ${image_name}"
        else
            if ! docker push "${image_name}"; then
                log_error "Failed to push Docker image"
                return "${EXIT_ERROR_DEPLOY}"
            fi
        fi
    fi

    # Deploy to environment (this is a placeholder)
    # In practice, you would use kubectl, helm, docker-compose, etc.
    log_info "Deployment placeholder for Docker image"
    log_info "Image ${image_name} is ready for deployment"

    return 0
}

# Deploy Node.js application
# Usage: deploy_nodejs
deploy_nodejs() {
    log_info "Deploying Node.js application..."

    # Check deployment method
    if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
        # Check for deployment scripts
        if grep -q '"deploy"' "${PROJECT_ROOT}/package.json"; then
            log_info "Running npm deploy..."
            run_cmd npm run deploy
        else
            log_info "No deploy script found in package.json"
            log_info "Artifacts are ready in: ${ARTIFACTS_DIR}"
        fi
    fi

    return 0
}

# Deploy Python application
# Usage: deploy_python
deploy_python() {
    log_info "Deploying Python application..."

    # Check for deployment scripts
    if [[ -f "${PROJECT_ROOT}/setup.py" ]] || [[ -f "${PROJECT_ROOT}/pyproject.toml" ]]; then
        log_info "Artifacts are ready in: ${ARTIFACTS_DIR}"
        log_info "Deploy using: twine upload ${ARTIFACTS_DIR}/*"
    fi

    return 0
}

# Deploy to Kubernetes
# Usage: deploy_kubernetes
deploy_kubernetes() {
    log_info "Deploying to Kubernetes..."

    if ! check_command kubectl; then
        log_warn "kubectl not found. Skipping Kubernetes deployment."
        return 0
    fi

    local namespace="${KUBE_NAMESPACE:-default}"
    local deployment="${KUBE_DEPLOYMENT:-app}"
    local container="${KUBE_CONTAINER:-app}"

    # Get image to deploy
    local image_file="${ARTIFACTS_DIR}/docker-image.txt"
    if [[ ! -f "${image_file}" ]]; then
        log_error "Docker image info not found"
        return "${EXIT_ERROR_BUILD}"
    fi

    local image_name
    image_name="$(cat "${image_file}")"

    log_info "Updating deployment: ${deployment}"
    log_info "Namespace: ${namespace}"
    log_info "Image: ${image_name}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: kubectl set image deployment/${deployment} ${container}=${image_name} -n ${namespace}"
        return 0
    fi

    # Update deployment
    if ! kubectl set image "deployment/${deployment}" "${container}=${image_name}" -n "${namespace}"; then
        log_error "Failed to update Kubernetes deployment"
        return "${EXIT_ERROR_DEPLOY}"
    fi

    # Wait for rollout
    log_info "Waiting for rollout to complete..."
    if ! kubectl rollout status "deployment/${deployment}" -n "${namespace}" --timeout="${HEALTH_CHECK_TIMEOUT}s"; then
        log_error "Rollout timed out"
        return "${EXIT_ERROR_DEPLOY}"
    fi

    log_success "Kubernetes deployment complete"
    return 0
}

# Deploy via SSH
# Usage: deploy_ssh
deploy_ssh() {
    log_info "Deploying via SSH..."

    local ssh_host="${SSH_HOST:-}"
    local ssh_user="${SSH_USER:-}"
    local ssh_path="${SSH_PATH:-/var/www/app}"

    if [[ -z "${ssh_host}" ]]; then
        log_error "SSH_HOST not set"
        return "${EXIT_ERROR_CONFIG}"
    fi

    log_info "Host: ${ssh_user}@${ssh_host}"
    log_info "Path: ${ssh_path}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy via SSH to ${ssh_host}"
        return 0
    fi

    # Create remote directory
    ssh "${ssh_user}@${ssh_host}" "mkdir -p ${ssh_path}"

    # Copy artifacts
    log_info "Copying artifacts to remote server..."
    rsync -avz --delete "${ARTIFACTS_DIR}/" "${ssh_user}@${ssh_host}:${ssh_path}/"

    # Restart service (example)
    # ssh "${ssh_user}@${ssh_host}" "systemctl restart myapp"

    log_success "SSH deployment complete"
    return 0
}

# =============================================================================
# Health Check
# =============================================================================

# Run health check after deployment
# Usage: post_deploy_health_check
post_deploy_health_check() {
    if [[ "${SKIP_HEALTH_CHECK}" == "true" ]] || [[ "${ENV_SKIP_HEALTH}" == "true" ]]; then
        log_info "Health check skipped"
        return 0
    fi

    log_info "Running health checks..."

    local health_url="${ENV_URL:-}"

    if [[ -z "${health_url}" ]]; then
        log_warn "No health check URL configured (ENV_URL not set)"
        return 0
    fi

    # Add health check path if not already present
    if [[ ! "${health_url}" =~ ${HEALTH_CHECK_PATH}$ ]]; then
        # Remove trailing slash if present and add path
        health_url="${health_url%/}/${HEALTH_CHECK_PATH#/}"
    fi

    log_info "Health check URL: ${health_url}"

    # Use health-check.sh if available, otherwise use curl
    if [[ "$(type -t run_health_check)" == "function" ]]; then
        run_health_check "${health_url}" || return $?
    else
        # Simple health check with curl
        local retries=0
        local max_retries="${HEALTH_CHECK_RETRIES}"
        local interval="${HEALTH_CHECK_INTERVAL}"

        while [[ ${retries} -lt ${max_retries} ]]; do
            if curl -f -s "${health_url}" > /dev/null 2>&1; then
                log_success "Health check passed"
                return 0
            fi

            retries=$((retries + 1))
            log_info "Health check attempt ${retries}/${max_retries} failed. Retrying in ${interval}s..."
            sleep "${interval}"
        done

        log_error "Health check failed after ${max_retries} attempts"
        return "${EXIT_ERROR_DEPLOY}"
    fi

    return 0
}

# =============================================================================
# Rollback
# =============================================================================

# Rollback deployment on failure
# Usage: rollback_deployment
rollback_deployment() {
    if [[ "${AUTO_ROLLBACK}" != "true" ]]; then
        log_warn "Auto-rollback disabled"
        return 0
    fi

    log_error "Deployment failed. Initiating rollback..."

    # Call rollback script if available
    if [[ -f "${SCRIPT_DIR}/rollback.sh" ]]; then
        "${SCRIPT_DIR}/rollback.sh" "${DEPLOY_ENVIRONMENT}" || log_error "Rollback failed"
    else
        log_warn "Rollback script not found"
        log_info "Manual rollback required"
    fi

    return "${EXIT_ERROR_DEPLOY}"
}

# =============================================================================
# Notification
# =============================================================================

# Send deployment notification
# Usage: send_notification status
send_notification() {
    local status="$1"
    local notifier_script="${SCRIPT_DIR}/../utils/notifiers.sh"

    if [[ ! -f "${notifier_script}" ]]; then
        return 0
    fi

    local message="Deployment to ${DEPLOY_ENVIRONMENT} ${status}"
    local version="${BUILD_VERSION:-$(get_version)}"

    # Source notifier script if available
    source "${notifier_script}" 2>/dev/null || true

    log_info "Sending deployment notification..."

    # Call notification function if available
    if [[ "$(type -t notify_slack)" == "function" ]] && [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        notify_slack "${message} (version: ${version})" || true
    fi

    return 0
}

# =============================================================================
# Main Deploy Function
# =============================================================================

# Main deployment logic
# Usage: main_deploy <environment>
main_deploy() {
    local environment="$1"

    log_section "Starting Deployment to ${environment}"

    # Load environment configuration
    load_environment_config "${environment}" || return $?

    # Set global environment variable
    export DEPLOY_ENVIRONMENT="${environment}"

    # Check auto-deploy setting
    if [[ "${ENV_AUTO_DEPLOY}" != "true" ]] && [[ "${FORCE_DEPLOY}" != "true" ]]; then
        log_error "Auto-deploy is disabled for ${environment}"
        log_error "Use --force to override"
        return "${EXIT_ERROR_VALIDATION}"
    fi

    # Pre-deployment checks
    pre_deploy_checks || return $?

    # Determine deployment method
    local project_type
    project_type="$(get_project_type)"
    local deploy_method="default"

    # Check for deployment method overrides
    if [[ -n "${DEPLOY_METHOD:-}" ]]; then
        deploy_method="${DEPLOY_METHOD}"
    elif [[ -n "${KUBE_DEPLOYMENT:-}" ]]; then
        deploy_method="kubernetes"
    elif [[ -n "${SSH_HOST:-}" ]]; then
        deploy_method="ssh"
    elif [[ "${project_type}" == "docker" ]]; then
        deploy_method="docker"
    fi

    log_info "Deployment method: ${deploy_method}"

    # Perform deployment
    local exit_code=0

    case "${deploy_method}" in
        kubernetes)
            deploy_kubernetes || exit_code=$?
            ;;
        ssh)
            deploy_ssh || exit_code=$?
            ;;
        docker)
            deploy_docker || exit_code=$?
            ;;
        nodejs)
            deploy_nodejs || exit_code=$?
            ;;
        python)
            deploy_python || exit_code=$?
            ;;
        *)
            log_info "Default deployment: artifacts ready in ${ARTIFACTS_DIR}"
            ;;
    esac

    if [[ ${exit_code} -ne 0 ]]; then
        rollback_deployment
        send_notification "failed"
        return ${exit_code}
    fi

    # Post-deployment health check
    post_deploy_health_check || exit_code=$?

    if [[ ${exit_code} -ne 0 ]]; then
        rollback_deployment
        send_notification "failed"
        return ${exit_code}
    fi

    # Run post-deploy command if configured
    if [[ -n "${POST_DEPLOY_COMMAND:-}" ]]; then
        log_info "Running post-deploy command..."
        if ! bash -c "${POST_DEPLOY_COMMAND}"; then
            log_warn "Post-deploy command failed"
        fi
    fi

    log_section "Deployment Complete"
    send_notification "succeeded"

    return 0
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 <environment> [options]

Deploy to the specified environment.

Arguments:
  environment          Target environment (dev, staging, prod)

Options:
  --skip-build         Skip build step
  --skip-health        Skip health check
  --pre-flight         Run pre-flight checks before deployment
  --force              Force deployment even if checks fail
  --dry-run            Show what would be deployed without deploying
  --help, -h           Show this help message

Environment Variables:
  DEPLOY_ENVIRONMENT   Target environment
  DEPLOY_STRATEGY      Deployment strategy (rolling, blue-green, recreate)
  AUTO_ROLLBACK        Auto-rollback on failure (default: true)
  ENV_URL              Health check URL for environment
  SSH_HOST             SSH host for deployment
  SSH_USER             SSH user for deployment
  SSH_PATH             Remote path for deployment
  KUBE_NAMESPACE       Kubernetes namespace
  KUBE_DEPLOYMENT      Kubernetes deployment name
  KUBE_CONTAINER       Kubernetes container name
  SLACK_WEBHOOK        Slack webhook for notifications

Examples:
  # Deploy to staging
  $0 staging

  # Deploy to production with pre-flight checks
  $0 prod --pre-flight

  # Deploy with health check skipped
  $0 dev --skip-health

  # Force deployment (bypasses pre-flight checks)
  $0 prod --force

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
            --skip-build)
                export SKIP_BUILD="true"
                shift
                ;;
            --skip-health)
                export SKIP_HEALTH_CHECK="true"
                shift
                ;;
            --force)
                export FORCE_DEPLOY="true"
                shift
                ;;
            --pre-flight)
                export RUN_PREFLIGHT="true"
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

    # Run main deploy function
    main_deploy "${environment}"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
