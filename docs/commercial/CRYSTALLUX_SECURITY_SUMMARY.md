---
Document: Crystallux Security Summary
Version: 1.0
Audience: Prospective and active clients
Owner: Mary Akintunde
Last Reviewed: 2026-04-27
Next Review: 2026-07-26
Contact: security@crystallux.org
---

# Crystallux Security Summary

## Executive Overview

Crystallux is a multi-client AI lead generation and sales platform that handles client business data, lead records, outreach communications, sales intelligence, AI-generated content, calendar workflows, and integrations with third-party systems. We treat security as a launch condition, not a roadmap item.

This document summarises the security posture Crystallux maintains today and the commitments we make to every client we onboard. It is written for prospects, partners, and procurement teams who need a calm, factual view of how we protect client data.

The full security operating manual sits behind this summary as an internal reference (`CRYSTALLUX_SECURITY_HANDBOOK.md`). The handbook covers 21 sections including penetration test scope, tenant isolation test plans, IAM assessment, architecture review, incident response, vulnerability management, backup and recovery, the information security policy, and the go-live readiness checklist.

## Platform Overview

Crystallux operates as a Software-as-a-Service platform with the following architectural layers:

- Public marketing site
- Authenticated client dashboards (per-tenant)
- Internal admin tooling
- API services and webhook endpoints
- Background automation (n8n workflows)
- AI orchestration (Anthropic Claude, OpenAI Whisper)
- Managed database (Supabase Postgres with Row Level Security)
- External integrations (Gmail, Twilio, Stripe, Cloudflare)

Every layer enforces the same trust model: tenant context is required to access data, and access is logged.

## Multi-Tenant Isolation

Tenant isolation is the highest-priority control on the platform. Crystallux uses a single shared database with tenant-scoped data partitioning enforced through three layers:

1. **Row Level Security (RLS)** on every client-scoped Postgres table. Policies enforce that no query can return data outside the caller's tenant scope.
2. **Per-client dashboard tokens** generated using cryptographically secure random bytes (`gen_random_bytes(32)`). Tokens are scoped to a single client and revocable.
3. **Tenant context propagation** through API requests, workflow executions, and AI prompts. No cross-tenant data is ever placed in the same context window.

We run a documented 7-test isolation protocol before onboarding any new client. All seven tests must pass for the client to be activated. The protocol is repeated whenever isolation-affecting code changes ship.

## Encryption

| Layer | Protection |
| ----- | ---------- |
| Data in transit (public web, API, dashboards, webhooks) | HTTPS / TLS 1.2+ enforced |
| Data in transit (internal service-to-service) | TLS enforced by managed providers |
| Data at rest (Supabase Postgres) | AES-256 encryption (provider-managed) |
| Data at rest (file storage) | AES-256 encryption (provider-managed) |
| Backups | Encrypted at rest and in transit |
| Secrets and integration tokens | Stored in n8n credentials vault and Cloudflare environment, never in source control |

## Access Control

Crystallux operates a role-based access control model with three primary roles:

- **Client User** — read access to their own tenant's data only, scoped through dashboard tokens
- **Crystallux Operator** — internal staff with limited operational scope (workflow execution, support actions)
- **Crystallux Administrator** — full platform access, restricted to founding personnel, MFA-enforced, all actions logged

Administrative access requires:

- Multi-factor authentication on every admin account
- Strong password and password manager
- Tenant-scoped session context for any data access
- Audit log capture for sensitive actions

Service accounts (workflow runners, integration credentials) use scoped tokens and are rotated when staff change or when a token is suspected to be exposed.

## Audit Logging

Crystallux captures sensitive events for review and incident reconstruction:

- Authentication events (success, failure, MFA challenges)
- Administrative actions (configuration changes, data access, exports)
- API and webhook activity
- Workflow execution records
- AI workflow metadata (model, tenant, request volume)
- Database audit trails on client-scoped tables
- Deployment history

Logs are retained according to our incident-response and compliance needs and are protected from modification by application code.

## Incident Response Commitment

Crystallux maintains a documented incident response process that covers:

- Detection (alerting, monitoring, client reports)
- Triage and severity classification (Critical, High, Medium, Low)
- Containment actions (session revocation, key rotation, account suspension, integration disable)
- Investigation and evidence preservation
- Eradication and recovery
- Communication to affected clients
- Post-incident review with root cause, control failures, and remediation actions

**Client notification commitment:** for any incident classified as High or Critical that affects a client's data, Crystallux will notify the affected client within 4 hours of confirmation.

The full incident response plan is in section 12 of the security handbook. A quick-reference card (`INCIDENT_RESPONSE_QUICK_SHEET.md`) covers the most common incident types with five-step containment playbooks.

## Vulnerability Management

Crystallux identifies, validates, prioritises, remediates, and verifies vulnerabilities through:

- Pre-launch and periodic penetration testing
- Dependency monitoring on application code
- Configuration review of integrations and infrastructure
- Client-reported and researcher-reported issue intake (security@crystallux.org)

Severity-based remediation timelines:

| Severity | Target Remediation |
| -------- | ------------------ |
| Critical | Immediate, with active mitigation in place until patched |
| High | Remediated within days, with compensating controls if needed |
| Medium | Remediated on the next scheduled release cycle |
| Low | Tracked in the backlog |

## Vendor Risk Position

Crystallux relies on a small set of mature, security-mature providers. Each is selected for its security posture, compliance certifications, and operational reliability:

| Provider | Use | Posture |
| -------- | --- | ------- |
| Supabase | Managed Postgres, auth, storage | SOC 2 Type II, encrypted at rest, automated backups |
| Anthropic | AI inference (Claude) | Enterprise-grade data handling, no training on customer data |
| OpenAI | Voice transcription (Whisper) | Enterprise-grade data handling |
| Cloudflare | Edge, DNS, Pages hosting | SOC 2, ISO 27001, DDoS protection |
| Stripe | Billing | PCI DSS Level 1 |
| Google Workspace | Email and identity | SOC 2 Type II, ISO 27001 |
| Twilio | SMS delivery | SOC 2 Type II |

Crystallux does not transfer client business data outside this stack. Integration tokens are stored in our credentials vault and used only for the integrations the client has explicitly authorised.

## Data Retention

Crystallux retains client data only for as long as required to deliver the contracted service:

- **Active client data** — retained for the duration of the engagement
- **Lead records** — retained per the client's configuration and applicable law
- **Communications and outreach records** — retained for the audit window required by CASL
- **Logs** — retained for the period required for incident reconstruction and compliance
- **On client offboarding** — client data is exported on request and deleted from active systems within 30 days, with backup tail removal following the backup retention schedule

Clients may request export or deletion of their data at any time by contacting security@crystallux.org.

## Compliance Alignment

Crystallux operates from Canada and aligns its controls with:

- **PIPEDA** — Personal Information Protection and Electronic Documents Act. Crystallux processes personal information lawfully, with consent where required, and applies the ten Fair Information Principles (accountability, identifying purposes, consent, limiting collection, limiting use, accuracy, safeguards, openness, individual access, challenging compliance).
- **CASL** — Canada's Anti-Spam Legislation. All electronic outreach honours consent records, identification requirements, and unsubscribe obligations. Outreach workflows include sender identification, working unsubscribe paths, and do-not-contact enforcement.

Crystallux is positioned to support clients who require additional compliance attestations (SOC 2, ISO 27001) as the platform scales. Current control design follows the principles in those frameworks.

## Tenant Isolation Validation

Before any new client is activated, Crystallux runs a 7-test isolation protocol covering:

1. Cross-tenant query isolation
2. Cross-tenant token rejection
3. Workflow execution scope
4. AI prompt isolation
5. Export scope
6. Webhook source validation
7. Audit log scope

All seven tests must pass. The protocol is documented in `dashboard/CLIENT_ISOLATION_TEST.md`.

## Pre-Launch Posture

Before activating client #1, Crystallux completes a pre-launch security readiness checklist covering: MFA enforcement on all admin accounts, tenant isolation 7-test pass, secrets hygiene (no credentials in source control or commit history), do-not-contact enforcement on seeded test data, automated backup verification, alert email coverage, dashboard token generation hygiene, and Row Level Security policy coverage on all client-scoped tables.

## Security Contact

For security questions, vulnerability reports, or incident notifications:

- **Email:** security@crystallux.org
- **General contact:** info@crystallux.org

We respond to security reports within one business day and prioritise valid findings on the severity timelines above.

## Document History

| Date | Version | Notes |
| ---- | ------- | ----- |
| 2026-04-27 | 1.0 | Initial release, extracted from Crystallux Security Handbook v1.0 |
