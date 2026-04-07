# Crystallux Server Infrastructure Guide

Production infrastructure setup for the Crystallux n8n instance on Hostinger VPS.

---

## Server Specs

| Component | Value |
|-----------|-------|
| OS | Ubuntu 24.04.4 LTS |
| CPU | 2 cores |
| RAM | 8 GB |
| Disk | 96 GB |
| Docker | 28.2.2 |
| n8n | latest (auto-updated) |
| Domain | automation.crystallux.org |
| SSL | Managed externally (Hostinger/Cloudflare) |

---

## Architecture

```
Internet → HTTPS (Hostinger/Cloudflare) → Port 5678 → n8n container
                                                        ↓
                                                    Redis container
                                                        ↓
                                                    n8n_data volume (SQLite + credentials)
```

Both containers are managed by Docker Compose. Redis is ready for worker queues when you scale.

---

## Quick Setup (First Time)

### Step 1 — Upload files to server

From your local machine, copy the scripts to the server:

```bash
scp scripts/docker-compose.prod.yml root@YOUR_SERVER_IP:/root/crystallux/n8n/
scp scripts/backup.sh root@YOUR_SERVER_IP:/root/crystallux/backups/
scp scripts/healthcheck.sh root@YOUR_SERVER_IP:/root/crystallux/monitoring/
scp scripts/update.sh root@YOUR_SERVER_IP:/root/crystallux/n8n/
scp scripts/server-setup.sh root@YOUR_SERVER_IP:/root/crystallux/n8n/
```

### Step 2 — SSH into server and run setup

```bash
ssh root@YOUR_SERVER_IP
cd ~/crystallux/n8n
bash server-setup.sh
```

The script will:
1. Install Docker Compose plugin
2. Back up current n8n data
3. Read your encryption key from the running container
4. Create `.env` file with the key
5. Stop the old container and start the new Compose stack
6. Install backup and health check cron jobs

### Step 3 — Verify

```bash
docker compose -f docker-compose.prod.yml ps
```

You should see `n8n` and `crystallux-redis` both running and healthy.

---

## Daily Operations

### View n8n logs
```bash
cd ~/crystallux/n8n
docker compose -f docker-compose.prod.yml logs -f n8n
```

### View health check log
```bash
tail -20 ~/crystallux/monitoring/health.log
```

### View backup log
```bash
tail -20 ~/crystallux/backups/backup.log
```

### List backups
```bash
ls -lh ~/crystallux/backups/n8n_data_*.tar.gz
```

---

## Update n8n

```bash
bash ~/crystallux/n8n/update.sh
```

This creates a backup first, then pulls the latest image and recreates the n8n container. Downtime: ~10 seconds.

---

## Restore from Backup

If something goes wrong:

```bash
# Stop n8n
cd ~/crystallux/n8n
docker compose -f docker-compose.prod.yml down

# Delete current data
docker volume rm n8n_data
docker volume create n8n_data

# Restore from backup
docker run --rm \
  -v n8n_data:/target \
  -v /root/crystallux/backups:/backup \
  alpine sh -c "cd /target && tar xzf /backup/n8n_data_YYYY-MM-DD_HHMM.tar.gz"

# Start n8n
docker compose -f docker-compose.prod.yml up -d
```

Replace `YYYY-MM-DD_HHMM` with the backup timestamp you want to restore.

---

## Scaling (When Ready)

When you need to scale (10+ clients, 500+ executions/day):

### Add n8n Worker
Add to `docker-compose.prod.yml`:

```yaml
  n8n-worker:
    image: n8nio/n8n:latest
    container_name: n8n-worker
    command: worker
    restart: always
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
    depends_on:
      - redis
      - n8n
```

And change `EXECUTIONS_MODE=regular` to `EXECUTIONS_MODE=queue` in the n8n service.

### Add Redis Authentication
See `docs/setup/redis-security.md` for step-by-step instructions.

---

## File Locations on Server

```
~/crystallux/
├── n8n/
│   ├── docker-compose.prod.yml    # Docker Compose stack
│   ├── .env                        # Encryption key (chmod 600)
│   ├── update.sh                   # Update script
│   └── encryption_key.txt          # Key backup (legacy)
├── backups/
│   ├── backup.sh                   # Backup script
│   ├── backup.log                  # Backup log
│   └── n8n_data_*.tar.gz           # Daily backups (7 days)
└── monitoring/
    ├── healthcheck.sh              # Health monitor
    └── health.log                  # Health log
```
