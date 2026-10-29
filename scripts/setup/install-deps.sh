#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Install Dependencies Script
# =============================================================================
# Platform detection and tool installation for CI/CD dependencies.
#
# Usage:
#   ./scripts/setup/install-deps.sh [options]
#
# Options:
#   --check          Check if dependencies are installed (don't install)
#   --tools LIST      Comma-separated list of tools to install
#   --platform PLAT   Force platform (linux, macos, windows)
#   --help, -h        Show help message
#
# Environment Variables:
#   SKIP_PROMPT       Skip confirmation prompts
#   INSTALL_DIR       Custom installation directory
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
CHECK_ONLY="${CHECK_ONLY:-false}"
SKIP_PROMPT="${SKIP_PROMPT:-false}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# Tool categories
NODE_TOOLS="node npm yarn pnpm"
PYTHON_TOOLS="python3 pip pipenv poetry"
GO_TOOLS="go golangci-lint"
DOCKER_TOOLS="docker docker-compose"
GIT_TOOLS="git gh"
GENERAL_TOOLS="jq curl wget shellcheck"

# =============================================================================
# Platform Detection
# =============================================================================

# Detect package manager for the platform
# Usage: detect_package_manager
detect_package_manager() {
    local os
    os="$(detect_os)"

    case "${os}" in
        linux)
            if check_command apt-get; then
                echo "apt"
            elif check_command yum; then
                echo "yum"
            elif check_command dnf; then
                echo "dnf"
            elif check_command pacman; then
                echo "pacman"
            elif check_command zypper; then
                echo "zypper"
            elif check_command apk; then
                echo "apk"
            else
                echo "unknown"
            fi
            ;;

        macos)
            if check_command brew; then
                echo "brew"
            else
                echo "unknown"
            fi
            ;;

        windows)
            if check_command chocolatey; then
                echo "choco"
            elif check_command scoop; then
                echo "scoop"
            else
                echo "unknown"
            fi
            ;;

        *)
            echo "unknown"
            ;;
    esac
}

# =============================================================================
# Dependency Checking
# =============================================================================

# Check if a tool is installed
# Usage: check_tool tool_name
check_tool() {
    local tool="$1"

    if check_command "${tool}"; then
        local version
        version=$(${tool} --version 2>/dev/null || echo "unknown")
        log_success "${tool} is installed (${version})"
        return 0
    else
        log_warn "${tool} is NOT installed"
        return 1
    fi
}

# Check all dependencies
# Usage: check_all_dependencies
check_all_dependencies() {
    log_section "Checking Installed Dependencies"

    local all_installed=true

    # Check general tools
    log_info "General tools:"
    for tool in ${GENERAL_TOOLS}; do
        if ! check_tool "${tool}"; then
            all_installed=false
        fi
    done

    # Check Git tools
    log_info "Git tools:"
    for tool in ${GIT_TOOLS}; do
        if ! check_tool "${tool}"; then
            all_installed=false
        fi
    done

    # Check Node.js tools
    log_info "Node.js tools:"
    for tool in ${NODE_TOOLS}; do
        if ! check_tool "${tool}"; then
            all_installed=false
        fi
    done

    # Check Python tools
    log_info "Python tools:"
    for tool in ${PYTHON_TOOLS}; do
        if ! check_tool "${tool}"; then
            all_installed=false
        fi
    done

    # Check Go tools
    log_info "Go tools:"
    for tool in ${GO_TOOLS}; do
        if ! check_tool "${tool}"; then
            all_installed=false
        fi
    done

    # Check Docker tools
    log_info "Docker tools:"
    for tool in ${DOCKER_TOOLS}; do
        if ! check_tool "${tool}"; then
            all_installed=false
        fi
    done

    if [[ "${all_installed}" == "true" ]]; then
        log_section "All Dependencies Installed"
        return 0
    else
        log_section "Some Dependencies Missing"
        return 1
    fi
}

# =============================================================================
# Installation Functions
# =============================================================================

# Install package on Linux
# Usage: install_linux package manager
install_linux() {
    local package="$1"
    local pkg_manager="$2"

    log_info "Installing ${package} using ${pkg_manager}..."

    case "${pkg_manager}" in
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y "${package}"
            ;;
        yum|dnf)
            sudo "${pkg_manager}" install -y "${package}"
            ;;
        pacman)
            sudo pacman -S --noconfirm "${package}"
            ;;
        zypper)
            sudo zypper install -y "${package}"
            ;;
        apk)
            sudo apk add "${package}"
            ;;
        *)
            log_error "Unknown package manager: ${pkg_manager}"
            return 1
            ;;
    esac
}

# Install package on macOS
# Usage: install_macos package
install_macos() {
    local package="$1"

    if ! check_command brew; then
        log_error "Homebrew not found. Please install from: https://brew.sh"
        return 1
    fi

    log_info "Installing ${package} using brew..."
    brew install "${package}"
}

# Install package on Windows
# Usage: install_windows package manager
install_windows() {
    local package="$1"
    local pkg_manager="$2"

    case "${pkg_manager}" in
        choco|chocolatey)
            log_info "Installing ${package} using chocolatey..."
            choco install -y "${package}"
            ;;
        scoop)
            log_info "Installing ${package} using scoop..."
            scoop install "${package}"
            ;;
        *)
            log_error "Unknown package manager: ${pkg_manager}"
            return 1
            ;;
    esac
}

# Install Node.js tools
# Usage: install_nodejs_tools
install_nodejs_tools() {
    log_info "Setting up Node.js tools..."

    if ! check_command node; then
        log_warn "Node.js not found. Installing..."
        local os
        os="$(detect_os)"

        case "${os}" in
            linux)
                install_linux "nodejs" "$(detect_package_manager)"
                ;;
            macos)
                install_macos "node"
                ;;
            windows)
                install_windows "nodejs" "$(detect_package_manager)"
                ;;
        esac
    fi

    # Install global npm packages
    if check_command npm; then
        log_info "Installing global npm packages..."

        local packages=()

        # Check and install yarn if not present
        if ! check_command yarn; then
            packages+=("yarn")
        fi

        # Install ESLint for linting
        if ! npm list -g eslint &>/dev/null; then
            packages+=("eslint")
        fi

        # Install useful tools
        if ! npm list -g npm-check-updates &>/dev/null; then
            packages+=("npm-check-updates")
        fi

        if [[ ${#packages[@]} -gt 0 ]]; then
            npm install -g "${packages[@]}"
        fi
    fi
}

# Install Python tools
# Usage: install_python_tools
install_python_tools() {
    log_info "Setting up Python tools..."

    if ! check_command python3; then
        log_warn "Python 3 not found. Installing..."
        local os
        os="$(detect_os)"

        case "${os}" in
            linux)
                install_linux "python3 python3-pip" "$(detect_package_manager)"
                ;;
            macos)
                install_macos "python"
                ;;
            windows)
                install_windows "python" "$(detect_package_manager)"
                ;;
        esac
    fi

    # Install Python packages via pip
    if check_command pip3 || check_command pip; then
        log_info "Installing Python packages..."

        local pip_cmd
        if check_command pip3; then
            pip_cmd="pip3"
        else
            pip_cmd="pip"
        fi

        local packages=()

        # Install linting tools
        if ! ${pip_cmd} show flake8 &>/dev/null; then
            packages+=("flake8")
        fi

        if ! ${pip_cmd} show pylint &>/dev/null; then
            packages+=("pylint")
        fi

        if ! ${pip_cmd} show black &>/dev/null; then
            packages+=("black")
        fi

        # Install testing tools
        if ! ${pip_cmd} show pytest &>/dev/null; then
            packages+=("pytest")
        fi

        if ! ${pip_cmd} show pytest-cov &>/dev/null; then
            packages+=("pytest-cov")
        fi

        # Install packaging tools
        if ! ${pip_cmd} show build &>/dev/null; then
            packages+=("build")
        fi

        if [[ ${#packages[@]} -gt 0 ]]; then
            ${pip_cmd} install --user "${packages[@]}"
        fi
    fi
}

# Install Go tools
# Usage: install_go_tools
install_go_tools() {
    log_info "Setting up Go tools..."

    if ! check_command go; then
        log_warn "Go not found. Installing..."
        local os
        os="$(detect_os)"

        case "${os}" in
            linux)
                install_linux "golang-go" "$(detect_package_manager)"
                ;;
            macos)
                install_macos "go"
                ;;
            windows)
                install_windows "golang" "$(detect_package_manager)"
                ;;
        esac
    fi

    # Install golangci-lint
    if ! check_command golangci-lint; then
        log_info "Installing golangci-lint..."
        if [[ "$(detect_os)" == "macos" ]]; then
            brew install golangci-lint
        else
            curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "${INSTALL_DIR}"
        fi
    fi
}

# Install Docker tools
# Usage: install_docker_tools
install_docker_tools() {
    log_info "Setting up Docker tools..."

    if ! check_command docker; then
        log_warn "Docker not found. Please install from: https://docs.docker.com/get-docker/"
        log_info "Docker installation requires manual setup"
        return 0
    fi

    log_success "Docker is installed"
}

# Install Git tools
# Usage: install_git_tools
install_git_tools() {
    log_info "Setting up Git tools..."

    if ! check_command git; then
        log_warn "Git not found. Installing..."
        local os
        os="$(detect_os)"

        case "${os}" in
            linux)
                install_linux "git" "$(detect_package_manager)"
                ;;
            macos)
                install_macos "git"
                ;;
            windows)
                install_windows "git" "$(detect_package_manager)"
                ;;
        esac
    fi

    # Install GitHub CLI if not present
    if ! check_command gh; then
        log_info "Installing GitHub CLI..."
        local os
        os="$(detect_os)"

        case "${os}" in
            linux)
                if [[ "$(detect_package_manager)" == "apt" ]]; then
                    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                    sudo apt update
                    sudo apt install -y gh
                else
                    log_warn "Please install gh manually from: https://cli.github.com"
                fi
                ;;
            macos)
                install_macos "gh"
                ;;
            windows)
                install_windows "gh" "$(detect_package_manager)"
                ;;
        esac
    fi
}

# Install general tools
# Usage: install_general_tools
install_general_tools() {
    log_info "Installing general tools..."

    local os
    os="$(detect_os)"
    local pkg_manager
    pkg_manager="$(detect_package_manager)"

    # jq
    if ! check_command jq; then
        case "${os}" in
            linux)
                install_linux "jq" "${pkg_manager}"
                ;;
            macos)
                install_macos "jq"
                ;;
            windows)
                install_windows "jq" "${pkg_manager}"
                ;;
        esac
    fi

    if ! check_command shellcheck; then
        case "${os}" in
            linux)
                install_linux "shellcheck" "${pkg_manager}"
                ;;
            macos)
                install_macos "shellcheck"
                ;;
            windows)
                install_windows "shellcheck" "${pkg_manager}"
                ;;
        esac
    fi
}

# =============================================================================
# Main Installation Function
# =============================================================================

# Install all or selected dependencies
# Usage: main_install [tools...]
main_install() {
    local tools=("$@")

    log_section "Installing Dependencies"

    # Detect platform and package manager
    local os
    os="$(detect_os)"
    local pkg_manager
    pkg_manager="$(detect_package_manager)"

    log_info "OS: ${os}"
    log_info "Package manager: ${pkg_manager}"

    if [[ "${pkg_manager}" == "unknown" ]]; then
        log_error "Could not detect package manager"
        log_error "Please install dependencies manually"
        return "${EXIT_ERROR_MISSING_DEPS}"
    fi

    # Install based on tool categories
    if [[ ${#tools[@]} -eq 0 ]] || [[ "${tools[0]}" == "all" ]]; then
        # Install all categories
        install_general_tools
        install_git_tools
        install_nodejs_tools
        install_python_tools
        install_go_tools
        install_docker_tools
    else
        # Install specific tools
        for tool in "${tools[@]}"; do
            case "${tool}" in
                node|nodejs|npm|yarn)
                    install_nodejs_tools
                    ;;
                python|pip|pytest)
                    install_python_tools
                    ;;
                go|golangci-lint)
                    install_go_tools
                    ;;
                docker)
                    install_docker_tools
                    ;;
                git|gh)
                    install_git_tools
                    ;;
                jq|shellcheck)
                    install_general_tools
                    ;;
                *)
                    log_warn "Unknown tool: ${tool}"
                    ;;
            esac
        done
    fi

    log_section "Installation Complete"
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 [options]

Install CI/CD dependencies for your platform.

Options:
  --check           Check if dependencies are installed (don't install)
  --tools LIST      Comma-separated list of tools to install
  --platform PLAT   Force platform (linux, macos, windows)
  --help, -h        Show this help message

Supported Tools:
  - General: jq, shellcheck, curl, wget
  - Git: git, gh (GitHub CLI)
  - Node.js: node, npm, yarn, pnpm
  - Python: python3, pip, pytest, flake8, pylint, black
  - Go: go, golangci-lint
  - Docker: docker, docker-compose

Environment Variables:
  SKIP_PROMPT       Skip confirmation prompts
  INSTALL_DIR       Custom installation directory (default: /usr/local/bin)

Examples:
  # Check what's installed
  $0 --check

  # Install all dependencies
  $0

  # Install specific tools
  $0 --tools node,go,docker

  # Install without prompts
  SKIP_PROMPT=true $0

EOF
}

# =============================================================================
# Main Script Entry Point
# =============================================================================

main() {
    local tools=()
    local show_help=false
    local force_platform=""

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help=true
                shift
                ;;
            --check)
                export CHECK_ONLY="true"
                shift
                ;;
            --tools)
                IFS=',' read -ra tools <<< "$2"
                shift 2
                ;;
            --platform)
                force_platform="$2"
                shift 2
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

    # Check only mode
    if [[ "${CHECK_ONLY}" == "true" ]]; then
        check_all_dependencies
        exit $?
    fi

    # Confirm installation
    if [[ "${SKIP_PROMPT}" != "true" ]]; then
        echo ""
        echo "This script will install CI/CD dependencies on your system."
        echo "Detected platform: $(detect_os)"
        echo ""
        read -p "Continue? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            exit "${EXIT_SUCCESS}"
        fi
    fi

    # Run installation
    if [[ ${#tools[@]} -eq 0 ]]; then
        tools=("all")
    fi

    main_install "${tools[@]}"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
