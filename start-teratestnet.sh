#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="${SCRIPT_DIR}/base/settings_local.conf"
BACKUP_FILE="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse command line arguments
USE_NGROK=true
for arg in "$@"; do
    case $arg in
        --no-ngrok)
            USE_NGROK=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--no-ngrok]"
            echo ""
            echo "Options:"
            echo "  --no-ngrok    Skip ngrok setup (for users with existing domain/proxy)"
            echo "  --help, -h    Show this help message"
            exit 0
            ;;
    esac
done

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_prerequisites() {
    echo_info "Checking prerequisites..."
    
    if [ "$USE_NGROK" = true ]; then
        if ! command -v ngrok &> /dev/null; then
            echo_error "ngrok is not installed. Please install ngrok and configure it with an auth token."
            echo "Visit https://ngrok.com/download for installation instructions."
            echo "Or use --no-ngrok if you have your own domain/proxy setup."
            exit 1
        fi
    fi
    
    if ! command -v docker &> /dev/null; then
        echo_error "Docker is not installed. Please install Docker."
        exit 1
    fi
    
    if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo_error "Docker Compose is not installed. Please install Docker Compose."
        exit 1
    fi
    
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo_error "Settings file not found at: $SETTINGS_FILE"
        exit 1
    fi
    
    echo_info "All prerequisites met."
}

process_ngrok_url() {
    local input=$1
    local url=""
    local domain=""
    
    # Remove trailing slash if present
    input="${input%/}"
    
    # Check if URL has protocol
    if [[ "$input" =~ ^https?:// ]]; then
        url="$input"
        # Extract domain from URL (remove protocol)
        domain="${url#*://}"
    else
        # No protocol, treat as domain
        domain="$input"
        url="https://$input"
    fi
    
    # Remove any path from domain (everything after first /)
    domain="${domain%%/*}"
    
    # Export both formats
    NGROK_URL="$url"
    NGROK_DOMAIN="$domain"
    
    echo_info "Processed ngrok URL:"
    echo "  - Full URL: $NGROK_URL"
    echo "  - Domain only: $NGROK_DOMAIN"
}

prompt_for_inputs() {
    echo
    echo_info "=== Teratestnet Configuration ==="
    echo
    
    if [ "$USE_NGROK" = true ]; then
        read -p "Enter your ngrok domain (e.g., example.ngrok-free.app): " URL_INPUT
    else
        read -p "Enter your domain/URL (e.g., teranode.example.com or https://teranode.example.com): " URL_INPUT
    fi
    
    if [ -z "$URL_INPUT" ]; then
        echo_error "Domain/URL cannot be empty"
        exit 1
    fi
    
    process_ngrok_url "$URL_INPUT"
    
    read -p "Enter RPC username: " RPC_USER
    if [ -z "$RPC_USER" ]; then
        echo_error "RPC username cannot be empty"
        exit 1
    fi
    
    read -s -p "Enter RPC password: " RPC_PASS
    echo
    if [ -z "$RPC_PASS" ]; then
        echo_error "RPC password cannot be empty"
        exit 1
    fi
    
    read -s -p "Confirm RPC password: " RPC_PASS_CONFIRM
    echo
    if [ "$RPC_PASS" != "$RPC_PASS_CONFIRM" ]; then
        echo_error "Passwords do not match"
        exit 1
    fi
    
    read -p "Enter Human Readable Client Name (for web interface viewing only) (optional, press Enter to skip): " CLIENT_NAME
    if [ -n "$CLIENT_NAME" ]; then
        if [ ${#CLIENT_NAME} -gt 100 ]; then
            echo_warning "Client Name is quite long (${#CLIENT_NAME} characters). Consider using a shorter identifier."
        fi
    fi

    read -p "Enter Miner Coinbase String (optional, press Enter to skip): " MINER_ID
    if [ -n "$MINER_ID" ]; then
        if [ ${#MINER_ID} -gt 100 ]; then
            echo_warning "Miner ID is quite long (${#MINER_ID} characters). Consider using a shorter identifier."
        fi
    fi
    
    echo
    echo_info "Configuration summary:"
    if [ "$USE_NGROK" = true ]; then
        echo "  - Ngrok Domain: $NGROK_DOMAIN"
    else
        echo "  - Domain: $NGROK_DOMAIN"
    fi
    echo "  - Full URL: $NGROK_URL"
    echo "  - RPC Username: $RPC_USER"
    echo "  - RPC Password: [hidden]"
    if [ -n "$MINER_ID" ]; then
        echo "  - Miner Coinbase: $MINER_ID"
    fi
    if [ -n "$CLIENT_NAME" ]; then
        echo "  - Client Name: $CLIENT_NAME"
    fi
    echo
    
    read -p "Is this correct? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo_info "Configuration cancelled."
        exit 0
    fi
}

backup_settings() {
    echo_info "Creating backup of settings.conf..."
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo_info "Backup created at: $BACKUP_FILE"
}

portable_sed_inplace() {
    local pattern="$1"
    local file="$2"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS requires backup extension for in-place editing
        sed -i '' "$pattern" "$file"
    else
        # Linux doesn't require backup extension
        sed -i "$pattern" "$file"
    fi
}

update_settings() {
    echo_info "Updating settings.conf..."
    
    local temp_file="${SETTINGS_FILE}.tmp"
    cp "$SETTINGS_FILE" "$temp_file"
    
    if grep -q "^asset_httpPublicAddress" "$temp_file"; then
        portable_sed_inplace "s|^asset_httpPublicAddress.*|asset_httpPublicAddress = ${NGROK_URL}/api/v1|" "$temp_file"
        echo_info "Updated asset_httpPublicAddress"
    else
        echo "asset_httpPublicAddress = ${NGROK_URL}/api/v1" >> "$temp_file"
        echo_info "Added asset_httpPublicAddress"
    fi
    
    if grep -q "^rpc_user" "$temp_file"; then
        portable_sed_inplace "s|^rpc_user.*|rpc_user = ${RPC_USER}|" "$temp_file"
        echo_info "Updated rpc_user"
    else
        echo "rpc_user = ${RPC_USER}" >> "$temp_file"
        echo_info "Added rpc_user"
    fi
    
    if grep -q "^rpc_pass" "$temp_file"; then
        portable_sed_inplace "s|^rpc_pass.*|rpc_pass = ${RPC_PASS}|" "$temp_file"
        echo_info "Updated rpc_pass"
    else
        echo "rpc_pass = ${RPC_PASS}" >> "$temp_file"
        echo_info "Added rpc_pass"
    fi
    
    if [ -n "$MINER_ID" ]; then
        if grep -q "^coinbase_arbitrary_text" "$temp_file"; then
            portable_sed_inplace "s|^coinbase_arbitrary_text.*|coinbase_arbitrary_text = ${MINER_ID}|" "$temp_file"
            echo_info "Updated coinbase_arbitrary_text (Miner ID)"
        else
            echo "coinbase_arbitrary_text = ${MINER_ID}" >> "$temp_file"
            echo_info "Added coinbase_arbitrary_text (Miner ID)"
        fi
    fi

    if [ -n "$CLIENT_NAME" ]; then
        if grep -q "^clientName" "$temp_file"; then
            portable_sed_inplace "s|^clientName.*|clientName = ${CLIENT_NAME}|" "$temp_file"
            echo_info "Updated clientName (Client Name)"
        else
            echo "clientName = ${CLIENT_NAME}" >> "$temp_file"
            echo_info "Added client name (Client Name)"
        fi
    fi

    
    mv "$temp_file" "$SETTINGS_FILE"
    echo_info "Settings updated successfully."
}

start_docker_compose() {
    echo_info "Starting Teratestnet with Docker Compose..."
    
    cd "$SCRIPT_DIR"
    
    if command -v docker compose &> /dev/null; then
        docker compose up -d
    else
        docker-compose up -d
    fi
    
    if [ $? -eq 0 ]; then
        echo_info "Docker Compose started successfully."
    else
        echo_error "Failed to start Docker Compose."
        exit 1
    fi
}

start_ngrok() {
    if [ "$USE_NGROK" = false ]; then
        echo_info "Skipping ngrok startup (--no-ngrok flag set)"
        return
    fi
    
    echo_info "Checking for existing ngrok process..."
    
    # Check if ngrok is already running
    if pgrep -x "ngrok" > /dev/null; then
        echo_info "Found existing ngrok process"
        
        # Check if the ngrok API is accessible and get tunnel info
        if curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -q "${NGROK_DOMAIN}"; then
            echo_info "ngrok is already running with domain: ${NGROK_DOMAIN}"
            echo_info "Using existing ngrok tunnel"
            echo_info "You can check ngrok status at: http://localhost:4040"
            echo_info "Public URL: ${NGROK_URL}"
            return
        else
            echo_warning "ngrok is running but not with the specified domain: ${NGROK_DOMAIN}"
            echo_error "Please stop the existing ngrok process and try again"
            echo_error "To stop ngrok: killall ngrok"
            exit 1
        fi
    fi
    
    echo_info "Starting new ngrok process with domain: $NGROK_DOMAIN"
    
    # Start ngrok with the user-supplied URL
    echo_info "Running: ngrok http --url=${NGROK_DOMAIN} 8090"
    ngrok http --url="${NGROK_DOMAIN}" 8090 &
    
    local ngrok_pid=$!
    
    sleep 3
    
    if ps -p $ngrok_pid > /dev/null 2>&1; then
        echo_info "ngrok started successfully (PID: $ngrok_pid)"
        echo_info "You can check ngrok status at: http://localhost:4040"
        echo_info "Public URL: ${NGROK_URL}"
    else
        echo_error "Failed to start ngrok. Please check your ngrok configuration."
        echo_error "Make sure you have a paid ngrok account with custom domain support if using --url"
        exit 1
    fi
}

set_fsm_state_running() {
    echo_info "Setting FSM state to RUNNING..."
    
    # Wait for blockchain container to be ready with retry loop
    local max_attempts=10
    local attempt=1
    local wait_time=6  # 6 seconds between attempts = 60 seconds total
    
    echo_info "Waiting for blockchain service to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        echo_info "Checking blockchain container status (attempt $attempt/$max_attempts)..."
        
        # Check if blockchain container is running
        if docker ps | grep "blockchain"; then
            # Try to execute a simple command to verify the container is responsive
            if docker exec blockchain teranode-cli getfsmstate &>/dev/null; then
                echo_info "Blockchain container is ready"
                break
            else
                echo_info "Container is running but not yet responsive..."
            fi
        else
            echo_info "Blockchain container not yet running..."
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            echo_error "Blockchain container failed to start after $max_attempts attempts (60 seconds)"
            echo_error "Cannot set FSM state to RUNNING"
            exit 1
        fi
        
        echo_info "Waiting ${wait_time} seconds before retry..."
        sleep $wait_time
        attempt=$((attempt + 1))
    done
    
    # Execute the FSM state transition command
    echo_info "Executing: docker exec -it blockchain teranode-cli setfsmstate --fsmstate RUNNING"
    if docker exec -it blockchain teranode-cli setfsmstate --fsmstate RUNNING; then
        echo_info "Successfully transitioned FSM state to RUNNING"
        echo_info "Teranode is now operational and ready to process transactions"
    else
        echo_error "Failed to set FSM state to RUNNING"
        echo_warning "You may need to manually run: docker exec -it blockchain teranode-cli setfsmstate --fsmstate RUNNING"
        echo_warning "Continuing anyway..."
    fi
}

show_completion_message() {
    echo
    echo_info "========================================="
    echo_info "Teratestnet started successfully!"
    echo_info "========================================="
    echo
    echo "Node Status:"
    echo "  - FSM State: RUNNING (operational)"
    echo "  - Docker Compose: Running in background"
    if [ "$USE_NGROK" = true ]; then
        echo "  - ngrok: Running (check http://localhost:4040)"
    fi
    echo
    echo "Endpoints:"
    echo "  - RPC endpoint: ${NGROK_URL}:9292"
    echo "  - Asset API: ${NGROK_URL}/api/v1"
    echo "  - P2P advertise: ${NGROK_DOMAIN}"
    echo
    echo "Credentials:"
    echo "  - RPC Username: $RPC_USER"
    echo "  - RPC Password: [saved in settings.conf]"
    if [ -n "$MINER_ID" ]; then
        echo "  - Miner ID: $MINER_ID"
    fi
    echo
    echo "To stop services:"
    echo "  - Docker: docker compose down"
    if [ "$USE_NGROK" = true ]; then
        echo "  - ngrok: killall ngrok"
    fi
    echo
    echo "Settings backup: $BACKUP_FILE"
    echo
    echo_info "Your Teranode is now ready to process transactions!"
}

main() {
    echo
    echo "======================================"
    echo "   Teratestnet Docker Helper Script"
    if [ "$USE_NGROK" = false ]; then
        echo "      (Running without ngrok)"
    fi
    echo "======================================"
    echo
    
    check_prerequisites
    prompt_for_inputs
    backup_settings
    update_settings
    start_docker_compose
    start_ngrok
    set_fsm_state_running
    show_completion_message
}

trap 'echo_error "Script interrupted. Exiting..."; exit 1' INT TERM

main "$@"
