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

## Credential state — what is confirmed and what is only reported

Values are never written down here. This records **where each key lives and how
confidently that is known**, because the difference between "set" and "verified"
is what let a dead key sit unnoticed from June to August.

| Credential | Where | State |
|---|---|---|
| `N8N_API_KEY` | GitHub Actions secret | **Set 2026-08-30**, and independently verified — the deploy job probes it before touching anything |
| `N8N_URL` | GitHub Actions secret | **Set 2026-08-30** → `https://automation.crystallux.org` |
| `N8N_API_KEY` | VPS / server | **Reported set, NOT verified.** There is no server access from the working machine, so this is taken on trust. It stays "unknown" here until either a script run confirms it or `docker inspect` is shared |
| `MCP_WEBHOOK_SECRET` | VPS / server | **Unverified — must be checked before MCP is expected to work.** See [#3b](#3b-set-the-mcp-secret) |
| `N8N_ENCRYPTION_KEY` | VPS / server | **Untouched, by instruction.** Not read, not modified, not rotated. It decrypts every credential n8n stores; it is not an API key and must never be swapped for one |

**Why the server key still counts as unknown.** The GitHub key is checked
automatically on every push. Nothing on the VPS checks its key — it fails
silently until some script happens to need it. That asymmetry is the actual root
cause of the June–August outage, not the expiry itself.

---

## The short version

**Do #1 today.** It is five minutes of clicking and it unblocks three separate
systems that have been silently broken since roughly June. Everything else on
this list can wait a week; #1 should not.

---

| Priority | Action Needed | Why | Product | Exact Steps for Owner | What Work Continues Without It |
|---|---|---|---|---|---|
| **1** | **Mint a new n8n API key** and store it as a GitHub secret | The current key returns **401**. Three things depend on it and all three are quietly broken: Sentinel's workflow monitoring (`sentinel_workflow_health` has **0 rows, ever**), the daily briefing (today's says *"The paused workflow entry is incomplete"* — that is the 401 surfacing as a garbled report), and CI deployment. **This is why nobody noticed the Sales Engine stopped on 8 June: the system that would have reported it has been blind since before that** | Platform, Sentinel | See [§1 below](#1-mint-a-new-n8n-api-key) | Everything else. But no claim about "what is running in production" can be trusted until this is done |
| **1b** | **Allow Code nodes to read environment variables** | **53 workflows cannot read their own secrets.** Probed live today: the MCP gateway answers `{"error":"process is not defined"}`. Anything reading `process.env` fails at its auth step — **all four Copilot endpoints**, the **Stripe webhook**, email/SMS/WhatsApp sending, the whole agent runtime, most of MGA, and the video chain. `blockers.md` §0ag says this was already configured; it is not true of the running instance, so either it was never set or it was lost when the container was recreated. **This may be the real reason Copilot, the agent layer and video show zero usage — not lack of adoption, but inability to authenticate** | Copilot, Billing, Messaging, MGA, Video, Agentic, MCP | See [§1b](#1b-allow-code-nodes-to-read-environment-variables) | Everything not on that list. **LUXI, Commerce, Sentinel and the Sales Engine do not use `process.env` and are unaffected** — checked across all 326 workflows |
| **2** | **Delete the six duplicate DevOps briefing workflows** in n8n | **Seven identical briefings run every day** — verified across 14 consecutive days. The repo contains **one**. Six are duplicate copies living in n8n, and each one calls Claude, so you are paying seven times for one report | Productivity / Ops | See [§2](#2-delete-the-six-duplicate-briefings) | Nothing blocks. Worth knowing: the CI bug that manufactured these is fixed, so they will not come back |
| **3** | **Re-import 54 corrected workflows** to the live server | Security fixes that are finished in the repo but **not live**: 47 endpoints that answered a bad token with an empty `200` now answer `401`; 7 that swallowed an unknown action now answer `400`; and the MCP tool gateway, which checked that an API key *existed* but never that it was *right* | Platform, MCP | See [§3](#3-ship-the-fail-closed-fixes) | All further code work. These are additive — no successful request changes behaviour |
| **3b** | **Set `MCP_WEBHOOK_SECRET` on the VPS** | The MCP tool gateway shipped in the same push as #3. Its old behaviour was to check that an API key was *present* and never compare it — any non-empty header could run all ten tools, including one that writes to `leads` and one that spends Google Places quota. The fix **fails closed on purpose**, so until this variable is set, both MCP endpoints answer `401`. That is safer than what was there before, not worse — but it is a change, and this is how you finish it | MCP / Tool gateway | See [§3b](#3b-set-the-mcp-secret) | Everything. MCP usage is **5 calls in the table's entire lifetime**, so nothing real is waiting on it |
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

## 1b. Allow Code nodes to read environment variables

n8n blocks `process.env` inside Code nodes unless you tell it not to. 53 of your
workflows read secrets that way, so right now they all fail — quietly, with an
empty response, which is exactly why this went unnoticed.

**Please send me this first, before changing anything:**

```
docker inspect n8n --format '{{json .Config.Env}}'
```

Blank out the values — I only need the variable **names**. That tells me whether
`N8N_BLOCK_ENV_ACCESS_IN_NODE` is missing or set wrong, and at the same time
gives me the live environment I need for §5. One command answers both.

Once I have seen it I will tell you the exact line to change. The fix itself is
one variable plus `docker restart n8n`, but I do not want to guess at your live
configuration — that is how working systems break.

**Do not run `docker compose up -d`.** See the warning in §5.

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

## 3b. Set the MCP secret

Unlike the n8n API key, this one **is** read by n8n itself — Code nodes read it
from the container's environment — so n8n has to restart to see it.

On the server, generate a secret:

```
openssl rand -hex 32
```

Add it to the same file the other n8n variables live in, as:

```
MCP_WEBHOOK_SECRET=<the value you just generated>
```

Then restart n8n:

```
docker restart n8n
```

`docker restart` reuses the container's existing configuration, so it is safe —
it is not the same as the `docker compose up -d` warned about in §5.

Verify. The first must return `401`, the second `200`:

```
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://automation.crystallux.org/webhook/crystallux-mcp -H 'X-MCP-API-Key: wrong' -H 'Content-Type: application/json' -d '{"tool_name":"get_pipeline_stats"}'
```

```
curl -s -o /dev/null -w '%{http_code}\n' https://automation.crystallux.org/webhook/crystallux-tools -H "X-MCP-API-Key: $MCP_WEBHOOK_SECRET"
```

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

> ### ⛔ Do not run `docker compose up -d` with the repo's file yet
>
> **Checked 2026-08-30 and the repo's `docker-compose.yml` is not what your
> server is running.** Proof: `docs/audit/blockers.md` §0ag records that
> `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` is already set live, and that LUXI and
> the copilot both depend on it. That variable does not appear anywhere in the
> repo's compose file. Neither does `MCP_WEBHOOK_SECRET`.
>
> So the live container is configured from something else — an edited copy on
> the server, an `env_file`, or a compose override. Bringing the container up
> from the repo's file would hand it a **smaller** environment than it has now
> and could drop the variables LUXI and the copilot rely on.
>
> This is a real way to break a working system, and it is the one thing on this
> page that could cause an outage rather than fix one.

**What to do instead — read-only, tells us what is actually deployed:**

```
cd /root/clx-deploy
```

```
docker inspect n8n --format '{{json .Config.Env}}'
```

Send me that output with any passwords and keys blanked out. I need the
variable **names**, not the values. Once I can see the live environment I will
write a compose file that matches it, plus the queue-mode fix, and the change
becomes safe.

Until then the queue-mode fix stays in the repo and is **not applied**. The only
cost of waiting is that the `n8n-worker` container keeps idling, which is what
it has been doing all along — no new harm.

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

---

## 1c. Create the `Cloudflare R2` credential in n8n (blocks 4 workflows)

**Correction to what I told you earlier: this is not AWS and you do not need an
AWS account.** I named it "aws" because that is the word n8n put in the error,
without checking what the nodes actually are. Having now read all five of them:

Every R2 node in the estate is `n8n-nodes-base.awsS3` referencing a credential
named **`Cloudflare R2`**. n8n calls the credential *type* `aws` because
Cloudflare R2 speaks the S3 API — the type name is n8n's, the provider is
Cloudflare. The workflows reference it **by name**, and no credential with that
name exists in n8n. Across all 326 workflows there is exactly one `aws`
credential name, so there is no chance it already exists under an alias.

**What to create** — n8n → Credentials → New → **AWS**, named exactly:

```
Cloudflare R2
```

The name must match character for character or the workflows will not bind.

Fill it with an **R2 API token** from the Cloudflare dashboard (R2 → Manage API
Tokens), not an AWS key:

- Access Key ID / Secret Access Key — from the R2 token
- Region: `auto`
- Endpoint / custom S3 endpoint: your R2 S3 API URL

**Least privilege:** scope the R2 token to **Object Read & Write** on the single
bucket these workflows use (`R2_BUCKET`, default `crystallux-videos`). Do not
grant account-level or admin R2 permissions. Four of the five nodes only upload;
`clx-video-storage-cleanup-v1` deletes, so read+write on that one bucket is the
correct floor — read-only would break the cleanup job.

**No workflow changes are needed.** The nodes already name the credential
correctly; creating it is the whole fix. Once it exists, tell me and the next
push deploys all four.

**Not launch-critical.** `clx-heygen-webhook-v1` belongs to Video
(`video_renders` = 0 rows, never rendered). The other three belong to
Insurance/MGA document generation (`policy_applications` = 0). None of them sits
on the revenue path, so this is P2 — it does not gate anything you are trying to
sell.
