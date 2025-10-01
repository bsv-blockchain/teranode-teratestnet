#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="${SCRIPT_DIR}/base/settings_local.conf"
SETTINGS_TEMPLATE="${SCRIPT_DIR}/base/settings_local.conf.template"
USE_EXISTING_CONFIG=false

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

    if [ ! -f "$SETTINGS_TEMPLATE" ]; then
        echo_error "Settings template file not found at: $SETTINGS_TEMPLATE"
        exit 1
    fi

    echo_info "All prerequisites met."
}

load_existing_config() {
    # Extract listen_mode (prefer namespaced key, fallback to non-namespaced)
    if grep -q "^listen_mode" "$SETTINGS_FILE"; then
        LISTEN_MODE=$(grep "^listen_mode" "$SETTINGS_FILE" | head -n1 | cut -d'=' -f2 | xargs)
    else
        LISTEN_MODE="listen_only"
    fi

    # Extract asset_httpPublicAddress and derive ngrok URL/domain
    if grep -q "^asset_httpPublicAddress" "$SETTINGS_FILE"; then
        local asset_url=$(grep "^asset_httpPublicAddress" "$SETTINGS_FILE" | cut -d'=' -f2 | xargs)
        # Remove the /api/v1 suffix to get base URL
        NGROK_URL="${asset_url%/api/v1}"
        # Extract domain from URL
        NGROK_DOMAIN="${NGROK_URL#*://}"
        NGROK_DOMAIN="${NGROK_DOMAIN%%/*}"
    else
        NGROK_URL="http://localhost"
        NGROK_DOMAIN="localhost"
    fi

    # Only enable ngrok if domain matches ngrok patterns and mode is full
    if [ "$LISTEN_MODE" = "full" ]; then
        if [[ "$NGROK_DOMAIN" == *.ngrok-free.app || "$NGROK_DOMAIN" == *.ngrok.io ]]; then
            USE_NGROK=true
        else
            USE_NGROK=false
        fi
    fi

    echo_info "Loaded configuration from existing file:"
    echo "  - Mode: $LISTEN_MODE"
    if [ "$LISTEN_MODE" = "full" ]; then
        echo "  - Domain: $NGROK_DOMAIN"
        echo "  - Full URL: $NGROK_URL"
    fi
}

check_existing_config() {
    if [ -f "$SETTINGS_FILE" ]; then
        echo
        echo_info "========================================="
        echo_info "Existing Configuration Detected"
        echo_info "========================================="
        echo
        echo_info "Found existing settings_local.conf file."
        echo
        echo "Current configuration preview:"
        echo "----------------------------------------"

        # Show key settings from existing file
        if grep -q "^listen_mode" "$SETTINGS_FILE"; then
            local mode=$(grep "^listen_mode" "$SETTINGS_FILE" | head -n1 | cut -d'=' -f2 | xargs)
            echo "  Mode: $mode"
        fi
        if grep -q "^asset_httpPublicAddress" "$SETTINGS_FILE"; then
            local asset_url=$(grep "^asset_httpPublicAddress" "$SETTINGS_FILE" | cut -d'=' -f2 | xargs)
            echo "  Asset URL: $asset_url"
        fi
        if grep -q "^rpc_user" "$SETTINGS_FILE"; then
            local rpc_user=$(grep "^rpc_user" "$SETTINGS_FILE" | head -n1 | cut -d'=' -f2 | xargs)
            echo "  RPC User: $rpc_user"
        fi
        if grep -q "^clientName" "$SETTINGS_FILE"; then
            local client_name=$(grep "^clientName" "$SETTINGS_FILE" | head -n1 | cut -d'=' -f2 | xargs)
            echo "  Client Name: $client_name"
        fi
        echo "----------------------------------------"
        echo

        echo "What would you like to do?"
        echo "  1. Use existing configuration (skip setup, just start services)"
        echo "  2. Reconfigure (overwrite with new settings)"
        echo

        read -p "Select option (1 or 2): " CONFIG_CHOICE

        if [ "$CONFIG_CHOICE" = "1" ]; then
            USE_EXISTING_CONFIG=true
            load_existing_config
            echo_info "Using existing configuration. Skipping setup steps..."
            return
        elif [ "$CONFIG_CHOICE" = "2" ]; then
            USE_EXISTING_CONFIG=false
            echo_info "Will generate new configuration after prompting for values..."
            return
        else
            echo_error "Invalid selection. Please run the script again and select 1 or 2"
            exit 1
        fi
    else
        echo_info "No existing configuration found. Will generate new settings_local.conf"
        USE_EXISTING_CONFIG=false
    fi
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

    # Prompt for node mode selection
    echo_info "Node Operation Mode Selection"
    echo
    echo "Please select how you want to run your Teranode:"
    echo "  1. Full mode - Fully participate in the network (requires ngrok or public domain)"
    echo "  2. Listen-only mode - Only receive blocks, no mining or transaction relay"
    echo
    echo_info "Listen-only mode is ideal for monitoring the network without external access"
    echo

    read -p "Select mode (1 for Full, 2 for Listen-only): " MODE_CHOICE

    if [ "$MODE_CHOICE" = "2" ]; then
        LISTEN_MODE="listen_only"
        echo_info "Listen-only mode selected - ngrok configuration not required"
        USE_NGROK=false
        # Set a placeholder URL for listen-only mode
        NGROK_URL="http://localhost"
        NGROK_DOMAIN="localhost"
    elif [ "$MODE_CHOICE" = "1" ]; then
        LISTEN_MODE="full"
        echo_info "Full mode selected - external access configuration required"

        if [ "$USE_NGROK" = true ]; then
            read -p "Enter your ngrok domain (e.g., example.ngrok-free.app): " URL_INPUT
        else
            read -p "Enter your domain/URL (e.g., teranode.example.com or https://teranode.example.com): " URL_INPUT
        fi

        if [ -z "$URL_INPUT" ]; then
            echo_error "Domain/URL cannot be empty for full mode"
            exit 1
        fi

        process_ngrok_url "$URL_INPUT"
    else
        echo_error "Invalid selection. Please run the script again and select 1 or 2"
        exit 1
    fi

    echo
    echo_info "RPC Credentials Configuration"
    echo_info "You can either:"
    echo "  1. Set RPC credentials now (automatic)"
    echo "  2. Configure them manually in settings_local.conf later"
    echo
    echo_info "Note: RPC credentials are required for remote access to your node"
    echo

    read -p "Would you like to set RPC credentials now? (y/n): " SET_RPC_CREDS

    if [[ "$SET_RPC_CREDS" =~ ^[Yy]$ ]]; then
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
    else
        echo_info "Skipping RPC credentials setup"
        echo_info "You can add them manually to ${SETTINGS_FILE}:"
        echo "  rpc_user = your_username"
        echo "  rpc_pass = your_password"
        RPC_USER=""
        RPC_PASS=""
    fi

    read -p "Enter Human Readable Client Name (for web interface viewing only) (optional, press Enter to skip): " CLIENT_NAME
    if [ -n "$CLIENT_NAME" ]; then
        if [ ${#CLIENT_NAME} -gt 100 ]; then
            echo_warning "Client Name is quite long (${#CLIENT_NAME} characters). Consider using a shorter identifier."
        fi
    fi

    # Mining configuration (only for full mode)
    MINING_ENABLED="false"
    MINING_ADDRESS=""
    MINER_TAG=""

    if [ "$LISTEN_MODE" = "full" ]; then
        echo
        echo_info "Mining Configuration"
        echo_info "Note: Mining requires computational resources and will use CPU"
        echo
        read -p "Would you like to enable CPU mining? (y/n): " ENABLE_MINING

        if [[ "$ENABLE_MINING" =~ ^[Yy]$ ]]; then
            MINING_ENABLED="true"

            read -p "Enter Bitcoin address for mining rewards: " MINING_ADDRESS
            while [ -z "$MINING_ADDRESS" ]; do
                echo_error "Mining address cannot be empty when mining is enabled"
                read -p "Enter Bitcoin address for mining rewards: " MINING_ADDRESS
            done

            read -p "Enter Miner Tag/Signature (e.g., /YourMinerTag/) (optional, press Enter to skip): " MINER_TAG
            if [ -z "$MINER_TAG" ]; then
                MINER_TAG="/Teratestnet/"
                echo_info "Using default miner tag: $MINER_TAG"
            fi

            echo_info "Mining will be enabled with:"
            echo "  - Mining address: $MINING_ADDRESS"
            echo "  - Miner Tag: $MINER_TAG"
            echo "  - CPU threads: 2"
        else
            echo_info "Mining disabled"
        fi
    else
        echo_info "Mining is not available in listen-only mode"
    fi

    echo
    echo_info "Configuration summary:"
    echo "  - Mode: $([ "$LISTEN_MODE" = "listen_only" ] && echo "Listen-only" || echo "Full")"
    if [ "$LISTEN_MODE" = "full" ]; then
        if [ "$USE_NGROK" = true ]; then
            echo "  - Ngrok Domain: $NGROK_DOMAIN"
        else
            echo "  - Domain: $NGROK_DOMAIN"
        fi
        echo "  - Full URL: $NGROK_URL"
    fi
    if [ -n "$RPC_USER" ]; then
        echo "  - RPC Username: $RPC_USER"
        echo "  - RPC Password: [hidden]"
    else
        echo "  - RPC Credentials: To be configured manually"
    fi
    if [ "$MINING_ENABLED" = "true" ]; then
        echo "  - Mining: Enabled"
        echo "  - Mining Address: $MINING_ADDRESS"
        echo "  - Miner Tag: $MINER_TAG"
    else
        echo "  - Mining: Disabled"
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

generate_settings_from_template() {
    echo_info "Generating settings_local.conf from template..."

    cp "$SETTINGS_TEMPLATE" "$SETTINGS_FILE"

    # Remove all commented lines and empty lines, creating a clean base
    portable_sed_inplace '/^#/d; /^$/d' "$SETTINGS_FILE"
}

update_settings() {
    echo_info "Updating settings_local.conf..."

    # Configure listen_mode
    if grep -q "^listen_mode" "$SETTINGS_FILE"; then
        portable_sed_inplace "s|^listen_mode.*|listen_mode.docker.m = ${LISTEN_MODE}|" "$SETTINGS_FILE"
        echo_info "Updated listen_mode to: ${LISTEN_MODE}"
    else
        echo "listen_mode.docker.m = ${LISTEN_MODE}" >> "$SETTINGS_FILE"
        echo_info "Added listen_mode: ${LISTEN_MODE}"
    fi

    # Only update asset_httpPublicAddress for full mode
    if [ "$LISTEN_MODE" = "full" ]; then
        if grep -q "^asset_httpPublicAddress" "$SETTINGS_FILE"; then
            portable_sed_inplace "s|^asset_httpPublicAddress.*|asset_httpPublicAddress.docker.m = ${NGROK_URL}/api/v1|" "$SETTINGS_FILE"
            echo_info "Updated asset_httpPublicAddress"
        else
            echo "asset_httpPublicAddress.docker.m = ${NGROK_URL}/api/v1" >> "$SETTINGS_FILE"
            echo_info "Added asset_httpPublicAddress"
        fi
    fi

    # Only update RPC credentials if they were provided
    if [ -n "$RPC_USER" ]; then
        if grep -q "^rpc_user" "$SETTINGS_FILE"; then
            portable_sed_inplace "s|^rpc_user.*|rpc_user.docker.m = ${RPC_USER}|" "$SETTINGS_FILE"
            echo_info "Updated rpc_user"
        else
            echo "rpc_user.docker.m = ${RPC_USER}" >> "$SETTINGS_FILE"
            echo_info "Added rpc_user"
        fi

        if grep -q "^rpc_pass" "$SETTINGS_FILE"; then
            portable_sed_inplace "s|^rpc_pass.*|rpc_pass.docker.m = ${RPC_PASS}|" "$SETTINGS_FILE"
            echo_info "Updated rpc_pass"
        else
            echo "rpc_pass.docker.m = ${RPC_PASS}" >> "$SETTINGS_FILE"
            echo_info "Added rpc_pass"
        fi
    else
        echo_warning "RPC credentials not configured. Remember to add them manually to settings_local.conf"
    fi

    if [ -n "$MINER_TAG" ]; then
        if grep -q "^coinbase_arbitrary_text" "$SETTINGS_FILE"; then
            portable_sed_inplace "s|^coinbase_arbitrary_text.*|coinbase_arbitrary_text.docker.m = ${MINER_TAG}|" "$SETTINGS_FILE"
            echo_info "Updated coinbase_arbitrary_text (Miner Tag)"
        else
            echo "coinbase_arbitrary_text.docker.m = ${MINER_TAG}" >> "$SETTINGS_FILE"
            echo_info "Added coinbase_arbitrary_text (Miner Tag)"
        fi
    fi

    if [ -n "$CLIENT_NAME" ]; then
        if grep -q "^clientName" "$SETTINGS_FILE"; then
            portable_sed_inplace "s|^clientName.*|clientName.docker.m = ${CLIENT_NAME}|" "$SETTINGS_FILE"
            echo_info "Updated clientName"
        else
            echo "clientName.docker.m = ${CLIENT_NAME}" >> "$SETTINGS_FILE"
            echo_info "Added clientName"
        fi
    fi

    echo_info "Settings updated successfully."
}

start_docker_compose() {
    echo_info "Starting Teratestnet with Docker Compose..."

    cd "$SCRIPT_DIR"

    # Determine compose command
    local compose_cmd=""
    if command -v docker compose &> /dev/null; then
        compose_cmd="docker compose up -d"
    else
        compose_cmd="docker-compose up -d"
    fi

    echo_info "Running: $compose_cmd"
    eval $compose_cmd

    if [ $? -eq 0 ]; then
        echo_info "Docker Compose started successfully."
    else
        echo_error "Failed to start Docker Compose."
        exit 1
    fi
}

start_ngrok() {
    if [ "$USE_NGROK" = false ]; then
        if [ "$LISTEN_MODE" = "listen_only" ]; then
            echo_info "Skipping ngrok setup (listen-only mode)"
        else
            echo_info "Skipping ngrok setup (--no-ngrok flag set)"
        fi
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

    echo
    echo_warning "========================================="
    echo_warning "NGROK SETUP REQUIRED"
    echo_warning "========================================="
    echo
    echo_info "Please open a new terminal window and run the following command:"
    echo
    echo -e "${GREEN}    ngrok http --url=${NGROK_DOMAIN} 8000${NC}"
    echo
    echo_info "This will create a tunnel from ${NGROK_URL} to your local Teranode asset cache service."
    echo
    echo_info "After starting ngrok, you can verify it's running at: http://localhost:4040"
    echo
    read -p "Press Enter once ngrok is running in another terminal... "

    # Verify ngrok is now running
    echo_info "Verifying ngrok connection..."

    local max_attempts=5
    local attempt=1
    local wait_time=2

    while [ $attempt -le $max_attempts ]; do
        if pgrep -x "ngrok" > /dev/null; then
            # Check if the ngrok API is accessible and get tunnel info
            if curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -q "${NGROK_DOMAIN}"; then
                echo_info "ngrok verified successfully!"
                echo_info "Tunnel established: ${NGROK_URL} -> localhost:8000"
                echo_info "You can monitor ngrok at: http://localhost:4040"
                return
            else
                echo_warning "ngrok is running but tunnel not yet established..."
            fi
        else
            echo_warning "ngrok process not detected..."
        fi

        if [ $attempt -eq $max_attempts ]; then
            echo_error "Could not verify ngrok is running with domain: ${NGROK_DOMAIN}"
            echo_error "Please ensure you ran the command exactly as shown above"
            echo_error "To retry, stop this script and run it again"
            exit 1
        fi

        echo_info "Retrying verification (attempt $attempt/$max_attempts)..."
        sleep $wait_time
        attempt=$((attempt + 1))
    done
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
    echo "  - Mode: $([ "$LISTEN_MODE" = "listen_only" ] && echo "Listen-only" || echo "Full")"
    echo "  - FSM State: RUNNING (operational)"
    echo "  - Docker Compose: Running in background"
    if [ "$USE_NGROK" = true ]; then
        echo "  - ngrok: Running in separate terminal (monitor at http://localhost:4040)"
    fi
    echo

    echo_info "Web Interface:"
    echo "  - Visit http://localhost:8090 in your browser to view the WebUI"
    echo

    if [ "$LISTEN_MODE" = "full" ]; then
        echo "Endpoints:"
        echo "  - RPC endpoint: http://localhost:9292"
        echo "  - Asset API: ${NGROK_URL}/api/v1"
    else
        echo "Endpoints (local only - listen-only mode):"
        echo "  - RPC endpoint: http://localhost:9292"
        echo "  - Asset API: http://localhost:8090/api/v1"
        echo "  - Note: External connections not available in listen-only mode"
    fi
    echo

    echo "Credentials:"
    if [ -n "$RPC_USER" ]; then
        echo "  - RPC Username: $RPC_USER"
        echo "  - RPC Password: [saved in settings_local.conf]"
    else
        echo "  - RPC Credentials: Not configured (add to settings_local.conf manually)"
    fi
    echo

    if [ "$MINING_ENABLED" = "true" ]; then
        echo "Mining Configuration:"
        echo "  - Mining Address: $MINING_ADDRESS"
        echo "  - Miner Tag: $MINER_TAG"
        echo "  - CPU Threads: 2"
        echo
        echo_info "To start CPU mining, run the following command:"
        echo
        echo "  docker run -d --name cpuminer \\"
        echo "    --network my-teranode-network \\"
        echo "    ghcr.io/bitcoin-sv/cpuminer:latest \\"
        echo "    --url=http://rpc:9292 \\"
        echo "    --algo=sha256d \\"
        echo "    --always-gmc \\"
        echo "    --retries=1 \\"
        echo "    --userpass='${RPC_USER:-bitcoin}:${RPC_PASS:-bitcoin}' \\"
        echo "    --coinbase-addr=$MINING_ADDRESS \\"
        echo "    --coinbase-sig=\"$MINER_TAG\" \\"
        echo "    --threads=2"
        echo
        echo "After starting the miner:"
        echo "  - Monitor logs: docker logs -f cpuminer"
        echo "  - Stop mining: docker stop cpuminer && docker rm cpuminer"
    else
        echo "Mining Status: DISABLED"
    fi
    echo

    echo_info "To monitor important logs, run:"
    echo "  docker compose logs -f -n 100 blockchain blockvalidation blockassembly subtreevalidation"
    echo

    echo "To stop services:"
    echo "  - Docker: docker compose down"
    if [ "$USE_NGROK" = true ]; then
        echo "  - ngrok: Stop the ngrok process in its terminal (Ctrl+C)"
    fi
    echo

    if [ "$LISTEN_MODE" = "listen_only" ]; then
        echo_info "Your Teranode is running in listen-only mode!"
        echo_info "The node will sync with the network but won't mine or relay transactions."
    else
        echo_info "Your Teranode is now ready to process transactions!"
    fi
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
    check_existing_config

    # Only run configuration steps if not using existing config
    if [ "$USE_EXISTING_CONFIG" = false ]; then
        prompt_for_inputs
        generate_settings_from_template
        update_settings
    else
        echo_info "Using existing configuration, proceeding to start services..."
    fi

    start_docker_compose
    start_ngrok
    set_fsm_state_running
    show_completion_message
}

trap 'echo_error "Script interrupted. Exiting..."; exit 1' INT TERM

main "$@"
