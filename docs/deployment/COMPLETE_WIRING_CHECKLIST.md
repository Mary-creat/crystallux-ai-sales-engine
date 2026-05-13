# Complete Wiring Checklist

> **Status (2026-05-13):** ~70% deployed. Migrations ✅. Workflows imported ✅. Seeds blocked → unblocked via direct SQL (`SEED_FIX_FINAL.md`). Remaining work organized below by time horizon.
>
> **Owner:** Mary Akintunde. **Cross-reference:** `docs/audit/blockers.md` (the original 30-section checklist), `docs/handbook/FOUNDER_OPERATIONS_HANDBOOK.md` §6 (vendor relationships), `docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md` §13 (gov funding) + §14 (Victory Enrichment).

---

## Honest timeline expectations

| Horizon | What lands | Effort |
|---|---|---|
| **Today (2 hrs)** | Seeds via SQL + smoke test current dashboards | Mary alone |
| **This week (5-10 hrs)** | Deploy 2 Cloudflare Pages projects + activate webhook-only workflows + seed your MGA client + first carrier appointment applications submitted | Mary alone |
| **Next 2-4 weeks** | External service signups (HeyGen, Postmark, Twilio, Stripe, Cal.com, etc.) — get credentials into n8n vault. Activate scheduled workflows. SR&ED log started. Non-profit lawyer engaged. | Mary + vendor onboarding rhythms |
| **Next 1-3 months** | Carrier appointments approved (Walnut, PolicyMe, Apollo first). E&O insurance bound. First LLQP advisor recruited + onboarded. First commission flowing. | Mary + carriers (external timeline, not yours to control) |
| **Months 3-6** | First paying SaaS customer. AdvisorAssist productization. NRC IRAP project. | Mary + emerging team |
| **Months 6-12** | Phase 4 social platform API approvals trickle in. Insurer Tier-1 portal conversations open. | Parallel to commercial growth |

---

## A. TODAY (2 hours, do this now)

### A1. Seeds via direct SQL — 5 min
- [ ] Open Supabase Studio → SQL Editor → paste the block from `docs/deployment/SEED_FIX_FINAL.md` → Run.
- [ ] Verification query returns `8 / 19 / 20 / 12 / 30 / 6 / 1 / 3`. If not, paste me the error.

### A2. Promote yourself to mga_principal — 1 min
```sql
UPDATE auth_users
SET user_role = 'mga_principal'
WHERE email = 'info@crystallux.org';
-- expect: UPDATE 1
```

### A3. Smoke-test the existing dashboards — 30 min
- [ ] Log into `mga.crystallux.org` as `info@crystallux.org`.
- [ ] Sidebar shows the principal section (Insurer Accounts, Demo Mode, White-Label, etc.).
- [ ] **Advisor → Calculators** → Income Replacement → annual_income_cents=7500000, years=15 → coverage estimate appears.
- [ ] **Advisor → Onboarding** → 30 days listed.
- [ ] **Principal → Carriers** → 8 rows appear.
- [ ] **Principal → Products** → 19 rows appear.
- [ ] **Principal → Compliance Queue** → loads (probably empty — that's fine).

If a page shows "Unauthorized" or stays blank, check browser DevTools Console → paste the network error to me.

### A4. Confirm the `clients` row for Crystallux Insurance Network — 2 min
```sql
SELECT id, client_name, industry, active
FROM clients
WHERE id = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';
-- expect: 1 row, industry='insurance', active=true
```

If `industry` ≠ `insurance`, `UPDATE clients SET industry='insurance' WHERE id='...';` so the compliance scorecard workflow finds it.

---

## B. THIS WEEK (5-10 hours, do over 3-5 sessions)

### B1. Deploy 2 new Cloudflare Pages projects — 60 min

**`insurer-dashboard/` → `portal.crystallux.org`:**
- Cloudflare Pages → Create project → Connect to GitHub → select this repo → set:
  - Branch: `scale-sprint-v1`
  - Build command: (none)
  - Build output: `insurer-dashboard`
  - Root directory: `insurer-dashboard`
- After first deploy: Custom domains → add `portal.crystallux.org` → wait for SSL.

**`insurer-marketing/` → `insurers.crystallux.org`:**
- Same flow. Build output: `insurer-marketing`. Root directory: `insurer-marketing`.
- Custom domains → add `insurers.crystallux.org`.

DNS: in Cloudflare DNS for `crystallux.org` zone, add CNAME `portal` → `<pages-project>.pages.dev`, CNAME `insurers` → `<pages-project>.pages.dev`.

### B2. Activate webhook-only workflows — 20 min

All these are safe to activate immediately (they only fire when something hits the webhook):

**Layer 1 universal (workflows/api/):**
- [ ] `clx-lead-distribute-v1`
- [ ] `clx-lead-reassign-v1`
- [ ] `clx-lead-self-claim-v1`
- [ ] `clx-team-member-preferences-update-v1`
- [ ] `clx-goal-template-create-v1`
- [ ] `clx-user-goals-assign-v1`
- [ ] `clx-user-goals-list-v1`
- [ ] `clx-team-goals-list-v1`
- [ ] `clx-supervisor-overview-v1`
- [ ] `clx-pre-meeting-briefing-fetch-v1`
- [ ] `clx-pre-meeting-briefing-effectiveness-v1`
- [ ] `clx-training-coach-chat-v1` (requires `ANTHROPIC_API_KEY` env — see C2)
- [ ] `clx-training-topic-list-v1`
- [ ] `clx-training-progress-tracker-v1`
- [ ] `clx-file-completeness-calculate-v1`
- [ ] `clx-file-completeness-rules-update-v1`
- [ ] `clx-production-report-generate-v1`
- [ ] `clx-production-report-fetch-v1`

**Layer 2 insurance (workflows/api/insurance-mga/):**
- [ ] `clx-mga-insurance-carrier-create-v1`
- [ ] `clx-mga-insurance-carrier-product-create-v1`
- [ ] `clx-mga-insurance-carriers-list-v1`
- [ ] `clx-mga-insurance-quote-engine-v1`
- [ ] `clx-mga-insurance-quote-manual-v1`
- [ ] `clx-mga-insurance-product-compare-v1`
- [ ] All 7 calculator workflows
- [ ] `clx-mga-insurance-onboarding-advance-v1`
- [ ] `clx-mga-insurance-onboarding-status-v1`
- [ ] `clx-mga-insurance-insurer-account-create-v1`
- [ ] `clx-mga-insurance-insurer-user-invite-v1`
- [ ] `clx-mga-insurance-insurer-session-validate-v1` (internal)
- [ ] `clx-mga-insurance-insurer-access-audit-v1` (internal)
- [ ] `clx-mga-insurance-compliance-score-fetch-v1`

**Leave dormant for now** (scheduled cron, activate later — see C3):
- Anything with a Schedule Trigger node — activate one at a time and watch logs.

**Leave dormant indefinitely until external APIs land** (Section D):
- All 6 content publishers (LinkedIn, IG, FB, YouTube, TikTok, X)
- `clx-content-engagement-poller-v1`
- `clx-content-comment-monitor-v1`

### B3. Recruit + onboard your 10 LLQP advisors — async

This is partly outside the platform (recruiting), partly inside (creating accounts).

For each advisor:
```sql
-- Replace with their real email + name
INSERT INTO auth_users (email, full_name, user_role, is_active)
VALUES ('advisor1@example.ca', 'Advisor One', 'advisor', true);

INSERT INTO team_members (client_id, user_id, email, full_name, active, reports_to_user_id)
SELECT
  '6edc687d-07b0-4478-bb4b-820dc4eebf5d',
  u.id, u.email, u.full_name, true,
  (SELECT id FROM auth_users WHERE email = 'info@crystallux.org')
FROM auth_users u WHERE u.email = 'advisor1@example.ca';
```

Advisor logs in at `mga.crystallux.org` and walks the 30-day onboarding curriculum. Section 14 onboarding seed populated this.

### B4. Apply for 3 first-tier carrier appointments — 4 hrs of paperwork

Per `docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md` Section 2 Phase 1:

- [ ] **Walnut Insurance** — partners@walnutinsurance.com — 30-60 day turnaround
- [ ] **PolicyMe** — partners@policyme.com — 30-60 day turnaround
- [ ] **Apollo Insurance** — submit via their MGA portal — 30-90 day turnaround

These are the fastest-appointing digital-friendly carriers. Tier-1 mutuals (Manulife, Sun Life, Canada Life) take 60-180 days — defer until after the first 3 land.

### B5. E&O insurance — 2-5 days

Mary's professional liability coverage. Required before any carrier appointment closes. Quote and bind via:
- **Magnes Group** (insurance-specialty broker)
- **APOLLO Insurance** (online quote)
- Cost: $400-$1,200/year typical for solo MGA

---

## C. NEXT 2-4 WEEKS — external service signups + credentials

### C1. External service signups (priority-ordered)

**Priority 1 — needed for any production use:**

| Service | Purpose | Cost | Sign-up time |
|---|---|---|---|
| **Postmark** | Transactional email | $10/mo (10K emails) | 1 day |
| **Twilio** | WhatsApp/SMS/voice | $0 base + per-message | 1-2 days |
| **Stripe** | Billing + checkout | 2.9% + 30¢ per txn | 1 day |
| **HeyGen Creator** | AI video personas | $29/mo | 1 day |
| **Cloudflare R2** | Video storage | $0.015/GB-mo + egress | 30 min |
| **Cal.com** | Booking integration | $15/mo/user | 1 day |

**Priority 2 — needed for full advisor experience:**

| Service | Purpose | Cost | Sign-up time |
|---|---|---|---|
| **Zoho Sign** | E-signatures (MGA agreements, applications) | $8/mo/user | 1-2 days |
| **Stripe Identity** | KYC verification | $1.50/verification | Same Stripe account |
| **ElevenLabs** | Voice cloning for video | $5/mo Starter | 30 min |
| **NewsAPI.org** | Market intelligence signals | Free up to 100/day | 30 min |
| **OpenWeather** | Weather signals for behavioral intel | Free up to 1K/day | 30 min |
| **Vapi** | AI voice calls | $0.05-0.20/min | 1-2 days |

**Priority 3 — for Phase 4 content marketing (Mary's BD task, 1-4 week approvals):**

| Service | Purpose | Cost | Approval time |
|---|---|---|---|
| **LinkedIn Developer** | Marketing API for content publishing | Free | 1-2 weeks |
| **Meta for Developers** | Instagram + Facebook publishing | Free | 1-3 weeks |
| **YouTube Data API** | YouTube publishing (Google Cloud Console) | Free up to quota | 1 day |
| **TikTok for Business** | TikTok publishing | Free | 2-4 weeks |
| **X Developer** | X (Twitter) publishing | $200/mo for posting tier | 1-7 days |

**Priority 4 — for advisor onboarding:**

| Service | Purpose | Cost |
|---|---|---|
| **Certn** | Advisor background checks | $30/check |

Most of these are documented in detail in `docs/handbook/FOUNDER_OPERATIONS_HANDBOOK.md` §6 — that's the authoritative vendor reference.

### C2. Wire credentials into n8n vault — 30 min per service

For each service above, after sign-up:

1. Get the API key from the service's dashboard.
2. n8n UI → Credentials → New → search for the service or create as "HTTP Custom Auth".
3. Save the credential with a canonical name. The workflows expect specific names — check the workflow JSONs for the `credentials.httpCustomAuth.name` value.

Canonical n8n credential names already used in workflows:

| Workflow references | Credential name expected in n8n |
|---|---|
| Supabase calls | `Supabase Crystallux Custom` (already configured if migrations ran) |
| Anthropic calls | None — uses `={{ $env.ANTHROPIC_API_KEY }}` expression. Add `ANTHROPIC_API_KEY` to `/root/crystallux/n8n/.env`. |
| HeyGen | `HeyGen API` (HTTP Custom Auth with Bearer header) |
| Postmark | `Postmark Server Token` (HTTP Header Auth with `X-Postmark-Server-Token`) |
| Twilio | `Twilio Crystallux` (Account SID + Auth Token) |
| Stripe | `Stripe Crystallux` (Bearer token) |
| Cal.com | `Cal.com API` (Bearer) |
| Zoho Sign | `Zoho Sign API` (OAuth — initial setup is a 10-min flow) |
| ElevenLabs | `ElevenLabs API` (Header: `xi-api-key`) |
| Vapi | `Vapi API` (Bearer) |

**Env vars in `/root/crystallux/n8n/.env`:**
```
ANTHROPIC_API_KEY=sk-ant-...
MARY_MASTER_TOKEN=<generate with: openssl rand -base64 32>
LICENSE_ENCRYPTION_KEY=<generate with: openssl rand -base64 32>
HEYGEN_API_KEY=<from HeyGen dashboard>
HEYGEN_WEBHOOK_SECRET=<from HeyGen webhook setup>
POSTMARK_SERVER_TOKEN=<from Postmark>
TWILIO_ACCOUNT_SID=<from Twilio>
TWILIO_AUTH_TOKEN=<from Twilio>
TWILIO_WHATSAPP_FROM=whatsapp:+14155238886
TWILIO_SMS_FROM=+1<your-twilio-number>
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
NEWSAPI_KEY=<from newsapi.org>
OPENWEATHER_API_KEY=<from openweathermap.org>
ELEVENLABS_API_KEY=<from elevenlabs.io>
VAPI_API_KEY=<from vapi.ai>
INTERNAL_EMAIL_SECRET=<already set>
N8N_BLOCK_ENV_ACCESS_IN_NODE=false  # already set; future workflows can use $env in Code nodes
```

After updating `.env`: `cd /root/crystallux/n8n && docker compose -f docker-compose.prod.yml restart n8n`.

### C3. Activate scheduled workflows (after webhook ones smoke-test clean) — 30 min

One at a time. Check n8n executions log 24h after each activation:

**Layer 1 universal:**
- [ ] `clx-performance-aggregator-v1` (00:30 daily)
- [ ] `clx-team-capacity-monitor-v1` (00:15 daily)
- [ ] `clx-performance-snapshot-v1` (Sun 01:00 + 1st-of-month)
- [ ] `clx-goal-progress-notification-v1` (Mon 09:00) — needs Postmark configured
- [ ] `clx-content-topic-generator-v1` (06:00 daily) — needs ANTHROPIC_API_KEY
- [ ] `clx-content-attribution-loop-v1` (02:00 daily)
- [ ] `clx-pre-meeting-briefing-generator-v1` (every 30 min) — needs ANTHROPIC_API_KEY
- [ ] `clx-no-show-multi-attempt-v1` (09:00 daily)
- [ ] `clx-file-completeness-bulk-refresh-v1` (03:00 daily)
- [ ] `clx-production-report-schedule-v1` (02:00 daily)

**Layer 2 insurance:**
- [ ] `clx-mga-insurance-compliance-score-calculate-v1` (04:00 daily)
- [ ] `clx-mga-insurance-compliance-alerts-v1` (every 4h)

**Keep dormant until 2-4 weeks of stable operation:**
- Content engagement poller + comment monitor (also: needs platform APIs)

### C4. Operational monitoring — 1 hr

- [ ] **UptimeRobot** (free tier — 50 monitors) — add checks for:
  - `https://automation.crystallux.org/webhook/auth/validate-session` (POST with dummy token, expect 401)
  - `https://mga.crystallux.org/` (HTTPS, expect 200)
  - `https://portal.crystallux.org/` (after B1, expect 200)
  - `https://insurers.crystallux.org/` (after B1, expect 200)
- [ ] **Sentry** (free tier) — add the Sentry DSN to frontends for client-side error tracking. Optional.
- [ ] **Supabase backup verification** — confirm Supabase auto-backups are enabled in Settings → Database → Backups. Daily, retained 7 days on free tier.
- [ ] **n8n executions log retention** — confirm `N8N_EXECUTIONS_DATA_PRUNE_MAX_COUNT` in docker-compose env. Default keeps 10,000 — fine for now.

### C5. SR&ED + IRAP outreach — 2-4 hrs

Per `docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md` §13:

- [ ] Create `docs/sred/2026-technical-log.md`. Backfill technical experiments from Session 1–3 commits (AI compliance pre-screening, behavioral trigger archetypes, training coach reinforcement loop, HeyGen-orchestrated video pipeline). Each entry: date, hypothesis, what was tested, conclusion.
- [ ] Submit NRC IRAP "interested in IRAP" form to Toronto regional office (`nrc-cnrc.gc.ca/eng/irap`).
- [ ] Apply for CDAP "Grow Your Business Online" stream ($2,400 + advisor). Eligible at zero revenue.

### C6. Non-profit lawyer engagement (Victory Enrichment) — 1-2 hr meeting

Per `docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md` §14:

- [ ] Engage a Canadian non-profit-specialist lawyer (Drache Aptowitzer, Carters Professional Corp, or similar). Initial consult $300-$600.
- [ ] Draft the Crystallux ↔ Victory service agreement (Stage 1 — operational integration). DO NOT execute any cross-entity transactions before this is signed.
- [ ] Establish Victory's charity-pricing policy + at least one other charity beneficiary so the arm's-length defense holds at CRA audit.

---

## D. NEXT 1-3 MONTHS — external timelines you don't control

### D1. Carrier appointment turnarounds

| Carrier | Typical timeline | Why |
|---|---|---|
| Walnut, PolicyMe, Apollo | 30-60 days | Digital-first, light contracting |
| iA Financial | 60-90 days | Mid-tier, standard contracting |
| Manulife, Sun Life, Canada Life | 90-180 days | Tier-1 mutuals, heavy contracting + due diligence |

**While waiting:** demo mode on the platform stays useful for prospect meetings. Use synthetic data.

### D2. First LLQP advisor onboarded end-to-end — 30 days

After your first carrier appointment closes, walk one advisor through the 30-day onboarding curriculum. Their completion is your operational proof — log every issue in `docs/audit/blockers.md`.

### D3. First commission flowing — variable

After advisor onboarded + carrier appointed + first policy bound: a real commission lands. This is **Phase 1 revenue** in the monetization doc. Celebrate, document the end-to-end flow, use as marketing asset.

### D4. First Phase 4 social platform API approval — variable

LinkedIn often first (1-2 weeks). Meta + TikTok longer. Until each lands, the corresponding publisher workflow stays dormant.

---

## E. MONTHS 3-6 — commercial growth

### E1. First paying SaaS customer (Phase 2)

After your MGA operations look credible, approach 3-5 design-partner MGAs in your network. Offer 50% off Year-1 in exchange for case-study rights. See monetization doc Section 2 Phase 2.

### E2. AdvisorAssist productization

10-14 hours of Claude Code work (next session topic when you're ready):
- Stripped-down "solo advisor" onboarding flow (skip MGA setup)
- Mobile-first UI polish
- Marketing site + pricing page + Stripe self-serve

### E3. NRC IRAP first project

Once ITA conversation is rolling, scope a $100-500K project around AI compliance + multi-vertical expansion.

---

## F. PRE-LAUNCH VERIFICATION QUERIES

Run these in Supabase SQL Editor after Section A completes:

```sql
-- 1. Counts confirmation
SELECT
  (SELECT count(*) FROM auth_users)                                              AS total_users,
  (SELECT count(*) FROM auth_users WHERE user_role = 'admin')                    AS admins,
  (SELECT count(*) FROM auth_users WHERE user_role = 'mga_principal')            AS mga_principals,
  (SELECT count(*) FROM auth_users WHERE user_role = 'advisor')                  AS advisors,
  (SELECT count(*) FROM clients WHERE active = true)                             AS active_clients,
  (SELECT count(*) FROM team_members WHERE active = true)                        AS active_team_members,
  (SELECT count(*) FROM insurance_carriers WHERE vertical_id = 'insurance')      AS carriers,
  (SELECT count(*) FROM carrier_products WHERE vertical_id = 'insurance')        AS products,
  (SELECT count(*) FROM leads)                                                   AS leads;

-- 2. Workflow activity heartbeat
SELECT count(*) AS executions_last_24h
FROM execution_entity
WHERE "startedAt" > now() - interval '24 hours';
-- (queries n8n's own db; only works if n8n shares the same Postgres)

-- 3. Compliance scorecard data is wiring up
SELECT * FROM compliance_scores
WHERE vertical_id = 'insurance'
ORDER BY snapshot_date DESC
LIMIT 1;
-- Empty is expected before C3 activates the cron.

-- 4. Insurer audit log is wiring up (after first portal login)
SELECT count(*) AS insurer_actions_logged
FROM insurer_access_log
WHERE created_at > now() - interval '24 hours';
```

---

## G. SMOKE-TEST SEQUENCE (do once after Section A + B complete)

**Advisor flow:**
1. Log in at `mga.crystallux.org` as an advisor (after B3).
2. Open **Today's Plan** → should show empty state or test tasks.
3. Open **Onboarding** → start Day 1 → click Start → verify status changes.
4. Open **Calculators** → run Income Replacement → confirm result.
5. Open **Product Compare** → pick 2-3 products from the seeded carriers → verify side-by-side renders.

**Principal flow:**
1. Log in as `info@crystallux.org`.
2. **Insurer Accounts** → create a test insurer account against an existing carrier_id.
3. **Demo Mode** → toggle on → verify dashboards show synthetic data; toggle off.
4. **Team Productivity / Team Goals** → confirms loads (likely empty until advisors are seeded).

**Insurer flow (after B1 deploys insurer-dashboard):**
1. From Principal → Insurer Accounts, invite a test insurer user.
2. That user signs in at `portal.crystallux.org`.
3. **Dashboard** → renders 4-quadrant layout.
4. **Compliance Scorecard** → shows score (after C3 activates the daily calculator).
5. **Monthly Production** → empty until carrier_id has policies; that's expected.
6. Confirm `SELECT * FROM insurer_access_log ORDER BY created_at DESC` shows every login + view.

---

## H. KNOWN UNKNOWNS / FUTURE WORK (not blocking launch)

- **n8n seed-workflow refactor** — move auth out of Code-node sandbox into HTTP-node parameters using `={{ $env.X }}` expressions. 2-hour next-session task. Until then, direct SQL seeds (Section A1) are the working pattern.
- **Auto DNS + SSL for white-label deployments** — Section 14 white-label workflow currently captures intent but DNS/SSL is manual Cloudflare config.
- **Phase 4 content publishers** — STUBS until platform APIs approve.
- **PDF/CSV report exports** — `production_reports.exported_count` is wired; renderer side-car is future work.
- **Sentinel Operations standalone product** — Year-1 internal use first, standalone later. See monetization doc Phase 7.

---

## Cross-references

- [`docs/audit/blockers.md`](../audit/blockers.md) — original 30-section deployment checklist (Sections 1–30 are the granular per-commit steps).
- [`docs/deployment/SEED_EXECUTION_GUIDE.md`](SEED_EXECUTION_GUIDE.md) — n8n-based seed guide (now superseded by `SEED_FIX_FINAL.md` for actual execution).
- [`docs/deployment/SEED_FIX_FINAL.md`](SEED_FIX_FINAL.md) — the working direct-SQL approach.
- [`docs/handbook/FOUNDER_OPERATIONS_HANDBOOK.md`](../handbook/FOUNDER_OPERATIONS_HANDBOOK.md) §6 — authoritative vendor reference for every external service.
- [`docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md`](../strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md) §13 — government funding programs + sequence. §14 — Victory Enrichment partnership compliance.
- [`docs/journal/SESSION_LOG.md`](../journal/SESSION_LOG.md) — chronological session history.
