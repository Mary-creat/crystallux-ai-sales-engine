# Client Contract Template — Master Services Agreement

> ⚠️ **This is a template. Canadian legal review required before signing with first 3 clients.**
>
> Get a Canadian business lawyer in Ontario to review this against Crystallux's specific business structure, current law, and your insurance coverage. Budget $500-1,500 for a one-time review of this + Terms of Service + Privacy Policy as a bundle. Review cadence: annually, or whenever a material term changes.

---

## MASTER SERVICES AGREEMENT

This Master Services Agreement (the "Agreement") is made effective as of **[EFFECTIVE_DATE]** (the "Effective Date") between:

**Crystallux Inc.** / Crystallux (Sole Proprietorship of Mary Akintunde), a Canadian business with Business Number **[BN]**, registered office at **[MARY_ADDRESS], Toronto, Ontario, Canada** ("Provider" or "Crystallux"); **AND**

**[CLIENT_LEGAL_NAME]**, a **[PROVINCE]** [corporation / partnership / sole proprietorship], with registered office at **[CLIENT_ADDRESS]** ("Client").

Provider and Client are each a "Party" and together the "Parties."

---

## 1. Services

Provider will deliver the Crystallux Sales Engine service for the Client, consisting of:

- **Prospect sourcing** via Apollo, LinkedIn, and Provider's proprietary intent signals
- **Personalised outreach generation** via Claude (Anthropic) models tuned to the Client's vertical
- **Multi-channel message delivery** across: email, LinkedIn, SMS, WhatsApp, voice, and video (subject to Client's enabled channels as configured in the dashboard)
- **Meeting booking automation** via the Client's Calendly or equivalent booking tool
- **Reply ingestion and routing** to the Client's nominated notification email
- **Real-time dashboard** with pipeline metrics, outreach logs, and billing status
- **Monthly strategy review call** of 30-60 minutes

Specific vertical configuration is documented in Exhibit A (Services Configuration) attached to and forming part of this Agreement.

**Vertical:** [CLIENT_VERTICAL — one of: insurance_broker, construction, real_estate, dental, consulting, moving_services, cleaning_services]
**Service tier:** [TIER — one of: Founding, Standard, Growth Pro, Intelligence]
**Target outcome:** [TARGET — from the matching `docs/verticals/{vertical}/README.md`]

---

## 2. Term

**Initial Term:** three (3) months commencing on the Effective Date.

**Renewal:** This Agreement auto-renews on a month-to-month basis after the Initial Term, unless terminated by either Party under clause 9.

**Annual Option:** At Client's written election during the Initial Term, the Parties may enter into a 12-month fixed term with a [DISCOUNT — e.g., 10%] discount on the monthly rate, billed monthly. This option carries founding-rate protection as described in clause 4.

---

## 3. Fees and payment

**Monthly Fee:** **$[PRICE] CAD** per month, plus applicable GST/HST.

**Founding Rate:** If Client is a Founding Client (one of the first 20 clients per vertical), the founding rate of $[FOUNDING_PRICE] CAD is **locked for 12 months** from the first paid invoice date. Upon lapse of the 12-month lock, the rate migrates to the then-current standard rate for the Client's vertical and service tier unless Client and Provider agree to a new founding lock.

**Trial:** Fourteen (14) days, unpaid. No fee is charged unless Client affirmatively continues past day 14 of the trial.

**Billing:** Monthly, in advance, via Stripe. Client authorises Provider to charge the payment method on file on the first day of each billing cycle.

**Taxes:** All fees are exclusive of GST/HST. Provider will collect and remit GST/HST based on Client's province of business via Stripe Tax.

**Late Payment:** If a payment fails, Provider will follow the sequence described in Provider's Payment Follow-Up operational policy, including notice, retry, and potential suspension of service after 14 days of non-payment.

---

## 4. Guarantee

**First-30-day target:** Provider commits to delivering **[GUARANTEE_TARGET — e.g., "10 qualified discovery meetings"]** within the first thirty (30) days of the first paid month of service.

**Remedy:** If Provider does not deliver the first-30-day target, Client's second monthly invoice is automatically waived. No partial credits are issued; no future discounts apply. Client's payment method is not charged for the second month.

**Conditions for guarantee eligibility:**

1. Client has activated at least the Email channel throughout the 30-day measurement window
2. Client has reviewed and approved the initial outreach batch within 3 business days of receipt
3. Client has responded to qualified leads surfaced by Provider within 48 hours of receipt
4. Client's Calendly or booking URL has been live and accepting bookings throughout the window

If any condition is not met, the guarantee does not apply, but Provider will work with Client to re-qualify for an extended guarantee period at Provider's discretion.

---

## 5. Client responsibilities

Client agrees to:

1. Provide accurate and current business information for Stripe billing and dashboard configuration
2. Approve Provider's initial outreach templates before the first live send
3. Maintain CASL-compliant consent practices for any contacts Client adds to the service outside of Provider's sourced leads
4. Respond to leads surfaced by Provider within a reasonable timeframe (48 hours for qualified reply-tier leads, unless otherwise agreed)
5. Notify Provider within 5 business days of any change to Client's business structure, licensing status, or compliance obligations that could affect the Services
6. Not use the Services to send outreach in violation of CASL, PIPEDA, or provincial regulatory rules (including but not limited to law society advertising rules, provincial dental regulatory rules, or provincial real estate council rules)

---

## 6. Provider responsibilities

Provider agrees to:

1. Maintain CASL-compliant outreach templates with appropriate sender identification, business address, and unsubscribe mechanisms
2. Handle all personal data collected through or processed by the Services in accordance with PIPEDA and the Privacy Policy
3. Respond to Client support tickets within four (4) business hours during business hours (Monday-Friday, 9am-5pm Eastern Time, Toronto)
4. Provide a monthly strategy review call of 30-60 minutes
5. Maintain the dashboard and workflow engine at 99.0% monthly uptime target (as described in the Service Level Agreement, Exhibit B)
6. Provide Client with a complete data export (leads, outreach history, campaigns) in CSV and JSON format within 14 days of termination

---

## 7. Service levels

A formal Service Level Agreement is attached as **Exhibit B**, incorporated by reference. Material SLA commitments:

- Platform uptime: 99.0% monthly (excluding scheduled maintenance)
- Outreach queue-to-send: 2 hours for batches queued during business hours
- Support response: 4 business hours acknowledgement, 24 business hours resolution
- Scheduled maintenance: announced 48 hours in advance

---

## 8. Data ownership

**Client data.** Client retains all right, title, and interest in data Client provides or that is generated on Client's behalf through the Services, including lead data, outreach messages sent on Client's behalf, reply data, and campaign configuration.

**Provider data.** Provider retains all right, title, and interest in the Crystallux platform, source code, automation workflows, prompt engineering, databases, and related intellectual property.

**Licence from Client to Provider.** Client grants Provider a non-exclusive, worldwide, royalty-free licence to process Client's data for the purpose of delivering the Services for the duration of the Term.

**Anonymised aggregate metrics.** Provider may use anonymised, aggregated metrics across all clients for benchmarking, product improvement, and marketing purposes. Client-identifiable or client-specific data will not be shared externally without separate written consent (see Testimonial & Case Study Consent form).

---

## 9. Termination

**By Client, for convenience.** Client may terminate this Agreement by providing thirty (30) days' written notice to Provider at info@crystallux.org. Termination is effective at the end of the billing period in which notice expires. No pro-rata refund is issued for unused days in the final billing period.

**By Provider, for cause.** Provider may terminate this Agreement immediately upon written notice for:
- Non-payment beyond 30 days after due date (following the payment-failure sequence)
- Material breach of clauses 5, 10, or 14 by Client not cured within 15 days of written notice
- CASL violation by Client using the Services
- Client's becoming insolvent, filing for bankruptcy, or suspending normal business operations

**By Provider, for convenience.** Provider may terminate this Agreement with 30 days' written notice. In such case, Provider refunds any pre-paid fees on a pro-rata basis.

**Effects of termination:**

Upon termination for any reason:
1. Services are discontinued at the end of the current billing period (for notice-based terminations) or immediately (for cause)
2. Stripe subscription is cancelled
3. Client's dashboard access is revoked
4. Provider exports Client data per clause 6(6)
5. After 90 days post-termination, Provider deletes personal data per the Privacy Policy

Clauses 8, 10, 11, 12, 13, 15, 16, and 18 survive termination.

---

## 10. Confidentiality

Each Party may disclose confidential information to the other in the course of this Agreement. Recipient agrees to:

1. Use Confidential Information only for purposes of performing obligations under this Agreement
2. Protect Confidential Information with the same care as its own proprietary information (and no less than a reasonable standard)
3. Not disclose Confidential Information to any third party except service providers under equivalent confidentiality obligations, or as required by law

"Confidential Information" includes, without limitation: business strategy, pricing, customer lists, technical specifications, source code, financial information, and any other information reasonably understood to be confidential.

Confidentiality obligations survive termination for two (2) years.

---

## 11. Intellectual property

Provider owns the Crystallux platform, logo, trademarks, documentation, and all automation workflows. Client owns Client's brand assets, trademarks, customer lists, and business data.

Neither Party may use the other's trademarks, logos, or branded materials without written consent, except:

- Provider may list Client's company name and logo on Provider's website and marketing materials as a customer reference, unless Client opts out in writing at any time
- Client may identify Crystallux as a vendor in Client's own internal communications and regulatory filings

---

## 12. Non-compete

For the duration of the Term and for a period of twelve (12) months thereafter, Provider shall not, without Client's written consent, provide substantially equivalent Services to any business:
- In Client's same vertical (as defined in clause 1)
- Whose registered office is located within fifty (50) kilometres of Client's registered office
- Whose revenue or employee count is within the same service tier as Client's

This non-compete does not restrict Provider from serving clients in different verticals, different geographic markets, or materially different business models.

---

## 13. Limitation of liability

**Aggregate cap.** Provider's aggregate liability under this Agreement is capped at the total fees paid by Client to Provider in the three (3) months immediately preceding the event giving rise to the liability.

**Excluded damages.** Neither Party is liable for indirect, consequential, special, incidental, or punitive damages, including lost profits, lost revenue, or loss of business opportunity.

**Exclusions to cap.** The liability cap does not apply to:
- Confidentiality breaches under clause 10
- IP infringement under clause 11
- A Party's gross negligence or willful misconduct

Provider carries Errors & Omissions (E&O) insurance of **$[COVERAGE_AMOUNT — e.g., 1,000,000]** in force throughout the Term.

---

## 14. Indemnification

**Client indemnifies Provider** against any third-party claims arising from:
- Client's violation of CASL, PIPEDA, or provincial regulatory rules using the Services
- Client's upload of contact information without proper CASL consent
- Client's misuse of the Services outside the scope authorised by this Agreement

**Provider indemnifies Client** against any third-party claims arising from:
- Provider's IP infringement
- Provider's violation of PIPEDA in its handling of Client's data

Both indemnifications are subject to the liability cap in clause 13 except where excluded in clause 13.

---

## 15. Dispute resolution

The Parties agree to attempt good-faith negotiation of any dispute before escalating. If negotiation fails within 30 days, the Parties will submit the dispute to binding arbitration under the **ADR Institute of Canada (ADRIC) Arbitration Rules** in Toronto, Ontario, before a single arbitrator.

The arbitrator's decision is final and binding. The prevailing Party may be entitled to recover its reasonable legal fees and costs, at the arbitrator's discretion.

---

## 16. Governing law

This Agreement is governed by the laws of the **Province of Ontario** and the federal laws of Canada applicable therein. Venue for any legal proceeding not subject to arbitration under clause 15 is the courts of Toronto, Ontario.

---

## 17. Entire agreement; amendment

**Entire agreement.** This Agreement, together with all Exhibits attached hereto, constitutes the entire agreement between the Parties and supersedes all prior agreements, oral or written.

**Amendments.** Any amendment must be in writing and signed by authorised representatives of both Parties.

**No waiver.** Failure by either Party to enforce a provision is not a waiver of that Party's right to enforce it later.

**Severability.** If any provision is held unenforceable, the remainder of the Agreement remains in full force.

**Assignment.** Neither Party may assign this Agreement without the other's written consent, except to a successor by merger or acquisition.

---

## 18. Notices

All notices under this Agreement must be in writing and delivered to the Parties at the addresses above (or as later updated). Email to info@crystallux.org (for Provider) and to [CLIENT_NOTIFICATION_EMAIL] (for Client) is acceptable for all routine notices. Notices of termination must be sent by email with delivery receipt requested.

---

## 19. Electronic signature

This Agreement may be executed electronically through DocuSign, HelloSign, or equivalent platform. Electronic signatures have the same effect as wet-ink signatures under Canadian federal and Ontario provincial law.

---

## Signatures

**Provider — Crystallux Inc.**

Name: Mary Akintunde
Title: Founder
Signature: ____________________________
Date: ____________________________

**Client — [CLIENT_LEGAL_NAME]**

Name: [CLIENT_SIGNER_NAME]
Title: [CLIENT_SIGNER_TITLE]
Signature: ____________________________
Date: ____________________________

---

## Exhibit A — Services Configuration

| Configuration item | Value |
|---|---|
| Vertical | [CLIENT_VERTICAL] |
| Service tier | [TIER] |
| Target outcome | [TARGET] |
| First-30-day guarantee target | [GUARANTEE_TARGET] |
| Enabled channels | [CHANNELS — from clients.channels_enabled] |
| Focus segments | [SEGMENTS — from clients.focus_segments] |
| Service area | [GEOGRAPHY] |
| Calendly URL | [BOOKING_URL] |
| Notification email | [CLIENT_NOTIFICATION_EMAIL] |
| Dashboard URL | [DASHBOARD_URL with client_id + token] |
| Stripe customer ID | [STRIPE_CUSTOMER_ID] |
| Stripe subscription ID | [STRIPE_SUBSCRIPTION_ID] |
| Stripe plan | [SELECTED_PLAN] |

---

## Exhibit B — Service Level Agreement

(Refer to the current published SLA on crystallux.org/sla. The SLA in effect on the Effective Date is attached as a PDF to this Agreement.)

---

## Fields Mary must complete per client

Before sending this template for signature:

- [ ] `[EFFECTIVE_DATE]` — today's date
- [ ] `[BN]` — Crystallux Business Number
- [ ] `[MARY_ADDRESS]` — Crystallux registered office
- [ ] `[CLIENT_LEGAL_NAME]` — exact legal name on the client's incorporation or BN
- [ ] `[CLIENT_ADDRESS]` — client's registered office
- [ ] `[PROVINCE]` — client's province of registration
- [ ] `[CLIENT_VERTICAL]` — consulting / real_estate / construction / dental / insurance_broker / moving_services / cleaning_services
- [ ] `[TIER]` — Founding / Standard / Growth Pro / Intelligence
- [ ] `[TARGET]` — per-vertical outcome (from the matching vertical README)
- [ ] `[PRICE]` — full CAD monthly rate
- [ ] `[FOUNDING_PRICE]` — founding CAD monthly rate (if Client is Founding)
- [ ] `[GUARANTEE_TARGET]` — e.g., "10 qualified discovery meetings"
- [ ] `[DISCOUNT]` — annual option discount (if applicable)
- [ ] `[COVERAGE_AMOUNT]` — Provider's E&O insurance coverage (default $1,000,000)
- [ ] Exhibit A — all configuration fields filled from Supabase `clients` row
- [ ] Exhibit B — attach current SLA PDF
- [ ] `[CLIENT_SIGNER_NAME]` / `[CLIENT_SIGNER_TITLE]` — from signing authority
- [ ] `[CLIENT_NOTIFICATION_EMAIL]` — client's primary email for notices

Send via DocuSign or HelloSign. Countersign within 24 hours of client signature.
