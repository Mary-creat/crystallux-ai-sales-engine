# Pipeline activation sequence — from holding position to end-to-end

**Purpose.** The ordered path from where the pipeline stands today to a lead
travelling Discovery → Booking on its own, with the intelligence layers feeding
it. Written 2026-09-16.

This is a **sequence, not a checklist**. Several steps are only safe in order,
and the reason is given each time. The pattern that caused the most damage this
sprint was a single correct action taken before the thing that makes it hold.

Companions: [`OWNER_ACTIONS_REQUIRED.md`](../architecture/OWNER_ACTIONS_REQUIRED.md)
(what is waiting on Mary), [`PRE_LAUNCH_CHECKLIST.md`](../security/PRE_LAUNCH_CHECKLIST.md)
(security gates before a real customer), [`SERVER_RUNBOOK.md`](SERVER_RUNBOOK.md).

---

## The chain, as built

Each stage reads one status and writes the next. Nothing else moves a lead.

| # | Workflow | Reads | Writes | Trigger |
|---|---|---|---|---|
| 1 | `clx-lead-import` | — | — | cron |
| 2 | `clx-b2c-discovery-v2.1` | — | `New Lead` | cron |
| 3 | `clx-lead-research-v2` | `New Lead` | research fields → `Researched` | cron |
| 4 | `clx-lead-scoring-v2` | `Researched` | `Scored` / `Research Failed` | cron |
| 5 | `clx-business-signal-detection-v2` | `Scored` | `Signal Detected` (only with a real signal) | cron, hourly |
| 6 | `clx-campaign-router-v2` | `Signal Detected` | `Campaign Assigned` / `Out of Focus` | cron |
| 7 | `clx-outreach-generation-v2` | `Campaign Assigned` | `Outreach Ready` | cron |
| 8 | `clx-outreach-sender-v2` | `Outreach Ready` | `Contacted` | cron |
| 9 | `clx-reply-ingestion-v1` | inbound webhook | `Replied` | hook |
| 10 | `clx-booking-v2` | `Replied` | `Booking Sent` / `Not Interested` | cron |
| 11 | `clx-pipeline-update-v2` | all | `is_stale` flags | cron |

**Repo `active` flags are not production truth.** Only `clx-lead-import` ships
`active: true`. Signal detection ships `active: false` and was nevertheless
running in production — that is how 145 leads were mislabelled in two weeks.
Treat the live state as unknown until read through the API.

## Where the leads actually are

Measured 2026-09-16 (4,006 leads):

| status | count | meaning |
|---|---|---|
| `Scored` | 1,378 + 205 | the 205 are the corrected batch |
| `Scoring Failed` | 1,318 | **a third of the database** — see step 3 |
| `New Lead` | 891 | never researched |
| `Signal Detected` | 19 | genuine signals, promoting now |
| `Outreach Ready` | 171 | **drafts already written, waiting on the Sender** |
| `Contacted` | 17 | every lead ever contacted |

Two things stand out. 171 leads already hold a draft — activating the Sender
acts on all of them immediately. And 1,318 failures against 17 contacts is the
real bottleneck; no amount of new discovery helps until that is understood.

---

## Phase 0 — Restore trust in what is deployed

**Nothing below this line is safe until this is done**, because every judgement
in this file is read from the repo, and the repo has been proven wrong about
production at least twice.

1. **n8n API key into `.env`** (`OWNER_ACTIONS` #0). The key there is from
   `2026-04-06` and answers `401`; its `iat` claim confirms it. The working key
   exists only in the GitHub Actions secret, which cannot be read back — if it
   is not saved elsewhere, mint a new one and put the same value in **both**.
2. **Diff live against repo for all 11 workflows above.** `scripts/n8n/compare-live-vs-repo.py`
   exists for this. Expect drift; signal detection is a known case.
3. **Redeploy whatever drifted.** CI deploys changed files only, so an unchanged
   file that drifted in production needs a forced `PUT` by id.

**Why first.** Activating a stage whose live code differs from the file you read
is how the last two defects happened.

## Phase 1 — Fix what is known broken

4. **Signal detection.** Redeploy it, then reactivate, then re-run the `#0d`
   correction. It must be redeployed *before* reactivation or it resumes
   mislabelling, and the correction must come *after* or the old build undoes it
   within the hour at a cost of one Claude call per lead.
5. **The 1,318 `Scoring Failed`.** Diagnose before touching. The repo's scorer
   writes `Research Failed` when a lead has no `research_summary`, and
   production has **zero** rows with that status — so the deployed scorer is
   probably older than the repo's. Once Phase 0 settles that, the likely path is
   re-research then re-score. **Do not bulk-reset them to `New Lead`:** if the
   cause is missing research, they return to failure and the model calls are
   spent for nothing.
6. **Decide the `Scored` dead end.** Nothing promotes a `Scored` lead onward —
   only signal detection and the staleness sweeper read it. So a lead that
   genuinely has no buying signal is re-checked forever and never contacted.
   That is correct *if* a signal is a prerequisite for outreach, and a silent
   leak if it is not. **This is a business decision, not a technical one.**

## Phase 2 — Prove one lead end to end, on the test inbox

Activate **one stage at a time**, watching the counts move between each. The
Sender's `to` stays hardcoded to the test inbox throughout.

```sql
SELECT lead_status, count(*) FROM leads
WHERE lead_pool = 'tenant' GROUP BY 1 ORDER BY 2 DESC;
```

7. Research → Scoring → Signal → Router. Confirm a lead advances one stage per
   run and nothing lands in an unexpected bucket.
8. **Generation.** Caps at `limit=25` per run, and carries seven guards
   including `researched_at IS NOT NULL`. Watch for `Outreach Ready` rising.
9. **Sender — the one to think about.** 171 leads are already `Outreach Ready`.
   The moment it is activated it works through them at the configured daily cap.
   Every message goes to the test inbox while this line stands:
   ```js
   const to = 'adesholaakintunde+clxtest@gmail.com'; // TESTING MODE
   ```
   **Read that line in the live workflow, not in the repo, before activating.**
10. **Reply → Booking.** Reply to one test email and confirm `Replied` appears
    and Booking v2 issues a link. This is the half never proven end to end.

## Phase 3 — The intelligence layers

These make the pipeline good rather than merely working. None of them blocks it.

11. **MAXI / vertical context** — industry playbooks resolve through
    `get_vertical_context()`; 8 verticals configured and verified. This is what
    makes outreach industry-specific.
12. **Market intelligence / signals** — GDELT, NewsAPI, Bank of Canada, weather
    feed the signal stage. Only worth turning up once step 4 is trustworthy.
13. **Personas / voice** — connects the persona layer to generated messages.
14. **Copilot + MCP Tool Gateway** — five dormant workflows. **This is the AI
    chat in the dashboard, Mary's #1 ask, already built.** Activating these is
    the whole job; the frontend auto-mounts on every admin page.

## Phase 4 — Go live

15. **Flip the Sender** `to` from the test address to `data.email`. One line,
    in the n8n UI, no re-import. **This is the irreversible one** — real people
    receive mail from this point.
16. **Warm up.** `channel_credentials.daily_send_limit = 25` before ramping;
    the default is 450 and sending 450 cold emails from a cold domain burns it.
17. **Watch the first day manually.** Replies, bounces, unsubscribes.

## Phase 5 — Gated on spend, not on engineering

18. **Anthropic top-up.** Research, scoring, signal and generation each cost a
    model call per lead. Re-researching 1,318 leads is a real bill — size it
    before starting Phase 1 step 5.
19. Other keys unlock dormant features, not the core pipeline: HeyGen (video),
    Twilio (WhatsApp/voice), social developer apps, ElevenLabs, Restream.

---

## The rule this file exists to enforce

Every defect this sprint had the same shape: something reported success and did
nothing, or something correct ran before the thing that makes it hold. A guard
gated by its own typo. A key that answered `401` for four months. A correction
that an hourly job would undo. A status that meant the opposite of its name.

So: **read the live thing, change one stage, watch the count move.** The chain
is eleven links and every one of them is observable in a single SQL query.
