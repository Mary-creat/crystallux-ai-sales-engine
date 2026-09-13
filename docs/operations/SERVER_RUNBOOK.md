# Server runbook — read this before touching the VPS

**Written 2026-09-12, after a near-miss.** Everything here was verified
against the running server, not assumed from this repository.

If you are new to this project, read the three red boxes first. They are the
commands that look routine and are not.

---

## 🚨 1. Never run `docker compose up -d` on its own

There are **two** compose files in `/root/crystallux/n8n`:

| File | What it is |
|---|---|
| `docker-compose.yml` | **Empty. A decoy.** Defines nothing. |
| `docker-compose.prod.yml` | **The real one.** This is what created the running container. |

Confirmed from the container's own labels:

```
com.docker.compose.project.config_files: /root/crystallux/n8n/docker-compose.prod.yml
com.docker.compose.project.working_dir:  /root/crystallux/n8n
```

`docker compose` defaults to `docker-compose.yml`. Running it plainly points
Docker at the empty file — which can recreate or remove the n8n container
**without the ~50 environment variables it needs to function**. Anthropic,
Stripe, Twilio, Postmark, HeyGen, Apollo and the internal secrets all live in
that environment. Losing them stops research, scoring, billing and messaging
at once.

**Always name the file:**

```bash
cd /root/crystallux/n8n
docker compose -f docker-compose.prod.yml up -d
```

The empty `docker-compose.yml` has been left in place on purpose — deleting
it on a live server is its own risk — but it should be removed or renamed
during the next planned maintenance window.

---

## 🚨 2. `N8N_ENCRYPTION_KEY` is not an API key

It decrypts every credential n8n has stored. Change it and **every saved
credential becomes unreadable** — Supabase, Gmail, Anthropic, Twilio, all of
them — and they cannot be recovered, only re-entered by hand.

Do not rotate it. Do not "tidy" it. Do not confuse it with `N8N_API_KEY`,
which is the management API token and is safe to rotate.

---

## 🚨 3. Outbound is disarmed, and that is deliberate

Four workflows can reach a real person's inbox. All four check a single
switch in the database before sending:

```sql
SELECT * FROM v_outbound_arming;   -- four rows, armed = false
```

It is flipped from **admin.crystallux.org → Settings**, never by editing
workflows. If you are testing and "nothing sends", check this first — it is
almost certainly working as designed.

Turning it on means real email to real businesses. That is the owner's
decision, not a developer's.

---

## Where everything actually lives

| Thing | Location |
|---|---|
| n8n container | `/root/crystallux/n8n`, container name `n8n` |
| Compose file | `docker-compose.prod.yml` (**not** `docker-compose.yml`) |
| Environment variables | `/root/crystallux/n8n/.env` |
| n8n data (workflows, credentials) | Docker volume `n8n_data` — survives restarts |
| Redis | container `crystallux-redis` |
| Database | Supabase, project `zqwatouqmqgkmaslydbr` |
| Workflow definitions | this repo, `workflows/` — 326 JSON files |
| Dashboards | Cloudflare Pages, built from `main` |

---

## Adding or changing an environment variable

```bash
cd /root/crystallux/n8n
nano .env
```

In `.env` the format is bare — no dash, no indent, no quotes:

```
MCP_WEBHOOK_SECRET=abc123...
```

Save with **Ctrl+O**, **Enter**, **Ctrl+X**, then:

```bash
docker compose -f docker-compose.prod.yml up -d
docker exec n8n printenv | grep MCP_WEBHOOK_SECRET
```

The verification step is not optional. A variable that silently failed to
load is indistinguishable from a broken feature, and this project has lost
weeks to exactly that — see "the name-mismatch family" below.

To list what the container actually has, **without printing secrets**:

```bash
docker exec n8n printenv | cut -d= -f1 | sort
```

That single command has been more accurate than the documentation every
time it has been run.

---

## Deploying workflow changes

You do not copy JSON to the server by hand.

1. Commit and push to `main`
2. GitHub Actions validates all 326 workflows and both migration folders
3. The deploy job updates changed workflows **in place, by id**

Two deliberate limits:

- **It never creates.** A brand-new workflow file will not appear in n8n; it
  must be imported once by hand, and its credentials re-selected, because
  credentials never travel inside a workflow file.
- **It never activates.** Activation is per-client and per-tier and is the
  owner's call.

**The nine protected workflows are skipped on an ordinary push.** To deploy
one, use Actions → *Crystallux CI/CD Pipeline* → **Run workflow**, set
`allow_protected` to `true`, and list the files in `files`.

---

## Migrations

SQL is **never** applied automatically. Files land in `db/migrations/`, and
the owner pastes them into the Supabase SQL editor. Validate before asking:

```bash
python scripts/validate-migrations.py db/migrations/your-file.sql
```

Write every migration to be safe to run twice — `IF NOT EXISTS`,
`WHERE NOT EXISTS`, `CREATE OR REPLACE`. It will be run twice eventually.

---

## The name-mismatch family — the bug this codebase keeps growing

Five instances found in one week. Each looked like a broken feature and was
a variable name:

| Reader expected | Server actually had |
|---|---|
| `MCP_API_KEY` (Copilot) | `MCP_WEBHOOK_SECRET` (gateway) |
| `POSTMARK_SERVER_TOKEN` ×3 | `POSTMARK_API_TOKEN` |
| `$vars.POSTMARK_SERVER_TOKEN` | — (a third mechanism entirely) |
| `autonomy_level` column | a key inside `escalation_rules` JSON |
| `followup_scheduled_at` | `next_followup_scheduled_at` was written |

**Before concluding a feature is broken, check the name.** And before adding
a variable, check what the container already has.

---

## Things that report success while doing nothing

This estate has a recurring failure shape: a green run that achieved
nothing. Known instances, all now fixed, all worth recognising the pattern:

- The **email scraper** ran hourly for four months with `dry_run` hardcoded
  `true`, finding emails and discarding every one.
- **`scan_city`** replied *"City scan queued"* and wrote no row.
- **Discovery** fetched each business's website and wrote it into a prose
  note instead of the `website` column, so the scraper could never see it.
- The **deploy job** once POSTed every workflow on every push and reported
  success while creating duplicates.
- **Signal detection** stamps `lead_status = 'Signal Detected'` on leads with
  no signal (live drift, still open).

When something "works but nothing happens", assume this shape first.

---

## The content-type family — a 200 that arrives unreadable

On 2026-09-12 nobody could sign in to any dashboard. The password was
right, the server wrote a session every time, and the browser was sent
straight back to the login page.

`clx-auth-validate-session` fetches the account profile from
`v_auth_users_access`. It asked for `Accept: application/vnd.pgrst.object+json`,
which is the correct PostgREST way to get one row instead of a
one-element array. PostgREST honours it and returns that string as the
**Content-Type**. n8n parses a body as JSON only for content types it
recognises, and that is not one of them, so the row arrived as text under
`data`. HTTP 200. Correct body. Unreadable.

Then the second fault: the gate treated a profile it could not read as a
profile that said `email_verified: false, products: []`, and still
answered `ok: true`. The dashboard believed it and redirected to
`/verify-email` — which could never help, because verifying writes to a
database nobody was reading. Every account was affected, `info@crystallux.org`
included.

**The rules this leaves behind:**

1. If an HTTP node asks for a vendor content type (`application/vnd.*`),
   set the node's response format to JSON explicitly. Do not assume the
   caller parses what the server sends.
2. A fetch that did not happen is not the same fact as a field that is
   false. Never substitute a default for a security-gate field. Fail with
   a name the caller can show a human.
3. Normalise the response shape before reading a field from it — row,
   `[row]`, `{data: {...}}`, `{data: "..."}`. The shape of a response
   must never decide whether somebody can sign in.
4. When a responder rebuilds its body by hand, check it forwards the
   status and reason it was given. `Respond Denied` here mapped every
   status to 401/403, so a 503 server fault reached the browser dressed
   as "sign in again".

Covered by `tests/agent/validate-session.test.js` (15 cases) and
`tests/agent/dashboard-auth.test.js` (12).

## Health checks

```bash
# n8n reachable
curl -s -o /dev/null -w '%{http_code}\n' https://automation.crystallux.org/webhook/admin/outbound-arming -X POST -d '{}' -H 'Content-Type: application/json'
# 401 = healthy (it is refusing an unauthenticated call)

# container up
docker ps --filter name=n8n

# recent logs
docker logs n8n --tail 100
```

For Supabase: an instant `401` on a bad key means the gateway is healthy.
A **504 on a good key** means PostgREST cannot reach Postgres — that is the
connection pool, and it does not recover on its own. Restart the project
from the Supabase dashboard.

---

## What a new developer should read, in order

1. This file
2. `CLAUDE.md` — the working agreement and what must not be touched
3. `docs/architecture/PROJECT_MASTER_COMPLETION.md` — what is actually
   finished, with the evidence for each claim
4. `docs/architecture/ARCHITECTURE_DOCTRINE.md` — decisions already made

Then, before building anything, check whether it exists. The estate is 326
workflows and 213 database tables, and the most common mistake here is
building a second copy of something that is already there — usually because
the first copy was silently broken rather than absent.
