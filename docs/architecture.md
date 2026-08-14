# CI/CD Toolkit Architecture

Technical architecture and design of the CI/CD Toolkit.

## Table of Contents

1. [Overview](#overview)
2. [Design Principles](#design-principles)
3. [Directory Structure](#directory-structure)
4. [Component Architecture](#component-architecture)
5. [Data Flow](#data-flow)
6. [Extensibility](#extensibility)
7. [Security Considerations](#security-considerations)

## Overview

The CI/CD Toolkit is designed as a modular, language-agnostic system for automating continuous integration and deployment pipelines.

### Key Goals

- **Language Agnostic**: Works with Node.js, Python, Go, Java, Docker, and more
- **Auto-Detection**: Automatically detects project type and tools
- **Composability**: Scripts can be used independently or combined
- **Extensibility**: Easy to add new languages, tools, and platforms
- **Best Practices**: Follows CI/CD industry best practices

### Architecture Layers

```
┌─────────────────────────────────────────────┐
│         CI/CD Platforms                     │
│  (GitHub Actions, GitLab CI, etc.)          │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│          Workflow Templates                  │
│  (CI, CD, Release, Security Scan)           │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│            Pipeline Scripts                  │
│  (lint.sh, test.sh, build.sh, deploy.sh)    │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│          Utility Libraries                   │
│  (common.sh, logger.sh, validators.sh)       │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│          Operating System                    │
│  (Linux, macOS, Windows via Git Bash)       │
└─────────────────────────────────────────────┘
```

## Design Principles

### 1. Modularity

Each script is self-contained and can be used independently:

```bash
# Use only what you need
bash scripts/ci/lint.sh
bash scripts/ci/test.sh
bash scripts/cd/build.sh
```

### 2. Convention over Configuration

Sensible defaults reduce configuration burden:

- Auto-detect project type
- Default output directories
- Standard configuration file locations

### 3. Fail Fast

Early validation prevents wasted time:

- Pre-flight checks
- Dependency validation
- Configuration verification

### 4. Observable

Comprehensive logging enables debugging:

- Structured logging (info, warn, error, debug)
- Log levels
- File output option

### 5. Idempotent

Scripts can be run multiple times safely:

- Check before creating
- Update existing resources
- Graceful handling of existing state

## Directory Structure

```
program-g-code/
├── scripts/
│   ├── ci/                    # Continuous Integration scripts
│   │   ├── lint.sh           # Linting
│   │   ├── test.sh           # Testing
│   │   └── coverage.sh       # Coverage reporting
│   │
│   ├── cd/                    # Continuous Deployment scripts
│   │   ├── build.sh          # Build artifacts
│   │   ├── deploy.sh         # Deploy to environments
│   │   └── rollback.sh       # Rollback deployments
│   │
│   ├── setup/                 # Setup and initialization
│   │   ├── install-deps.sh   # Install dependencies
│   │   └── init-project.sh   # Initialize project
│   │
│   └── utils/                 # Utility libraries
│       ├── common.sh         # Core utilities
│       ├── logger.sh         # Logging functions
│       ├── validators.sh     # Validation functions
│       ├── notifiers.sh      # Notifications
│       └── health-check.sh   # Health checks
│
├── config/
│   └── ci-cd.conf            # Configuration template
│
├── .github/workflows/        # GitHub Actions workflows
├── .github/hooks/            # Pre-commit hooks
├── .gitlab-ci.yml             # GitLab CI pipeline
│
├── examples/                 # Example projects
│   ├── simple-nodejs/
│   └── simple-python/
│
├── docs/                     # Documentation
│
├── .github/
│   └── workflows/            # GitHub Actions workflows
│
├── .gitlab-ci.yml            # GitLab CI configuration
├── .gitignore                # Language-agnostic gitignore
└── README.md                 # Main documentation
```

## Component Architecture

### Core Libraries

#### common.sh

**Purpose**: Shared utilities and functions

**Responsibilities**:
- Color definitions
- Exit code constants
- Command checking
- OS detection
- Project type detection
- Configuration loading
- Version management

**Key Functions**:
- `error_exit()` - Error handling
- `check_command()` - Command verification
- `detect_os()` - OS detection
- `get_project_type()` - Project type detection
- `load_config()` - Configuration loading
- `get_version()` - Version retrieval

#### logger.sh

**Purpose**: Structured logging

**Responsibilities**:
- Colored console output
- Log level filtering
- File logging
- CI/CD platform integration

**Key Functions**:
- `log_info()` - Info messages (blue)
- `log_success()` - Success messages (green)
- `log_warn()` - Warnings (yellow)
- `log_error()` - Errors (red)
- `log_debug()` - Debug messages (gray)
- `log_section()` - Section headers

**Log Levels**:
```
debug (0) → info (1) → warn (2) → error (3)
```

#### validators.sh

**Purpose**: Input validation

**Responsibilities**:
- Environment variable validation
- URL validation
- Semantic version validation
- File/directory validation
- Command version checking

**Key Functions**:
- `validate_env_vars()` - Validate environment variables
- `validate_url()` - Validate URL format
- `validate_semver()` - Validate semantic version
- `check_commands()` - Check multiple commands
- `check_docker()` - Verify Docker installation

### Pipeline Scripts

#### CI Scripts (scripts/ci/)

**lint.sh**
- Detects project type
- Selects appropriate linter
- Runs linting
- Supports `--fix` flag
- Returns proper exit codes

**test.sh**
- Detects test runner
- Runs tests with or without coverage
- Supports parallel execution
- Generates JUnit XML reports
- Handles timeouts

**coverage.sh**
- Generates coverage reports
- Supports multiple formats (lcov, cobertura, html)
- Enforces coverage thresholds
- Merges coverage sources

#### CD Scripts (scripts/cd/)

**build.sh**
- Detects build system
- Builds artifacts
- Supports Docker builds
- Multi-platform support
- Generates build metadata

**deploy.sh**
- Pre-deployment checks
- Multi-environment support
- Health check validation
- Post-deployment notifications
- Auto-rollback on failure

**rollback.sh**
- Version management
- Rollback to previous/specific version
- Database rollback support
- Service restart

### Setup Scripts

**install-deps.sh**
- Platform detection
- Package manager detection
- Installs language-specific tools
- Validates installations

**init-project.sh**
- Interactive initialization
- Configuration file generation
- Workflow setup
- Environment file templates

### Utility Scripts

**notifiers.sh**
- Slack notifications
- Email notifications
- Generic webhooks
- Microsoft Teams
- Discord

**health-check.sh**
- HTTP endpoint checks
- TCP port checks
- Database health checks
- Container health checks
- Kubernetes pod checks

## Data Flow

### CI Pipeline Flow

```
┌──────────────┐
│ Code Change  │
└──────┬───────┘
       │
┌──────▼───────┐
│   Lint       │ ──► common.sh, logger.sh, validators.sh
│              │ ──► Detect project type
│              │ ──► Run linter (eslint, flake8, etc.)
└──────┬───────┘
       │
┌──────▼───────┐
│   Test       │ ──► common.sh, logger.sh
│              │ ──► Detect test runner
│              │ ──► Run tests with/without coverage
└──────┬───────┘
       │
┌──────▼───────┐
│   Coverage   │ ──► Parse coverage reports
│              │ ──► Enforce thresholds
│              │ ──► Generate reports
└──────────────┘
```

### CD Pipeline Flow

```
┌──────────────┐
│   Build      │ ──► Detect build system
│              │ ──► Build artifacts
│              │ ──► Generate metadata
└──────┬───────┘
       │
┌──────▼───────┐
│ Pre-Deploy   │ ──► Validate artifacts
│  Checks      │ ──► Check git status
│              │ ──► Verify approvals
└──────┬───────┘
       │
┌──────▼───────┐
│   Deploy     │ ──► Deploy to environment
│              │ ──► Wait for deployment
└──────┬───────┘
       │
┌──────▼───────┐
│Health Check  │ ──► Check service health
│              │ ──► Retry with backoff
└──────┬───────┘
       │
       ├──────────────────┐
       │                  │
   ┌───▼────┐      ┌─────▼─────┐
   │ Success │      │  Failure  │
   └───┬────┘      └─────┬─────┘
       │                  │
┌──────▼───────┐   ┌──────▼──────┐
│ Notify       │   │  Rollback   │
│              │   │  Notify     │
└──────────────┘   └─────────────┘
```

### Configuration Loading Flow

```
┌──────────────────┐
│ Script Starts    │
└─────┬────────────┘
      │
┌─────▼────────────┐
│ Source common.sh │
└─────┬────────────┘
      │
┌─────▼────────────────────┐
│ Load Configuration        │
│ (1) config/ci-cd.conf    │
│ (2) .ci-cd.conf         │
│ (3) Environment vars    │
│ (4) Command-line flags   │
└─────┬────────────────────┘
      │
┌─────▼────────────┐
│ Validate Config  │
└─────┬────────────┘
      │
┌─────▼────────────┐
│ Set Defaults     │
└─────┬────────────┘
      │
┌─────▼────────────┐
│ Execute Script   │
└──────────────────┘
```

## Extensibility

### Adding Language Support

1. **Add detection logic** to `common.sh`:
```bash
get_project_type() {
    # ... existing cases ...

    if [[ -f "${PROJECT_ROOT}/Cargo.toml" ]]; then
        echo "rust"
    fi
}
```

2. **Add linter** to `lint.sh`:
```bash
lint_rust() {
    local rust_cmd="cargo"
    if ! check_command "${rust_cmd}"; then
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi
    ${rust_cmd} clippy -- -D warnings
}
```

3. **Add test runner** to `test.sh`:
```bash
test_rust() {
    cargo test --verbose
}
```

### Adding Platform Support

1. **Add OS detection** to `common.sh`:
```bash
detect_os() {
    local os_name="$(uname -s)"
    case "${os_name}" in
        FreeBSD*)
            echo "freebsd"
            ;;
        # ... existing cases ...
    esac
}
```

### Adding Notification Channels

1. **Add to `notifiers.sh`**:
```bash
notify_telegram() {
    local message="$1"
    local webhook_url="${TELEGRAM_WEBHOOK:-}"
    # Implementation
}
```

## Security Considerations

### Secret Management

- Never log secrets
- Use environment variables
- Store in CI/CD platform secret stores
- Validate secret presence before use

### Dependency Security

- Run security scans
- Check for vulnerabilities
- Pin dependency versions
- Update dependencies regularly

### Deployment Security

- Require approval for production
- Use encrypted connections
- Verify deployments
- Automatic rollback on failure

### File Permissions

```bash
# Make scripts executable
chmod +x scripts/**/*.sh

# But not executable for config files
chmod 644 config/ci-cd.conf
```

### Input Validation

All inputs are validated:
- File paths (prevent path traversal)
- URLs (prevent SSRF)
- Commands (prevent injection)
- Versions (validate format)

## Performance Optimization

### Parallel Execution

```bash
# Run tests in parallel
bash scripts/ci/test.sh --parallel

# Parallel jobs
PARALLEL_JOBS=8 bash scripts/ci/test.sh
```

### Caching

```bash
# Docker build cache
USE_CACHE=true bash scripts/cd/build.sh --docker

# npm cache
npm ci --prefer-offline
```

### Incremental Builds

- Only rebuild changed components
- Skip unnecessary steps
- Use build artifacts

## Testing the Toolkit

### Unit Testing

Test individual functions:
```bash
source scripts/utils/common.sh
get_project_type
```

### Integration Testing

Test full workflows:
```bash
cd examples/simple-nodejs
../../scripts/ci/lint.sh
../../scripts/ci/test.sh
../../scripts/cd/build.sh
```

### Platform Testing

Test on multiple platforms:
- Linux (Ubuntu, Debian, CentOS)
- macOS (Intel, Apple Silicon)
- Windows (Git Bash, WSL)

## Future Enhancements

Potential improvements:
- [ ] Web UI for pipeline management
- [ ] Real-time log streaming
- [ ] Metrics and dashboards
- [ ] A/B deployment support
- [ ] Canary deployments
- [ ] Blue-green deployments
- [ ] Kubernetes native deployment
- [ ] Terraform integration
- [ ] More language support
- [ ] Plugin system
