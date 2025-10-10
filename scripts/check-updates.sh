#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STATE_FILE="$PROJECT_DIR/.update-state"
REPO_OWNER="bsv-blockchain"
REPO_NAME="teranode"
API_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/tags"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_update() {
    echo -e "${BLUE}[UPDATE]${NC} $1"
}

get_latest_tag() {
    local latest_tag=""

    # Try multiple methods for cross-platform compatibility
    if command -v curl >/dev/null 2>&1; then
        # Method 1: Use curl with basic text processing (most compatible)
        latest_tag=$(curl -s "$API_URL" 2>/dev/null | grep '"name":' | head -n1 | sed -e 's/.*"name": *"//' -e 's/".*//')

        # Method 2: Fallback using different parsing if first method fails
        if [ -z "$latest_tag" ]; then
            latest_tag=$(curl -s "$API_URL" 2>/dev/null | grep -o '"name": *"[^"]*"' | head -n1 | cut -d'"' -f4)
        fi

        # Method 3: Alternative API endpoint for releases (smaller payload)
        if [ -z "$latest_tag" ]; then
            latest_tag=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -e 's/.*"tag_name": *"//' -e 's/".*//')
        fi
    else
        echo_error "curl is not available. Cannot check for updates."
        return 1
    fi

    if [ -z "$latest_tag" ]; then
        echo_error "Failed to retrieve latest tag from GitHub API"
        return 1
    fi

    echo "$latest_tag"
}

get_current_tag() {
    if [ -f "$STATE_FILE" ]; then
        grep "^last_checked_tag=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2
    fi
}

save_current_tag() {
    local tag="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Create or update state file
    {
        echo "last_checked_tag=$tag"
        echo "last_check_time=$timestamp"
    } > "$STATE_FILE"
}

prompt_for_upgrade() {
    local current_tag="$1"
    local latest_tag="$2"

    echo
    echo_update "========================================="
    echo_update "NEW TERANODE VERSION AVAILABLE!"
    echo_update "========================================="
    echo
    echo_update "Current version: $current_tag"
    echo_update "Latest version:  $latest_tag"
    echo
    echo_update "A new version of Teranode is available for upgrade."
    echo_update "This will:"
    echo_update "  1. Stop all running containers (docker compose down)"
    echo_update "  2. Pull latest changes from git (git pull)"
    echo_update "  3. Start containers with new version (docker compose up -d)"
    echo
    echo_warning "Note: This will temporarily stop your Teranode services."
    echo

    read -p "Would you like to upgrade now? (y/n): " UPGRADE_CHOICE

    if [[ "$UPGRADE_CHOICE" =~ ^[Yy]$ ]]; then
        perform_upgrade "$latest_tag"
    else
        echo_info "Upgrade cancelled. You can run this script again later to upgrade."
        echo_info "Or run the upgrade manually with:"
        echo_info "  docker compose down && git pull && docker compose up -d"
        save_current_tag "$latest_tag"
    fi
}

perform_upgrade() {
    local new_tag="$1"

    echo_info "Starting upgrade process..."

    cd "$PROJECT_DIR"

    # Step 1: Stop containers
    echo_info "Stopping Teranode containers..."
    if command -v docker compose >/dev/null 2>&1; then
        docker compose down
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose down
    else
        echo_error "Neither 'docker compose' nor 'docker-compose' found"
        return 1
    fi

    # Step 2: Pull latest changes
    echo_info "Pulling latest changes from git..."
    if ! git pull; then
        echo_error "Failed to pull latest changes. Manual intervention required."
        return 1
    fi

    # Step 3: Start containers
    echo_info "Starting Teranode containers with new version..."
    if command -v docker compose >/dev/null 2>&1; then
        docker compose up -d
    else
        docker-compose up -d
    fi

    if [ $? -eq 0 ]; then
        echo_info "Upgrade completed successfully!"
        echo_info "Teranode has been updated to version: $new_tag"
        save_current_tag "$new_tag"

        # Wait a moment for services to start
        echo_info "Waiting for services to start..."
        sleep 10

        echo_info "You can check service status with: docker compose ps"
        echo_info "View logs with: docker compose logs -f"
    else
        echo_error "Failed to start containers after upgrade"
        echo_error "Please check the logs and restart manually if needed"
        return 1
    fi
}

check_for_updates() {
    local silent_mode="$1"

    if [ "$silent_mode" != "silent" ]; then
        echo_info "Checking for Teranode updates..."
    fi

    # Get latest tag from GitHub
    local latest_tag
    latest_tag=$(get_latest_tag)

    if [ $? -ne 0 ] || [ -z "$latest_tag" ]; then
        if [ "$silent_mode" != "silent" ]; then
            echo_error "Failed to check for updates"
        fi
        return 1
    fi

    # Get current tag from state file
    local current_tag
    current_tag=$(get_current_tag)

    if [ "$silent_mode" != "silent" ]; then
        echo_info "Latest version: $latest_tag"
        if [ -n "$current_tag" ]; then
            echo_info "Last checked version: $current_tag"
        else
            echo_info "First time checking for updates"
        fi
    fi

    # Compare versions
    if [ -z "$current_tag" ]; then
        # First run - just save the current version
        save_current_tag "$latest_tag"
        if [ "$silent_mode" != "silent" ]; then
            echo_info "Saved current version as baseline: $latest_tag"
        fi
    elif [ "$current_tag" != "$latest_tag" ]; then
        # New version available
        if [ "$silent_mode" = "silent" ]; then
            echo_update "New Teranode version available: $latest_tag (current: $current_tag)"
            echo_update "Run 'scripts/check-updates.sh' to upgrade interactively"
            save_current_tag "$latest_tag"
        else
            prompt_for_upgrade "$current_tag" "$latest_tag"
        fi
    else
        # Up to date
        if [ "$silent_mode" != "silent" ]; then
            echo_info "Teranode is up to date (version: $current_tag)"
        fi
        # Update timestamp
        save_current_tag "$current_tag"
    fi
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --silent    Check for updates without interactive prompts"
    echo "  --force     Force check even if recently checked"
    echo "  --help, -h  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0           # Interactive update check"
    echo "  $0 --silent  # Silent check (for background monitoring)"
}

main() {
    local silent_mode=""
    local force_check=""

    # Parse command line arguments
    for arg in "$@"; do
        case $arg in
            --silent)
                silent_mode="silent"
                shift
                ;;
            --force)
                force_check="true"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo_error "Unknown option: $arg"
                show_usage
                exit 1
                ;;
        esac
    done

    # Check prerequisites
    if ! command -v curl >/dev/null 2>&1; then
        echo_error "curl is required but not installed"
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo_error "git is required but not installed"
        exit 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo_error "docker is required but not installed"
        exit 1
    fi

    # Perform update check
    check_for_updates "$silent_mode"
}

# Handle script interruption
trap 'echo_error "Update check interrupted"; exit 1' INT TERM

main "$@"