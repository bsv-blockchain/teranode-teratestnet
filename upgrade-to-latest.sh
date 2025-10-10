#!/bin/bash

set -e

echo "🔄 Upgrading to latest Teranode Teratestnet..."

# Check if we're on the main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "❌ Error: You are currently on branch '$CURRENT_BRANCH'"
    echo "   Please switch to the 'main' branch before upgrading:"
    echo "   git checkout main"
    exit 1
fi

echo "✅ On main branch, proceeding with upgrade..."

# Stash any local changes
echo "📦 Stashing local changes..."
git stash

# Pull latest changes
echo "⬇️  Pulling latest changes..."
git pull

# Pop stashed changes back
echo "📦 Restoring local changes..."
if git stash list | grep -q "stash@{0}"; then
    git stash pop
fi

# Check for git conflicts
if git ls-files -u | grep -q .; then
    echo "❌ Git conflicts detected!"
    echo "   Please resolve the conflicts manually and then run:"
    echo "   docker compose up -d"
    exit 1
fi

echo "✅ No conflicts detected"

# Restart Docker services with latest images
echo "🐳 Restarting Docker services..."
docker compose up -d

echo "🎉 Upgrade complete! All services are starting with the latest version."
echo "   Run 'docker compose ps' to check service status"