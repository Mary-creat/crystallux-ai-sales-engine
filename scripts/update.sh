#!/bin/bash
# Crystallux n8n Update Script
# Backs up first, then updates n8n to latest version
# Downtime: ~10 seconds
#
# Usage: bash /root/crystallux/n8n/update.sh

TIMESTAMP=$(date +%Y-%m-%d_%H%M)

echo "[$TIMESTAMP] Starting n8n update..."

# Step 1: Backup before update
echo "[$TIMESTAMP] Creating pre-update backup..."
bash /root/crystallux/backups/backup.sh
if [ $? -ne 0 ]; then
  echo "[$TIMESTAMP] ERROR: Backup failed! Aborting update."
  exit 1
fi

# Step 2: Pull latest image (while n8n is still running)
echo "[$TIMESTAMP] Pulling latest n8n image..."
docker pull n8nio/n8n:latest

# Step 3: Recreate n8n container with new image
echo "[$TIMESTAMP] Recreating n8n container..."
if [ -f /root/crystallux/n8n/docker-compose.prod.yml ]; then
  cd /root/crystallux/n8n
  docker compose -f docker-compose.prod.yml up -d --force-recreate n8n
else
  # Fallback for non-compose setup
  echo "[$TIMESTAMP] No compose file found. Manual update required."
  echo "Run: docker stop n8n && docker rm n8n && docker run (with your params)"
  exit 1
fi

# Step 4: Wait and verify
echo "[$TIMESTAMP] Waiting 30 seconds for n8n to start..."
sleep 30

wget --spider -q --timeout=10 http://localhost:5678/healthz
if [ $? -eq 0 ]; then
  NEW_VERSION=$(docker inspect n8n --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null)
  echo "[$TIMESTAMP] UPDATE COMPLETE — n8n is running version $NEW_VERSION"
else
  echo "[$TIMESTAMP] WARNING — n8n may not be responding yet. Check: docker logs n8n"
fi
