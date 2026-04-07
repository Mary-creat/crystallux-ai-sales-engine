#!/bin/bash
# Crystallux Server Setup Script
# Migrates from single docker run to full production stack
#
# Prerequisites:
#   - SSH access to Hostinger VPS as root
#   - n8n currently running as single container
#   - n8n_data volume exists
#
# Usage: bash server-setup.sh
#
# IMPORTANT: Run this on your Hostinger VPS, not your local machine

set -e
TIMESTAMP=$(date +%Y-%m-%d_%H%M)

echo "========================================="
echo "Crystallux Production Infrastructure Setup"
echo "========================================="
echo ""

# Step 1: Install Docker Compose plugin
echo "[1/8] Installing Docker Compose plugin..."
apt-get update -qq
apt-get install -y -qq docker-compose-plugin
docker compose version
echo "Done."
echo ""

# Step 2: Create backup before migration
echo "[2/8] Creating backup of current n8n data..."
mkdir -p /root/crystallux/backups
docker run --rm \
  -v n8n_data:/source:ro \
  -v /root/crystallux/backups:/backup \
  alpine tar czf "/backup/n8n_data_pre_migration_$TIMESTAMP.tar.gz" -C /source .
echo "Backup saved: /root/crystallux/backups/n8n_data_pre_migration_$TIMESTAMP.tar.gz"
echo ""

# Step 3: Read current encryption key
echo "[3/8] Reading current n8n encryption key..."
CURRENT_KEY=$(docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}' | grep N8N_ENCRYPTION_KEY | cut -d= -f2)
if [ -z "$CURRENT_KEY" ]; then
  echo "ERROR: Could not read N8N_ENCRYPTION_KEY from running container!"
  echo "Check: docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}'"
  exit 1
fi
echo "Encryption key found: ${CURRENT_KEY:0:8}..."
echo ""

# Step 4: Create .env file for Docker Compose
echo "[4/8] Creating .env file..."
cat > /root/crystallux/n8n/.env << ENVEOF
N8N_ENCRYPTION_KEY=$CURRENT_KEY
ENVEOF
chmod 600 /root/crystallux/n8n/.env
echo "Saved to /root/crystallux/n8n/.env (permissions: 600)"
echo ""

# Step 5: Copy docker-compose.prod.yml
echo "[5/8] Copying production Docker Compose file..."
# This file should already be at /root/crystallux/n8n/docker-compose.prod.yml
# If running from the repo, copy it:
if [ ! -f /root/crystallux/n8n/docker-compose.prod.yml ]; then
  echo "ERROR: docker-compose.prod.yml not found at /root/crystallux/n8n/"
  echo "Copy it from the repo: scripts/docker-compose.prod.yml"
  exit 1
fi
echo "Done."
echo ""

# Step 6: Stop current container and start new stack
echo "[6/8] Migrating to Docker Compose stack..."
echo "Stopping current n8n container..."
docker stop n8n
docker rm n8n
echo "Starting new stack..."
cd /root/crystallux/n8n
docker compose -f docker-compose.prod.yml up -d
echo "Waiting 30 seconds for n8n to start..."
sleep 30

# Verify n8n is running
wget --spider -q --timeout=10 http://localhost:5678/healthz
if [ $? -eq 0 ]; then
  echo "n8n is running and healthy!"
else
  echo "WARNING: n8n may still be starting. Check: docker compose -f docker-compose.prod.yml logs n8n"
fi
echo ""

# Step 7: Install backup and monitoring scripts
echo "[7/8] Setting up backup and monitoring scripts..."
cp /root/crystallux/n8n/backup.sh /root/crystallux/backups/backup.sh 2>/dev/null || true
cp /root/crystallux/n8n/healthcheck.sh /root/crystallux/monitoring/healthcheck.sh 2>/dev/null || true
chmod +x /root/crystallux/backups/backup.sh 2>/dev/null || true
chmod +x /root/crystallux/monitoring/healthcheck.sh 2>/dev/null || true
echo "Done."
echo ""

# Step 8: Set up cron jobs
echo "[8/8] Setting up cron jobs..."
# Remove any existing crystallux cron entries
crontab -l 2>/dev/null | grep -v crystallux > /tmp/crontab_clean || true
# Add backup (daily at 2 AM) and health check (every 5 min)
echo "0 2 * * * /root/crystallux/backups/backup.sh >> /root/crystallux/backups/backup.log 2>&1" >> /tmp/crontab_clean
echo "*/5 * * * * /root/crystallux/monitoring/healthcheck.sh >> /root/crystallux/monitoring/health.log 2>&1" >> /tmp/crontab_clean
crontab /tmp/crontab_clean
rm /tmp/crontab_clean
echo "Cron jobs installed:"
echo "  - Backup: daily at 2:00 AM"
echo "  - Health check: every 5 minutes"
echo ""

echo "========================================="
echo "Setup complete!"
echo "========================================="
echo ""
echo "Verify:"
echo "  docker compose -f /root/crystallux/n8n/docker-compose.prod.yml ps"
echo "  curl http://localhost:5678/healthz"
echo ""
echo "Update n8n:"
echo "  bash /root/crystallux/n8n/update.sh"
echo ""
echo "View logs:"
echo "  docker compose -f /root/crystallux/n8n/docker-compose.prod.yml logs -f n8n"
echo ""
