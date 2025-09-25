#!/bin/sh

# Initialize data directories with correct ownership
# This script runs as root to create directories and set proper ownership

set -e

echo "Initializing data directories..."

# Define required directories
DIRECTORIES="
postgres
aerospike/data
aerospike/smd
aerospike/asmt
teranode
prometheus
grafana/grafana.db
"

# Create directories
for dir in $DIRECTORIES; do
    echo "Creating /data/$dir"
    mkdir -p "/data/$dir"
done

# Set ownership to the specified user
echo "Setting ownership to ${USER_ID}:${GROUP_ID}..."
chown -R "${USER_ID}:${GROUP_ID}" /data

echo "Directory initialization complete"
