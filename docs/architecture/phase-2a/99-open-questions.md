# Phase 2a — Open Questions for Mary's Morning Review

These are architectural contradictions or ambiguities I found between the
Phase 2a brief and the existing repo state. Per the brief's "STOP and
surface" rule, I am not auto-resolving any of them. Each one has a
recommended path; please confirm or override before this scaffolding
gets imported into n8n.

The scaffolding I produced tonight assumes the **recommended path** for
each question — if you change a recommendation, the relevant doc needs
a follow-up edit before code lands.

---

## Q1. Tavus integration is not actually new — there is already a complete dormant pipeline

**What the brief says:** Tavus is a new credential, Mary creates manually,
Component 1 (Content Generator) is the introduction of Tavus to the
platform.

**What the repo actually contains** (all dormant, none active):

| File | What it does |
|---|---|
| `workflows/clx-video-outreach-v1.json` | Tavus video generation workflow. Schedule trigger every 2hrs (batch), manual webhook (single lead), Anthropic for script composition, niche-overlay-templated prompts. Updates `leads.video_status` and `leads.video_request_id`. Triggered as 48h-no-booking fallback by `clx-booking-v2` via `Execute Workflow`. |
| `workflows/clx-video-ready-v1.json` | Tavus callback webhook receiver (`POST /clx-video-ready-v1`). Correlates Tavus job by `request_id` → `leads` row, updates `leads.video_status` on terminal events. |
| `workflows/clx-booking-v2.json` | References Tavus (per grep) — likely the Execute Workflow handoff. |

The deactivation note on `clx-video-outreach-v1` says: *"DEACTIVATED — do
not turn on until TAVUS_API_KEY + TAVUS_REPLICA_ID are in .env, the
Tavus n8n credential is created, at least one client has
video_enabled=true, and the Anthropic credential is bound to Compose
Video Script."* So the existing pipeline expects the same Tavus
credential the Phase 2a brief asks Mary to create.

**The implication for Phase 2a's Component 1:** there are two distinct
use cases that both want Tavus, and only one is genuinely new.

| Use case | Workflow | Status | Distribution target |
|---|---|---|---|
| (a) Personalized video for **one** outreach lead | `clx-video-outreach-v1` (existing, dormant) | Already designed | Single lead via outreach engine |
| (b) Shareable content video for **many** viewers across platforms | Phase 2a Content Generator (new) | To be built | Multiple platforms (LinkedIn, YouTube, Twitter, blog) |

**Recommended path (what tonight's scaffolding assumes):**
Component 1 is **only job (b)** — content-marketing video for
multi-platform distribution. Job (a) stays with `clx-video-outreach-v1`,
unchanged. Both share the same Tavus credential and the same Anthropic
credential, but operate against different data tables (`content_pieces`
for Component 1, `leads.video_*` for Video Outreach).

**Decision needed:**
1. Confirm Component 1 is content-marketing only and the existing Video
   Outreach v1 is left alone (recommended).
2. OR fold both into a single "video generation" subsystem with
   distribution mode as a parameter (cleaner architecturally, but
   requires editing a dormant existing workflow — slightly higher risk).

I picked option 1 for tonight's scaffolding because it strictly obeys
the "do not modify existing workflows" rule. Switching to option 2
later is a one-day refactor, not a redesign.

---

## Q2. Existing engines are schedule-triggered, not webhook-triggered — the brief's "calls out to" model doesn't match reality

**What the brief says:**
> Component 1 must call out to those (existing components 2-5), not
> replicate them.

The brief's broker-track flow describes calling `clx-outreach-sender-v2`
with a video URL.

**What the repo actually contains:**
- `clx-outreach-sender-v2` is **schedule-triggered every 60 minutes**.
  Its first node is `Schedule Trigger`, not `Webhook`. It polls the
  `leads` table for rows in `lead_status='Campaign Assigned'` (or
  similar) and processes them.
- `clx-outreach-generation-v2` is **schedule-triggered every 15 minutes**.
- `clx-follow-up-v2` is almost certainly the same pattern (not
  re-verified, low-risk assumption).
- `clx-booking-v2` has both — schedule trigger AND a webhook entrypoint
  for direct invocation. This is the exception.

**The implication:** Crystallux's coordination pattern is **state-driven
via Supabase**, not pub-sub via webhooks. Workflows write to
`leads`/`appointment_log`/`scan_log` etc., and downstream workflows
pick up the new state on their next scheduled tick. Direct
`Execute Workflow` calls exist (Booking v2 → Video Outreach v1) but
are the minority.

**What this means for Component 1:** Phase 2a's Content Generator does
**not** "call" the existing engines. It writes a `content_pieces` row,
and:
- For broker-track personalized outreach: an INSERT into the new
  junction table `lead_persona_links` records the persona/content link,
  then a small bridge UPDATE writes `leads.video_url` from
  `content_pieces.tavus_video_url` and sets `leads.lead_status =
  'Campaign Assigned'` (touching only existing columns — leads schema
  unchanged). The existing Outreach Sender picks the lead up on its
  next 60-min tick.
- For builder-track multi-platform distribution: writes
  `platform_variants` rows, and the new distribution workflows
  (`clx-video-distribute-linkedin` etc.) are the things that fire to
  each platform — those *are* webhook-triggered because they're new.

**Decision needed:**
1. Confirm the state-driven pattern for the broker integration
   (recommended — matches the codebase's existing convention).
2. OR retrofit a webhook trigger onto `clx-outreach-sender-v2` so
   Component 1 can push synchronously. **NOT recommended** — that's
   a modification to a dormant-but-soon-to-be-active workflow and
   contradicts the "do not break what's working" principle once
   Outreach Sender goes live.

Tonight's broker-track doc (`04-broker-revenue-track.md`) assumes
option 1.

---

## Q3. `niche_overlays.video_script_template` already exists — relationship to new `personas` table?

**What the brief says:** Add a `personas` table; persona_id flows
through everything; "one replica, multiple personas via prompt
framing."

**What the repo contains:**
- `clx-video-outreach-v1` has a `Fetch Niche Overlay` node that does:
  `GET /niche_overlays?niche_name=eq.{niche}&select=video_script_template&limit=1`
- So there's an existing `niche_overlays` table with at minimum
  `niche_name` and `video_script_template` columns. Probably more.

**Relationship between niche and persona:**
- A **niche** is a vertical (insurance broker, construction, moving,
  etc.) — already used to template *what* the video says about a lead's
  industry.
- A **persona** is a speaker identity (Mary the Broker, Mary the
  Builder, Crystallux client X) — controls *who appears to be saying
  it* and *how they frame it*.

These are orthogonal axes. A single video has both:
`(persona = Mary the Broker, niche = life insurance prospect)`.

**Recommended path (tonight's scaffolding assumes):**
The migration adds a new `personas` table with
`niche_overlay_default text REFERENCES niche_overlays(niche_name)` so
each persona has a default niche framing but can be overridden per
content piece. `content_pieces.persona_id` and `content_pieces.niche`
are both columns — neither replaces the other. `niche_overlays` is
left untouched.

**Decision needed:**
1. Confirm niche × persona is two axes, not one (recommended).
2. OR persona supersedes niche, and niche_overlays gets deprecated.
   Don't recommend this — would force a redesign of existing video
   outreach.

Tonight's schema doc (`01-personas-and-distribution-schema.md`)
assumes option 1.

---

## Q4. `clx-content-platform-adapt` should it use Anthropic or pure templating?

**What the brief says:** Component 1 produces canonical content;
distribution layer adapts per platform.

**What the brief leaves open:** Is platform adaptation
(`clx-video-platform-adapt.json`) a deterministic template
transformation (LinkedIn = first 1300 chars, YouTube = full + tags,
Twitter = 280-char hook + thread), or does it call Anthropic to
rewrite per platform?

Option A (deterministic templates): zero per-piece API cost,
predictable, easy to test. Loses tone fidelity per platform.

Option B (Anthropic per platform): higher fidelity, costs ~$0.05 per
adaptation × 4 platforms × N pieces. Slower.

Option C (hybrid): deterministic for caption length / hashtag policy,
Anthropic only for the platform-specific *hook* (first sentence). Best
balance.

**Recommended path:** Option C. Tonight's scaffolding stubs the
adapter workflow with both code paths but defaults to Option C with a
config flag.

**Decision needed:** Confirm C, or override.

---

## Q5. Tavus pricing — flagging as estimate per brief, but want explicit Mary-confirmation path

The brief says: "DO NOT promise specific Tavus pricing — flag as
estimate, link to current pricing pages."

`03-tavus-integration-plan.md` includes order-of-magnitude estimates
based on publicly listed Tavus tiers as of late 2025 / early 2026,
clearly flagged "estimate, verify at signup". When Mary creates the
Tavus account, she'll see actual pricing and should overwrite the
numbers in that doc.

**Decision needed:** None tonight. Action item: when the Tavus account
is created, update `03-tavus-integration-plan.md` with confirmed
pricing.

---

## Q6. Persona row for Mary the Broker vs. Mary the Builder — same physical person, two persona rows?

**What the brief says:** Mary the Broker and Mary the Builder are two
distinct personas. Both run on the same engine, just with different
persona rows.

**Implication:** The `personas` table will have at least two rows for
the same human person. That's fine — distinct framing/audience. But:

1. Should both share a single Tavus replica (same face/voice) and
   differentiate purely via prompt? **Recommended.** Saves one replica
   slot and one replica training cycle. Matches the "one replica,
   multiple personas via prompt framing" line in the brief.
2. Or should each persona have its own replica? Higher fidelity, but
   2× cost and 2× setup time. Not recommended for MVP.

**Recommended path:** One Tavus replica, both personas reference it.
`personas.tavus_replica_id` is a column; personas with the same
replica_id share the trained likeness; the prompt + caption framing is
what differentiates them.

**Decision needed:** Confirm one-replica-two-personas.

---

## Q7. Multi-tenant client personas — billing model

**What the brief says:** "Per-client usage caps + Stripe metering hooks
(stubbed, not implemented)."

**What's ambiguous:** Is the unit of billing
- per content piece generated?
- per Tavus minute consumed?
- per platform variant published?
- some combination?

**Recommended path (tonight's scaffolding assumes):** Bill by **Tavus
minutes consumed per persona per month**, with a soft cap before hard
cutoff. `personas.monthly_tavus_minute_cap` and a usage-tracking table
(`persona_usage_log`). Stripe metering hooks emit `tavus_minutes_used`
events keyed by persona_id → client_id → Stripe customer_id.

This matches Crystallux's existing per-client cap pattern
(`clients.video_monthly_cap` already exists for outreach video).

**Decision needed:** Confirm Tavus-minutes-per-persona is the billing
unit (recommended), or specify alternate.

---

## Summary table

| ID | Question | Recommended | Tonight's scaffolding assumes |
|---|---|---|---|
| Q1 | Tavus pipeline already exists — Component 1 scope | Content marketing only | ✓ recommended |
| Q2 | Engines are schedule-triggered, not webhook | State-driven coordination | ✓ recommended |
| Q3 | niche × persona axes | Two orthogonal axes | ✓ recommended |
| Q4 | Platform adapter strategy | Hybrid (template + Anthropic hook) | ✓ recommended |
| Q5 | Tavus pricing | Estimate now, confirm at signup | ✓ flagged |
| Q6 | One replica or many | One replica, prompt-differentiated | ✓ recommended |
| Q7 | Billing unit | Tavus minutes per persona per month | ✓ recommended |

**Action for Mary:** read this file, confirm or override each, then say
"Q1=A, Q2=A, Q3=A, ..." and I'll either lock the design or revise the
docs accordingly. Migration is not yet applied; workflow stubs are not
yet imported.
