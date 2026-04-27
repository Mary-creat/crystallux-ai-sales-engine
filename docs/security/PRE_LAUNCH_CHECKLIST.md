---
Document: Crystallux Pre-Launch Security Checklist
Version: 1.0
Status: Active
Owner: Mary Akintunde
Last Reviewed: 2026-04-27
Next Review: Before each new client activation
Source: CRYSTALLUX_SECURITY_HANDBOOK.md §18 (Go-Live Security Readiness Checklist)
---

# Crystallux Pre-Launch Security Checklist

This checklist must be fully completed and signed off before activating Crystallux for client #1 and re-verified before each subsequent new-client activation.

Anything that cannot be checked is a launch blocker. Do not deploy a client onto an incomplete checklist.

---

## Must Have Before First Client

### Authentication and Multi-Factor

- [ ] MFA enabled on Mary's admin Google Workspace account
- [ ] MFA enabled on n8n admin login
- [ ] MFA enabled on Supabase project owner account

### Tenant Isolation

- [ ] Tenant isolation 7-test protocol PASSED (per `dashboard/CLIENT_ISOLATION_TEST.md`)
- [ ] Per-client dashboard tokens generated via `gen_random_bytes(32)`
- [ ] RLS policies active on all client-scoped tables

### Workflow Safety

- [ ] All workflow JSONs verified `active: false` except `clx-lead-import`
- [ ] `TESTING_EMAIL` redirect active in 7 sender workflows
- [ ] `TESTING_PHONE` redirect active in 1 SMS workflow
- [ ] `do_not_contact = true` verified on 859 seeded leads
- [ ] `do_not_contact = true` verified on Mitch Insurance test record

### Secrets Hygiene

- [ ] No credentials hardcoded in repo
- [ ] No secrets in commit history

### Operational Coverage

- [ ] Supabase auto-backup confirmed active
- [ ] `info@crystallux.org` receiving alerts (test email sent)
- [ ] `security@crystallux.org` alias forwarding (test email sent)

---

## Document State Required

- [ ] Privacy Policy live with PIPEDA-aligned language
- [ ] Terms of Service live with Canadian governance
- [ ] `security.txt` live at `/.well-known/security.txt`

---

## Mary's Personal Security

- [ ] Personal Google Workspace MFA + recovery codes saved
- [ ] Password manager active (1Password, Bitwarden, or similar)
- [ ] All Crystallux logins in password manager
- [ ] No shared admin credentials with anyone
- [ ] Recovery email/phone set on critical accounts

---

## Sign-Off

| Field | Value |
| ----- | ----- |
| Checklist completed by | Mary Akintunde |
| Date completed | _______________ |
| Client being activated | _______________ |
| All items checked | [ ] Yes |
| Launch approved | [ ] Yes |

If any item is not checked, the cause must be documented here before launch:

```
(blank if all checked)
```

---

## Related Documents

- Full handbook: `CRYSTALLUX_SECURITY_HANDBOOK.md`
- Incident response: `INCIDENT_RESPONSE_QUICK_SHEET.md`
- Client summary: `../commercial/CRYSTALLUX_SECURITY_SUMMARY.md`
- Isolation test protocol: `../../dashboard/CLIENT_ISOLATION_TEST.md`
