#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Project Initialization Script
# =============================================================================
# Interactive project initialization with CI/CD configuration.
#
# Usage:
#   ./scripts/setup/init-project.sh [options]
#
# Options:
#   --config FILE     Use existing config file
#   --skip-prompts    Use default values without prompting
#   --ci-only         Only set up CI (skip CD)
#   --cd-only         Only set up CD (skip CI)
#   --help, -h        Show help message
#
# Environment Variables:
#   PROJECT_NAME      Project name (default: directory name)
#   PROJECT_TYPE      Project type (auto, nodejs, python, go, etc.)
################################################################################

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "${SCRIPT_DIR}/../utils/common.sh"
source "${SCRIPT_DIR}/../utils/logger.sh"

# =============================================================================
# Configuration
# =============================================================================
SKIP_PROMPTS="${SKIP_PROMPTS:-false}"
CI_ONLY="${CI_ONLY:-false}"
CD_ONLY="${CD_ONLY:-false}"
CONFIG_OUTPUT="${CONFIG_OUTPUT:-${PROJECT_ROOT}/.ci-cd.conf}"

# Default values
DEFAULT_PROJECT_NAME="$(basename "${PROJECT_ROOT}")"
DEFAULT_PROJECT_TYPE="auto"
DEFAULT_CI_ENABLED="true"
DEFAULT_CD_ENABLED="true"
DEFAULT_ENVIRONMENTS="dev,staging,prod"

# =============================================================================
# Interactive Prompts
# =============================================================================

# Prompt user for input with default value
# Usage: prompt prompt_text default_value
prompt() {
    local text="$1"
    local default="$2"
    local result

    if [[ "${SKIP_PROMPTS}" == "true" ]]; then
        echo "${default}"
        return 0
    fi

    read -p "${text} [${default}]: " result
    echo "${result:-${default}}"
}

# Prompt yes/no question
# Usage: prompt_yes_no prompt_text default_yes
prompt_yes_no() {
    local text="$1"
    local default="$2"
    local result

    if [[ "${SKIP_PROMPTS}" == "true" ]]; then
        [[ "${default}" == "true" ]]
        return $?
    fi

    local default_str="y/N"
    if [[ "${default}" == "true" ]]; then
        default_str="Y/n"
    fi

    read -p "${text} [${default_str}]: " result
    result=$(echo "${result}" | tr '[:upper:]' '[:lower:]')

    if [[ -z "${result}" ]]; then
        [[ "${default}" == "true" ]]
        return $?
    fi

    [[ "${result}" =~ ^(yes|y)$ ]]
}

# =============================================================================
# Configuration Generation
# =============================================================================

# Detect project configuration
# Usage: detect_project_config
detect_project_config() {
    log_info "Detecting project configuration..."

    # Detect project type
    local detected_type
    detected_type="$(get_project_type)"

    if [[ "${detected_type}" == "unknown" ]]; then
        log_warn "Could not auto-detect project type"
    else
        log_info "Detected project type: ${detected_type}"
    fi

    # Check for existing config
    if [[ -f "${PROJECT_ROOT}/.ci-cd.conf" ]] || [[ -f "${PROJECT_ROOT}/config/ci-cd.conf" ]]; then
        log_info "Existing configuration file found"
    fi
}

# Generate configuration file
# Usage: generate_config
generate_config() {
    log_section "Generating Configuration File"

    local project_name
    project_name="$(prompt "Project name" "${DEFAULT_PROJECT_NAME}")"

    local project_type
    project_type="$(prompt "Project type (auto, nodejs, python, go, maven, gradle, docker)" "${DEFAULT_PROJECT_TYPE}")"

    local ci_enabled
    ci_enabled="$(prompt_yes_no "Enable CI?" "true")"
    local cd_enabled
    cd_enabled="$(prompt_yes_no "Enable CD?" "true")"

    local environments
    environments="$(prompt "Environments (comma-separated)" "${DEFAULT_ENVIRONMENTS}")"

    local docker_registry
    docker_registry="$(prompt "Docker registry (leave empty if not using)" "")"

    local slack_webhook
    slack_webhook="$(prompt "Slack webhook URL (leave empty if not using)" "")"

    # Build configuration file
    local config
    config="# CI/CD Configuration for ${project_name}
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

[general]
project_type=${project_type}
log_level=info
dry_run=false

"

    if [[ "${ci_enabled}" == "true" ]]; then
        config+="
[ci]
lint_enabled=true
test_enabled=true
coverage_enabled=true
coverage_threshold=80
parallel_tests=true
test_timeout=300
parallel_jobs=4
test_results_dir=test-results
coverage_dir=coverage
"
    fi

    if [[ "${cd_enabled}" == "true" ]]; then
        config+="
[cd]
build_tool=auto
docker_registry=${docker_registry}
environments=${environments}
health_check_path=/health
health_check_timeout=300
auto_rollback=true
artifacts_dir=dist
"
    fi

    if [[ -n "${slack_webhook}" ]]; then
        config+="
[notifications]
enabled=true
slack_webhook=${slack_webhook}
enabled_events=deploy_success,deploy_failure
"
    fi

    # Write configuration file
    log_info "Writing configuration to: ${CONFIG_OUTPUT}"
    echo "${config}" > "${CONFIG_OUTPUT}"

    log_success "Configuration file created"
}

# Create GitHub Actions workflows
# Usage: create_github_workflows
create_github_workflows() {
    log_section "Creating GitHub Actions Workflows"

    local workflows_dir="${PROJECT_ROOT}/.github/workflows"
    ensure_dir "${workflows_dir}"

    # CI workflow
    local ci_workflow="${workflows_dir}/ci.yml"
    if [[ ! -f "${ci_workflow}" ]]; then
        cat > "${ci_workflow}" << 'EOF'
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run linting
        run: bash scripts/ci/lint.sh

  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run tests
        run: bash scripts/ci/test.sh --coverage

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: test-results/

      - name: Upload coverage reports
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage
          path: coverage/
EOF
        log_success "Created: ${ci_workflow}"
    else
        log_info "File exists: ${ci_workflow}"
    fi

    # CD workflow
    local cd_workflow="${workflows_dir}/cd.yml"
    if [[ ! -f "${cd_workflow}" ]]; then
        cat > "${cd_workflow}" << 'EOF'
name: CD

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build
        run: bash scripts/cd/build.sh

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/

  deploy-staging:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: staging
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Download artifacts
        uses: actions/download-artifact@v4
        with:
          name: dist
          path: dist/

      - name: Deploy to staging
        run: bash scripts/cd/deploy.sh staging

  deploy-production:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: production
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Download artifacts
        uses: actions/download-artifact@v4
        with:
          name: dist
          path: dist/

      - name: Deploy to production
        run: bash scripts/cd/deploy.sh prod
EOF
        log_success "Created: ${cd_workflow}"
    else
        log_info "File exists: ${cd_workflow}"
    fi
}

# Create GitLab CI configuration
# Usage: create_gitlab_ci
create_gitlab_ci() {
    log_section "Creating GitLab CI Configuration"

    local gitlab_ci="${PROJECT_ROOT}/.gitlab-ci.yml"

    if [[ ! -f "${gitlab_ci}" ]]; then
        cat > "${gitlab_ci}" << 'EOF'
stages:
  - lint
  - test
  - build
  - deploy

variables:
  GIT_STRATEGY: fetch

before_script:
  - set -euo pipefail

lint:
  stage: lint
  script:
    - bash scripts/ci/lint.sh
  tags:
    - docker

test:
  stage: test
  script:
    - bash scripts/ci/test.sh --coverage
  coverage: '/Coverage: \d+\.\d+/'
  artifacts:
    reports:
      junit: test-results/*.xml
    coverage_reports:
      coverage_format: cobertura
      path: coverage/cobertura-coverage.xml
  artifacts:
    paths:
      - test-results/
      - coverage/
    expire_in: 1 week
  tags:
    - docker

build:
  stage: build
  script:
    - bash scripts/cd/build.sh
  artifacts:
    paths:
      - dist/
    expire_in: 1 week
  tags:
    - docker

deploy:staging:
  stage: deploy
  script:
    - bash scripts/cd/deploy.sh staging
  environment:
    name: staging
    url: $STAGING_URL
  only:
    - main
  tags:
    - docker

deploy:production:
  stage: deploy
  script:
    - bash scripts/cd/deploy.sh prod
  environment:
    name: production
    url: $PRODUCTION_URL
  when: manual
  only:
    - tags
  tags:
    - docker
EOF
        log_success "Created: ${gitlab_ci}"
    else
        log_info "File exists: ${gitlab_ci}"
    fi
}

# Create environment configuration files
# Usage: create_env_files
create_env_files() {
    log_section "Creating Environment Configuration"

    local environments="${DEFAULT_ENVIRONMENTS}"
    IFS=',' read -ra envs <<< "${environments}"

    for env in "${envs[@]}"; do
        local env_file="${PROJECT_ROOT}/.env.${env}"
        local env_example="${env_file}.example"

        if [[ ! -f "${env_example}" ]]; then
            cat > "${env_example}" << EOF
# ${env^} Environment Configuration
# Copy this file to .env.${env} and fill in the values

# Application settings
NODE_ENV=${env}
APP_URL=

# Database
DATABASE_URL=
DATABASE_POOL_SIZE=10

# API keys
API_KEY=
API_SECRET=

# Third-party services
SLACK_WEBHOOK=

# Feature flags
FEATURE_NEW_UI=false
EOF
            log_success "Created: ${env_example}"
        fi
    done

    # Create .gitignore entry for env files
    local gitignore_env="${PROJECT_ROOT}/.env.gitignore"
    if [[ ! -f "${gitignore_env}" ]]; then
        cat > "${gitignore_env}" << EOF
# Environment files
.env
.env.*
!.env.*.example
EOF
        log_success "Created: ${gitignore_env}"
    fi
}

# Create documentation
# Usage: create_documentation
create_documentation() {
    log_section "Creating Documentation"

    local docs_dir="${PROJECT_ROOT}/docs"
    ensure_dir "${docs_dir}"

    # CI/CD usage guide
    local usage_doc="${docs_dir}/CI-CD.md"
    if [[ ! -f "${usage_doc}" ]]; then
        cat > "${usage_doc}" << 'EOF'
# CI/CD Documentation

This project uses the CI/CD Toolkit for automation.

## Quick Start

### Local Development

```bash
# Lint code
bash scripts/ci/lint.sh

# Run tests
bash scripts/ci/test.sh

# Generate coverage
bash scripts/ci/coverage.sh

# Build project
bash scripts/cd/build.sh
```

### CI/CD Platforms

This project is configured for:
- **GitHub Actions**: `.github/workflows/`
- **GitLab CI**: `.gitlab-ci.yml`

## Configuration

Configuration is in `.ci-cd.conf`.

## Deployment

### Staging

```bash
# Manual deployment
bash scripts/cd/deploy.sh staging

# Or push to main branch (auto-deploys)
```

### Production

```bash
# Manual deployment
bash scripts/cd/deploy.sh prod

# Or create and push a tag
git tag v1.0.0
git push origin v1.0.0
```

## Rollback

```bash
# Rollback to previous version
bash scripts/cd/rollback.sh prod

# Rollback to specific version
bash scripts/cd/rollback.sh prod --version 1.0.1
```
EOF
        log_success "Created: ${usage_doc}"
    fi
}

# Display summary
# Usage: display_summary
display_summary() {
    log_section "Initialization Complete"

    echo ""
    echo "The following files have been created:"
    echo ""
    echo "  Configuration:"
    echo "    - .ci-cd.conf"
    echo ""
    echo "  Workflows:"
    echo "    - .github/workflows/ci.yml"
    echo "    - .github/workflows/cd.yml"
    echo "    - .gitlab-ci.yml"
    echo ""
    echo "  Environment:"
    echo "    - .env.*.example"
    echo ""
    echo "  Documentation:"
    echo "    - docs/CI-CD.md"
    echo ""
    echo "Next steps:"
    echo "  1. Review and customize .ci-cd.conf"
    echo "  2. Create environment files from .env.*.example templates"
    echo "  3. Commit and push to trigger CI/CD pipelines"
    echo ""
}

# =============================================================================
# Main Initialization Function
# =============================================================================

# Main initialization logic
# Usage: main_init
main_init() {
    log_section "CI/CD Project Initialization"

    log_info "Project root: ${PROJECT_ROOT}"
    log_info "Project name: ${DEFAULT_PROJECT_NAME}"

    # Detect existing configuration
    detect_project_config

    # Generate configuration
    generate_config

    # Create CI/CD files
    if [[ "${CI_ONLY}" != "true" ]]; then
        if [[ "${CD_ONLY}" != "true" ]]; then
            create_github_workflows
            create_gitlab_ci
        fi
    fi

    if [[ "${CI_ONLY}" != "true" ]]; then
        create_env_files
    fi

    create_documentation

    # Display summary
    display_summary
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << 'EOF'
Usage: ./scripts/setup/init-project.sh [options]

Interactive project initialization with CI/CD configuration.

Options:
  --config FILE     Use existing config file as template
  --skip-prompts    Use default values without prompting
  --ci-only         Only set up CI (skip CD workflows)
  --cd-only         Only set up CD (skip CI workflows)
  --help, -h        Show this help message

Environment Variables:
  PROJECT_NAME      Project name (default: directory name)
  PROJECT_TYPE      Project type (auto, nodejs, python, go, etc.)

This script will:
  - Create .ci-cd.conf configuration file
  - Set up GitHub Actions workflows
  - Create GitLab CI configuration
  - Generate environment file templates
  - Create CI/CD documentation

Examples:
  # Interactive initialization
  ./scripts/setup/init-project.sh

  # Use defaults for all prompts
  ./scripts/setup/init-project.sh --skip-prompts

  # CI configuration only
  ./scripts/setup/init-project.sh --ci-only

EOF
}

# =============================================================================
# Main Script Entry Point
# =============================================================================

main() {
    local show_help=false
    local use_config=""

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help=true
                shift
                ;;
            --config)
                use_config="$2"
                shift 2
                ;;
            --skip-prompts)
                export SKIP_PROMPTS="true"
                shift
                ;;
            --ci-only)
                export CI_ONLY="true"
                shift
                ;;
            --cd-only)
                export CD_ONLY="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit "${EXIT_ERROR_GENERAL}"
                ;;
        esac
    done

    if [[ "${show_help}" == "true" ]]; then
        show_help
        exit "${EXIT_SUCCESS}"
    fi

    # Load existing config if provided
    if [[ -n "${use_config}" ]] && [[ -f "${use_config}" ]]; then
        log_info "Using config template: ${use_config}"
        CONFIG_OUTPUT="${PROJECT_ROOT}/.ci-cd.conf"
        cp "${use_config}" "${CONFIG_OUTPUT}"
    fi

    # Run initialization
    main_init
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
