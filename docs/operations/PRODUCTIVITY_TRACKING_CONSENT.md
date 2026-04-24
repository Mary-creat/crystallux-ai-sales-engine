# Productivity Tracking — Agent Consent

**Status:** Template · **Version:** 1.0 · **Effective:** 2026-04-25

Crystallux Productivity Tracking is a **coaching tool, not surveillance**.
Agents opt in voluntarily. Withdrawal is permanent for the current
cycle and disables further tracking immediately.

## What IS tracked

- Outreach activity generated inside Crystallux (emails sent, calls
  placed via Vapi, follow-ups, script usage).
- Appointments held (from the Calendly integration).
- Leads qualified / deals closed (self-reported via the dashboard).
- Dashboard session time (aggregate — how long the browser tab was
  focused on Crystallux, not what you clicked).

## What is NOT tracked

- Browsing outside Crystallux (no website monitoring).
- Keyboard, mouse, or clipboard (no keyloggers, no mouse heatmaps).
- Screen recording (no screenshots, no webcam).
- Personal messages or non-Crystallux communications.
- Activity outside your declared working hours.
- Any non-Crystallux application.

## Data retention

- Raw activity events: 12 months, then anonymised.
- Daily summaries: retained indefinitely, anonymised after 12 months.
- Agents can request deletion of their own data at any time via
  `support@crystallux.org`.

## Your rights (PIPEDA — Canadian federal privacy law)

- Access your data anytime via the dashboard ("My Productivity").
- Correct inaccuracies (contact support).
- Withdraw consent anytime (writes
  `team_members.productivity_tracking_consent = false`).
- File a complaint with the Privacy Commissioner of Canada.

## Who sees what

- **You:** always see your own data.
- **Your manager:** only if you explicitly toggle
  "Share with manager" on.
- **Mary / Crystallux admins:** aggregate platform stats only, not
  individual agent data, unless investigation is required and has
  been requested in writing.
- **Other clients / agents:** never.

## Coaching, not surveillance

We use this data to:

- Identify where you can grow professionally.
- Spot burnout signals early (3+ red days in a row triggers a
  coaching note, not a reprimand).
- Celebrate productive days.
- Suggest focus areas.

We do **not** use it to:

- Fire or discipline agents.
- Compare agents publicly.
- Share with other clients.
- Market or advertise.

## Consent form

By signing below, I consent to Crystallux tracking my work activity
as described above. I understand I may withdraw consent at any time.

- Agent name: ____________________________
- Agent email: ____________________________
- Client organisation: ____________________________
- Signature: ____________________________
- Date: ____________________________
- Consent version: 1.0

## Admin operational notes

- Collect via DocuSign or a signed PDF before flipping
  `team_members.productivity_tracking_consent = true`.
- Store signed forms in `docs/private/client-consent/` (gitignored).
- Record `productivity_tracking_consent_version = '1.0'` in the same
  UPDATE that sets the consent boolean.
- If this document is ever materially updated (retention changes,
  new data types, new disclosure), bump the version to 1.1 and
  invalidate every consent that carries 1.0 by setting
  `productivity_tracking_consent = false` for those rows and
  re-collecting.

## Version history

- **1.0** (2026-04-25) — Initial version.
