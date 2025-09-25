#!/bin/bash

echo "Stopping all services..."
docker compose down

echo "Removing data directory contents..."
rm -rf data/*

echo "Data reset complete. Run './start-teratestnet.sh' to restart with fresh data."
echo "If everything is configured correctly you can start Teranode again with 'docker compose up -d' and 'docker exec -it blockchain teranode-cli setfsmstate --fsmstate running' once it's started up."