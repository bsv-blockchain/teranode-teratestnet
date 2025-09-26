#!/bin/bash

# List of Docker volumes used by the Teranode services
VOLUMES="
postgres-data
aerospike-data
aerospike-smd
aerospike-asmt
teranode-data
prometheus-data
grafana-data
nginx-cache
"

echo "Stopping all services..."
docker compose down

echo ""
echo "WARNING: This will permanently delete all blockchain data stored in Docker volumes!"
echo "Docker volumes to be removed:"
for volume in $VOLUMES; do
    if docker volume inspect "${PWD##*/}_$volume" >/dev/null 2>&1; then
        echo "  ${PWD##*/}_$volume (exists)"
    else
        echo "  ${PWD##*/}_$volume (doesn't exist)"
    fi
done

echo ""
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing Docker volumes..."
    for volume in $VOLUMES; do
        volume_name="${PWD##*/}_$volume"
        if docker volume inspect "$volume_name" >/dev/null 2>&1; then
            echo "Removing volume: $volume_name"
            docker volume rm "$volume_name"
        else
            echo "Volume $volume_name doesn't exist, skipping"
        fi
    done
    echo "Data reset complete."
else
    echo "Operation cancelled."
    exit 1
fi

echo "Data reset complete. Run './start-teratestnet.sh' to restart with fresh data."
echo "If everything is configured correctly you can start Teranode again with 'docker compose up -d' and 'docker exec -it blockchain teranode-cli setfsmstate --fsmstate running' once it's started up."