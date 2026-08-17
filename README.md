# ⚙️ Program G-Code: CI/CD Toolkit

> **A comprehensive, language-agnostic CI/CD toolkit providing scripts, templates, and workflows for automating your development pipeline.**


---

## ✨ Features

- **Language-Agnostic**: Works with Node.js, Python, Go, Java, Docker, and more
- **Auto-Detection**: Automatically detects project type and tools
- **GitHub Actions & GitLab CI**: Ready-to-use workflow templates
- **Comprehensive Scripts**: Lint, test, build, deploy, and rollback utilities
- **Pre-flight Checks**: Status and documentation validation before operations
- **Health Checks**: Built-in deployment validation
- **Notifications**: Slack, email, and webhook support
- **Rollback Support**: Automatic rollback on deployment failure
- **Configurable**: Centralized configuration file with environment variable overrides


---

## 🚀 Quick Start

### 1. Clone or Copy to Your Project

```bash
# Clone the repository
git clone https://github.com/Galen-Chu/program-g-code.git
cd program-g-code

# Or copy the scripts directory to your project
cp -r scripts/ /path/to/your/project/
cp -r config/ /path/to/your/project/
```

### 2. Initialize Your Project

```bash
# Run the initialization script
bash scripts/setup/init-project.sh
```

This will:
- Create a `ci-cd.conf` configuration file in your project
- Detect your project type
- Set up basic CI/CD workflows

### 3. Install Dependencies (Optional)

```bash
# Install required tools for your platform
bash scripts/setup/install-deps.sh
```

### 4. Run Scripts

```bash
# Lint your code
bash scripts/ci/lint.sh

# Run tests
bash scripts/ci/test.sh

# Build artifacts
bash scripts/cd/build.sh

# Deploy to environment
bash scripts/cd/deploy.sh staging
```


---

## 🏗️ Project Structure

```
program-g-code/
├── scripts/
│   ├── ci/
│   │   ├── lint.sh          # Lint code (auto-detects linter)
│   │   ├── test.sh          # Run tests (auto-detects runner)
│   │   └── coverage.sh      # Generate coverage reports
│   ├── cd/
│   │   ├── build.sh         # Build artifacts
│   │   ├── deploy.sh        # Deploy to environments
│   │   └── rollback.sh      # Rollback deployments
│   ├── setup/
│   │   ├── install-deps.sh  # Install required tools
│   │   └── init-project.sh  # Initialize project
│   └── utils/
│       ├── common.sh            # Core utilities
│       ├── logger.sh            # Logging functions
│       ├── validators.sh        # Input validation
│       ├── notifiers.sh         # Notifications
│       ├── health-check.sh      # Health checks
│       ├── status-check.sh      # CI/CD status checking
│       ├── doc-check.sh         # Documentation validation
│       ├── pre-flight.sh        # Pre-flight check orchestrator
│       └── update-changelog.sh  # CHANGELOG automation
├── config/
│   └── ci-cd.conf           # Configuration template
├── .github/workflows/       # GitHub Actions workflows (ci, cd, release, security-scan)
├── .github/hooks/           # Pre-commit hooks
├── .gitlab-ci.yml            # GitLab CI pipeline definition
├── examples/
│   ├── simple-nodejs/       # Node.js example project
│   └── simple-python/       # Python example project
└── docs/
    ├── getting-started.md   # Getting started guide
    ├── configuration.md     # Configuration reference
    └── scripts-reference.md # Script documentation
```


---

## ⚙️ Configuration

Create a `config/ci-cd.conf` file in your project (or use `.ci-cd.conf` in the root):

```ini
[general]
project_type=auto
log_level=info
dry_run=false

[ci]
lint_enabled=true
test_enabled=true
coverage_threshold=80
parallel_tests=true

[cd]
build_tool=auto
docker_registry=
environments=dev,staging,prod
health_check_timeout=300
auto_rollback=true

[notifications]
slack_webhook=
enabled_events=deploy_success,deploy_failure
```

See [Configuration Guide](docs/configuration.md) for all options.


---

## 📖 Usage

### Command-Line Interface

All scripts support common options:

```bash
bash scripts/ci/lint.sh --help
bash scripts/ci/test.sh --log-level debug
bash scripts/cd/build.sh --dry-run
bash scripts/cd/deploy.sh --config custom.conf staging
```

### Environment Variables

Override configuration with environment variables:

```bash
export LOG_LEVEL=debug
export DRY_RUN=true
export BUILD_VERSION=1.0.0
bash scripts/cd/build.sh
```


---

## 🌐 Supported Languages and Tools

### Node.js / JavaScript

- **Linters**: ESLint, Standard, TSLint
- **Test Runners**: Jest, Mocha, Jasmine, Vitest
- **Package Managers**: npm, yarn, pnpm
- **Coverage**: Istanbul, c8, Vitest

### Python

- **Linters**: flake8, pylint, black
- **Test Runners**: pytest, unittest
- **Coverage**: Coverage.py, pytest-cov
- **Package Managers**: pip, poetry, pipenv

### Go

- **Linters**: golangci-lint, gofmt, golint
- **Test Runners**: go test
- **Coverage**: go test -cover

### Java

- **Linters**: Checkstyle, SpotBugs
- **Test Runners**: JUnit, TestNG
- **Build Tools**: Maven, Gradle

### Docker

- **Build**: Dockerfile, docker-compose
- **Multi-stage builds**: Supported
- **Registry push**: Docker Hub, ECR, GCR, ACR


---

## 🔄 CI/CD Platform Integration

### GitHub Actions

The workflows are in `.github/workflows/` (ci, cd, release, security-scan).
Copy them to your project, or use them directly by forking this repo:

Features:
- Matrix builds across OS and language versions
- Dependency caching
- Test report uploads
- Coverage report uploads
- Environment-based deployments with approval gates

### GitLab CI

Copy the GitLab CI configuration to your project:

```bash
cp .gitlab-ci.yml /path/to/your/project/
```

Features:
- Pipeline stages: lint, test, build, deploy
- Job artifacts and reports
- Cache configuration
- Environment-specific deployments
- Manual approval for production


---

## 📜 Scripts Reference

### CI Scripts

#### `scripts/ci/lint.sh`

Run linters based on project type.

```bash
# Lint all files
bash scripts/ci/lint.sh

# Lint specific files
bash scripts/ci/lint.sh src/

# Auto-fix issues
bash scripts/ci/lint.sh --fix
```

#### `scripts/ci/test.sh`

Run tests with configurable runners.

```bash
# Run all tests
bash scripts/ci/test.sh

# Run specific test file
bash scripts/ci/test.sh tests/test_api.py

# Run with coverage
bash scripts/ci/test.sh --coverage

# Parallel execution
bash scripts/ci/test.sh --parallel
```

#### `scripts/ci/coverage.sh`

Generate coverage reports.

```bash
# Generate coverage report
bash scripts/ci/coverage.sh

# Enforce threshold
bash scripts/ci/coverage.sh --threshold 80

# Output format
bash scripts/ci/coverage.sh --format lcov
```

### CD Scripts

#### `scripts/cd/build.sh`

Build project artifacts.

```bash
# Build with auto-detection
bash scripts/cd/build.sh

# Specific version
bash scripts/cd/build.sh --version 1.0.0

# Docker build
bash scripts/cd/build.sh --docker

# Multi-platform
bash scripts/cd/build.sh --platform linux/amd64,linux/arm64
```

#### `scripts/cd/deploy.sh`

Deploy to environments.

```bash
# Deploy to staging
bash scripts/cd/deploy.sh staging

# Deploy to production with pre-flight checks
bash scripts/cd/deploy.sh prod --pre-flight

# Skip health checks
bash scripts/cd/deploy.sh dev --skip-health-check

# Force deployment (bypasses pre-flight checks)
bash scripts/cd/deploy.sh prod --force
```

#### `scripts/cd/rollback.sh`

Rollback to previous version.

```bash
# Rollback to previous version
bash scripts/cd/rollback.sh prod

# Rollback to specific version
bash scripts/cd/rollback.sh prod --version 1.0.1

# List available versions
bash scripts/cd/rollback.sh prod --list
```

### Utility Scripts

#### `scripts/utils/health-check.sh`

Check service health.

```bash
# HTTP endpoint check
bash scripts/utils/health-check.sh https://api.example.com/health

# TCP port check
bash scripts/utils/health-check.sh --tcp localhost:8080

# With retry
bash scripts/utils/health-check.sh --retry 10 --interval 5 https://api.example.com/health
```

#### `scripts/utils/notifiers.sh`

Send notifications.

```bash
# Slack notification
SLACK_WEBHOOK=https://hooks.slack.com/... \
  bash scripts/utils/notifiers.sh slack "Deployment successful"

# Email notification
bash scripts/utils/notifiers.sh email "Build failed" --to devops@example.com

# Webhook notification
bash scripts/utils/notifiers.sh webhook https://hooks.example.com/deploy
```

#### `scripts/utils/status-check.sh`

Check CI/CD-relevant project status.

```bash
# Quick status check
bash scripts/utils/status-check.sh --quick

# Full check with fail-fast
bash scripts/utils/status-check.sh --fail-on-dirty --fail-on-ci-fail

# JSON output for automation
bash scripts/utils/status-check.sh --json

# Check before deployment
bash scripts/utils/status-check.sh --fail-on-ci-fail --fail-on-behind
```

Checks:
- Git working directory status
- Branch sync status vs main
- CI pipeline status (via GitHub CLI)
- Recent commits

#### `scripts/utils/doc-check.sh`

Validate project documentation.

```bash
# Check all documentation
bash scripts/utils/doc-check.sh

# Check only required files
bash scripts/utils/doc-check.sh --required-only

# Check and create missing templates
bash scripts/utils/doc-check.sh --fix

# Fail if required docs are missing
bash scripts/utils/doc-check.sh --fail-on-missing

# Check for outdated documentation
bash scripts/utils/doc-check.sh --check-staleness
```

Validates:
- Required docs (README.md)
- Recommended docs (CHANGELOG.md, CONTRIBUTING.md, LICENSE)
- Documentation age/staleness
- README content quality

#### `scripts/utils/pre-flight.sh`

Orchestrate comprehensive pre-flight checks.

```bash
# Run all pre-flight checks
bash scripts/utils/pre-flight.sh

# Quick pre-flight check
bash scripts/utils/pre-flight.sh --quick

# Strict mode (fail on any issues)
bash scripts/utils/pre-flight.sh --strict

# Skip documentation checks
bash scripts/utils/pre-flight.sh --skip-docs

# Auto-fix documentation issues
bash scripts/utils/pre-flight.sh --fix
```

Integrates:
- Dependency checks
- Configuration validation
- Status checks (via status-check.sh)
- Documentation checks (via doc-check.sh)

#### `scripts/utils/update-changelog.sh`

Automate CHANGELOG.md updates following Keep a Changelog format.

```bash
# Interactive mode (recommended)
bash scripts/utils/update-changelog.sh

# Quick entry
bash scripts/utils/update-changelog.sh --type added --message "Add new feature" --issue 123

# Auto-generate from commits
bash scripts/utils/update-changelog.sh --auto

# Preview without writing
bash scripts/utils/update-changelog.sh --type fixed --message "Fix bug" --dry-run

# Validate CHANGELOG format
bash scripts/utils/update-changelog.sh --validate
```

Features:
- Interactive prompts with commit context
- Support for all Keep a Changelog types (Added, Changed, Fixed, etc.)
- Issue/PR reference tracking
- CHANGELOG format validation
- Dry-run mode for preview


---

## 📝 CHANGELOG Workflow

This toolkit includes automated CHANGELOG management to track project changes.

### When to Update CHANGELOG

**Required for:**
- ✅ New features (`feat:` commits)
- ✅ Bug fixes (`fix:` commits)
- ✅ Breaking changes
- ✅ Performance improvements

**Not required for:**
- ❌ Documentation only changes
- ❌ Code style/formatting
- ❌ Internal refactoring
- ❌ Test updates

### Quick Start

```bash
# Make your code changes
git add .

# Update CHANGELOG
bash scripts/utils/update-changelog.sh

# Commit everything together
git add CHANGELOG.md
git commit -m "feat: add new feature"
```

### Automation

The toolkit includes:

1. **Pre-commit hook** (optional):
   ```bash
   cp .github/hooks/pre-commit-changelog.sh .git/hooks/pre-commit
   chmod +x .git/hooks/pre-commit
   ```

2. **CI validation**: CHANGELOG checks run in:
   - GitHub Actions (on PRs)
   - GitLab CI (on MRs)

3. **Interactive tool**: `update-changelog.sh` with:
   - Commit context awareness
   - Type selection
   - Format validation

### Release Process

When releasing:

```bash
# 1. Update CHANGELOG.md manually
# Move items from [Unreleased] to [VERSION]

# 2. Tag release
git tag v1.1.0

# 3. Push
git push && git push --tags
```

For detailed workflow, see [CONTRIBUTING.md](CONTRIBUTING.md#changelog-workflow).


---

## 📁 Examples

See the `examples/` directory for complete working examples:

- **simple-nodejs**: Express API with tests and linting
- **simple-python**: Flask application with pytest


---

## 🌍 Environment Configuration

Configure deployment environments in `ci-cd.conf`:

```ini
[environment.dev]
auto_deploy=true
skip_health_check=true
url=https://dev.example.com

[environment.staging]
auto_deploy=true
required_approvals=1
url=https://staging.example.com

[environment.prod]
auto_deploy=false
required_approvals=2
url=https://prod.example.com
```


---

## 📢 Notifications

Configure Slack webhooks, email, or generic webhooks:

```bash
# Slack
export SLACK_WEBHOOK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
export SLACK_CHANNEL=#deployments

# Email
export SMTP_SERVER=smtp.example.com
export SMTP_USERNAME=notifications@example.com
export SMTP_PASSWORD=your-password
export EMAIL_RECIPIENTS=team@example.com

# Generic webhook
export WEBHOOK_URL=https://hooks.example.com/deploy
export WEBHOOK_METHOD=POST
```


---

## 🛠️ Troubleshooting

### Enable Debug Logging

```bash
export LOG_LEVEL=debug
bash scripts/ci/test.sh
```

### Dry Run Mode

See what would happen without making changes:

```bash
export DRY_RUN=true
bash scripts/cd/deploy.sh staging
```

### Check Script Dependencies

```bash
bash scripts/setup/install-deps.sh --check
```

### Validate Configuration

```bash
bash scripts/utils/validators.sh --config
```


---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.


---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


---

## 📞 Support

- **Documentation**: See the [docs/](docs/) directory
- **Issues**: Report bugs on GitHub Issues
- **Discussions**: Use GitHub Discussions for questions


---

## 🗺️ Roadmap

- [ ] Azure DevOps pipelines
- [ ] Bitbucket Pipelines
- [ ] Kubernetes deployment support
- [ ] Terraform integration
- [ ] Monitoring and observability hooks
- [ ] More language-specific templates


---

## 🙏 Acknowledgments

Built with love for the DevOps community. Inspired by best practices from GitHub Actions, GitLab CI, and modern CI/CD platforms.
