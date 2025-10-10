#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$PROJECT_DIR/.update-monitor.pid"
LOG_FILE="$PROJECT_DIR/.update-monitor.log"
CHECK_INTERVAL=3600  # 1 hour in seconds

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

is_monitor_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0  # Process is running
        else
            # PID file exists but process is not running
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1  # PID file doesn't exist
}

start_monitor() {
    if is_monitor_running; then
        local pid=$(cat "$PID_FILE")
        echo_warning "Update monitor is already running (PID: $pid)"
        echo_info "Use '$0 stop' to stop it first"
        return 1
    fi

    echo_info "Starting Teranode update monitor..."
    echo_info "Check interval: $CHECK_INTERVAL seconds ($(($CHECK_INTERVAL / 3600)) hour(s))"
    echo_info "Log file: $LOG_FILE"

    # Start the monitoring loop in background
    (
        log_message "Update monitor started (PID: $$)"

        while true; do
            log_message "Checking for updates..."

            # Run the update checker in silent mode
            if "$SCRIPT_DIR/check-updates.sh" --silent >> "$LOG_FILE" 2>&1; then
                log_message "Update check completed successfully"
            else
                log_message "Update check failed or encountered an error"
            fi

            log_message "Sleeping for $CHECK_INTERVAL seconds..."
            sleep "$CHECK_INTERVAL"
        done
    ) &

    local monitor_pid=$!
    echo "$monitor_pid" > "$PID_FILE"

    echo_info "Update monitor started with PID: $monitor_pid"
    echo_info "Monitor will check for updates every $(($CHECK_INTERVAL / 3600)) hour(s)"
    echo_info "View logs with: tail -f $LOG_FILE"
    echo_info "Stop monitor with: $0 stop"
}

stop_monitor() {
    if ! is_monitor_running; then
        echo_warning "Update monitor is not running"
        return 1
    fi

    local pid=$(cat "$PID_FILE")
    echo_info "Stopping update monitor (PID: $pid)..."

    if kill "$pid" 2>/dev/null; then
        rm -f "$PID_FILE"
        log_message "Update monitor stopped"
        echo_info "Update monitor stopped successfully"
    else
        echo_error "Failed to stop update monitor process"
        # Clean up stale PID file
        rm -f "$PID_FILE"
        return 1
    fi
}

status_monitor() {
    if is_monitor_running; then
        local pid=$(cat "$PID_FILE")
        echo_info "Update monitor is running (PID: $pid)"
        echo_info "Check interval: $CHECK_INTERVAL seconds ($(($CHECK_INTERVAL / 3600)) hour(s))"
        echo_info "Log file: $LOG_FILE"

        if [ -f "$LOG_FILE" ]; then
            echo_info "Last few log entries:"
            tail -n 5 "$LOG_FILE" | while read line; do
                echo "  $line"
            done
        fi
    else
        echo_info "Update monitor is not running"
    fi
}

view_logs() {
    if [ -f "$LOG_FILE" ]; then
        if [ "$1" = "--follow" ] || [ "$1" = "-f" ]; then
            echo_info "Following update monitor logs (Ctrl+C to exit):"
            tail -f "$LOG_FILE"
        else
            echo_info "Recent update monitor logs:"
            tail -n 20 "$LOG_FILE"
        fi
    else
        echo_warning "No log file found at: $LOG_FILE"
    fi
}

restart_monitor() {
    echo_info "Restarting update monitor..."
    stop_monitor
    sleep 2
    start_monitor
}

configure_monitor() {
    echo_info "Current configuration:"
    echo "  Check interval: $CHECK_INTERVAL seconds ($(($CHECK_INTERVAL / 3600)) hour(s))"
    echo "  Log file: $LOG_FILE"
    echo "  PID file: $PID_FILE"
    echo

    read -p "Enter new check interval in hours (current: $(($CHECK_INTERVAL / 3600))): " new_hours

    if [[ "$new_hours" =~ ^[0-9]+$ ]] && [ "$new_hours" -gt 0 ]; then
        local new_interval=$((new_hours * 3600))

        # Update the script with new interval
        sed -i.bak "s/^CHECK_INTERVAL=[0-9]*/CHECK_INTERVAL=$new_interval/" "$0"

        echo_info "Check interval updated to $new_hours hour(s)"
        echo_info "Changes will take effect on next monitor restart"

        if is_monitor_running; then
            read -p "Restart monitor now to apply changes? (y/n): " restart_choice
            if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
                restart_monitor
            fi
        fi
    else
        echo_error "Invalid input. Please enter a positive number"
    fi
}

show_usage() {
    echo "Usage: $0 {start|stop|restart|status|logs|configure}"
    echo ""
    echo "Commands:"
    echo "  start      Start the update monitor daemon"
    echo "  stop       Stop the update monitor daemon"
    echo "  restart    Restart the update monitor daemon"
    echo "  status     Show current monitor status"
    echo "  logs       Show recent log entries"
    echo "  logs -f    Follow log entries in real-time"
    echo "  configure  Configure monitor settings"
    echo ""
    echo "The monitor checks for Teranode updates every $(($CHECK_INTERVAL / 3600)) hour(s)"
    echo "and logs all activity to: $LOG_FILE"
}

main() {
    case "${1:-}" in
        start)
            start_monitor
            ;;
        stop)
            stop_monitor
            ;;
        restart)
            restart_monitor
            ;;
        status)
            status_monitor
            ;;
        logs)
            view_logs "$2"
            ;;
        configure)
            configure_monitor
            ;;
        --help|-h|help)
            show_usage
            ;;
        "")
            echo_error "No command specified"
            show_usage
            exit 1
            ;;
        *)
            echo_error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Handle script interruption
trap 'echo_error "Monitor command interrupted"; exit 1' INT TERM

main "$@"