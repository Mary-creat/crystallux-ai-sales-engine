# Phase 2a — Rollout Plan

Four weeks. Revenue-first ordering: Mary's broker book before any
marketing content, marketing content before the first paying SaaS
client, first paying SaaS client before generalized self-service.

> **Gate before any of this:** Mary reviews and confirms the seven
> open questions in [`99-open-questions.md`](./99-open-questions.md).
> Migration apply, persona seed updates, and stub-workflow imports
> are all blocked on that review.

## Week 1 — Mary the Broker (Real Revenue)

**Goal:** 5–10 personalized outreach videos for Mary's live insurance
prospects. Real bookings against real people.

| Day | Action | Owner |
|---|---|---|
| Mon | Morning Q&A review on `99-open-questions.md` | Mary + Claude |
| Mon | Apply `2026-05-02-phase-2a-foundation.sql` to Supabase | Mary |
| Mon | Activate the 25 imported auth/admin/client webhooks | Mary |
| Tue | Tavus account + replica training started | Mary |
| Wed | Replica training completes; `personas.tavus_replica_id` set | Mary |
| Wed | Activate `clx-video-content-generate` and `clx-video-tavus-status-poll` (only) | Mary |
| Thu | First broker content_piece generated end-to-end (not yet outreach-bridged — sanity check) | Mary |
| Thu | Bridge first 3 leads manually (`UPDATE leads SET content_piece_id=…, lead_status='Campaign Assigned'`) | Mary |
| Thu | Activate `clx-outreach-generation-v2` and `clx-outreach-sender-v2` | Mary |
| Fri | First outreach fires; first reply or first booking | system |
| Fri | Reconcile `persona_usage_log` against Tavus dashboard for billing accuracy | Mary |

**Phase 2a Component 1 workflows activated this week:**
`clx-video-content-generate`, `clx-video-tavus-status-poll`. Nothing
else from the api/video folder yet.

**Out-of-scope this week:** platform adapters, distribution workflows,
builder track, multi-tenant.

**Risk to manage:** the existing `clx-video-outreach-v1` (personalized
outreach Tavus pipeline) remains dormant. Do **not** activate it the
same week as Component 1 — keep one Tavus consumer at a time during
initial bedding-in to keep blast radius small. Re-evaluate in Week 5.

## Week 2 — Mary the Builder (Demonstration Content)

**Goal:** 1–3 marketing videos published to LinkedIn / YouTube /
Twitter. Each piece is proof of capability for future client
conversations.

| Day | Action |
|---|---|
| Mon | Update `personas` row for `mary_builder` with prompt_framing + replica_id (same replica) |
| Tue | Create LinkedIn / YouTube / Twitter API credentials in n8n (manual) |
| Tue | Activate `clx-video-platform-adapt` |
| Wed | Activate `clx-video-distribute-linkedin`, `clx-video-distribute-youtube`, `clx-video-distribute-twitter` |
| Thu | Generate first builder-track content_piece + adapt for 3 platforms |
| Thu | Publish to all 3 platforms; observe `distribution_log` entries |
| Fri | Manual review: external_post_url for each, sanity-check formatting |
| Fri | Generate piece #2 + #3 to validate the loop |

**Workflows activated this week:** `clx-video-platform-adapt` plus
the 3 primary distribute workflows.

**Out-of-scope this week:** Dev.to / blog / TikTok / Reels / Shorts
(scaffolded as registry rows but not wired). Engagement metric polling.

**Demonstration value:** by Friday Mary has external_post_url links
across 3 platforms produced from one canonical content_piece — that
literal artifact is the sales asset for Week 4 client conversations.

## Week 3 — Multi-Tenant Readiness (Plumbing)

**Goal:** The system is ready for a paying client to use Component 1
isolated from Mary's data. No client onboarded yet.

| Action |
|---|
| Add `clx-client-content` webhook (Phase 2b pre-work — list content_pieces filtered by session client_id) |
| Add `clx-client-distribution` webhook (list distribution_log filtered by session client_id) |
| Verify cross-tenant isolation: synthetic test client A cannot see client B's personas/content/variants/log |
| Wire Stripe metering stub: persona_usage_log INSERT triggers a no-op log entry tagged for Phase 2c |
| Document the persona-onboarding script (concierge runbook) for Mary to use with first client |
| Update `03-tavus-integration-plan.md` with **confirmed** Tavus pricing once Mary's account billing cycle has 2 weeks of data |
| Tavus replica training script: a 1-page checklist to send to first client so they can record their training video |

**Workflows added:** `clx-client-content`, `clx-client-distribution`
(Phase 2b territory, listed here because the rollout depends on them).

**Risk to manage:** RLS verification is the load-bearing test.
Cross-tenant leak in client dashboards = trust catastrophe. Mary
should personally execute the synthetic-test plan before Week 4.

## Week 4 — First Crystallux Client Onboarded

**Goal:** One paying client successfully generates and publishes
content via their own persona, with Stripe metering tracking actual
Tavus minutes consumed.

| Day | Action |
|---|---|
| Mon | First-client onboarding call (Mary leads, concierge replica setup) |
| Mon | Stripe subscription created (existing `clx-stripe-provision-v1` runs) |
| Tue | Client records Tavus training video; replica training started |
| Wed | Replica trained; admin inserts client persona row, sets `clients.default_persona_id` |
| Wed | Client logs into dashboard, generates first content_piece via "Generate Content" panel |
| Thu | Client publishes to LinkedIn (first paid distribution) |
| Thu | Verify persona_usage_log row written; Stripe metering hook fires (still stubbed but log captured) |
| Fri | Retrospective: what concierge steps did Mary do that should automate next? Phase 2c backlog seeded |

**Workflows activated this week:** none new — system from Week 1–3
serves the first client. The work this week is operational, not
engineering.

**Phase 2c trigger criteria:** when a second client onboards. Phase
2c work begins only when the first client has generated 5+ content
pieces successfully (proves the loop works at scale of 1) and Mary
can articulate the top 3 friction points from the concierge process.

## Cross-cutting checklists

### Migration apply (Week 1, Monday)

- [ ] `99-open-questions.md` reviewed and answered
- [ ] Q1–Q7 confirmations recorded (or doc revisions made if changed)
- [ ] Backup current Supabase schema before apply
- [ ] Apply `2026-05-02-phase-2a-foundation.sql`
- [ ] Verify all 6 new tables present
- [ ] Verify additive columns added (`leads.persona_context_id`,
      `leads.content_piece_id`, `clients.default_persona_id`,
      `campaigns.persona_id`)
- [ ] Verify the 8 distribution_platforms seed rows
- [ ] Verify the 2 personas seed rows (`mary_broker`, `mary_builder`)
- [ ] Run `LIMIT 0` SELECTs against each new table for column existence

### Workflow activation discipline

The 6 stub workflows in `workflows/api/video/` are imported dormant.
**Do not activate any of them before:**
- The migration is applied (status row counts must succeed)
- Tavus credential exists in n8n
- The relevant persona row has `tavus_replica_id` set

Activation order matches rollout:
1. Week 1: `clx-video-content-generate` + `clx-video-tavus-status-poll`
2. Week 2: `clx-video-platform-adapt`, then the 3 distribute workflows
3. Week 4: no new activations — same 6 workflows serve the first client

### What stays dormant indefinitely

- `clx-video-distribute-devto` — not scaffolded yet (Phase 2c)
- `clx-video-distribute-blog` — not scaffolded yet (Phase 2c)
- `clx-video-distribute-tiktok` / `reels` / `shorts` — Phase 2d

`distribution_platforms.active=false` for these prevents the adapter
from generating variants, even if a client asked.

## Phase 2a exit criteria

Phase 2a is complete when:
- [ ] First content_piece generated end-to-end on Mary's broker track
- [ ] First broker outreach lands on a real lead with the new video
- [ ] First builder-track piece distributed to 3 platforms
- [ ] First paying client onboarded with their own persona
- [ ] Cross-tenant isolation verified
- [ ] All 7 open questions formally closed (in this branch's commit log)
- [ ] Phase 2c backlog drafted from Week 4 retrospective

When those land, this branch (`phase-2a-scaffolding`) gets merged into
`scale-sprint-v1`, then merged forward into `main` per existing
release flow.
