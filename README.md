# Teratestnet Docker Helper Script

This script automates the setup and configuration of a Teratestnet node using Docker Compose. It handles network configuration, RPC credentials, and optional ngrok tunnel setup for nodes without public IP addresses.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Command Line Options](#command-line-options)
- [Configuration Parameters](#configuration-parameters)
- [Usage Examples](#usage-examples)
- [Settings Modified](#settings-modified)
- [Troubleshooting](#troubleshooting)
- [Stopping Services](#stopping-services)

## Prerequisites

### Required Software

1. **Docker** - Container runtime
   - Installation: [https://docs.docker.com/get-docker/](https://docs.docker.com/get-docker/)

2. **Docker Compose** - Multi-container orchestration
   - Usually included with Docker Desktop
   - Standalone installation: [https://docs.docker.com/compose/install/](https://docs.docker.com/compose/install/)

3. **Ngrok** (optional - not needed with `--no-ngrok` flag)
   - Required for nodes without public IP addresses
   - Installation: See [NGROK_PREREQUISITES.md](./NGROK_PREREQUISITES.md)
   - Sign up for free account at [https://ngrok.com](https://ngrok.com)
   - Configure auth token: `ngrok config add-authtoken YOUR_TOKEN`

### System Requirements

- Linux, macOS, or Windows with WSL2
- Minimum 32GB RAM recommended
- 40GB+ available disk space
- Active internet connection

### Required open firewall ports (if not using Ngrok)

- 8000 (Nginx Asset Proxy)
- 9905 (P2P)

## Quick Start

### Default Setup (with ngrok)

For users without a public IP address or domain:

```bash
./start-teratestnet.sh
```

### Custom Domain Setup (without ngrok)

For users with existing domain/reverse proxy:

```bash
./start-teratestnet.sh --no-ngrok
```

## Command Line Options

### `--no-ngrok`

Skip ngrok setup and validation. Use this option if you have:
- A public IP address with port forwarding configured
- An existing reverse proxy (nginx, Apache, Cloudflare Tunnel, etc.)
- A custom domain pointing to your server

**Example:**
```bash
./start-teratestnet.sh --no-ngrok
```

### `--help` / `-h`

Display usage information and available options.

**Example:**
```bash
./start-teratestnet.sh --help
```

## Configuration Parameters

The script will prompt you for the following information:

### 1. Domain/URL

**With ngrok (default):**
- **Prompt:** "Enter your ngrok domain (e.g., example.ngrok-free.app)"
- **Format:** Can be entered with or without `https://` prefix
- **Examples:**
  - `mynode.ngrok-free.app`
  - `https://mynode.ngrok-free.app`

**Without ngrok (`--no-ngrok`):**
- **Prompt:** "Enter your domain/URL (e.g., teranode.example.com)"
- **Format:** Your public domain or IP address
- **Examples:**
  - `teranode.example.com`
  - `https://teranode.example.com`
  - `node.mydomain.org`

The script automatically:
- Adds `https://` prefix if not provided
- Removes trailing slashes
- Separates domain from protocol for P2P configuration

### 2. RPC Username

- **Prompt:** "Enter RPC username"
- **Purpose:** Username for JSON-RPC authentication
- **Requirements:** Cannot be empty
- **Example:** `rpcuser`

### 3. RPC Password

- **Prompt:** "Enter RPC password"
- **Purpose:** Password for JSON-RPC authentication
- **Requirements:**
  - Cannot be empty
  - Must be confirmed (entered twice)
  - Hidden during input for security

### 4. Miner ID (Optional)

- **Prompt:** "Enter Miner ID (optional, press Enter to skip)"
- **Purpose:** Sets the `coinbase_arbitrary_string` in the configuration
- **Requirements:**
  - Optional field
  - Warning shown if longer than 100 characters
- **Example:** `MyMiningNode-001`

## Usage Examples

### Example 1: Standard Setup with ngrok

```bash
$ ./start-teratestnet.sh

====================================
   Teratestnet Docker Helper Script
====================================

[INFO] Checking prerequisites...
[INFO] All prerequisites met.

=== Teratestnet Configuration ===

Enter your ngrok domain (e.g., example.ngrok-free.app): mynode.ngrok-free.app
[INFO] Processed ngrok URL:
  - Full URL: https://mynode.ngrok-free.app
  - Domain only: mynode.ngrok-free.app
Enter RPC username: alice
Enter RPC password: [hidden]
Confirm RPC password: [hidden]
Enter Miner ID (optional, press Enter to skip): AliceNode-01

[INFO] Configuration summary:
  - Ngrok Domain: mynode.ngrok-free.app
  - Full URL: https://mynode.ngrok-free.app
  - RPC Username: alice
  - RPC Password: [hidden]
  - Miner ID: AliceNode-01

Is this correct? (y/n): y
```

### Example 2: Custom Domain Without ngrok

```bash
$ ./start-teratestnet.sh --no-ngrok

====================================
   Teratestnet Docker Helper Script
      (Running without ngrok)
====================================

[INFO] Checking prerequisites...
[INFO] All prerequisites met.

=== Teratestnet Configuration ===

Enter your domain/URL (e.g., teranode.example.com): teranode.mydomain.com
[INFO] Processed ngrok URL:
  - Full URL: https://teranode.mydomain.com
  - Domain only: teranode.mydomain.com
Enter RPC username: nodeoperator
Enter RPC password: [hidden]
Confirm RPC password: [hidden]
Enter Miner ID (optional, press Enter to skip):

[INFO] Configuration summary:
  - Domain: teranode.mydomain.com
  - Full URL: https://teranode.mydomain.com
  - RPC Username: nodeoperator
  - RPC Password: [hidden]

Is this correct? (y/n): y
```

## Settings Modified

https://docs.google.com/document/d/1BsTx3bkfTNXWL2h-iaOpm1CLt7rCCMhtCHjgf7ooKwE/edit?usp=sharingThe script modifies the following settings in `../base/settings.conf`:

| Setting | Description | Example Value |
|---------|-------------|---------------|
| `asset_httpAddress` | Internal HTTP address for asset service | `https://example.ngrok-free.app/api/v1` |
| `asset_httpPublicAddress` | Public HTTP address for asset service | `https://example.ngrok-free.app/api/v1` |
| `rpc_user` | RPC authentication username | `myuser` |
| `rpc_pass` | RPC authentication password | `mypassword` |
| `coinbase_arbitrary_string` | Miner identification string (optional) | `MyMiner-01` |

### Important Notes:

- **Backup Created:** The script automatically creates a backup of `settings.conf` before making changes
- **Backup Location:** `settings.conf.backup.YYYYMMDD_HHMMSS`

## Troubleshooting

### Common Issues

#### 1. Ngrok Not Found

**Error:** "ngrok is not installed"

**Solutions:**
- Install ngrok following instructions in [NGROK_PREREQUISITES.md](./NGROK_PREREQUISITES.md)
- Or use `--no-ngrok` flag if you have your own domain/proxy

#### 2. Docker Not Running

**Error:** "Cannot connect to the Docker daemon"

**Solution:**
```bash
# Linux
sudo systemctl start docker

# macOS/Windows
# Start Docker Desktop application
```

#### 3. Port Already in Use

**Error:** "bind: address already in use"

**Solution:**
```bash
# Find process using the port
sudo lsof -i :8090

# Stop conflicting service or change port configuration
```

#### 4. Invalid Credentials

**Error:** "Passwords do not match"

**Solution:**
- Carefully re-enter the password
- Ensure no extra spaces or characters

#### 5. Ngrok Tunnel Failed

**Error:** "Failed to start ngrok"

**Solutions:**
- Verify ngrok auth token: `ngrok config check`
- Check firewall allows outbound HTTPS (port 443)
- Try different ngrok region if timeouts occur

### Checking Service Status

**Docker Compose Status:**
```bash
docker compose ps
```

**Ngrok Status (when using ngrok):**
- Web interface: http://localhost:4040
- Shows active tunnels and request inspection

**View Logs:**
```bash
# All services
docker compose logs

# Specific service
docker compose logs blockchain
```

## Stopping Services

### Stop All Services

```bash
# Stop Docker containers
docker compose down

# Stop ngrok (if running)
killall ngrok
```

### Stop Individual Components

```bash
# Stop only Docker services (keep ngrok running)
docker compose stop

# Stop only ngrok (keep Docker running)
killall ngrok

# Stop specific Docker service
docker compose stop blockchain
```

### Clean Shutdown

For a complete cleanup:

```bash
# Stop and remove containers, networks, volumes
docker compose down -v

# Stop ngrok
killall ngrok

# Restore original settings (optional)
cp settings.conf.backup.YYYYMMDD_HHMMSS ../base/settings.conf
```

## Service Endpoints

After successful startup, the following endpoints are available:

| Service | Endpoint | Description |
|---------|----------|-------------|
| RPC | `https://[your-domain]:9292` | JSON-RPC interface |
| Asset API | `https://[your-domain]/api/v1` | Asset service API |
| P2P | `[your-domain]` (no protocol) | Peer-to-peer communication |
| Ngrok Dashboard | `http://localhost:4040` | Ngrok status (only with ngrok) |
| Prometheus | `http://localhost:9090` | Metrics collection |
| Grafana | `http://localhost:3000` | Metrics visualization |

## Advanced Configuration

### Environment Variables

You can override settings using environment variables:

```bash
# Override network setting
network=testnet ./start-teratestnet.sh

# Override log level
logLevel=DEBUG ./start-teratestnet.sh
```

### Manual Configuration

To manually edit settings after initial setup:

1. Edit `../base/settings.conf`
2. Restart services:
   ```bash
   docker compose restart
   ```

### Using Different Ports

If default ports conflict, modify the port mappings in `docker-compose.yml` before running the script.

## Security Considerations

1. **RPC Credentials**
   - Use strong, unique passwords
   - Never commit credentials to version control
   - Consider using environment variables for production

2. **Ngrok Security**
   - Free ngrok URLs are public
   - Consider paid ngrok plan for reserved domains
   - Implement additional authentication layers

3. **Firewall Configuration**
   - Only expose necessary ports
   - Use firewall rules to restrict access
   - Consider VPN for administrative access

4. **Backup Strategy**
   - Regularly backup data directories
   - Test restore procedures
   - Keep multiple backup versions

## Getting Help

- **Script Help:** `./start-teratestnet.sh --help`
- **Docker Issues:** Check Docker documentation
- **Ngrok Issues:** Visit [ngrok documentation](https://ngrok.com/docs)
- **Teranode Issues:** Consult [Teranode documentation](https://bsv-blockchain.github.io/teranode/)
