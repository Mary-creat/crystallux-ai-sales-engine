---
Document: Crystallux Incident Response Quick Sheet
Version: 1.0
Audience: On-call / printable card
Owner: Mary Akintunde
Last Reviewed: 2026-04-27
Next Review: 2026-07-26
Source: CRYSTALLUX_SECURITY_HANDBOOK.md §12 (Incident Response Plan)
---

# Crystallux Incident Response — Quick Sheet

Print this. Keep it on your desk and pinned in your password manager. The full plan is in handbook §12; this card is for the first 30 minutes.

---

## Emergency Contacts

| Role | Contact |
| ---- | ------- |
| Mary Akintunde (Crystallux owner) | [phone TBD by Mary] / security@crystallux.org |
| Supabase Support | support@supabase.com |
| Anthropic Support | support.anthropic.com |
| Stripe Security | security@stripe.com |
| Cloudflare Support | support.cloudflare.com |

---

## Severity Definitions

| Severity | Definition |
| -------- | ---------- |
| **Critical** | Active breach, cross-tenant exposure, admin compromise, major outage |
| **High** | Sensitive data exposure, integration compromise, exploitable severe flaw |
| **Medium** | Contained issue with limited blast radius |
| **Low** | Minor security event or hardening issue |

**Client notification rule:** any High or Critical incident affecting a client's data → notify the affected client within 4 hours of confirmation.

---

## Containment Playbooks

Five common incident types. Run the five steps in order. Do not skip steps. Document every action with a timestamp.

### 1. Account Compromise

1. Revoke all active sessions
2. Force password reset on affected account
3. Rotate any API keys associated
4. Audit logs for unauthorized actions
5. Re-enable MFA if disabled

### 2. Cross-Tenant Exposure

1. Suspend the platform if active leak
2. Identify affected tenants from logs
3. Alert affected clients within 4 hours
4. Document scope of exposure
5. Snapshot evidence before remediation

### 3. Integration Token Leak

1. Revoke leaked token immediately
2. Rotate to new token
3. Audit logs for unauthorized API calls
4. Notify affected client if their data accessed
5. Update secrets vault with new credential

### 4. Webhook Abuse

1. Disable webhook endpoint
2. Audit recent webhook events for malicious payloads
3. Rotate webhook signing secret
4. Re-enable with new secret + signature verification
5. Document attack pattern

### 5. Data Export Anomaly

1. Suspend the exporting user account
2. Identify what was exported (size, fields, timestamp)
3. Audit user's recent activity
4. Determine if export was legitimate
5. Restore access with restrictions or escalate

---

## After Containment

For every High or Critical incident, complete a post-incident review per handbook §12 covering:

- Timeline
- Root cause
- Impacted tenants
- Data involved
- Control failures
- Remediation actions
- Control improvements
- Owner and due dates
- Executive summary

---

## Evidence to Preserve

Before any remediation, snapshot or export:

- Authentication logs
- Admin activity logs
- API logs
- Webhook logs
- Export logs
- Integration token events
- Workflow execution records
- AI workflow metadata
- Database audit trails
- Deployment history
- Communications timeline

---

**Full incident response plan:** `CRYSTALLUX_SECURITY_HANDBOOK.md` § 12
**Security contact:** security@crystallux.org
