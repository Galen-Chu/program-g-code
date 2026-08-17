#!/usr/bin/env bash
################################################################################
# CI/CD Toolkit - Notification Utilities
# =============================================================================
# Send notifications to various platforms (Slack, email, webhooks).
#
# Usage:
#   ./scripts/utils/notifiers.sh <platform> "message" [options]
#
# Platforms:
#   slack, email, webhook, teams, discord
#
# Environment Variables:
#   SLACK_WEBHOOK    Slack webhook URL
#   SLACK_CHANNEL    Slack channel (overrides webhook default)
#   SMTP_SERVER      SMTP server for email
#   SMTP_USERNAME    SMTP username
#   SMTP_PASSWORD    SMTP password
#   EMAIL_RECIPIENTS Comma-separated email recipients
#   WEBHOOK_URL      Generic webhook URL
################################################################################

set -euo pipefail

# Get script directory
_NOTIFIERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="_NOTIFIERS_DIR"
fi

# Source dependencies
source "${_NOTIFIERS_DIR}/common.sh"
source "${_NOTIFIERS_DIR}/logger.sh"

# =============================================================================
# Notification Configuration
# =============================================================================
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
SLACK_CHANNEL="${SLACK_CHANNEL:-}"
SLACK_USERNAME="${SLACK_USERNAME:-CI/CD}"
SLACK_ICON="${SLACK_ICON:-:robot_face:}"

SMTP_SERVER="${SMTP_SERVER:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USERNAME="${SMTP_USERNAME:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
EMAIL_SENDER="${EMAIL_SENDER:-noreply@example.com}"
EMAIL_RECIPIENTS="${EMAIL_RECIPIENTS:-}"

WEBHOOK_URL="${WEBHOOK_URL:-}"
WEBHOOK_METHOD="${WEBHOOK_METHOD:-POST}"
WEBHOOK_CONTENT_TYPE="${WEBHOOK_CONTENT_TYPE:-application/json}"

# Notification colors
COLOR_SUCCESS="good"
COLOR_WARNING="warning"
COLOR_ERROR="danger"
COLOR_INFO="#36a64f"

# =============================================================================
# Slack Notifications
# =============================================================================

# Send Slack notification
# Usage: notify_slack "message" [color] [channel]
notify_slack() {
    local message="$1"
    local color="${2:-${COLOR_INFO}}"
    local channel="${3:-${SLACK_CHANNEL}}"

    if [[ -z "${SLACK_WEBHOOK}" ]]; then
        log_warn "SLACK_WEBHOOK not configured. Skipping Slack notification."
        return 0
    fi

    log_debug "Sending Slack notification..."

    # Build JSON payload
    local payload='{
        "username": "'"${SLACK_USERNAME}"'",
        "icon_emoji": "'"${SLACK_ICON}"'",
        "text": "'"${message}"'"
    }'

    # Add channel if specified
    if [[ -n "${channel}" ]]; then
        payload=$(echo "${payload}" | jq ".channel = \"${channel}\"")
    fi

    # Add attachment with color
    payload=$(echo "${payload}" | jq '.attachments = [{"color": "'"${color}"'", "text": "'"${message}"'"}]')

    # Send webhook
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would send Slack notification: ${message}"
        return 0
    fi

    local response
    response=$(curl -s -X POST "${SLACK_WEBHOOK}" \
        -H 'Content-Type: application/json' \
        -d "${payload}" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_success "Slack notification sent"
        return 0
    else
        log_error "Failed to send Slack notification"
        log_error "Response: ${response}"
        return 1
    fi
}

# Send Slack notification with rich formatting
# Usage: notify_slack_rich "title" "message" "fields_json" [color]
notify_slack_rich() {
    local title="$1"
    local message="$2"
    local fields="$3"
    local color="${4:-${COLOR_INFO}}"

    if [[ -z "${SLACK_WEBHOOK}" ]]; then
        log_warn "SLACK_WEBHOOK not configured. Skipping Slack notification."
        return 0
    fi

    log_debug "Sending rich Slack notification..."

    # Build JSON payload
    local payload='{
        "username": "'"${SLACK_USERNAME}"'",
        "icon_emoji": "'"${SLACK_ICON}"'",
        "attachments": [{
            "color": "'"${color}"'",
            "title": "'"${title}"'",
            "text": "'"${message}"'",
            "fields": '"${fields}"',
            "footer": "CI/CD Toolkit",
            "ts": '"$(date +%s)"'
        }]
    }'

    # Add channel if specified
    if [[ -n "${SLACK_CHANNEL}" ]]; then
        payload=$(echo "${payload}" | jq ".channel = \"${SLACK_CHANNEL}\"")
    fi

    # Send webhook
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would send rich Slack notification"
        return 0
    fi

    local response
    response=$(curl -s -X POST "${SLACK_WEBHOOK}" \
        -H 'Content-Type: application/json' \
        -d "${payload}" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_success "Rich Slack notification sent"
        return 0
    else
        log_error "Failed to send Slack notification"
        return 1
    fi
}

# =============================================================================
# Email Notifications
# =============================================================================

# Send email notification
# Usage: notify_email "subject" "body" [recipients]
notify_email() {
    local subject="$1"
    local body="$2"
    local recipients="${3:-${EMAIL_RECIPIENTS}}"

    if [[ -z "${recipients}" ]]; then
        log_warn "No email recipients configured. Skipping email notification."
        return 0
    fi

    if [[ -z "${SMTP_SERVER}" ]]; then
        log_warn "SMTP_SERVER not configured. Skipping email notification."
        return 0
    fi

    log_debug "Sending email notification..."

    # Create email content
    local email_content="Subject: ${subject}
From: ${EMAIL_SENDER}
To: ${recipients}
Content-Type: text/plain; charset=UTF-8

${body}"

    # Send email using curl
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would send email to ${recipients}"
        return 0
    fi

    # Try sendmail first
    if check_command sendmail; then
        echo "${email_content}" | sendmail -t
        log_success "Email sent via sendmail"
        return 0
    fi

    # Try mail command
    if check_command mail; then
        echo "${body}" | mail -s "${subject}" "${recipients}"
        log_success "Email sent via mail"
        return 0
    fi

    # Try curl with SMTP
    if check_command curl; then
        log_warn "Direct SMTP not implemented. Please configure sendmail or mail."
        return 1
    fi

    log_error "No mail sending method available"
    return 1
}

# Send HTML email notification
# Usage: notify_email_html "subject" "html_body" [recipients]
notify_email_html() {
    local subject="$1"
    local html_body="$2"
    local recipients="${3:-${EMAIL_RECIPIENTS}}"

    if [[ -z "${recipients}" ]]; then
        log_warn "No email recipients configured"
        return 0
    fi

    log_debug "Sending HTML email notification..."

    local email_content="Subject: ${subject}
From: ${EMAIL_SENDER}
To: ${recipients}
Content-Type: text/html; charset=UTF-8

${html_body}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would send HTML email to ${recipients}"
        return 0
    fi

    if check_command sendmail; then
        echo "${email_content}" | sendmail -t
        log_success "HTML email sent"
        return 0
    fi

    log_error "sendmail not available"
    return 1
}

# =============================================================================
# Webhook Notifications
# =============================================================================

# Send generic webhook notification
# Usage: notify_webhook "data" [url] [method] [content_type]
notify_webhook() {
    local data="$1"
    local url="${2:-${WEBHOOK_URL}}"
    local method="${3:-${WEBHOOK_METHOD}}"
    local content_type="${4:-${WEBHOOK_CONTENT_TYPE}}"

    if [[ -z "${url}" ]]; then
        log_warn "Webhook URL not configured. Skipping webhook notification."
        return 0
    fi

    log_debug "Sending webhook notification to ${url}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would send webhook to ${url}"
        return 0
    fi

    local response
    response=$(curl -s -X "${method}" "${url}" \
        -H "Content-Type: ${content_type}" \
        -d "${data}" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_success "Webhook notification sent"
        return 0
    else
        log_error "Failed to send webhook notification"
        log_error "Response: ${response}"
        return 1
    fi
}

# =============================================================================
# Microsoft Teams Notifications
# =============================================================================

# Send Teams notification
# Usage: notify_teams "title" "message" [webhook_url]
notify_teams() {
    local title="$1"
    local message="$2"
    local webhook_url="${3:-${TEAMS_WEBHOOK:-}}"

    if [[ -z "${webhook_url}" ]]; then
        log_warn "TEAMS_WEBHOOK not configured. Skipping Teams notification."
        return 0
    fi

    log_debug "Sending Teams notification..."

    # Build adaptive card payload
    local payload='{
        "@type": "MessageCard",
        "@context": "https://schema.org/extensions",
        "summary": "'"${title}"'",
        "themeColor": "0078D7",
        "title": "'"${title}"'",
        "text": "'"${message}"'"
    }'

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would send Teams notification"
        return 0
    fi

    local response
    response=$(curl -s -X POST "${webhook_url}" \
        -H 'Content-Type: application/json' \
        -d "${payload}" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_success "Teams notification sent"
        return 0
    else
        log_error "Failed to send Teams notification"
        return 1
    fi
}

# =============================================================================
# Discord Notifications
# =============================================================================

# Send Discord notification
# Usage: notify_discord "message" [webhook_url]
notify_discord() {
    local message="$1"
    local webhook_url="${3:-${DISCORD_WEBHOOK:-}}"

    if [[ -z "${webhook_url}" ]]; then
        log_warn "DISCORD_WEBHOOK not configured. Skipping Discord notification."
        return 0
    fi

    log_debug "Sending Discord notification..."

    local payload='{
        "content": "'"${message}"'"
    }'

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would send Discord notification"
        return 0
    fi

    local response
    response=$(curl -s -X POST "${webhook_url}" \
        -H 'Content-Type: application/json' \
        -d "${payload}" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_success "Discord notification sent"
        return 0
    else
        log_error "Failed to send Discord notification"
        return 1
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================

# Format deployment notification message
# Usage: format_deployment_message environment status version
format_deployment_message() {
    local environment="$1"
    local status="$2"
    local version="${3:-unknown}"
    local project_name="${PROJECT_NAME:-$(basename "${PROJECT_ROOT}")}"

    local emoji=""
    case "${status}" in
        success|succeeded)
            emoji=":white_check_mark:"
            ;;
        failure|failed)
            emoji=":x:"
            ;;
        started|pending)
            emoji=":hourglass:"
            ;;
        *)
            emoji=":information_source:"
            ;;
    esac

    echo "${emoji} *${project_name}* deployment to *${environment}* ${status}"
    echo ""
    echo "Version: \`${version}\`"
    echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
}

# Format test notification message
# Usage: format_test_message status total passed failed
format_test_message() {
    local status="$1"
    local total="${2:-0}"
    local passed="${3:-0}"
    local failed="${4:-0}"

    local emoji=""
    case "${status}" in
        success|succeeded)
            emoji=":white_check_mark:"
            ;;
        failure|failed)
            emoji=":x:"
            ;;
        *)
            emoji=":information_source:"
            ;;
    esac

    echo "${emoji} Test results: ${status}"
    echo ""
    echo "Total: ${total} | Passed: ${passed} | Failed: ${failed}"
}

# Send notification based on event type
# Usage: notify_event event_type status [extra_data]
notify_event() {
    local event_type="$1"
    local status="$2"
    shift 2
    local extra_data=("$@")

    case "${event_type}" in
        deployment)
            local environment="${extra_data[0]:-unknown}"
            local version="${extra_data[1]:-unknown}"
            local message
            message="$(format_deployment_message "${environment}" "${status}" "${version}")"
            local color="${COLOR_INFO}"

            case "${status}" in
                success|succeeded) color="${COLOR_SUCCESS}" ;;
                failure|failed) color="${COLOR_ERROR}" ;;
                warning) color="${COLOR_WARNING}" ;;
            esac

            if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
                notify_slack "${message}" "${color}"
            fi
            ;;

        test)
            local total="${extra_data[0]:-0}"
            local passed="${extra_data[1]:-0}"
            local failed="${extra_data[2]:-0}"
            local message
            message="$(format_test_message "${status}" "${total}" "${passed}" "${failed}")"
            local color="${COLOR_INFO}"

            case "${status}" in
                success|succeeded) color="${COLOR_SUCCESS}" ;;
                failure|failed) color="${COLOR_ERROR}" ;;
            esac

            if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
                notify_slack "${message}" "${color}"
            fi
            ;;

        *)
            log_warn "Unknown event type: ${event_type}"
            ;;
    esac
}

# =============================================================================
# Main Script Entry Point
# =============================================================================

show_help() {
    cat << EOF
Usage: $0 <platform> "message" [options]

Send notifications to various platforms.

Platforms:
  slack       Send Slack notification
  email       Send email notification
  webhook     Send generic webhook
  teams       Send Microsoft Teams notification
  discord     Send Discord notification

Options:
  --help, -h  Show this help message

Environment Variables:
  SLACK_WEBHOOK    Slack webhook URL
  SLACK_CHANNEL    Slack channel (overrides webhook default)
  SMTP_SERVER      SMTP server for email
  SMTP_USERNAME    SMTP username
  SMTP_PASSWORD    SMTP password
  EMAIL_SENDER     Email sender address
  EMAIL_RECIPIENTS Comma-separated email recipients
  WEBHOOK_URL      Generic webhook URL
  TEAMS_WEBHOOK    Microsoft Teams webhook URL
  DISCORD_WEBHOOK  Discord webhook URL

Examples:
  # Send Slack notification
  $0 slack "Deployment successful"

  # Send email
  $0 email "Build failed" --to devops@example.com

  # Send webhook
  $0 webhook '{"status": "success"}'

EOF
}

main() {
    local platform=""
    local message=""
    local show_help=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit "${EXIT_ERROR_GENERAL}"
                ;;
            *)
                if [[ -z "${platform}" ]]; then
                    platform="$1"
                elif [[ -z "${message}" ]]; then
                    message="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ "${show_help}" == "true" ]]; then
        show_help
        exit "${EXIT_SUCCESS}"
    fi

    # Validate arguments
    if [[ -z "${platform}" ]] || [[ -z "${message}" ]]; then
        log_error "Platform and message are required"
        echo ""
        show_help
        exit "${EXIT_ERROR_GENERAL}"
    fi

    # Send notification based on platform
    case "${platform}" in
        slack)
            notify_slack "${message}"
            ;;
        email)
            notify_email "CI/CD Notification" "${message}"
            ;;
        webhook)
            notify_webhook "${message}"
            ;;
        teams)
            notify_teams "CI/CD Notification" "${message}"
            ;;
        discord)
            notify_discord "${message}"
            ;;
        *)
            log_error "Unknown platform: ${platform}"
            exit "${EXIT_ERROR_GENERAL}"
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Export functions for use in other scripts
export -f notify_slack
export -f notify_slack_rich
export -f notify_email
export -f notify_email_html
export -f notify_webhook
export -f notify_teams
export -f notify_discord
export -f format_deployment_message
export -f format_test_message
export -f notify_event
