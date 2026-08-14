# Pipelines Guide

Guide for setting up and configuring CI/CD pipelines.

## Table of Contents

1. [Pipeline Overview](#pipeline-overview)
2. [GitHub Actions](#github-actions)
3. [GitLab CI](#gitlab-ci)
4. [Custom Pipelines](#custom-pipelines)
5. [Pipeline Best Practices](#pipeline-best-practices)

## Pipeline Overview

### Pipeline Stages

Typical CI/CD pipeline stages:

```
┌─────────────┐
│    Lint     │  Code quality checks
└──────┬──────┘
       │
┌──────▼──────┐
│    Test     │  Unit and integration tests
└──────┬──────┘
       │
┌──────▼──────┐
│   Build     │  Build artifacts
└──────┬──────┘
       │
┌──────▼──────┐
│   Deploy    │  Deploy to environments
│  (staging)  │
└──────┬──────┘
       │
┌──────▼──────┐
│   Deploy    │  Deploy to production
│  (prod)     │  (with approval)
└─────────────┘
```

### CI vs CD

**CI (Continuous Integration):**
- Linting
- Testing
- Coverage
- Security scanning

**CD (Continuous Deployment):**
- Building artifacts
- Deploying to environments
- Health checks
- Rollback

## GitHub Actions

### Workflow Files

Location: `.github/workflows/`

**CI Workflow** (`ci.yml`):
- Linting on all pushes
- Testing in matrix (OS × version)
- Coverage reporting
- Security scanning

**CD Workflow** (`cd.yml`):
- Build on push to main
- Deploy to staging automatically
- Deploy to production with manual approval

### Setting Up GitHub Actions

1. **Copy workflow files:**
```bash
cp .github/workflows/ci.yml /path/to/your/project/.github/workflows/
cp .github/workflows/cd.yml /path/to/your/project/.github/workflows/
cp .github/workflows/release.yml /path/to/your/project/.github/workflows/
cp .github/workflows/security-scan.yml /path/to/your/project/.github/workflows/
```

2. **Configure secrets:**
Go to: Repository → Settings → Secrets and variables → Actions

Required secrets:
- `NPM_TOKEN` - For publishing to npm
- `CODECOV_TOKEN` - For coverage reporting
- `SLACK_WEBHOOK` - For notifications
- `SNYK_TOKEN` - For security scanning
- `GITHUB_TOKEN` - Automatically provided

3. **Customize workflows:**
Edit `.github/workflows/ci.yml`:
```yaml
env:
  NODE_VERSION: '20'  # Change to your version
```

### GitHub Actions Features

#### Matrix Builds

Test across multiple OS and versions:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    node-version: ['18', '20', '22']
```

#### Caching

Speed up builds with caching:

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: ${{ env.NODE_VERSION }}
    cache: 'npm'
```

#### Artifacts

Upload test results and coverage:

```yaml
- name: Upload test results
  uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: test-results/
```

#### Environment Deployment

Deploy with approval gates:

```yaml
deploy-production:
  environment:
    name: production
    url: https://app.example.com
```

### GitHub Actions Events

| Event | Trigger |
|-------|---------|
| `push` | Push to branch |
| `pull_request` | Pull request created/updated |
| `workflow_dispatch` | Manual trigger |
| `release` | Release created |

## GitLab CI

### Pipeline Configuration

File: `.gitlab-ci.yml`

### Setting Up GitLab CI

1. **Copy configuration:**
```bash
cp .gitlab-ci.yml /path/to/your/project/.gitlab-ci.yml
```

2. **Configure variables:**
Go to: Project → Settings → CI/CD → Variables

Required variables:
- `DEV_URL` - Development environment URL
- `STAGING_URL` - Staging environment URL
- `PRODUCTION_URL` - Production URL
- `SLACK_WEBHOOK` - For notifications

3. **Configure runners:**
Go to: Project → Settings → CI/CD → Runners

### GitLab CI Features

#### Pipeline Stages

```yaml
stages:
  - lint
  - test
  - build
  - deploy
```

#### Job Artifacts

```yaml
test:
  artifacts:
    reports:
      junit: test-results/*.xml
    paths:
      - test-results/
    expire_in: 1 week
```

#### Environments

```yaml
deploy:staging:
  environment:
    name: staging
    url: $STAGING_URL
```

#### Manual Jobs

```yaml
deploy:prod:
  when: manual
  only:
    - tags
```

#### Review Apps

```yaml
review:apps:
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    on_stop: stop_review
```

## Custom Pipelines

### Creating Custom Pipelines

1. **Create workflow file:**
```bash
# .github/workflows/custom.yml
name: Custom Pipeline

on:
  push:
    branches: [main]

jobs:
  custom-job:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run custom script
        run: bash scripts/custom/my-script.sh
```

2. **Create GitLab CI job:**
```yaml
# .gitlab-ci.yml
custom:job:
  stage: build
  script:
    - bash scripts/custom/my-script.sh
```

### Pipeline Templates

#### Minimal CI

```yaml
name: Minimal CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/ci/test.sh
```

#### Full CI/CD

```yaml
name: Full CI/CD

on:
  push:
    branches: [main]
  release:
    types: [created]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/ci/lint.sh

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/ci/test.sh --coverage

  build:
    runs-on: ubuntu-latest
    needs: [lint, test]
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/cd/build.sh

  deploy:
    runs-on: ubuntu-latest
    needs: build
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/cd/deploy.sh staging
```

## Pipeline Best Practices

### 1. Fast Feedback

- Run linting first (fastest check)
- Run tests in parallel
- Use caching for dependencies

### 2. Fail Fast

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    # ... linting is fast, catches issues early

  test:
    runs-on: ubuntu-latest
    needs: lint  # Only run tests if linting passes
```

### 3. Artifact Management

- Keep artifacts for a reasonable time
- Upload only necessary files
- Use artifact retention policies

### 4. Security

- Never log secrets
- Use GitHub Secrets / GitLab Variables
- Rotate credentials regularly
- Scan for secrets in code

### 5. Notifications

- Notify on failures only (reduce noise)
- Include relevant context
- Use appropriate channels

### 6. Environment Separation

- Use separate environments for dev/staging/prod
- Require approval for production
- Use different URLs per environment

### 7. Monitoring

- Track pipeline success rate
- Monitor build times
- Alert on repeated failures

### 8. Documentation

- Document pipeline configuration
- Include pipeline runbooks
- Keep diagrams up to date

## Pipeline Patterns

### Monorepo Pipeline

```yaml
# Run for specific paths
jobs:
  api:
    runs-on: ubuntu-latest
    if: contains(github.event.commits[0].modified, 'api/')
    steps:
      - run: bash scripts/ci/test.sh api/

  web:
    runs-on: ubuntu-latest
    if: contains(github.event.commits[0].modified, 'web/')
    steps:
      - run: bash scripts/ci/test.sh web/
```

### Matrix With Exclusions

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest]
    node: ['18', '20']
  exclude:
    - os: windows-latest
      node: '18'  # Skip this combination
```

### Conditional Deployment

```yaml
deploy:prod:
  if: |
    github.ref == 'refs/heads/main' &&
    github.event_name == 'push' &&
    !contains(github.event.head_commit.message, '[skip-deploy]')
```

### Cached Dependencies

```yaml
- name: Cache node modules
  uses: actions/cache@v3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

## Troubleshooting Pipelines

### Pipeline Fails Silently

1. Check logs for each step
2. Look for `set -e` causing early exit
3. Enable debug logging: `LOG_LEVEL=debug`

### Workflow Not Triggering

1. Check branch names
2. Verify workflow file syntax
3. Check GitHub Actions / GitLab CI settings

### Permission Errors

1. Check runner permissions
2. Verify file access rights
3. Check environment variable access

### Timeouts

1. Increase job timeout
2. Optimize slow steps
3. Use caching

For more troubleshooting tips, see [Troubleshooting](./troubleshooting.md).
