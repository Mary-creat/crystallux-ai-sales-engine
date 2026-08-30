# Owner actions required — Mary

**Things only you can do.** Everything on this list needs a credential, a
payment, an approval, a physical device, or permission to touch real customers
and real money. Engineering work does not stop while these sit here — the last
column says exactly what continues without each one.

Companion to [`PROJECT_MASTER_COMPLETION.md`](PROJECT_MASTER_COMPLETION.md),
which is the full state of the platform. The long historical backlog lives in
[`docs/audit/blockers.md`](../audit/blockers.md); this file is only the open
owner-gated items, newest thinking first.

Last reviewed: **2026-08-30**.

---

## The short version

**Do #1 today.** It is five minutes of clicking and it unblocks three separate
systems that have been silently broken since roughly June. Everything else on
this list can wait a week; #1 should not.

---

| Priority | Action Needed | Why | Product | Exact Steps for Owner | What Work Continues Without It |
|---|---|---|---|---|---|
| **1** | **Mint a new n8n API key** and store it as a GitHub secret | The current key returns **401**. Three things depend on it and all three are quietly broken: Sentinel's workflow monitoring (`sentinel_workflow_health` has **0 rows, ever**), the daily briefing (today's says *"The paused workflow entry is incomplete"* — that is the 401 surfacing as a garbled report), and CI deployment. **This is why nobody noticed the Sales Engine stopped on 8 June: the system that would have reported it has been blind since before that** | Platform, Sentinel | See [§1 below](#1-mint-a-new-n8n-api-key) | Everything else. But no claim about "what is running in production" can be trusted until this is done |
| **2** | **Delete the six duplicate DevOps briefing workflows** in n8n | **Seven identical briefings run every day** — verified across 14 consecutive days. The repo contains **one**. Six are duplicate copies living in n8n, and each one calls Claude, so you are paying seven times for one report | Productivity / Ops | See [§2](#2-delete-the-six-duplicate-briefings) | Nothing blocks. Worth knowing: the CI bug that manufactured these is fixed, so they will not come back |
| **3** | **Re-import 54 corrected workflows** to the live server | Security fixes that are finished in the repo but **not live**: 47 endpoints that answered a bad token with an empty `200` now answer `401`; 7 that swallowed an unknown action now answer `400`; and the MCP tool gateway, which checked that an API key *existed* but never that it was *right* | Platform, MCP | See [§3](#3-ship-the-fail-closed-fixes) | All further code work. These are additive — no successful request changes behaviour |
| **4** | **Put one real order through LUXI / Commerce** | **0 orders, 0 reservations, 0 commerce events — ever.** The stack runs on live Stripe keys and has never taken a payment. This is the largest untested surface on the platform, and it involves real money, so it needs you | LUXI / Commerce, Billing | See [§4](#4-sell-one-thing) | Everything. But "commercially ready" cannot honestly be claimed for a commerce product that has never completed a sale |
| **5** | **Restart n8n to pick up the queue-mode fix** | The main n8n container ran in `regular` mode while a worker container ran in `queue` mode. n8n only hands jobs to a worker when the **main** instance is in queue mode, so the worker has been sitting idle — a scaling tier you are paying for in RAM and never reached. Fixed in the repo; applying it restarts n8n (~20 seconds), which is why it is your call | Platform | See [§5](#5-apply-the-queue-mode-fix) | Everything. This is a performance fix, not a correctness one |
| **6** | **Decide: restart the Sales Engine, or retire it** | No lead acquired since **2026-05-28**. No email sent since **2026-06-08**. 13 emails, ever, all to the test inbox. Meanwhile 2,518 leads sit in the database and **831 of them score 50 or above** — the qualified pipeline exists and nothing is touching it. Restarting means real outreach to real businesses, which is your authorization to give | Sales Engine | Needs #1 first, so you can see which schedules are actually on. Then say restart or retire — a decision either way | Everything. But a fourth month of accidental darkness is worse than a deliberate retirement |
| **7** | **Platform approvals for social + WhatsApp** | All six social publishers are stubs and the content distribution loop is a shell. WhatsApp is gated on Meta review. These are external companies' approval queues — no amount of engineering shortens them | Creative / Content, Messaging | Submit Meta (WhatsApp Business + Instagram), LinkedIn, and TikTok app reviews. Each takes days to weeks | Everything else. Content and messaging stay `STUB` / `BLOCKED_EXTERNAL` until the approvals land |
| **8** | **Provision avatar media IDs, or formally defer six of seven** | Seven personas are registered — AVA, LUXI, MAXI, LUMI, LUMA, LETY, EAZA — but **only LUXI has HeyGen and ElevenLabs IDs**. The other six cannot render or speak. Provisioning costs money per persona | Avatars | Either buy the HeyGen/ElevenLabs seats for the six, or mark them deferred so they stop reading as broken | Everything. Right now six personas look half-built when they are actually unfunded |

---

## 1. Mint a new n8n API key

**Do this one first.** Five minutes.

1. Open <https://automation.crystallux.org> and log in.
2. Go to **Settings → API**.
3. Click **Create an API key**. Copy it.
4. Open <https://github.com/Mary-creat/crystallux-ai-sales-engine/settings/secrets/actions>
5. Find `N8N_API_KEY`, click the pencil icon, paste the new key, save.
6. Check `N8N_URL` is also set there. It should be:

```
https://automation.crystallux.org
```

7. Tell me it is done. I will confirm the key works and report what is actually
   running in production — which nobody has been able to see for months.

**Keep the key somewhere safe.** It is the credential the whole deployment path
depends on.

---

## 2. Delete the six duplicate briefings

Do this **after** #1, because the cleanup script needs the API key.

In n8n, open the workflow list and search for the DevOps briefing workflow. You
will see seven near-identical entries. Keep the one whose name matches the repo
exactly; delete the other six.

There is also a script for it:

```
bash scripts/n8n/audit-duplicates.sh
```

That one is **read-only** — it shows you what it would remove. Run it first and
send me the output before deleting anything, so we agree on which six.

---

## 3. Ship the fail-closed fixes

54 workflows changed. All additive: a request that succeeds today still
succeeds, with the same response. What changes is that a request that should
have been *rejected* now actually gets rejected, instead of receiving an empty
`200` that looks like the endpoint is broken.

On the server:

```
cd /root/clx-deploy
```

```
git pull origin main
```

Then re-import. The existing helper takes one file at a time:

```
bash scripts/n8n/ship.sh <filename.json>
```

Once #1 is done, CI does this automatically on every push and you will not need
to run it by hand again.

---

## 4. Sell one thing

The commerce stack is wired to **live Stripe keys** and has never taken a
payment. Everything about it — reservation, payment, fulfilment, the ledger —
is unproven against reality.

Suggested smallest safe test:

1. In the admin console, open **Commerce** and add one cheap real item.
2. Open it as a lot in the live sale queue.
3. From a different browser (or your phone), buy it yourself with a real card.
4. Confirm all four: the order appears, stock decrements, the ledger row is
   written, and Stripe shows the payment.
5. Refund yourself.

That single loop tests more of the commerce product than every static check in
this repo combined. **It moves real money, so it needs to be you.**

---

## 5. Apply the queue-mode fix

This restarts n8n for roughly twenty seconds. Pick a quiet moment.

On the server:

```
cd /root/clx-deploy
```

```
git pull origin main
```

```
docker compose up -d n8n n8n-worker
```

Afterwards, confirm n8n is healthy:

```
docker compose ps
```

If anything looks wrong, the rollback is to set `EXECUTIONS_MODE` back to
`regular` in `docker-compose.yml` and run the same `up -d` command. Tell me and
I will walk you through it.

---

## Closed recently

- **"Top up Anthropic credits"** — named as *the* blocker in every document since
  June. **Verified 2026-08-28: the API key returns HTTP 200**, and the briefing
  workflow calls Claude seven times a day and gets output. Credits were not the
  blocker and had not been for some time. The Sales Engine is dark because its
  scheduled workflows are not running.
- **MCP tool gateway auth** — fixed in the repo at `0a17874`. Ships with #3.
- **CI manufacturing duplicate workflows** — fixed 2026-08-30. This was the
  source of the duplicates in #2; they will not regenerate.
