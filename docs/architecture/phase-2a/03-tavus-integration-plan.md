# Phase 2a — Tavus Integration Plan

> **Important context:** Tavus is **not new** to this codebase. The
> repo already contains `clx-video-outreach-v1` (a dormant Tavus
> generation pipeline for personalized outreach video) and
> `clx-video-ready-v1` (a Tavus callback receiver). Tonight's Phase 2a
> work adds **content-marketing video** as a second use case that
> shares the same Tavus credential and the same replica. See Q1 in
> [`99-open-questions.md`](./99-open-questions.md).

## What Mary needs to do manually

1. **Create a Tavus account** at <https://www.tavus.io/>.
2. **Train one personal replica** of Mary's face/voice. Tavus calls
   this a "replica" — it's the trained likeness used to render videos.
   The replica training process requires recording a 2–3 minute
   training video (script provided by Tavus). Allow ~24h for the
   replica to finish training before testing.
3. **Capture two values**:
   - `TAVUS_API_KEY` — from Tavus dashboard → API Keys
   - `TAVUS_REPLICA_ID` — from Tavus dashboard → Replicas → the
     replica ID after training completes
4. **Add to n8n**:
   - Create a new n8n credential (Header Auth type) named
     **"Tavus Crystallux"** with `x-api-key: <TAVUS_API_KEY>`.
   - Update both internal personas in Supabase:
     ```sql
     UPDATE personas SET tavus_replica_id = '<TAVUS_REPLICA_ID>'
      WHERE persona_key IN ('mary_broker','mary_builder');
     ```
   - The same replica_id serves both personas; differentiation is via
     `personas.prompt_framing`. See Q6.

## Replica policy — one or many?

**Recommended (Q6 path):** one replica, many personas.

| Persona | Replica | Differentiation |
|---|---|---|
| Mary the Broker | `<MARY_REPLICA_ID>` | `prompt_framing` = broker voice, financial-product expertise |
| Mary the Builder | `<MARY_REPLICA_ID>` | `prompt_framing` = founder voice, tech-product narrative |
| Future Crystallux client X | `<CLIENT_X_REPLICA_ID>` | Each client trains their own replica when onboarded |

Internal personas share the replica because they're the same physical
person. Client personas get distinct replicas because they're distinct
people.

## API surface used

Component 1 uses two Tavus endpoints:

### 1. Submit a video render job
```http
POST https://tavusapi.com/v2/videos
Headers: x-api-key: <TAVUS_API_KEY>
Body:    {
           "replica_id":   "<TAVUS_REPLICA_ID>",
           "script":       "<composed script>",
           "video_name":   "<descriptive name>",
           "callback_url": null
         }
Returns: { "video_id": "tvs_...", "status": "queued" }
```

### 2. Poll job status
```http
GET https://tavusapi.com/v2/videos/<video_id>
Returns: {
           "video_id":    "tvs_...",
           "status":      "queued" | "generating" | "ready" | "failed",
           "download_url":"https://...",          // when ready
           "thumbnail_url":"https://...",          // when ready
           "duration":    47                       // seconds
         }
```

Polling cadence: every 90 seconds, batch up to 25 in-flight jobs per
poll. Typical render time per Tavus docs: 2–10 minutes for a 60-second
script.

## Cost estimate — flagged as ESTIMATE, verify at signup

> **Pricing as of January 2026, publicly listed. Subject to change.**
> **Verify on the Tavus pricing page before relying on these numbers.**
> <https://www.tavus.io/pricing>

Public Tavus tiers (best-known, late-2025/early-2026 reference):

| Tier | Monthly cost | Included video minutes | Overage |
|---|---|---|---|
| Free | $0 | 3 min | n/a |
| Hobby | ~$39/mo | 10 min | ~$5/min |
| Pro | ~$375/mo | 100 min | varies |
| Enterprise | custom | custom | custom |

**Phase 2a sizing assumption:**

| Track | Pieces/week | Avg duration | Minutes/month |
|---|---|---|---|
| Broker (Week 1) | 5–10 | 60s | ~7 min |
| Builder (Week 2+) | 3 | 60–90s | ~12 min |
| Client (Week 4+, per client) | 2–4 | 60s | ~3–4 min/client |

**Total Mary-only (Weeks 1–3): ~20 min/month → Hobby tier at ~$39/mo.**

When the first paying client onboards (Week 4): factor in their
minutes against per-client billing. The persona_usage_log tracks
actual consumption, and `clients.video_monthly_cap` (already exists on
the clients table) is the soft cutoff.

**Action item:** When Mary creates the Tavus account and sees actual
pricing, update this doc with confirmed numbers.

## Replica setup checklist

- [ ] Account created at tavus.io
- [ ] Recorded training video per Tavus instructions
- [ ] Replica training completed (typically ~24h)
- [ ] Replica preview reviewed by Mary (face, voice fidelity acceptable)
- [ ] `TAVUS_API_KEY` captured
- [ ] `TAVUS_REPLICA_ID` captured
- [ ] n8n credential "Tavus Crystallux" created (Header Auth, x-api-key)
- [ ] Both internal personas updated in Supabase with replica_id
- [ ] Tested via `POST /content/generate` against a draft topic
- [ ] First successful `content_pieces.status='ready'` row observed

## Operational notes

- **Rate limits:** Tavus has per-account concurrent-job limits on
  lower tiers. Hobby is typically 1–2 concurrent. Polling workflow
  caps at 25 in-flight to stay well under enterprise limits but Mary
  should expect serial generation on Hobby until upgrade.
- **Failure modes:** Tavus jobs can fail silently if the script
  contains content the model rejects. The polling workflow captures
  `status='failed'` and writes the reason to `content_pieces.status_detail`.
  Manual retry is a re-POST of `/content/generate` with the same
  inputs.
- **Replica retraining:** if Mary wants a different look later (e.g.
  professional headshot vs casual), train a new replica, update
  `personas.tavus_replica_id`. Existing `content_pieces` rows retain
  the old replica_id for traceability.
