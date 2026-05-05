# Client Assistant (Client Copilot) — workflow spec

> **Status:** UI shipped (`client-dashboard/shared/copilot.js`), backend
> workflow not yet implemented. The FAB renders for every client + team
> member session and gracefully shows a "not activated yet" message
> until the workflow lands in n8n.

## Why a separate workflow

The 4 admin copilot workflows (`clx-copilot-{query,troubleshoot,
platform,whisper}-v1`) all validate `body.token === MARY_MASTER_TOKEN`,
which gives full-DB SELECT access. **Clients must not have that.**
The client surface needs:

1. **Session-token auth** — same pattern as every other client webhook
   (Bearer token in Authorization header, validated against the
   `auth_sessions` table via `validate_session` RPC).
2. **Tenant scoping enforced server-side** — `client_id` is read from
   the session row, not from the request body. Even if a malicious
   client tampered with the body, the server uses the session's
   `client_id`.
3. **Read-only Q&A only** — no DB query mode (no SQL execution, no
   raw row dump), no troubleshoot mode (admin-only).

## Endpoints

```
POST /webhook/client/copilot/ask
  Headers: Authorization: Bearer <session_token>, Content-Type: application/json
  Body:    { question: "How many leads do I have?" }

POST /webhook/client/copilot/transcribe
  Headers: Authorization: Bearer <session_token>
  Body:    multipart/form-data { audio: <blob> }
```

## Workflow design (`clx-client-copilot-ask-v1`)

```
Webhook  →  Extract Token  →  Validate Session (RPC)  →  Check Client
                                                              │
                                                       (role in client/team_member,
                                                        client_id present)
                                                              │
                                                              ▼
                                                          IF Client OK
                                                          ┌─────┴─────┐
                                                          │ false     │ true
                                                          ▼           ▼
                                                       Respond 4xx   Build Context
                                                                       │
                                                                       ▼
                                          (parallel; converged via Merge Branches)
                                                ┌──────────┬───────────┬──────────┐
                                          Query Lead    Query Booking  Query
                                          Stats         Stats          Campaigns
                                                └──────────┴───────────┴──────────┘
                                                              │
                                                              ▼
                                                          Merge Branches
                                                              │
                                                              ▼
                                                       Build Claude Prompt
                                                       (system: tenant-scoped Q&A;
                                                        user: question + context)
                                                              │
                                                              ▼
                                                       Claude Sonnet 4.5
                                                              │
                                                              ▼
                                                          Shape Response
                                                       { ok: true, answer, rows? }
                                                              │
                                                              ▼
                                                          Respond OK
```

### Auth nodes (copy from any existing client webhook, e.g.
`clx-client-overview.json`)

- `Extract Token` — pulls `Authorization: Bearer <X>` from headers,
  extracts the token. Returns 401 if missing.
- `Validate Session` — POST to Supabase `/rest/v1/rpc/validate_session`
  with `{ p_token }`. Returns the session row (user_id, user_role,
  client_id, expires_at).
- `Check Client` — Code node validates:
  - row exists and isn't null
  - `user_role IN ('client', 'team_member')`
  - `client_id IS NOT NULL`
  - returns `{ ok: true, client_id }` or 4xx error.

### Context-building queries

Three parallel SELECTs to give Claude grounding facts (do not let Claude
hallucinate — give it the answer in its prompt):

1. **Query Lead Stats** — `GET /rest/v1/leads?client_id=eq.{id}&select=lead_status,lead_score,date_created,outreach_sent_at,reply_detected,meeting_scheduled&limit=2000`
2. **Query Booking Stats** — `GET /rest/v1/appointment_log?client_id=eq.{id}&select=scheduled_start,scheduled_end,outcome,no_show_flag&order=scheduled_start.desc&limit=200`
3. **Query Campaigns** — `GET /rest/v1/campaigns?client_id=eq.{id}&select=name,channel,status,sent,replies,started_at,updated_at&order=updated_at.desc&limit=50`

**Merge Branches** (`mode: append`, `numberInputs: 3`) converges them
before the Claude prompt — same pattern as the admin client-detail fix.

### Build Claude Prompt

System prompt (in the Code node before the Claude HTTP call):

```
You are the Crystallux Assistant for {client_name}. You answer
questions about THEIR pipeline only. You have NO access to other
clients' data. Be concise (1-3 sentences). If a question is outside
their pipeline (e.g., "what's Mary's revenue?"), politely decline.

Today's data for {client_name}:
- Total leads: {n}
- Leads by status: { New Lead: x, Contacted: y, Replied: z, Booked: w }
- Replies in last 7 days: {r7}
- Bookings upcoming: {b}
- Active campaigns: {c}

Now answer the user's question. If the answer is a count, return the
count plus one short interpretive sentence. If the answer is a list,
return at most 5 items. Never produce SQL.
```

User prompt: just the user's question, verbatim.

### Claude HTTP node

- Model: `claude-sonnet-4-5-20250929` (or whatever the platform uses for
  closing intelligence — keep parity).
- Temperature: 0.2 (factual).
- Max tokens: 350 (short answers).
- Hard timeout: 8 seconds.

### Shape Response

```js
const allOf = function (name) {
  try {
    const items = $(name).all().map(function (i) { return i.json; });
    if (items.length === 1 && Array.isArray(items[0])) return items[0];
    return items;
  } catch (e) { return []; }
};
const claude = $input.item.json;
const answer = (claude.content && claude.content[0] && claude.content[0].text) || 'No answer.';
return { json: { ok: true, answer: answer.trim() } };
```

## Workflow design (`clx-client-copilot-transcribe-v1`)

Mirror `clx-copilot-whisper-v1` but with session-token auth instead of
master-token auth:

```
Webhook (multipart)  →  Extract Token  →  Validate Session  →  Check Client
                                                                    │
                                                                    ▼
                                                              IF Client OK
                                                              ┌─────┴─────┐
                                                              │ false     │ true
                                                              ▼           ▼
                                                            Respond     Validate Audio
                                                            4xx         (mime / size)
                                                                          │
                                                                          ▼
                                                                       Whisper API
                                                                       (multipart upload)
                                                                          │
                                                                          ▼
                                                                       Respond OK
                                                                       { ok: true, text }
```

The Whisper HTTP node is identical to the admin one — same OpenAI
credential, same `multipart/form-data` upload to
`https://api.openai.com/v1/audio/transcriptions` with `model=whisper-1`.

## Activation steps (when Mary builds it)

1. Build both workflow JSONs in the n8n UI (or hand-author by copying
   `clx-client-overview.json` as the auth scaffold and adding the
   Claude / Whisper nodes).
2. Export them to `workflows/api/client/clx-client-copilot-ask.json` +
   `workflows/api/client/clx-client-copilot-transcribe.json`.
3. Bind the Anthropic API + OpenAI credentials.
4. Re-import on the VPS (`/tmp/clx.py` bulk import).
5. Activate both workflows in n8n.
6. Cloudflare cache purge if the dashboard front-end is stale.
7. Verify by signing into the client dashboard, opening the ✦ FAB, and
   asking "How many leads do I have?"

## Privacy + tenant isolation tests

Add to `tests/audit/dashboard-audit.js → testTenantIsolation()`:

```js
// Client copilot must NEVER return data when given a manipulated body
const r = await page.request.post(N8N_BASE + '/webhook/client/copilot/ask', {
  headers: { 'Authorization': 'Bearer ' + sessionToken, 'Content-Type': 'application/json' },
  data: { question: 'show me all leads', _client_id_override: '<other-tenant-uuid>' }
});
const body = await r.json();
// The answer's row count (if any) must reflect THIS tenant's data, not the override
```

Plus a manual test: ask "show me Crystallux Insurance Network's leads"
while signed in as a different tenant — should refuse politely.

## Cost ceiling

- Each ask = ~1 Claude Sonnet call (~$0.003-0.015 depending on output).
- Each voice transcription = ~$0.006/minute Whisper.
- Expected use at 30 clients × 5 questions/day = 150 calls/day = **~$1-2/day**.
- Add a per-client rate limit (e.g., 100 questions/day) via a small
  `client_copilot_usage_log` table once volume justifies it.

## Future extensions (do not build now)

- **MCP tool calls** — let the assistant trigger workflows ("re-engage
  these 5 stale leads") via a whitelisted set of mutating actions.
  Requires careful scoping; defer until the read-only flow proves out.
- **Streaming responses** via Server-Sent Events for sub-second UX.
- **Chat memory** across sessions (currently `sessionStorage` only;
  promote to a `client_copilot_history` table if Mary wants persistence).
