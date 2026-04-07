#!/bin/bash
# Crystallux Health Monitor
# Checks n8n is responding, auto-restarts if down
#
# Install via cron:
#   crontab -e
#   */5 * * * * /root/crystallux/monitoring/healthcheck.sh >> /root/crystallux/monitoring/health.log 2>&1

LOG_DIR="/root/crystallux/monitoring"
TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)
N8N_URL="http://localhost:5678/healthz"
MAX_RETRIES=2

check_health() {
  wget --spider -q --timeout=10 "$N8N_URL" 2>/dev/null
  return $?
}

# First check
if check_health; then
  # Healthy — log only every hour (on the hour) to avoid log bloat
  MINUTE=$(date +%M)
  if [ "$MINUTE" = "00" ]; then
    echo "[$TIMESTAMP] OK — n8n is healthy"
  fi
  exit 0
fi

# First check failed — wait 10 seconds and retry
echo "[$TIMESTAMP] WARNING — n8n health check failed, retrying in 10s..."
sleep 10

if check_health; then
  echo "[$TIMESTAMP] OK — n8n recovered on retry"
  exit 0
fi

# Both checks failed — restart the container
echo "[$TIMESTAMP] CRITICAL — n8n is unresponsive, restarting container..."

# Try docker compose first, fall back to docker restart
if [ -f /root/crystallux/n8n/docker-compose.prod.yml ]; then
  cd /root/crystallux/n8n
  docker compose -f docker-compose.prod.yml restart n8n
else
  docker restart n8n
fi

# Wait for startup
sleep 30

# Verify recovery
if check_health; then
  echo "[$TIMESTAMP] RECOVERED — n8n restarted successfully"
else
  echo "[$TIMESTAMP] FATAL — n8n failed to recover after restart!"
fi
