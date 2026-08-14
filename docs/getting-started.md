# Getting Started with CI/CD Toolkit

A comprehensive guide to get started with the CI/CD Toolkit.

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [Project Initialization](#project-initialization)
4. [Running Scripts](#running-scripts)
5. [Configuration](#configuration)
6. [CI/CD Integration](#cicd-integration)
7. [Next Steps](#next-steps)

## Installation

### Clone or Copy

```bash
# Clone the repository
git clone https://github.com/Galen-Chu/program-g-code.git
cd program-g-code

# Or copy to your existing project
cp -r scripts/ /path/to/your/project/
cp -r config/ /path/to/your/project/
```

### Initialize Your Project

```bash
# Run the initialization script
bash scripts/setup/init-project.sh
```

This will:
- Detect your project type
- Create `.ci-cd.conf` configuration file
- Set up CI/CD workflows
- Generate environment file templates

### Install Dependencies (Optional)

```bash
# Install CI/CD dependencies for your platform
bash scripts/setup/install-deps.sh

# Check what's already installed
bash scripts/setup/install-deps.sh --check
```

## Quick Start

### 1. Lint Your Code

```bash
# Lint all files
bash scripts/ci/lint.sh

# Auto-fix issues
bash scripts/ci/lint.sh --fix

# Lint specific directory
bash scripts/ci/lint.sh src/
```

### 2. Run Tests

```bash
# Run all tests
bash scripts/ci/test.sh

# Run with coverage
bash scripts/ci/test.sh --coverage

# Run specific test file
bash scripts/ci/test.sh tests/test_api.py
```

### 3. Build Artifacts

```bash
# Build with auto-detected tools
bash scripts/cd/build.sh

# Build with specific version
bash scripts/cd/build.sh --version 1.0.0

# Build Docker image
bash scripts/cd/build.sh --docker
```

### 4. Deploy to Environment

```bash
# Deploy to staging
bash scripts/cd/deploy.sh staging

# Deploy to production
bash scripts/cd/deploy.sh prod

# Skip health checks
bash scripts/cd/deploy.sh dev --skip-health-check
```

## Project Initialization

The toolkit supports automatic project type detection:

| Type          | Detection Files                          |
|---------------|------------------------------------------|
| Node.js       | `package.json`                           |
| Python        | `requirements.txt`, `setup.py`, `pyproject.toml` |
| Go            | `go.mod`                                 |
| Maven         | `pom.xml`                                |
| Gradle        | `build.gradle`, `build.gradle.kts`        |
| Docker        | `Dockerfile`, `docker-compose.yml`        |

### Interactive Initialization

```bash
bash scripts/setup/init-project.sh
```

You'll be prompted for:
- Project name
- Project type
- CI/CD settings
- Environment names
- Notification settings

### Non-Interactive Initialization

```bash
# Use all defaults
SKIP_PROMPTS=true bash scripts/setup/init-project.sh

# CI configuration only
bash scripts/setup/init-project.sh --ci-only

# CD configuration only
bash scripts/setup/init-project.sh --cd-only
```

## Running Scripts

### Common Options

All scripts support these common options:

```bash
--help, -h          Show help message
--log-level LEVEL   Set log level (debug|info|warn|error)
--config FILE       Use custom configuration file
--dry-run           Simulate actions without making changes
```

### Environment Variables

Override configuration with environment variables:

```bash
# Log level
export LOG_LEVEL=debug

# Dry run mode
export DRY_RUN=true

# Build version
export BUILD_VERSION=1.0.0

# Project type (override auto-detection)
export PROJECT_TYPE=nodejs
```

## Configuration

### Configuration File

The toolkit uses `.ci-cd.conf` for configuration:

```ini
[general]
project_type=auto
log_level=info
dry_run=false

[ci]
lint_enabled=true
test_enabled=true
coverage_threshold=80

[cd]
build_tool=auto
environments=dev,staging,prod
health_check_timeout=300
auto_rollback=true

[notifications]
slack_webhook=
enabled_events=deploy_success,deploy_failure
```

### Environment-Specific Configuration

Create environment files:

```bash
# Development
.env.dev

# Staging
.env.staging

# Production
.env.prod
```

Example `.env.prod`:

```bash
NODE_ENV=production
API_URL=https://api.example.com
DATABASE_URL=postgresql://user:pass@host:5432/db
SLACK_WEBHOOK=https://hooks.slack.com/...
```

## CI/CD Integration

### GitHub Actions

The toolkit includes GitHub Actions workflows (in `.github/workflows/`):

```bash
# Copy to your project
cp .github/workflows/ci.yml /path/to/your/project/.github/workflows/
cp .github/workflows/cd.yml /path/to/your/project/.github/workflows/
```

#### Features

- **CI Workflow** (`ci.yml`):
  - Linting on all pushes
  - Testing in matrix (OS × language version)
  - Coverage reporting
  - Security scanning

- **CD Workflow** (`cd.yml`):
  - Build on push to main
  - Deploy to staging automatically
  - Deploy to production with manual approval
  - Health checks
  - Automatic rollback

### GitLab CI

```bash
# Copy to your project
cp .gitlab-ci.yml /path/to/your/project/
```

#### Features

- Pipeline stages: lint, test, build, deploy
- Environment-specific deployments
- Manual approval for production
- Review apps for merge requests

### Manual Triggering

**GitHub Actions:**
```bash
# Use GitHub CLI
gh workflow run ci.yml
gh workflow run cd.yml -f environment=staging
```

**GitLab CI:**
```bash
# Trigger pipeline via API
curl -X POST \
  -F token=$CI_JOB_TOKEN \
  -F ref=main \
  https://gitlab.com/api/v4/projects/:id/trigger/pipeline
```

## Next Steps

### Customize Configuration

1. Edit `.ci-cd.conf` for your project needs
2. Set up environment files (`.env.*`)
3. Configure notification webhooks

### Add Custom Scripts

```bash
# Create custom script
scripts/custom/my-script.sh

# Make executable
chmod +x scripts/custom/my-script.sh

# Use in workflows
bash scripts/custom/my-script.sh
```

### Set Up Monitoring

```bash
# Health checks
bash scripts/utils/health-check.sh https://api.example.com/health

# Notifications
bash scripts/utils/notifiers.sh slack "Deployment complete"
```

### Examples

Check the example projects:

- [`examples/simple-nodejs/`](../examples/simple-nodejs/) - Node.js Express API
- [`examples/simple-python/`](../examples/simple-python/) - Python Flask API

## Common Use Cases

### Node.js Project

```bash
# Initialize
npm init -y
bash scripts/setup/init-project.sh

# Install dev dependencies
npm install -D eslint jest

# Run checks
bash scripts/ci/lint.sh
bash scripts/ci/test.sh --coverage
```

### Python Project

```bash
# Initialize
bash scripts/setup/init-project.sh

# Install dev dependencies
pip install pytest flake8

# Run checks
bash scripts/ci/lint.sh
bash scripts/ci/test.sh --coverage
```

### Docker Project

```bash
# Build Docker image
bash scripts/cd/build.sh --docker

# Push to registry
DOCKER_REGISTRY=registry.example.com \
  bash scripts/cd/build.sh --docker

# Deploy
bash scripts/cd/deploy.sh prod
```

## Troubleshooting

### Script Not Found

```bash
# Make scripts executable
chmod +x scripts/**/*.sh
```

### Permission Denied

```bash
# Run with bash explicitly
bash scripts/ci/lint.sh
```

### Configuration Not Loading

```bash
# Specify config file explicitly
bash scripts/ci/test.sh --config /path/to/config.conf
```

For more troubleshooting tips, see [Troubleshooting](./troubleshooting.md).
