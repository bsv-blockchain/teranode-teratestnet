# Teratestnet Docker Helper

> [!IMPORTANT]
> **This repository is archived. Use [teranode-quickstart](https://github.com/bsv-blockchain/teranode-quickstart) instead.**
>
> `teranode-quickstart` replaces this repo and covers all four networks — mainnet, testnet, teratestnet and regtest — from one interactive `setup.sh`. It also ships UTXO snapshot seeding, per-service memory limits scaled to host RAM, Aerospike/Postgres tuning helpers, and a version-pinned `update.sh` that tracks current Teranode releases.
>
> This repo is pinned to Teranode v0.15.1 and gets no further updates. Everything below is kept for reference only.

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
- **Ngrok** (if using default setup) - See [SETUP_GUIDE](./docs/SETUP_GUIDE.md#example-1-standard-setup-with-ngrok)
- 32GB+ RAM, 40GB+ disk space
- Linux, macOS, or Windows with WSL2

## What It Does

1. Configures your Teranode instance with:
   - Domain/URL (ngrok or custom)
   - RPC credentials
   - Optional Miner Tag
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

# Reset to start syncing from genesis
./reset-data.sh
```

## Documentation

For detailed setup instructions, configuration options, troubleshooting, and advanced usage, see:
- [Complete Setup Guide](./docs/SETUP_GUIDE.md)

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

## Community

Join our Telegram group for announcements and discussions:
- 📢 [Join Teratestnet Community](https://t.me/+FIcJEMznX0xiMzlk)
