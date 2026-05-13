# Independent Operations Guide

> **For:** Mary running Crystallux as a solo non-technical founder without retained technical support.
>
> **Goal:** every routine question or routine breakage has a documented path that doesn't require external help. External help is reserved for genuinely hard problems (Section 7 below).
>
> **This guide doesn't duplicate the handbook.** It tells you which existing section to open when something happens, plus adds: escalation triggers, a decision tree, and a resource directory.

---

## 1. Daily operations (5 min, every morning, with coffee)

Open this in a tab during your first coffee. Do **all five** in order.

| # | Step | Where | What good looks like |
|---|---|---|---|
| 1 | Check the n8n status page | `https://automation.crystallux.org/healthz` | HTTP 200 |
| 2 | Check yesterday's leads count | Admin Copilot ✦ → "leads from yesterday" OR Supabase Studio → SQL Editor → `SELECT count(*) FROM leads WHERE created_at > now() - interval '1 day';` | Number > 0 if active acquisition; 0 acceptable if dormant |
| 3 | Check `scan_errors` for unresolved rows | Copilot ✦ → "show me unresolved scan errors" OR `SELECT count(*) FROM scan_errors WHERE resolved_at IS NULL;` | Ideally 0; > 5 means inspect |
| 4 | Skim today's calendar — any meetings on `bookings`? | `mga.crystallux.org/advisor/today.html` | List loads; brief generated if any meeting < 2h away |
| 5 | Glance at `regulatory_audit_log` for yesterday's principal actions | Copilot ✦ → "show me yesterday's audit log actions" | Mostly your own actions; anything unexpected is a flag |

**Full version with exact SQL:** `docs/handbook/FOUNDER_OPERATIONS_HANDBOOK.md` §3.1.

---

## 2. Weekly operations (30 min, every Monday morning)

| # | Step | Why |
|---|---|---|
| 1 | Apply Sessions 1–3 schemas if any new migration landed | Keep production schema current |
| 2 | Re-import any newly-modified workflows | Stay in sync with `scale-sprint-v1` |
| 3 | Activate / deactivate workflows as needed | Per `COMPLETE_WIRING_CHECKLIST.md` Section C3 |
| 4 | Review last week's MRR + lead volume | Track Phase 1 + Phase 2 progress against monetization-strategy targets |
| 5 | Review last week's `scan_errors` resolution rate | Operational hygiene |
| 6 | Review pending carrier appointment applications | Phase 1 dependency |
| 7 | Update `docs/journal/CRYSTALLUX_STATUS.md` with current state | Future-self continuity |

**Full version with checklists:** `FOUNDER_OPERATIONS_HANDBOOK.md` §3.2.

---

## 3. Monthly operations (2 hours, every 1st of month)

| # | Step | Why |
|---|---|---|
| 1 | Reconcile Stripe + bank | Catch billing failures early |
| 2 | Pay vendor invoices (Postmark, Twilio, HeyGen, n8n hosting, Supabase, etc.) | Stay paid up — see Section 8 below for the vendor list |
| 3 | Review monthly production report per active MGA tenant | Self-audit + insurer-pitch material |
| 4 | Run the SR&ED technical log monthly batch entry | Future tax refund — see `MONETIZATION_STRATEGY.md` §13 |
| 5 | Check carrier appointment progress + apply for one new carrier | Diversify Phase 1 revenue |
| 6 | Review monetization-strategy phase-by-phase status | Adjust execution priorities |
| 7 | Update `MEMORY.md` index in `~/.claude/projects/.../memory/` if anything material changed | Cross-session continuity |
| 8 | Back up Supabase manually (one-click in Supabase Studio) | Belt and suspenders |

**Full version:** `FOUNDER_OPERATIONS_HANDBOOK.md` §3.3.

---

## 4. Emergency procedures (read these once now, before you need them)

The handbook §4 contains seven playbooks. **Bookmark this list:**

| Scenario | Playbook | Time-to-recovery |
|---|---|---|
| Everything is down (every webhook returns 5xx) | §4.1 — "Everything is down" | 15–60 min |
| Lead generation stopped (zero new leads in 24h) | §4.2 — "Lead generation stopped" | 30 min – 2 hrs |
| I lost my keys / master token | §4.3 — "I lost my keys" | 1–4 hrs (regenerate + redeploy) |
| Customer says something is broken | §4.4 — "Customer says something is broken" | varies — see playbook |
| I need to roll back a bad deploy | §4.5 — "I need to roll back" | 5–30 min |
| Database is broken | §4.6 — "Database is broken" | 30 min – 2 hrs |
| Need emergency contacts | §4.7 — "Emergency contacts" | 5 min |

**Action: open `FOUNDER_OPERATIONS_HANDBOOK.md` §4 once this week and skim all 7 playbooks.** Read them when calm. Re-reading during an incident wastes the most valuable 10 minutes you have.

---

## 5. Which tool for which problem

You have **3 tools** for operating Crystallux. Use the right one for the job.

### 5a. Admin Copilot ✦ (in-product chat assistant)

**Use for:**
- Quick database questions ("how many leads today?")
- Diagnosing a single `scan_errors` row
- Asking "what does workflow X do?"
- Anything you'd open Supabase Studio for just to run one SELECT

**Don't use for:**
- Writing or executing migrations
- Restarting containers
- Editing workflows
- Anything multi-step

**How to use:** see `OPERATIONS_ASSISTANT_VISION.md`.

**Cost:** $20–$50/month at normal use.

### 5b. Claude Code (CLI / chat with repo access)

**Use for:**
- Writing or modifying workflows
- Reading + writing repo files
- Generating SQL migrations
- Diagnosing a bug across multiple files
- Building new features
- Drafting documentation

**Don't use for:**
- Live database inspection (use Copilot or Supabase Studio)
- Live operational SSH (use a terminal)

**Cost:** Anthropic API + your time. Subscription if you use Claude Pro/Max.

### 5c. Terminal / direct SSH / Supabase Studio

**Use for:**
- Restarting containers (`docker compose restart`)
- Tail logs (`docker logs n8n -f`)
- Direct SQL on Supabase (the SQL Editor)
- Running curl smoke tests
- Anything Copilot or Claude Code can't do

---

## 6. Self-service troubleshooting decision tree

When something breaks, walk this tree top-to-bottom. Stop at the first branch that matches.

```
SOMETHING IS BROKEN
│
├─ Is it user-visible (someone saw an error in a UI)?
│   │
│   ├─ YES → start with §4.4 "Customer says something is broken"
│   │       → ask Copilot ✦ for a SELECT on the relevant table
│   │       → if still stuck, jump to "Is it the platform?" below
│   │
│   └─ NO → it's an alerting issue → go to "Is alerting noisy?" below
│
├─ Is the platform itself unreachable (mga.crystallux.org / admin.crystallux.org return 5xx or timeout)?
│   │
│   ├─ Cloudflare Pages? → check Cloudflare status page; redeploy from Pages UI
│   ├─ n8n container? → SSH → docker ps → docker logs n8n --tail 100 → restart if dead
│   ├─ Supabase? → check status.supabase.com; failover plan in §4.6
│   │
│   └─ All up but slow? → check Supabase query performance / n8n executions log
│
├─ Is alerting noisy (scan_errors filling up)?
│   │
│   ├─ Same error repeating → likely a workflow with bad credential or schema change
│   │     → Copilot ✦ → "show me top 5 scan_errors by count today"
│   │     → fix root cause → mark batch as resolved
│   │
│   └─ Different errors mixed → triage by severity, fix one at a time
│
├─ Is it a money / billing issue?
│   │
│   ├─ Stripe webhook failed → check Stripe webhook dashboard for failed deliveries → replay
│   ├─ Carrier commission mismatch → reconcile via reports, contact carrier MGA-relations
│   └─ Customer can't pay → SaaS subscription failed → §4.4 playbook
│
└─ Is it a compliance / regulatory issue?
    │
    ├─ Suitability or replacement disclosure missing on an issued policy → STOP
    │     → engage compliance officer or escalate (Section 7 below)
    │     → do NOT improvise
    │
    └─ Audit-log gap → reproducible? → file as scan_error → fix workflow → backfill audit log via direct INSERT
```

---

## 7. When to seek external help — escalation triggers

You're a solo founder. Asking for help is **operational efficiency**, not weakness. Escalate when **any** of the following are true:

### 7a. Technical escalation triggers

- A platform issue has resisted your fixes for **> 2 hours** of focused work.
- The error involves payment processing or money flowing the wrong way.
- The error involves regulatory data (compliance, audit log, suitability, replacement disclosure).
- You're considering running a `DELETE` or `DROP` and you're not 100% sure of the consequence.
- The error is in production and a customer is affected for **> 30 minutes**.
- You've run `git push --force` or similar destructive git op and want to verify before continuing.

→ **Who to escalate to:**
- **Freelance DevOps** (Upwork, Toptal, or referral) — $50–$150/hr — for n8n / Docker / Cloudflare / Supabase ops issues.
- **Freelance full-stack** ($75–$200/hr) — for repo-level work that Claude Code is struggling on.
- **Claude Code in a new chat** — paste the failing command + actual output + ask. Often unblocks in 1 round-trip.

### 7b. Regulatory / legal escalation triggers

- Customer complaint about a policy + suitability concern.
- Carrier audit notification.
- FSRA / AMF / IIROC inquiry.
- PIPEDA complaint or data breach suspicion.
- Any related-party transaction with Victory Enrichment (per `MONETIZATION_STRATEGY.md` §14, lawyer review is **non-negotiable** before execution).

→ **Who to escalate to:**
- **Non-profit / charity lawyer** (Drache Aptowitzer / Carters Professional Corp) — for Victory-related questions.
- **Insurance regulatory lawyer** (Norton Rose Fulbright / McMillan / Cassels) — for carrier / regulator escalations.
- **Privacy lawyer / OPC submission** — for PIPEDA matters.
- **Your E&O insurer's claim hotline** — if a customer-facing incident could trigger E&O coverage.

### 7c. Strategic escalation triggers

- A potential customer asking for terms you've never given (custom pricing, white-label, enterprise SLA).
- A potential investor inquiry.
- A potential acquirer inquiry.
- A potential carrier-strategic-partnership inquiry.

→ **Who to escalate to:**
- **Accountant / fractional CFO** (for pricing + financial-model questions).
- **Founder / startup advisor** (mentor network — many of you are 1 intro away from a great one).
- **Securities / corporate lawyer** for investor + acquirer conversations.

**Rule:** never close an irreversible decision (firing customer, signing investor term sheet, accepting acquisition offer) in fewer than **72 hours**, even if the other side pressures urgency. Pressure to move fast is a red flag, not a green light.

---

## 8. Resource directory (vendor + support contacts)

This is the operational rolodex. **Update as you sign vendors. Print and stick to wall if useful.**

### Critical platform vendors (call these if the platform is down)

| Vendor | Why critical | Account email | Support email / URL |
|---|---|---|---|
| **Supabase** | Database | `info@crystallux.org` | https://supabase.com/dashboard/support/new |
| **Cloudflare** | DNS + frontends + R2 | `info@crystallux.org` | https://dash.cloudflare.com/?to=/:account/support |
| **VPS provider** (Hetzner / DigitalOcean / etc.) | n8n container hosting | (your account) | (provider's support panel) |
| **Anthropic** | Claude API for AI features | `info@crystallux.org` | https://console.anthropic.com/support |

### Operational vendors (impact features, not platform uptime)

| Vendor | Feature | Support |
|---|---|---|
| **Postmark** | Email | support@postmarkapp.com |
| **Twilio** | SMS / WhatsApp / voice | https://support.twilio.com |
| **HeyGen** | AI video personas | support@heygen.com |
| **Stripe** | Billing + Identity | https://support.stripe.com |
| **Cal.com** | Booking | https://cal.com/help |
| **Zoho Sign** | E-signatures | https://www.zoho.com/sign/support.html |
| **Vapi** | Voice agent | https://vapi.ai/support |
| **ElevenLabs** | Voice cloning | https://elevenlabs.io/support |
| **Certn** | Background checks | support@certn.co |
| **NewsAPI / OpenWeather** | Market intel signals | (low criticality; degraded gracefully) |

### Insurance-industry contacts (Phase 1 / Phase 4)

| Contact | Type | Email |
|---|---|---|
| **Walnut Insurance** | Carrier appointment | partners@walnutinsurance.com |
| **PolicyMe** | Carrier appointment | partners@policyme.com |
| **Apollo Insurance** | Carrier appointment | (apply via their MGA portal) |
| **Manulife / Sun Life / Canada Life** | Carrier appointment (tier 1, later) | (apply via each carrier's broker-services portal) |
| **Your E&O insurer** | Professional liability | (insert when bound) |

### Government / funding (per MONETIZATION_STRATEGY §13)

| Program | Office | Contact |
|---|---|---|
| **SR&ED specialist** | (engage Year 2+) | G6 Consulting / RDP Associates / NorthBridge |
| **NRC IRAP** | Toronto regional office | nrc-cnrc.gc.ca/eng/irap |
| **CDAP** | Federal economic development | ised-isde.canada.ca/cdap |
| **Ontario Trillium Foundation** | (Victory Enrichment use) | otf.ca |
| **Provincial economic dev** | Ontario Together Trade Fund / Investissement Québec / etc. | (province-specific) |

### Legal (per MONETIZATION_STRATEGY §14)

| Need | Suggested firm |
|---|---|
| Non-profit / charity law (Victory Enrichment) | Drache Aptowitzer / Carters Professional Corp |
| Insurance regulatory | Norton Rose Fulbright / McMillan / Cassels |
| Privacy / PIPEDA | INQ Law / nNovation LLP |
| Corporate / securities | Osler / Stikeman / Fasken |

### Documentation locations (when something's confusing)

| Question | Doc to open |
|---|---|
| "Where do I deploy / wire / activate X?" | `docs/deployment/COMPLETE_WIRING_CHECKLIST.md` |
| "How does feature X work?" | `docs/architecture/OPERATIONS_HANDBOOK.md` (the big architecture doc) |
| "What's the revenue strategy?" | `docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md` |
| "How do I do daily / weekly / monthly operations?" | `docs/handbook/FOUNDER_OPERATIONS_HANDBOOK.md` §3 |
| "Something is on fire" | `docs/handbook/FOUNDER_OPERATIONS_HANDBOOK.md` §4 |
| "How do I make a decision about pricing / hiring / etc?" | `docs/handbook/FOUNDER_OPERATIONS_HANDBOOK.md` §7 |
| "What's the latest state?" | `docs/journal/SESSION_LOG.md` (most-recent entry) |
| "What is the Admin Copilot ✦?" | `docs/handbook/OPERATIONS_ASSISTANT_VISION.md` |

---

## 9. The "I'm overwhelmed" reset

If you're spinning, here's the **shortest possible sequence** to know where you stand:

```bash
# 1. Verify platform health (10 sec each)
curl -fsSI https://mga.crystallux.org/ | head -1
curl -fsSI https://admin.crystallux.org/ | head -1
curl -fsSI https://app.crystallux.org/ | head -1
```

```sql
-- 2. In Supabase SQL Editor — health-check query (one shot)
SELECT
  (SELECT count(*) FROM leads WHERE created_at > now() - interval '7 days')                    AS leads_last_7d,
  (SELECT count(*) FROM bookings WHERE created_at > now() - interval '7 days')                 AS bookings_last_7d,
  (SELECT count(*) FROM scan_errors WHERE resolved_at IS NULL)                                 AS unresolved_errors,
  (SELECT count(*) FROM auth_users WHERE user_role IN ('advisor','sub_agent') AND is_active)   AS active_advisors,
  (SELECT count(*) FROM insurance_carriers WHERE vertical_id = 'insurance' AND active)         AS active_carriers;
```

```
3. Open docs/journal/SESSION_LOG.md → read the most-recent entry.
4. Open docs/deployment/COMPLETE_WIRING_CHECKLIST.md → find your time-horizon row.
5. Do the next single task in the checklist. Just that one. Then breathe.
```

If you've done all 5 and still feel lost, you've earned a 30-minute break. Take it.

---

## 10. The honest summary

Operating Crystallux as a solo founder is a stack of small daily disciplines. The platform is built. The handbook is written. The Admin Copilot ✦ is ready to activate. The wiring checklist is sequenced. The monetization strategy is documented.

**Most of your operational problems will be resolved by reading the right section of the right doc.** External help is for the genuinely-hard 10% — escalate without hesitation when those triggers fire (Section 7), and don't burn yourself out trying to solve everything alone.

---

## Cross-references

- [`FOUNDER_OPERATIONS_HANDBOOK.md`](FOUNDER_OPERATIONS_HANDBOOK.md) — the canonical operations handbook. This guide is its distillation + glue.
- [`OPERATIONS_ASSISTANT_VISION.md`](OPERATIONS_ASSISTANT_VISION.md) — the Admin Copilot ✦.
- [`../deployment/COMPLETE_WIRING_CHECKLIST.md`](../deployment/COMPLETE_WIRING_CHECKLIST.md) — remaining-work roadmap.
- [`../deployment/SEED_FIX_FINAL.md`](../deployment/SEED_FIX_FINAL.md) — current deployment unblock.
- [`../strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md`](../strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md) — revenue + funding + Victory partnership.
- [`../audit/blockers.md`](../audit/blockers.md) — granular per-commit deployment checklist.
- [`../journal/SESSION_LOG.md`](../journal/SESSION_LOG.md) — chronological session memory.
