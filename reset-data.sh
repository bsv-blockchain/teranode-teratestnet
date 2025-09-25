#!/bin/bash

# Get the real path of the data directory
DATA_DIR=$(realpath "data")

echo "Stopping all services..."
docker compose down

echo ""
echo "WARNING: This will permanently delete all blockchain data!"
echo "Data directory: $DATA_DIR"
echo "Contents to be removed:"
if [ -d "$DATA_DIR" ] && [ "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
    ls -la "$DATA_DIR"
else
    echo "  (directory is empty or doesn't exist)"
fi

echo ""
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing data directory contents..."
    rm -rf data/*
    echo "Data reset complete."
else
    echo "Operation cancelled."
    exit 1
fi

echo "Data reset complete. Run './start-teratestnet.sh' to restart with fresh data."
echo "If everything is configured correctly you can start Teranode again with 'docker compose up -d' and 'docker exec -it blockchain teranode-cli setfsmstate --fsmstate running' once it's started up."