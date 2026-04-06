# Redis Security Setup Guide

Step-by-step instructions for enabling Redis password authentication in the Crystallux Docker stack without downtime.

---

## Why Enable Redis Authentication

By default, Redis has no password. Any container on the Docker network can read and write to it. Enabling a password ensures only n8n and its workers can access the queue.

---

## Prerequisites

- SSH access to your Hostinger VPS
- Current Crystallux stack running and healthy
- No active workflow executions (check n8n UI first)

---

## Step 1 — Generate a Strong Password

On your server, run:

```bash
openssl rand -base64 32
```

Copy the output. This is your Redis password.

---

## Step 2 — Add Password to .env

Open your `.env` file on the server:

```bash
nano /path/to/crystallux/.env
```

Add or update this line:

```
REDIS_PASSWORD=your-generated-password-here
```

Save and exit.

---

## Step 3 — Update docker-compose.yml

Open `docker-compose.yml` and make these three changes:

**A. Uncomment the Redis command:**

```yaml
redis:
  image: redis:7-alpine
  restart: always
  command: redis-server --requirepass ${REDIS_PASSWORD}
```

**B. Uncomment QUEUE_BULL_REDIS_PASSWORD in the n8n service:**

```yaml
n8n:
  environment:
    - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
```

**C. Uncomment QUEUE_BULL_REDIS_PASSWORD in the n8n-worker service:**

```yaml
n8n-worker:
  environment:
    - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
```

---

## Step 4 — Apply During Maintenance Window

Choose a time when no workflows are actively running (check n8n execution list).

```bash
cd /path/to/crystallux

# Stop all containers gracefully
docker compose down

# Verify all containers stopped
docker compose ps

# Start with new configuration
docker compose up -d

# Verify all containers are running
docker compose ps
```

---

## Step 5 — Verify Redis Authentication

Test that Redis now requires a password:

```bash
# This should FAIL with NOAUTH error
docker exec crystallux-redis-1 redis-cli PING

# This should succeed with PONG
docker exec crystallux-redis-1 redis-cli -a "your-password-here" PING
```

---

## Step 6 — Verify n8n Connectivity

1. Open n8n at https://automation.crystallux.org
2. Run any workflow manually (e.g. Pipeline Update)
3. Check it completes successfully
4. If it fails with Redis connection errors, check that `QUEUE_BULL_REDIS_PASSWORD` matches `REDIS_PASSWORD`

---

## Rollback If Something Goes Wrong

If n8n cannot connect to Redis after the change:

```bash
# Stop everything
docker compose down

# Comment out the Redis password lines in docker-compose.yml
# Remove REDIS_PASSWORD from .env (or leave it empty)

# Restart without password
docker compose up -d
```

---

## Troubleshooting

**n8n shows "Redis connection refused"**
- Check that all three uncommented lines use the same `${REDIS_PASSWORD}` variable
- Run `docker compose config` to verify the password is being interpolated

**Redis container keeps restarting**
- Check logs: `docker logs crystallux-redis-1`
- Ensure the `command:` line syntax is correct

**Workflows stuck in "waiting" state**
- The Redis queue was cleared on restart — this is expected
- Any workflows that were mid-execution will need to be re-triggered

---

## Security Notes

- Never commit the actual `.env` file to GitHub
- Rotate the Redis password quarterly
- The password only protects against other containers on the same Docker network
- For external access protection, ensure Redis port (6379) is NOT exposed in docker-compose (it is not by default)
