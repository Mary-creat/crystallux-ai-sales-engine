# Phase 2a — Multi-Tenant Content Track

How a paying Crystallux client uses Component 1 with their own
persona, RLS-isolated, on a metered subscription.

## Pattern: client === client_id, persona_id is content scope

Each onboarded client gets at least one `personas` row scoped to their
`client_id`. The same `client_id` already gates every other `api/client/*`
webhook (overview, leads, campaigns, billing, etc.) — content
generation simply joins that fence.

```
clients.id  ◄────────────  personas.client_id  ◄────  content_pieces.persona_id
                                                   ◄────  platform_variants (via piece)
                                                   ◄────  distribution_log
                                                   ◄────  persona_usage_log.persona_id
                                                                          .client_id
```

Existing Crystallux RLS on `clients` flows transitively: a client
session only sees `personas` where `client_id=<session.client_id>`,
and from there only sees content/variants/logs whose `persona_id`
belongs to one of their personas.

## Onboarding flow (per client)

1. **Existing process unchanged:** Stripe subscription created, `clients`
   row provisioned by `clx-stripe-provision-v1`.
2. **New step (manual in Phase 2a):** admin inserts a persona row:
   ```sql
   INSERT INTO personas
     (persona_key, display_name, client_id, persona_type,
      tavus_replica_id, prompt_framing, monthly_tavus_minute_cap)
   VALUES
     ('client_acme_founder', 'John at Acme Roofing',
      '<acme_client_id>', 'client_owned',
      '<JOHN_REPLICA_ID>',
      'You are John, founder of Acme Roofing in Hamilton ON …',
      <pulled from clients.video_monthly_cap>);
   UPDATE clients SET default_persona_id = <new_persona_id>
     WHERE id = '<acme_client_id>';
   ```
3. **Client-side:** the client's dashboard exposes a "Generate Content"
   panel (Phase 2b client UI) that POSTs to `/content/generate` with
   their session token. The webhook resolves persona via session
   `client_id` join.
4. **Tavus replica:** each client trains their own. Phase 2a doesn't
   automate replica training — it's an onboarding-call concierge step.

## Auth model in `clx-video-content-generate` for client sessions

Same pattern as `api/client/clx-client-overview.json` (verified
against existing webhook):

```js
// Step 4 — Check Client (after Validate Session)
const row = $input.item.json[0];
if (row.user_role === 'admin') {
  // Internal personas: verify request persona is internal
  return { json: { ok: true, scope: 'admin', client_id: null } };
}
if (row.user_role === 'client' || row.user_role === 'team_member') {
  if (!row.client_id) return { json: { ok: false, status: 403, error: 'No client mapped to session' } };
  return { json: { ok: true, scope: 'client', client_id: row.client_id } };
}
return { json: { ok: false, status: 403, error: 'Insufficient role' } };

// Step 5 — Resolve Persona (with scope check)
//   admin scope:  any persona where client_id IS NULL
//   client scope: persona must have client_id = session.client_id
```

Cross-tenant attempt (client A requests persona belonging to client B)
returns 403; the resolve step compares `persona.client_id` against
session `client_id` before returning the persona row.

## Usage caps & metering hooks

Two layers, matching the existing `clients.video_monthly_cap` pattern:

### Soft cap (warning)
On insert into `persona_usage_log`, a Supabase trigger (NOT in this
migration — Phase 2c) checks rolling-30d sum vs. `personas.monthly_tavus_minute_cap`:
- ≤ 80% of cap: no action
- 80–99%: insert `admin_action_log` notice + email client primary contact
- ≥ 100%: continue but flag `cap_exceeded=true` (downstream UI shows warning)

### Hard cap (cutoff)
`clx-video-content-generate` runs a precheck before submitting Tavus:
```sql
SELECT
  p.monthly_tavus_minute_cap AS cap,
  COALESCE(SUM(u.tavus_minutes_used) FILTER (WHERE u.occurred_at > now() - interval '30 days'), 0) AS used
FROM personas p
LEFT JOIN persona_usage_log u ON u.persona_id = p.id
WHERE p.id = $persona_id
GROUP BY p.id;
```
If `used + estimated_for_this_request > cap × hard_cutoff_factor`
(default 1.10 for grace), respond `429 Too Many Requests` with
`error: 'monthly_cap_exceeded'`.

### Stripe metering (stubbed — Phase 2c)

Each `persona_usage_log` insert that has a `client_id` will fire a
Stripe metered usage event:
```
POST https://api.stripe.com/v1/billing/meter_events
  event_name: tavus_minutes_used
  payload:    { stripe_customer_id, value: <minutes>, persona_id, content_piece_id }
```

Phase 2a writes the row but **does not call Stripe**. The webhook
shape and dispatcher workflow are pre-stubbed in
`clx-video-content-generate` as a no-op node labeled
`Stripe Meter Hook (STUBBED — Phase 2c)`.

## Per-client adapter behavior

Client personas use the same shared adapter
(`clx-video-platform-adapt`) and platform publishers as internal
personas. No per-client adapter forks — the prompt framing on the
persona row is what differentiates output.

Future per-client customization (custom hashtag library, brand voice
overrides, branded thumbnail templates) goes into a new
`persona_distribution_overrides` table — Phase 2c, not 2a.

## Client dashboard surface (Phase 2b — out of scope tonight, scaffolded for design coherence)

Two new client-dashboard panels eventually expose:
- **Content Library** — list of `content_pieces` for the client's
  personas, filterable by status / persona / topic
- **Distribution Activity** — `distribution_log` entries with
  external_post_url and engagement counters

Both panels use existing `api/client/*` auth pattern, just two more
webhooks (`clx-client-content` and `clx-client-distribution`). Phase
2b ships these alongside the first paying client.

## Week 4 success criteria (first paying client onboarded)

- [ ] One real `clients` row with `subscription_status='active'`
- [ ] One client-owned `personas` row with their replica_id
- [ ] Client successfully generates first content_piece via dashboard
- [ ] Client publishes to at least one platform
- [ ] Tavus minutes reconciled into persona_usage_log
- [ ] Stripe metering hook fires (still stubbed in Phase 2a — verify
      in Phase 2c when actually wired)

## Out of scope for Week 4

- Self-service replica training (still concierge for first 5 clients)
- Bulk content generation (one-at-a-time only in Phase 2a)
- Automated content_piece → lead bridging on the client side
  (matches Phase 2b broker-track work)
- Per-client brand overrides on adapters
