# Security sweep — 2026-05-20

Repo-wide grep for exposed secrets / hardcoded credentials. Triggered by Mary's final-push execution directive (Task 1).

## Result: CLEAN. No production credentials exposed.

### What was scanned

Pattern set across `workflows/**/*.json`, `**/*.html`, `**/*.js`, `**/*.md`, `**/*.sql`, `**/*.yml`, `**/*.yaml`, `.env*`, `scripts/**`:

- `sk-ant-api03-` (Anthropic), `sk_live_` / `pk_live_` / `sk_test_` (Stripe)
- `eyJhbGci…` (JWTs — Supabase service_role, n8n API tokens)
- `AKIA…` (AWS), `AIza…` (Google API), `ghp_` (GitHub PAT)
- `xoxb-` / `xoxp-` (Slack), `pm_` (Postmark), `key-` (Mailgun)
- `Authorization: Bearer <40+ chars>`, `password: "<8+ chars>"`, `service_role: "eyJ…"`

### What was found

| Pattern hit | File | Line | Verdict |
|---|---|---|---|
| `AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX` | `docs/setup/google-search-setup.md` | 32 | **PLACEHOLDER** ("it looks like…") — intentional template, no value |
| `password":"<test-password>"` | `docs/deployment/N8N_IMPORT_GUIDE.md` | 370 | **PLACEHOLDER** — `<test-password>` is the literal placeholder string in a curl example |

### `.env` status

The local `.env` on workstations contains real production keys (Anthropic, n8n admin JWT, Supabase service_role JWT, MARY_MASTER_TOKEN). This file is **correctly gitignored** and verified **never committed**:

```bash
$ git ls-files .env
(empty)
$ git log --all --oneline -- .env
(empty)
$ git ls-tree HEAD .env
(empty)
$ git check-ignore -v .env
.gitignore:69:.env	.env
```

The `.gitignore` already excludes `.env`, `.env.*`, with an `!.env.example` exception so the template file remains tracked.

### `.env.example` status

Tracked. Contains only template placeholders (`your-claude-api-key`, etc.) — no real secrets. Safe.

### Workflow JSON inspection

All n8n credential references use named credential vault entries (`Supabase Crystallux Custom`, `Anthropic Crystallux`, etc.) — no inline secrets. HTTP node `Authorization` header values are either:

- Empty strings (filled at runtime by the credential vault), or
- `{{ $env.XXX }}` template references

No inline `Bearer <jwt>` or `apikey: <secret>` literals found.

### HTML / JS inspection

Client-side code uses `clxApi.adminGet(…)` / `clxApi.call(…)` patterns that go through the webhook layer; no API keys embedded in client-side scripts.

### Docs inspection

Setup docs (`docs/setup/*.md`, `docs/deployment/*.md`) use placeholder syntax (`<your-key>`, `AIzaSy…XXX`) consistently. No accidentally-pasted real values.

## What this means

No remediation needed. The repo is safe to push to a public mirror without leaking credentials. The local `.env` on Mary's VPS and her workstation continues to hold real values — those should still be guarded as usual (file permissions, not stored in shared Dropbox, etc.) but nothing in source control is at risk.

If Mary suspects a key was ever leaked through another channel (Slack paste, chat log, third-party tool), rotate via:

- Anthropic: console.anthropic.com → API Keys → Rotate
- n8n: UI → Settings → API → revoke + create new
- Supabase: dashboard → Settings → API → generate new service_role key
- MARY_MASTER_TOKEN: `openssl rand -hex 32` → replace in n8n env vars
