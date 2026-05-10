# Review Management Vision (Insurance MGA — Layer 2 Part B)

> **Audience:** any engineer or operator working on the review system. Explains the 7 review types, the behavioral-signal → review pipeline, and how everything is unified through the video engagement layer.

## Why "review" is the central abstraction

In a regulated insurance MGA, every meaningful client interaction post-issuance is a **review**:

- The annual policy review FSRA expects (and requires you to document)
- The renewal-window conversation 60 days before policy expiry
- The "I just had a baby" call (life event review)
- The claim being filed (claim review)
- The complaint that needs human + regulator handling (complaint review)
- The pre-issuance suitability gate before a new policy binds (pre-issuance review)
- The random compliance audit you do on ~10% of your book per quarter (compliance audit review)

Traditional MGAs treat each of these as a separate process with separate tools. Crystallux treats them as **one table (`policy_reviews`) with one type column** so the dashboard, the audit trail, the video engagement layer, and the SLA monitor all work uniformly.

## The 7 review types

| Type | Trigger | Default priority | Video template | Owner |
|---|---|---|---|---|
| `pre_issuance` | Suitability gate before binding (Layer 2 Part A) | medium | n/a | advisor |
| `annual` | Yearly via scheduler OR `birthday` BI signal | medium | `birthday` / `annual_review_due` | advisor |
| `triggered_event` | Behavioral signal: marriage / baby / new_job / job_loss / home_purchase / business_expansion / etc. | high | matched per signal_type | advisor |
| `renewal` | 60 days before `policy_applications.renewal_date` | high (urgent at <14d) | `renewal_due` | advisor |
| `claim` | Client files claim (`/claim-review` webhook) | urgent | `claim_filed` | advisor |
| `compliance_audit` | Random 10%/quarter sampling | low | n/a | compliance_officer |
| `complaint` | Client/regulator complaint filed | high (urgent if material) | n/a | mga_principal + compliance_officer |

## Schema highlights

`policy_reviews`:
- `review_type` — the 7 enum above
- `trigger_source` — `scheduled` / `behavioral_signal` / `market_signal` / `client_request` / `carrier_request` / `regulator_request`
- `trigger_signal_id` (soft FK to `behavioral_signals.id`) + `trigger_signal_type` — which signal woke this review up
- `video_render_id` (soft FK to `video_renders.id`) + `video_engagement_status` — links to the existing video pipeline from commit 25c0886
- `priority` — `urgent` / `high` / `medium` / `low` (drives sort order in advisor dashboard)
- `status` — `scheduled` / `in_progress` / `completed` / `overdue` / `escalated` / `cancelled`
- `client_situation_changes` (jsonb) — captured during conduct
- `recommendations` (jsonb) — outcome of the conducted review
- `outcome` — `coverage_unchanged` / `coverage_increased` / `coverage_decreased` / `new_policy_added` / `policy_replaced` / `client_no_response` / `escalated`

All vertical-tagged with `vertical_id='insurance'`. Index on `(vertical_id, due_date)` partial WHERE `status IN ('scheduled','in_progress')` makes the overdue scan efficient.

## The behavioral signal → review pipeline

This is the **unique competitive advantage** Layer 2 Part B unlocks. Every BI signal that lands on a lead with an in-force policy can become a personalized review touchpoint.

```
Behavioral Intelligence pipeline (existing — commit 25c0886)
  ↓ inserts behavioral_signals row with signal_type, relevance_score
clx-behavioral-trigger-engine-v1 (existing, daily) decides which signals fire
  ↓ POST /webhook/mga/insurance/review-triggered-event (NEW, Part B)
clx-mga-insurance-review-triggered-event-v1
  ↓ maps signal_type → trigger_signal_type via lookup table:
       baby_born          → baby
       marriage           → marriage
       job_change         → new_job
       job_loss           → job_loss
       home_purchase      → home_purchase
       business_expansion → business_expansion
       birthday_window_7d → birthday (treated as annual review)
       retirement_planning_age → retirement_planning_age
       child_milestone    → child_milestone
  ↓ creates policy_reviews row (priority=high, due_date=NOW+7d)
  ↓ POST /webhook/mga/insurance/review-video-generate
clx-mga-insurance-review-video-generator-v1
  ↓ looks up matching video_review_templates row
  ↓ Claude personalizes script (first_name, company, signal context)
  ↓ chains existing clx-video-script-generator-v1 (commit 25c0886)
  ↓ HeyGen renders video → R2 stores → landing_page_url assigned
  ↓ POST /webhook/mga/insurance/review-video-deliver
clx-mga-insurance-review-video-deliver-v1
  ↓ chooses channel (whatsapp > sms > email) per lead.phone/email
  ↓ sends personal intro + landing page URL
  ↓ updates video_engagement_status='sent'

Client engages with landing page (existing video tracking)
  ↓ POST /webhook/mga/insurance/review-video-engagement
clx-mga-insurance-review-video-engagement-tracker-v1
  ↓ updates video_engagement_status: viewed → replied → meeting_booked

Daily 09:00 ET — clx-mga-insurance-review-followup-v1
  ↓ stale detection:
     'sent' >3d no engagement     → AI WhatsApp nudge
     'viewed' >7d no reply        → AI personal followup
     'replied' >7d no booking     → notify advisor
```

## The 12 seeded video review templates

Seeded by `clx-mga-insurance-video-review-templates-seed-v1.json` (Mary POSTs once after deploy). Templates committed inline in the workflow JSON (also documented in this README) so they're version-controlled. Each template has:

- `trigger_event` (the signal type it matches)
- `script_template` (with `{{variables}}` for personalization)
- `tone` (celebratory / congratulatory / supportive / informative / urgent)
- `cta_text`
- `recommended_persona_id` + `recommended_look_id` (HeyGen avatar)
- `duration_seconds` (45-75s typical)

The 12: `birthday`, `new_job`, `marriage`, `baby`, `home_purchase`, `business_expansion`, `job_loss`, `annual_review_due`, `renewal_due`, `claim_filed`, `retirement_planning_age`, `child_milestone`.

Future verticals (mortgage, real estate) will get their own template seeds tagged `vertical_id='mortgage'` etc. Same engine, different tone library.

## Operational SLA

The `clx-mga-insurance-review-overdue-monitor-v1` runs daily 06:30 UTC and enforces:

| State | Action |
|---|---|
| Past `due_date` AND `status` in (`scheduled`, `in_progress`) | Mark `status='overdue'` + advisor reminder |
| 30+ days overdue | `status='escalated'` + email mga_principal + `regulatory_audit_log` event `review_escalated_overdue` |

Combined with the daily review-followup workflow, the system has **no silent failure modes**. Every review either gets engaged with, gets re-attempted by AI, gets escalated to advisor, or gets escalated to MGA principal. **Nothing falls through the cracks.**

## What this enables for Mary's MGA business

1. **The 10 LLQP-licensed advisors can each carry 2-3× their previous book** because reviews don't burn calendar time.
2. **Carrier confidence** — every conducted review writes to `regulatory_audit_log`. A carrier asking "show me the past 12 months of reviews on these 50 policies" is a 30-second query.
3. **Behavioral signals become revenue** — every life event triggers a personalized video that runs while the advisor sleeps. Even if engagement rate is 15-25%, that's recurring re-engagement that didn't exist before.
4. **Compliance officer focus on real risk** — AI handles the 90% of routine reviews. Compliance officer time goes to the 10% that genuinely need human judgment (audits, complaints, AML edge cases from Layer 2 Part A).

## Cross-references

- Schema: [`db/migrations/insurance-mga-operations-schema.sql`](../../db/migrations/insurance-mga-operations-schema.sql)
- Video strategy detail: [`VIDEO_ENGAGEMENT_STRATEGY.md`](VIDEO_ENGAGEMENT_STRATEGY.md)
- BI pipeline (the upstream signal source): `workflows/api/intelligence/clx-behavioral-*-v1.json` (commit 25c0886)
- Video pipeline (the downstream rendering): `workflows/api/video/clx-video-*-v1.json` (commit 25c0886)
- Layer 2 Part A compliance reviews (different table — `compliance_reviews` for KYC/suit/disclosure/final): [`AI_COMPLIANCE_VISION.md`](AI_COMPLIANCE_VISION.md)
