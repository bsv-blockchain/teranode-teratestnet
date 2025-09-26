# Teratestnet Docker Helper

Automated setup for Teranode on the Teratestnet network using Docker Compose.

## Quick Start

```bash
# Standard setup (with ngrok for nodes without public IP)
./start-teratestnet.sh

# Custom domain setup (if you have public IP/domain)
./start-teratestnet.sh --no-ngrok
```

## Prerequisites

- **Docker** and **Docker Compose** installed
- **Ngrok** (if using default setup) - See [NGROK_PREREQUISITES.md](./NGROK_PREREQUISITES.md)
- 32GB+ RAM, 40GB+ disk space
- Linux, macOS, or Windows with WSL2

## What It Does

1. Configures your Teranode instance with:
   - Domain/URL (ngrok or custom)
   - RPC credentials
   - Optional Miner ID
2. Starts all required services via Docker Compose
3. Sets up networking (ngrok tunnel or your custom domain)

## Key Commands

```bash
# Start services
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs [service]

# Stop services
docker compose down

# Clean shutdown (removes data)
docker compose down -v
```

## Documentation

For detailed setup instructions, configuration options, troubleshooting, and advanced usage, see:
- [Complete Setup Guide](./docs/SETUP_GUIDE.md)
- [Ngrok Prerequisites](./NGROK_PREREQUISITES.md)

## Service Endpoints

| Service | Port | Description |
|---------|------|-------------|
| RPC | 9292 | JSON-RPC interface |
| Asset API | 8000 | Asset service API |
| Prometheus | 9090 | Metrics |
| Grafana | 3000 | Monitoring dashboard |

## Help

- Run `./start-teratestnet.sh --help` for command options
- Check [docs/SETUP_GUIDE.md](./docs/SETUP_GUIDE.md) for troubleshooting
- Teranode documentation: https://bsv-blockchain.github.io/teranode/