#!/bin/bash
# Crystallux Automated Backup Script
# Backs up n8n_data volume daily, keeps last 7 days
#
# Install via cron:
#   crontab -e
#   0 2 * * * /root/crystallux/backups/backup.sh >> /root/crystallux/backups/backup.log 2>&1

BACKUP_DIR="/root/crystallux/backups"
TIMESTAMP=$(date +%Y-%m-%d_%H%M)
BACKUP_FILE="$BACKUP_DIR/n8n_data_$TIMESTAMP.tar.gz"
KEEP_DAYS=7

echo "[$TIMESTAMP] Starting n8n backup..."

# Create backup from the n8n_data volume
docker run --rm \
  -v n8n_data:/source:ro \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf "/backup/n8n_data_$TIMESTAMP.tar.gz" -C /source .

if [ $? -eq 0 ]; then
  SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "[$TIMESTAMP] Backup complete: $BACKUP_FILE ($SIZE)"
else
  echo "[$TIMESTAMP] ERROR: Backup failed!"
  exit 1
fi

# Rotate old backups — keep last 7 days
find "$BACKUP_DIR" -name "n8n_data_*.tar.gz" -mtime +$KEEP_DAYS -delete
REMAINING=$(ls -1 "$BACKUP_DIR"/n8n_data_*.tar.gz 2>/dev/null | wc -l)
echo "[$TIMESTAMP] Backups retained: $REMAINING"
