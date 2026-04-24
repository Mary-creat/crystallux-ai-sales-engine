# Call Recording & Analysis — Consent Policy

**Status:** Template · **Version:** 1.0 · **Effective:** 2026-04-25

This document governs how Crystallux records, transcribes, and
analyses voice calls under Canadian law. It applies any time
Listening Intelligence (B.12c-1) is active for a client.

## Canadian legal framework

Under federal (PIPEDA) and provincial privacy law, both parties on
a call must be informed that the call is being recorded. Single-party
consent, which is acceptable in some US jurisdictions, is **not**
sufficient in Canada. CRTC Unsolicited Telecommunications Rules
reinforce this for outbound commercial calls.

Key implications:

- Every recorded call must open with a disclosure. Script lives in
  `clients.customer_consent_disclosure_script` (default English
  template supplied by the migration).
- Customers may opt out at any time during the call. Opt-out must
  stop recording + transcription immediately.
- Recorded calls are personal information under PIPEDA — access,
  correction, deletion, and complaint rights all apply.

## Agent consent

Agents using the platform consent to:

- Calls being recorded via Vapi while `call_recording_consent = true`.
- Transcripts being processed by Claude for classification + coaching.
- Post-call summaries being visible to their manager only if they
  also toggle `share_with_manager = true` (see Productivity Tier
  consent doc).

Consent is captured in `team_members.call_recording_consent` +
`_at` + `_version`. Flip back to `false` to withdraw.

## Customer disclosure script (required)

The default, stored in `clients.customer_consent_disclosure_script`:

> "This call is being recorded and analyzed for quality and coaching
> purposes. You may opt out at any time during this call."

Clients may customise this; Mary should review the customised script
against provincial requirements before enabling the tier.

## What IS captured

- Audio stream handed to Vapi.
- Real-time transcript chunks written to `call_transcript_chunks`.
- AI classification (sentiment / intent / topics) per chunk.
- Post-call coaching analysis written to `call_event_log`.

## What is NOT captured

- Calls outside the Crystallux platform (agent's personal phone).
- Calls where the customer declined consent (agent ends the recording
  stream before any chunk is persisted).
- Non-call audio (webinars, meetings outside Vapi).
- Keystrokes, screen activity, browsing, or non-call metadata.

## Data retention

- Full transcript text (`call_transcript_chunks.transcript_text`):
  **30 days**, then replaced with a null/anonymised marker via a
  scheduled cleanup job (not included in this migration — add as a
  follow-up task before go-live).
- `call_event_log` summaries + analysis: retained indefinitely,
  anonymised after 12 months.
- Agent may request deletion of their own calls anytime via
  `support@crystallux.org`.

## Customer rights (PIPEDA)

- Right to know the call is recorded (satisfied by the disclosure).
- Right to access a transcript of their own call (Mary retrieves via
  `call_id` lookup).
- Right to correction of inaccuracies.
- Right to deletion of their recorded call data.
- Right to file a complaint with the Privacy Commissioner of Canada.

## Who sees what

- **Agent:** all own call data.
- **Manager:** post-call summaries if the agent opted in to
  `share_with_manager`. Manager never gets full transcripts by
  default — only the summary + coaching notes.
- **Mary / admins:** aggregate patterns via
  `get_agent_call_patterns` RPC. Full transcripts only when a formal
  investigation is opened.
- **Customer:** receives their own transcript on request.
- **Other clients / other agents:** never.

## Prohibited uses

Call recordings + transcripts MUST NOT be used to:

- Fire or discipline agents.
- Name-and-shame internally or externally.
- Sell or share with third parties.
- Market or up-sell the customer beyond the engagement that the
  call was placed under.

## Agent consent form

I, the undersigned, consent to the following while performing work
through the Crystallux platform:

- [ ] My voice calls may be recorded by Vapi.
- [ ] Transcripts may be processed by Claude for coaching analysis.
- [ ] My manager may see post-call summaries (optional — controlled
      separately by the productivity `share_with_manager` toggle).
- [ ] Data retention as specified above.

I understand that I may withdraw consent at any time, that coaching
is non-punitive, and that I have full PIPEDA rights.

- Agent name: ____________________________
- Client organisation: ____________________________
- Signature: ____________________________
- Date: ____________________________
- Consent version: 1.0

## Customer opt-out handling

If a customer declines recording mid-call:

1. Agent immediately stops the Vapi stream from the agent console.
2. Agent logs in CRM: "Customer opted out of recording at HH:MM".
3. Any `call_transcript_chunks` already captured for this `call_id`
   are deleted within 24h by a support ticket in Notion.
4. Lead record marked `customer_declined_recording = true` (add
   column in a follow-up migration when live-needed).

## Operational notes

- Review the disclosure script quarterly for legal compliance — bump
  to version 1.1 if any material language changes.
- Audit quarterly: pull a random sample of 10 calls and verify the
  disclosure was read within the first 30 seconds.
- If the `CONSENT_VIOLATION_DETECTED` monitoring threshold fires,
  stop all recording for that client, notify the Privacy Commissioner
  proactively, and initiate a root-cause investigation.

## Version history

- **1.0** (2026-04-25) — Initial version.
