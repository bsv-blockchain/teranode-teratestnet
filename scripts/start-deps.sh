#!/bin/bash

usage() {
    echo "Usage: $0 [service-name|all]"
    echo ""
    echo "Available services:"
    echo "  cpuminer   - CPU miner service"
    echo "  coinbase   - Coinbase service"
    echo "  tx-blaster - Transaction blaster service"
    echo "  aerospike  - Aerospike database service"
    echo "  redpanda   - Redpanda (Kafka) service"
    echo "  ngrok      - Ngrok tunnel service"
    echo "  all        - Start all services (default)"
    echo ""
    echo "Example:"
    echo "  $0 cpuminer"
    echo "  $0 all"
    exit 1
}

start_cpuminer() {
    echo "Starting cpuminer service..."
    docker run --network=host --replace --name cpuminer -d ghcr.io/bitcoin-sv/cpuminer:latest --algo=sha256d --debug --always-gmc --retries=2 --url=http://0.0.0.0:9292 --userpass=bitcoin:bitcoin --coinbase-addr=mftwFnpdujtDXRwFUzaviLhFbVYg5Hs9Ag --threads=2 --coinbase-sig="/Teranode-Dylan/"
}

start_coinbase() {
    echo "Starting coinbase service..."
    docker run --network=host --replace --name coinbase -e "SERVICE_NAME=tx-blaster" -v /git/teranode-coinbase/settings.conf:/app/settings.conf:Z -v /git/teranode-coinbase/settings_local.conf:/app/settings_local.conf:Z -e  "txblaster_dataDir=/data" -e "PROFILE_PORT=9191" -e "blockchain_store=postgres://teranode:teranode@localhost:5432/teranode_db" 434394763103.dkr.ecr.eu-north-1.amazonaws.com/teranode-coinbase:d9d3de28145453f8699718e3fe53e6499a96c3ce /app/blaster.run -workers=50 -print=0 -profile=:7092 -log=0 -limit=0
}

start_tx_blaster() {
    echo "Starting tx-blaster service..."
    docker run --network=host --replace --name tx-blaster -e "SERVICE_NAME=tx-blaster" -v /git/teranode-coinbase/settings.conf:/app/settings.conf:Z -v /git/teranode-coinbase/settings_tx_local.conf:/app/settings_local.conf:Z -v /mnt/nvme/coinbase:/data:Z -e "txblaster_dataDir=/data" -e "PROFILE_PORT=9291" -e "blockchain_store=postgres://teranode:teranode@localhost:5432/teranode_db"  --entrypoint=/app/blaster.run 434394763103.dkr.ecr.eu-north-1.amazonaws.com/teranode-coinbase:d9d3de28145453f8699718e3fe53e6499a96c3ce -workers=10 -print=0 -profile=:7092 -log=0 -limit=0
}

start_ngrok() {
    echo "Starting ngrok..."
    ngrok http --url=galts-gulch-explorer.ngrok.app http://localhost:5173
}

start_aerospike() {
    echo "Starting aerospike service..."
    docker run --replace -d -v /mnt/nvme/aerospike/data:/opt/aerospike/data:Z -v /opt/aerospike/etc:/opt/aerospike/etc/:Z --name aerospike -p 3000-3002:3000-3002 container.aerospike.com/aerospike/aerospike-server --config-file /opt/aerospike/etc/aerospike.conf
}

start_redpanda() {
    echo "Starting redpanda service..."
    docker run --replace --name redpanda -d \
        -p 9092:9092 \
        -p 9093:9093 \
        -p 9644:9644 \
        -p 8081:8081 \
        redpandadata/redpanda:latest \
        redpanda start \
        --smp 1 \
        --overprovisioned \
        --node-id 0 \
        --kafka-addr PLAINTEXT://0.0.0.0:9092 \
        --advertise-kafka-addr PLAINTEXT://127.0.0.1:9092 \
        --schema-registry-addr 0.0.0.0:8081 \
        --rpc-addr 0.0.0.0:33145 \
        --advertise-rpc-addr 127.0.0.1:33145
}

SERVICE="${1:-all}"

case "$SERVICE" in
    cpuminer)
        start_cpuminer
        ;;
    coinbase)
        start_coinbase
        ;;
    tx-blaster)
        start_tx_blaster
        ;;
    ngrok)
        start_ngrok
        ;;
    aerospike)
        start_aerospike
        ;;
    redpanda)
        start_redpanda
        ;;
    all)
        start_cpuminer
        start_coinbase
        start_tx_blaster
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "Error: Unknown service '$SERVICE'"
        echo ""
        usage
        ;;
esac
