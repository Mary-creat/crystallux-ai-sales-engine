# Onboarding Call Script — 30 Minutes

**Purpose:** structured kickoff call between Mary and a newly-signed client. Converts contract-signing energy into configured-and-running pipeline within the hour.

**Pre-call setup:**

- Client has a Calendly-booked 30-minute slot
- Mary has their contract in front of her (on-screen, with key fields highlighted)
- Mary has a blank `clients` row ready to fill in Supabase
- Mary has a dashboard URL template ready

---

## Pre-call email (sent 24h before)

Mary sends this 24 hours before the scheduled onboarding call.

```
Subject: Tomorrow's onboarding — 3 things to bring

Hi [First Name],

Excited for our call tomorrow at [time]. 30 minutes, we'll knock
out everything we need to get you live.

Three things to have ready:

1. **Your ideal client profile specifics** — top 3 customer types
   in the last 12 months. Rough sizes, industries, cities served.
   One sentence each is enough.

2. **Your Calendly or preferred booking URL** — where I should
   route qualified leads to book calls with you.

3. **Email sender authorisation** — if you want outreach to send
   from your own business email (not info@crystallux.org), have
   the admin of that inbox ready to grant Gmail delegation. If
   you'd rather start with a generic sender and transition later,
   totally fine — we do that with most clients.

Call details: [Zoom / Google Meet link]

— Mary

PS: no pre-work needed beyond the above. We do the heavy lifting
on the call.
```

---

## Call structure (30 minutes, time-boxed)

### 0:00 - 5:00 · Welcome + relationship building

> "Hi [First Name], thanks for making the time. Before we dive in
> I want to make sure we're clear on one thing: this call is me
> doing 80% of the setup in real time, so by the end of 30 minutes
> you have a working dashboard and your first campaign is getting
> seeded. You just provide a few answers I'll walk you through.
>
> Any questions from the contract or the demo you want to touch
> first?"

If they have contract questions: address directly, don't defer. Usually takes 2-3 minutes max.

If no questions: "Great, let's go."

### 5:00 - 15:00 · Information gathering

Use this checklist in front of you. Fill in answers live — don't save for "after the call" or you'll forget details and have to follow up.

#### ICP refinement

- "Give me your top 3 customer types from the last 12 months. Just titles / business types / locations."
- "What size of business is your sweet spot? Revenue range or employee count?"
- "What service area do you cover — by province, city, or radius?"
- "Residential, commercial, or both?" *(sets `clients.focus_segments`)*
- "Which vertical fits you best from our catalog — [list matching verticals from their contract]?" *(confirm `clients.vertical`)*

#### Channel configuration

- "Which channels do you want live from day 1?" *(sets `clients.channels_enabled`)*
  - Email — always on
  - LinkedIn — requires Unipile credential; ask if they have their LinkedIn login-ready
  - SMS / WhatsApp — requires Twilio; default off unless they're primarily residential
  - Voice — deferred (DNCL real-check blocker); explain timeline
  - Video — deferred (24h Tavus training); offer for month 2

#### Calendly + booking

- "What's your Calendly link for discovery calls?" *(sets `clients.calendly_link`)*
- "Preferred meeting length when qualified replies come in — 15, 20, 30 minutes?"
- "Any specific times/days you don't want meetings booked? (weekends, etc.)"

#### Sender email

- "Will outreach send from info@crystallux.org (generic) or your own email (e.g., [name]@[company].com)?"
- If own email: walk through Gmail OAuth delegation steps now or schedule a 10-minute follow-up

#### Existing leads

- "Do you have an existing lead list (CSV, CRM export) you want to import?"
- If yes: we'll import post-call; they need to have CASL-compliant contacts only
- If no: we'll source from scratch via Apollo + vertical discovery sources

### 15:00 - 25:00 · Platform walkthrough (live in their account)

Share screen. Open their dashboard using the URL + token you've just provisioned.

#### Dashboard tour (5 minutes)

Point with cursor at each panel:

1. **Client context banner** — confirms they're looking at their account specifically
2. **Pipeline stats** — will populate within 24h as the first prospects land
3. **Leads grid** — empty for now; will fill with sourced prospects
4. **Channels Active** — shows which channels they've enabled
5. **Billing panel** — reflects their Stripe subscription (if Stripe activation is complete)
6. **Recent emails** — where they'll see outreach sends as they happen

#### First campaign setup (3 minutes)

Show them what happens in the next 24 hours:

> "Here's what happens next. I'm going to load the first 50
> prospects matching your ICP into your account this afternoon.
> Lead research runs tonight — Claude drafts a one-paragraph
> research summary on each. Tomorrow morning, the campaign router
> assigns them to campaigns. By tomorrow afternoon, outreach
> generation is queued.
>
> Wednesday morning, you'll see the first batch of 10-15 draft
> outreach emails in your dashboard. Review them, flag anything
> that feels off, and we send.
>
> First real outreach hits a prospect's inbox Thursday at the
> latest."

Show them where to click in the dashboard to review drafts.

#### Weekly check-in schedule (2 minutes)

> "Every Friday, we do a 15-minute check-in call. Same Zoom link,
> same time. Agenda is always: wins this week, metrics review,
> blockers, optimisations, your questions.
>
> First check-in is [date 7 days from today]. I'll send the
> calendar invite after this call."

### 25:00 - 30:00 · First-week expectations + next check-in

> "Three things to watch for in the next week:
>
> 1. **Wednesday** — draft outreach ready for your review. Takes
>    about 15 minutes to read 10-15 drafts and flag issues.
>
> 2. **Thursday** — first real outreach goes out. You'll see it
>    in your dashboard's recent-emails panel.
>
> 3. **Friday** — our first weekly check-in. Come with any
>    questions or adjustments.
>
> If anything urgent comes up between now and Friday, email
> info@crystallux.org — I respond within 4 business hours.
>
> Your dashboard URL + token are in the welcome email that
> hit your inbox 2 minutes ago. Bookmark it.
>
> Sound good?"

Capture their yes. End the call.

---

## Post-call checklist (within 2 hours of call)

Mary executes these in order:

- [ ] **Create/update the client row** in Supabase with:
  - `client_name`
  - `client_slug` (URL-friendly, for intake URL)
  - `vertical`
  - `focus_segments` (from their residential/commercial answer)
  - `channels_enabled` (from their channel answer)
  - `calendly_link`
  - `notification_email` (their preferred ops email)
  - `dashboard_token` (generated)
- [ ] **Provision Stripe subscription** via `clx-stripe-provision-v1` webhook POST per `OPERATIONS_HANDBOOK §21.8`
- [ ] **Load first 50 prospects** matching their ICP (manual Apollo query + SQL insert, or via the form intake for bulk CSV)
- [ ] **Run pipeline dry** by triggering `clx-lead-research-v2` manual webhook for each — pipeline flows through to `clx-outreach-generation-v2` automatically
- [ ] **Test first outreach in TESTING MODE** — confirm drafts land in `adesholaakintunde+clxtest@gmail.com`, check copy quality before flipping any channel live
- [ ] **Send dashboard URL welcome email** (see template in `docs/commercial/DEMO_VIDEO_SCRIPT.md` — post-demo email variant)
- [ ] **Schedule day-7 check-in call** via Calendly; send calendar invite
- [ ] **Add client to weekly review rotation** (Notion / Google Sheet tracking all active clients for Friday check-ins)
- [ ] **Start day-7 monitoring** for early churn signals (see `docs/operations/CLIENT_SUCCESS_PLAYBOOK.md`)

---

## Common objections during the onboarding call + responses

### "I'm worried my ICP is too narrow"

> "That's actually the best case. The narrower we start, the more
> personalised the outreach can be. We can widen in week 2 if
> volume is too low. We can't narrow quickly once we've sent
> broad — clients hate it when an unrelated lead shows up."

### "I don't want my existing leads to receive automated outreach"

> "Totally respected. We can flag your existing leads as
> `do_not_contact=true` in your client row. They'll never receive
> Crystallux outreach. We source net-new prospects for you."

### "What if the outreach copy makes me look bad?"

> "Three safeguards: (1) you review every first-batch draft
> before anything sends; (2) you can pause any channel or the
> whole workflow with one email to me; (3) the outreach is
> peer-advisor tone, not vendor pitch — we can show you live
> examples from other clients in your vertical right now."

### "What happens if a reply gets through and I'm not ready?"

> "The reply lands in your dashboard and hits your `notification_email`
> within 2 minutes. You respond directly to the prospect from your
> own email. Crystallux doesn't auto-reply on your behalf for any
> real business conversations — only the initial outreach is
> automated."

### "Can we just start with email and add other channels later?"

> "Yes — most founding clients do exactly that. Email activates in
> week 1. LinkedIn can be added any time after Unipile is
> configured (2-3 day setup). Voice and video are month-2
> decisions. We pace channel activation to your comfort."

### "What does the guarantee window actually mean?"

> "Your first 30 days of paid service. If we don't hit your target
> (e.g., 10 qualified meetings for consulting), your second month
> is automatically free — no invoice. The 30-day clock starts on
> your first real outreach send, not today's contract date.
> Usually that's within 5 business days."

---

## Red flags to capture during the call

If any of these surface, flag to revisit within 48 hours:

- **Client can't articulate their ICP in 2 sentences** — they don't know who they're selling to yet; outreach will be generic
- **Client wants immediate high-volume sends** (50+ per day from day 1) — deliverability risk; pace them down
- **Client asks for custom HTML email templates** — outside our product scope; redirect to dedicated-replica video or custom integration add-on
- **Client has never used a CRM or dashboard** — onboarding will need more hand-holding; book a second 30-minute session
- **Client's vertical is on the inactive list (legal/moving/cleaning)** — should not have signed; exit gracefully, refund if needed

---

## Call recording policy

- **Record with consent only.** Open the call: "I'd like to record this so I don't miss details in the configuration — is that okay with you?"
- **Use Loom or Zoom recording**, not third-party recording tools
- **Store in Google Drive** under `/clients/[client-slug]/onboarding-recording.mp4`
- **Delete after 180 days** unless the client becomes a case-study candidate (then keep per consent form)
- **Never share the recording** outside Crystallux without written consent

If client declines: don't record. Take notes in real time. Follow up with a written recap email within 24 hours.
