# Operations Assistant Vision (a.k.a. the Admin Copilot ✦)

> **Honest status (2026-05-13):** what you might call the "Operations Assistant" is **already built** and lives in this repo as the **Admin Copilot ✦**. It is currently dormant — needs activation per `docs/audit/blockers.md` section 6. This document explains what it does, when to activate it, where its current limits are, and what to add later.

## What you have today (built, dormant)

A conversational AI layer embedded directly in `admin.crystallux.org`. Opens via the **✦ FAB** in the bottom-right of every admin page, or with `Ctrl+K` / `Cmd+K`. Admin-only (hidden for client + insurer sessions).

**4 capabilities:**

| Capability | What you ask | What it does |
|---|---|---|
| **Database query** | "How many policies issued this month?" | Claude writes a safe `SELECT`, server runs it via the `admin_execute_select` RPC, result renders as a table / scalar / chart. |
| **Troubleshoot error** | "Why did scan_error #abc fail?" | Claude reads recent `scan_errors`, diagnoses root cause, suggests a fix. Can auto-call `mark_error_resolved` after your confirmation. |
| **Platform Q&A** | "Which workflow handles no-show recovery?" | Claude answers grounded in the OPERATIONS_HANDBOOK + ROADMAP + workflow source. Never invents capabilities. |
| **Voice input** | (click mic, speak 60s) | Audio → Whisper → transcript auto-populates the chat box for review. |

**Spec lives at:** `docs/architecture/OPERATIONS_HANDBOOK.md` §22.

## Architecture (short version)

```
┌─ admin-dashboard ────────────────────────────────────────────────┐
│  ✦ FAB (shared/copilot.js)                                       │
│  ↓                                                                │
│  POST /webhook/copilot/{query, troubleshoot, platform, transcribe}│
└──────────────┬───────────────────────────────────────────────────┘
               ▼
┌─ n8n workflows ──────────────────────────────────────────────────┐
│  clx-copilot-query-v1        Claude Sonnet → SELECT → execute    │
│  clx-copilot-troubleshoot-v1 Claude Sonnet + scan_errors lookup  │
│  clx-copilot-platform-v1     Claude Sonnet + handbook RAG        │
│  clx-copilot-whisper-v1      OpenAI Whisper transcription        │
└──────────────┬───────────────────────────────────────────────────┘
               ▼
┌─ Supabase ───────────────────────────────────────────────────────┐
│  admin_execute_select RPC    SELECT-only, validated, audited     │
│  mark_error_resolved RPC     write op gated to error mark-as-fixed│
│  admin_action_log            every prompt + result logged        │
└──────────────────────────────────────────────────────────────────┘
```

## Safety guardrails (already in code)

1. **Admin-token required.** Every webhook validates the request against `MARY_MASTER_TOKEN` (env var) before Claude is invoked. Wrong token = 401.
2. **Read-only default.** Database access is locked to `SELECT` at two layers:
   - The workflow's prompt instructs Claude to produce only `SELECT` statements + rejects anything containing `INSERT/UPDATE/DELETE/DROP/ALTER`.
   - The `admin_execute_select` RPC re-validates the SQL with a regex blacklist + requires a `LIMIT` clause. Defence in depth — even if Claude jailbreaks the prompt, the database refuses.
3. **Write requires explicit confirmation.** Only ONE write RPC is exposed: `mark_error_resolved`. It is suggest-only; the UI shows the proposed action and waits for you to click "Confirm" before executing.
4. **All actions logged.** Every prompt + generated SQL + result summary + success/error written to `admin_action_log`. Regulatory-quality audit trail.
5. **Rate-limited.** Soft cap ~100 queries/day before Anthropic rate limits kick in. Adjustable.
6. **Secrets never leak.** System prompts explicitly forbid Claude from echoing credentials or raw API keys. The query workflow never receives `.env` access.
7. **Client isolation preserved.** The ✦ FAB is injected only into `admin-dashboard/` — never into `client-dashboard/`, `insurance-mga-dashboard/`, `insurer-dashboard/`. Verified by CSP + role checks on every page load.

## Cost

| Component | Per call | Typical month (30–60 queries/day) |
|---|---|---|
| Claude Sonnet (query / troubleshoot / platform) | $0.003 – $0.015 | $15 – $40 |
| OpenAI Whisper (per minute of audio) | ~$0.006 | $5 – $10 |
| **Total typical** | | **$20 – $50** |

Negligible at solo-founder volume. Stays under $100/mo even at heavy daily use.

## When to activate

**Activate now if** you want to:
- Query "how many of X today" from any admin page without opening Supabase Studio.
- Diagnose a `scan_errors` row in 2 questions instead of a 20-minute browser dive.
- Ask "what does workflow Y do" and get an honest answer grounded in the handbook.
- Use voice during a busy day instead of typing.

**Activation steps** (the durable version is `docs/audit/blockers.md` §6):

1. Apply migration `docs/architecture/migrations/2026-04-24-admin-copilot.sql` to Supabase.
2. Add `OPENAI_API_KEY` and confirm `ANTHROPIC_API_KEY` are in `/root/crystallux/n8n/.env`.
3. Restart n8n container.
4. In n8n UI → Credentials → create:
   - `Anthropic API` (HTTP Header Auth, `x-api-key` = `{{ $env.ANTHROPIC_API_KEY }}`)
   - `OpenAI` (HTTP Header Auth, `Authorization` = `Bearer {{ $env.OPENAI_API_KEY }}`)
5. Open each of the 4 Copilot workflows + bind credentials to Claude/OpenAI HTTP nodes.
6. Activate all 4 workflows (`active=true`).
7. Visit `admin.crystallux.org/pages/overview.html?token=<MARY_MASTER_TOKEN>` once — token caches in localStorage. The ✦ FAB appears bottom-right. Press `Ctrl+K`.

**Total time: ~30 minutes.** No code changes needed.

## When NOT to use the Operations Assistant

The Operations Assistant is excellent at **read-only diagnosis + Q&A**. It is **bad at**:

- **Multi-step deployment work** (run a migration, restart a container, deploy a frontend). Use Claude Code locally for that — it has access to your repo + can write commits.
- **Things requiring SSH** (n8n container restart, log inspection). Use a terminal directly.
- **Strategic decisions** (pricing, hiring, partnerships). Those route through this handbook's Section 7 (Decision Frameworks).
- **Multi-turn complex reasoning** (the Copilot is a single-shot per webhook today — see "Future work" below).

Decision rule: **if the answer is a SELECT, use the Copilot. If the answer requires WRITE / SSH / multi-step work, use Claude Code or a terminal.**

## Future work (already scoped, not yet built)

Per `docs/architecture/OPERATIONS_HANDBOOK.md` §22 "Future work":

1. **Persistent multi-turn memory.** Today every Copilot interaction is single-shot. Multi-turn would let you say "now group those results by month" without re-stating the original query. ~6–8 hours of build.
2. **Inline chart rendering.** Today scalar / table results are rendered; bar/line/pie charts for time-series queries would be an upgrade. ~4 hours.
3. **Suggested follow-up questions.** Claude proposes "did you also want to see…?" prompts based on the current result. ~3 hours.
4. **Voice output (TTS).** Read responses aloud via ElevenLabs. ~5 hours.
5. **Saved queries.** Bookmark common queries (e.g., "monthly_production_today") for one-click rerun. ~4 hours.
6. **Whitelisted write actions.** Right now only `mark_error_resolved` is auto-executable. Add a curated allowlist of safe writes (assign lead to advisor, mark booking confirmed, activate workflow) gated by per-action confirmation. ~10 hours.
7. **Client-side Copilot.** The CLIENT_COPILOT_SPEC.md ports the same pattern to client-dashboard for self-serve customer support. Foundation built; needs the 2 client copilot workflows finished. ~4–6 hours.

**Build budget when ready:** the items above total 30–40 hours. Most-valuable-first order: 1 → 6 → 2 → 5 → 3 → 4 → 7.

## When to invest in the next iteration

Don't build any of the future-work items until **you've used the dormant Admin Copilot for 1–2 weeks of real operations** and can name specifically which limitation you hit most. Premature investment in features you haven't validated burns build cycles. The 30-minute activation gives you 80% of the value; the rest is incremental.

## Cross-references

- [`docs/architecture/OPERATIONS_HANDBOOK.md`](../architecture/OPERATIONS_HANDBOOK.md) §22 — full Admin Copilot spec.
- [`docs/audit/blockers.md`](../audit/blockers.md) §6 — activation checklist.
- [`docs/architecture/CLIENT_COPILOT_SPEC.md`](../architecture/CLIENT_COPILOT_SPEC.md) — sibling client-side assistant spec.
- [`admin-dashboard/shared/copilot.js`](../../admin-dashboard/shared/copilot.js) — the actual frontend.
- [`workflows/clx-copilot-query-v1.json`](../../workflows/clx-copilot-query-v1.json), `clx-copilot-troubleshoot-v1.json`, `clx-copilot-platform-v1.json`, `clx-copilot-whisper-v1.json` — the 4 backend workflows.
- [`docs/architecture/migrations/2026-04-24-admin-copilot.sql`](../architecture/migrations/2026-04-24-admin-copilot.sql) — backing tables + RPCs.
