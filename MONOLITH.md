# Running Teranode on Teratestnet

This tutorial will guide you through setting up and running a Teranode instance on the `teratestnet` network in a monolithic environment with containerized dependencies.

## Overview

Teranode is a highly scalable Bitcoin SV node implementation designed to handle enterprise-level transaction volumes. The `teratestnet` is a test network specifically designed for testing Teranode capabilities.

This guide covers:
- Setting up all required dependencies (PostgreSQL, Kafka/Redpanda, Aerospike)
- Configuring Teranode for teratestnet
- Running Teranode in a Docker container
- Monitoring and troubleshooting your node

## Prerequisites

### System Requirements

- **CPU**: Minimum 8 cores (16+ recommended)
- **RAM**: Minimum 32GB (64GB+ recommended)
- **Storage**:
  - SSD with at least 500GB free space
  - NVMe recommended for Aerospike and block storage
- **Operating System**: Linux (Ubuntu 20.04+ or similar)

### Software Requirements

- Docker (version 20.10 or higher)
- Docker Compose (optional, for orchestrated setup)
- Git
- Basic command line tools (curl, wget)

### Network Requirements

Ensure the following ports are available:
- **5432**: PostgreSQL
- **9092**: Kafka/Redpanda
- **3000-3002**: Aerospike
- **9292**: Teranode RPC
- **9905**: P2P port
- **8000**: Health check endpoint

## Directory Setup

Create the following directory structure for data persistence. This example uses `/mnt/nvme` as the base directory for optimal performance, but you can adjust to your preferred location:

```bash
# Define base directory (adjust as needed)
export TERANODE_BASE=/mnt/nvme

# Create subdirectories for each service
mkdir -p $TERANODE_BASE/coinbase
mkdir -p $TERANODE_BASE/aerospike/data
mkdir -p $TERANODE_BASE/aerospike/etc
mkdir -p $TERANODE_BASE/teranode/data/{blockstore,subtreestore,external,subtree_quorum}
mkdir -p $TERANODE_BASE/postgres/data

# Set proper permissions
chmod -R 755 $TERANODE_BASE
```

## PostgreSQL Setup

PostgreSQL stores blockchain metadata and transaction information.

### 1. Create PostgreSQL initialization script

```bash
cat > $TERANODE_BASE/postgres/init.sql << 'EOF'
CREATE ROLE teranode LOGIN
  PASSWORD 'teranode'
  SUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION;
grant teranode to postgres;
CREATE DATABASE teranode_db
  WITH OWNER = teranode
  ENCODING = 'UTF8'
  CONNECTION LIMIT = -1;
EOF
```

### 2. Start PostgreSQL container

```bash
docker run -d \
  --name postgres-teranode \
  --network host \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_DB=postgres \
  -v $TERANODE_BASE/postgres/data:/var/lib/postgresql/data \
  -v $TERANODE_BASE/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql \
  postgres:14-alpine
```

### 3. Verify PostgreSQL is running

```bash
docker logs postgres-teranode
# Wait for "database system is ready to accept connections"

# Test connection
docker exec -it postgres-teranode psql -U teranode -d teranode_db -c "\l"
```

## Kafka/Redpanda Setup

Redpanda is a Kafka-compatible streaming platform used for message passing between Teranode components.

### Start Redpanda container

```bash
docker run -d \
  --name redpanda-teranode \
  --network host \
  -v $TERANODE_BASE/redpanda:/var/lib/redpanda/data \
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
```

### Verify Redpanda is running

```bash
docker logs redpanda-teranode
# Check for "Redpanda is ready"

# List topics (should be empty initially)
docker exec -it redpanda-teranode rpk topic list
```

## Aerospike Setup

Aerospike is a high-performance NoSQL database used for UTXO storage.

### 1. Create Aerospike configuration

```bash
cat > $TERANODE_BASE/aerospike/etc/aerospike.conf << 'EOF'
service {
    proto-fd-max 15000
    work-directory /opt/aerospike
}

logging {
    console {
        context any info
    }
}

network {
    service {
        address any
        port 3000
    }

    heartbeat {
        mode multicast
        multicast-group 239.1.99.222
        port 9918
        interval 150
        timeout 10
    }

    fabric {
        port 3001
    }

    info {
        port 3003
    }
}

namespace utxo-store {
    replication-factor 1
    memory-size 4G
    nsup-period 120

    storage-engine device {
        device /opt/aerospike/data/utxo.dat
        filesize 50G
        data-in-memory false
    }
}
EOF
```

### 2. Create storage file

```bash
# Create a 50GB file for Aerospike storage
docker run --rm -v $TERANODE_BASE/aerospike/data:/data alpine \
  dd if=/dev/zero of=/data/utxo.dat bs=1G count=50
```

### 3. Start Aerospike container

```bash
docker run -d \
  --name aerospike-teranode \
  --network host \
  -v $TERANODE_BASE/aerospike/data:/opt/aerospike/data \
  -v $TERANODE_BASE/aerospike/etc:/opt/aerospike/etc \
  aerospike/aerospike-server \
  --config-file /opt/aerospike/etc/aerospike.conf
```

### 4. Verify Aerospike is running

```bash
docker logs aerospike-teranode
# Check for "service ready"

# Check cluster status
docker exec -it aerospike-teranode asadm -e "info"
```

## Teranode Configuration

### 1. Create settings file

Create a comprehensive `settings_local.conf` that includes all necessary configurations. Note that we'll substitute the TERANODE_BASE variable after creating the file:

```bash
# First, create the file with placeholder
cat > $TERANODE_BASE/teranode/settings_local.conf << 'EOF'
# Teratestnet Configuration
# This file contains all necessary overrides for running on teratestnet

# Network identification - REQUIRED for teratestnet
network = teratestnet

# Your node's identity (replace with your values)
# Generate a new private key for your node
coinbase_wallet_private_key = <YOUR_PRIVATE_KEY>
p2p_private_key = <YOUR_P2P_PRIVATE_KEY>

# Database connections
blockchain_store = postgres://teranode:teranode@localhost:5432/teranode_db
utxostore = aerospike://localhost:3000/utxo-store?set=utxo&externalStore=file:///data/external

# Kafka settings
KAFKA_HOSTS = localhost:9092

# File stores (using host paths with TERANODE_BASE)
# Note: When running in Docker, these paths will be mapped to /data inside the container
txstore = file://${TERANODE_BASE}/teranode/data/txstore
subtreestore = file://${TERANODE_BASE}/teranode/data/subtreestore?localTTLStore=file&localTTLStorePath=${TERANODE_BASE}/teranode/data/subtreestore-ttl-1
blockstore = file://${TERANODE_BASE}/teranode/data/blockstore?localTTLStore=file&localTTLStorePath=${TERANODE_BASE}/teranode/data/blockstore-ttl-1
temp_store = file://${TERANODE_BASE}/teranode/data/tempstore
subtree_quorum_path = ${TERANODE_BASE}/teranode/data/subtree_quorum

# Performance tuning for initial sync
KAFKA_PARTITIONS_HIGH = 32

# Mining settings
minminingtxfee = 0
coinbase_arbitrary_text = "/YourNodeName/"

# Logging
logLevel = INFO

# Asset service (update after setting up ngrok or public URL)
# asset_httpPublicAddress = https://your-url.ngrok.app${asset_apiPrefix}

# P2P settings (optional - for public nodes)
# p2p_advertise_addresses.teratestnet = "your-url.ngrok.app"

# RPC settings (already in base config, but can override here if needed)
# rpc_user = bitcoin
# rpc_pass = bitcoin
EOF

# Now substitute the TERANODE_BASE variable with the actual path
sed -i "s|\${TERANODE_BASE}|$TERANODE_BASE|g" $TERANODE_BASE/teranode/settings_local.conf
```

### 2. Prepare for Docker vs Host execution

If running with Docker, create a version with container paths:

```bash
# Create a Docker-specific version that uses /data paths
cp $TERANODE_BASE/teranode/settings_local.conf $TERANODE_BASE/teranode/settings_local_docker.conf

# Replace host paths with container paths for Docker
sed -i "s|file://$TERANODE_BASE/teranode/data/|file:///data/|g" $TERANODE_BASE/teranode/settings_local_docker.conf
sed -i "s|$TERANODE_BASE/teranode/data/|/data/|g" $TERANODE_BASE/teranode/settings_local_docker.conf
```

### 3. Generate keys (if needed)

```bash
# Generate a Bitcoin private key for coinbase
# You can use any Bitcoin wallet to generate this

# Generate P2P private key
openssl rand -hex 64
```

## Starting Teranode

### 1. Download Teranode image

```bash
# Replace with the actual Teranode image URL
docker pull <TERANODE_IMAGE_URL>
```

### 2. Start Teranode container

```bash
docker run -d \
  --name teranode \
  --network host \
  -v $TERANODE_BASE/teranode/settings_local_docker.conf:/app/settings_local.conf:ro \
  -v $TERANODE_BASE/teranode/data:/data \
  -e SERVICE_NAME=teranode \
  -e PROFILE_PORT=9091 \
  -e SETTINGS_CONTEXT=teratestnet \
  <TERANODE_IMAGE_URL>
```

### 3. Monitor startup

```bash
# Watch logs
docker logs -f teranode

# Check health endpoint
curl http://localhost:8000/health
```

## Alternative: Running Teranode Binary Directly

If you prefer to run Teranode directly on your host machine instead of using Docker:

### 1. Set environment variables

```bash
# Required for teratestnet
export SETTINGS_CONTEXT=teratestnet

# Optional: set service name
export SERVICE_NAME=teranode
```

### 2. Place settings file with binary

Copy the `settings_local.conf` to the same directory as your teranode binary:

```bash
# Copy settings to binary location
cp $TERANODE_BASE/teranode/settings_local.conf /path/to/teranode/binary/directory/

# Or if running from the teranode directory
cd /path/to/teranode/binary/directory
cp $TERANODE_BASE/teranode/settings_local.conf .
```

### 3. Run the binary

```bash
# From the directory containing both the binary and settings_local.conf
./teranode

# Or with full path (settings_local.conf must be in same directory as binary)
/path/to/teranode
```

## Optional: Running CPU Miner

To mine blocks on teratestnet, you can run the CPU miner alongside your Teranode instance:

### 1. Generate a mining address

First, you'll need a Bitcoin address for receiving mining rewards. You can:
- Use an existing wallet that supports testnet
- Generate one using any Bitcoin wallet software
- Use this example testnet address: `mftwFnpdujtDXRwFUzaviLhFbVYg5Hs9Ag` (DO NOT use in production)

### 2. Start CPU miner

Using Docker:

```bash
docker run -d \
  --name cpuminer \
  --network host \
  ghcr.io/bitcoin-sv/cpuminer:latest \
  --algo=sha256d \
  --url=http://localhost:9292 \
  --userpass=bitcoin:bitcoin \
  --coinbase-addr=<YOUR_MINING_ADDRESS> \
  --coinbase-sig="/YourMinerTag/" \
  --threads=2
```

Using the helper script:

```bash
# The script includes a default address - modify it first
./scripts/start-deps.sh cpuminer
```

### 3. Customize miner settings

- `--coinbase-addr`: Your Bitcoin address for mining rewards
- `--coinbase-sig`: Your miner tag (appears in blocks you mine)
- `--threads`: Number of CPU threads to use (adjust based on your system)
- `--url`: RPC endpoint of your Teranode (default: http://localhost:9292)
- `--userpass`: RPC credentials (default: bitcoin:bitcoin)

### 4. Monitor mining

```bash
# Check miner logs
docker logs -f cpuminer

# Check if you're mining blocks
curl -u bitcoin:bitcoin -X POST http://localhost:9292 \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"1.0","id":"1","method":"getmininginfo","params":[]}'
```

**Note**: CPU mining is only practical on testnet. For mainnet, specialized ASIC hardware is required.

## Next Steps: Using Your Teranode Instance

Once your Teranode is running and syncing with the network, refer to the [Miners Getting Started Guide](../miners/minersGettingStarted.md) for detailed information on:

- Checking sync status
- Submitting transactions
- Using the RPC interface
- Monitoring node performance
- Basic maintenance operations

## Using the Helper Script

The provided `scripts/start-deps.sh` script can help manage individual services:

```bash
cd /git/teranode-public/docs/tutorials/teratestnet
chmod +x scripts/start-deps.sh

# Start individual services
./scripts/start-deps.sh aerospike
./scripts/start-deps.sh redpanda

# Note: The script uses specific paths that may need adjustment
```

## Exposing the Asset Service

Once Teranode is running, you'll need to expose your asset service to participate in the network. The asset service allows other nodes to retrieve transaction and block data from your node.

### Option 1: Using ngrok (Recommended for Testing)

[ngrok](https://ngrok.com) provides a secure tunnel to expose your local services to the internet without complex firewall configuration.

#### 1. Install ngrok

```bash
# Download ngrok
wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
tar xvzf ngrok-v3-stable-linux-amd64.tgz
sudo mv ngrok /usr/local/bin/

# Sign up at https://ngrok.com and get your auth token
ngrok config add-authtoken <YOUR_AUTH_TOKEN>
```

#### 2. Expose the Asset Service

The asset service runs on port 8090 by default. You can use the helper script or run ngrok directly:

```bash
# Manually expose the asset service
ngrok http 8090

# Note: The helper script's ngrok command is configured for a different service (port 5173)
```

#### 3. Configure Teranode with Your ngrok URL

Once ngrok is running, it will display a URL like `https://abc123.ngrok.app`. Update your `settings_local.conf`:

```bash
# Add this to your settings_local.conf
echo "asset_httpPublicAddress = https://abc123.ngrok.app\${asset_apiPrefix}" >> $TERANODE_BASE/teranode/settings_local.conf

# Restart Teranode to apply the change
docker restart teranode
```

### Option 2: Direct Internet Exposure (Production)

For production deployments, you should expose the asset service directly:

1. **Configure firewall** to allow inbound traffic on port 8090
2. **Set up a domain** pointing to your server
3. **Configure TLS** with a reverse proxy (nginx/caddy)
4. **Update settings** with your public URL:

```bash
asset_httpPublicAddress = https://your-domain.com${asset_apiPrefix}
```

### Option 3: Using Custom Domain with ngrok

For a more professional setup while testing, you can use a custom domain with ngrok:

```bash
# If you have a paid ngrok plan with custom domains
ngrok http --domain=your-custom-domain.ngrok.app 8090
```

### Verifying Asset Service Exposure

Test that your asset service is accessible:

```bash
# From another machine or using a different network
curl https://your-ngrok-url.ngrok.app/api/v1/health

# Should return a health check response
```

### Important Notes

- **ngrok free tier** has limitations (e.g., connection limits, random URLs)
- **For production**, use direct exposure with proper security measures
- **Update P2P settings** to advertise your public address:
  ```
  p2p_advertise_addresses = "your-public-domain.com"
  ```

## Monitoring and Troubleshooting

### Health Checks

- **Teranode health**: `http://localhost:8000/health`
- **RPC endpoint**: `http://localhost:9292` (user: bitcoin, pass: bitcoin)
- **Metrics**: `http://localhost:9091/metrics`

### Common Issues

1. **Database connection errors**
   - Verify PostgreSQL is running: `docker ps | grep postgres`
   - Check credentials in settings files
   - Ensure database `teranode_db` exists

2. **Kafka connection issues**
   - Check Redpanda logs: `docker logs redpanda-teranode`
   - Verify port 9092 is accessible
   - Ensure topics are created (they're auto-created on first use)

3. **Aerospike errors**
   - Check namespace configuration matches settings
   - Verify storage file exists and has proper permissions
   - Monitor memory usage - Aerospike needs sufficient RAM

4. **P2P connection issues**
   - Ensure port 9905 is open for P2P connections
   - Check bootstrap addresses in settings
   - Verify network connectivity to other teratestnet nodes

### Logs Location

All logs are available through Docker:
```bash
docker logs teranode          # Main Teranode logs
docker logs postgres-teranode # PostgreSQL logs
docker logs redpanda-teranode # Kafka/Redpanda logs
docker logs aerospike-teranode # Aerospike logs
```

## Security Considerations

### Change Default Credentials

1. **PostgreSQL**: Change the default `teranode` password
2. **RPC**: Update `rpc_user` and `rpc_pass` in settings
3. **Private Keys**: Generate unique keys for your node

### Network Security

1. Use firewall rules to restrict access to service ports
2. Only expose necessary ports (P2P, RPC if needed)
3. Consider using a reverse proxy for RPC access
4. Enable TLS for production deployments

### Volume Permissions

Ensure proper ownership of data directories:
```bash
# Set ownership for containerized services
sudo chown -R 999:999 $TERANODE_BASE/postgres/data
sudo chown -R 1001:1001 $TERANODE_BASE/aerospike/data
```

## Next Steps

1. Monitor initial blockchain sync progress
2. Set up automated backups for critical data
3. Configure monitoring and alerting
4. Join the teratestnet community for support

For more information, refer to the main Teranode documentation.
