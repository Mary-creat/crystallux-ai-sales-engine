# Crystallux Insurance Network — Marketing Site

Public-facing marketing + lead-capture site for Mary's Canadian insurance MGA. **Separate brand** from the Crystallux SaaS site at `crystallux.org`.

- **Target URL:** `insurance.crystallux.org`
- **Brand:** Crystallux Insurance Network (the MGA, not the SaaS).
- **Audience:** B2C insurance buyers (life, health, P&C, business).
- **Tech:** plain HTML + plain CSS + vanilla JS. No build pipeline. Inter from Google Fonts. Same conventions as `site/` and the admin/client dashboards.
- **Deployed via:** Cloudflare Pages. CSP locked down in `_headers`; only Calendly + Cloudflare Analytics whitelisted.

## Pages

| File | Purpose |
|---|---|
| `index.html` | Home — hero, 7 product tiles, why-us, how-it-works, carrier strip, trust badges, CTA band |
| `life-insurance.html` … `business-insurance.html` | One landing page per product line (7 total) |
| `compare.html` | Static side-by-side comparison (Phase 1) |
| `needs-assessment.html` | Static lead-capture form (Phase 2 = AI quiz) |
| `how-it-works.html` / `why-choose-us.html` / `about.html` / `contact.html` | Trust + conversion pages |
| `blog/index.html` | Blog landing (stub for SEO) |
| `resources/life-insurance-guide.html` / `critical-illness-explained.html` / `calculator-collection.html` | Long-form SEO content |
| `privacy.html` / `terms.html` / `disclosure.html` | Compliance pages (mandatory) |

## Lead capture

All forms POST to:

```
POST https://automation.crystallux.org/webhook/mga/insurance/lead-capture
```

Handler workflow: `workflows/api/insurance-mga/clx-mga-insurance-lead-capture-v1.json`. Inserts into `leads` (vertical_id='insurance', client_id = Crystallux Insurance Network test tenant) + writes a `regulatory_audit_log` row. Public CORS endpoint, no session-token auth. CASL consent is enforced client-side AND recorded server-side (`consent_given_at`, `consent_method='web_form_checkbox'`).

## Deployment

1. **Cloudflare Pages project:**
   - Project name: `crystallux-insurance-marketing`
   - Production branch: `scale-sprint-v1` (or `main` post-merge)
   - Build command: *(none — static)*
   - Build output: `insurance-marketing`
2. **Custom domain:**
   - Cloudflare DNS: `CNAME insurance → crystallux-insurance-marketing.pages.dev`
   - Add custom domain in Pages project settings → SSL auto-provisions.
3. **Workflow import:**
   ```bash
   docker exec n8n n8n import:workflow \
     --input=/data/workflows/api/insurance-mga/clx-mga-insurance-lead-capture-v1.json
   ```
   Activate in n8n UI.
4. **Smoke test:**
   - Open `insurance.crystallux.org/contact.html`, fill form, submit. Expect "Thanks — a licensed advisor will be in touch within one business day."
   - Verify a row appears in `leads` with `vertical_id='insurance'`, `source='contact'`, `consent_given_at` populated.

## Compliance checklist (Mary)

Before going live publicly, please verify:

- [ ] FSRA license number filled into `disclosure.html` (currently placeholder `#X`).
- [ ] LLQP license numbers for each advisor on `about.html`.
- [ ] E&O policy details up to date (carrier, amount, expiry).
- [ ] Carrier appointment list reconciled with current contracts — remove any carrier on `index.html` carrier strip and product pages where appointment isn't active.
- [ ] Privacy contact email (`privacy@crystallux.org`) is monitored.
- [ ] Complaints email (`complaints@crystallux.org`) is monitored.
- [ ] Cookie banner copy reviewed by counsel (PIPEDA + Quebec Law 25).
- [ ] Calendly account configured and embed URL added to `contact.html` Calendly block.

## Phases

This is **Phase 1 — Marketing Foundation**. Subsequent phases are documented in `docs/architecture/MGA_MARKETING_ROADMAP.md`:

- **Phase 2 (Month 3–6):** AI Discovery Engine — convert `needs-assessment.html` to multi-step interactive flow with Claude-powered recommendations.
- **Phase 3 (Month 6–12):** Static comparison engine with side-by-side product pages backed by `carrier_products` data.
- **Phase 4 (Year 2):** Live quote engine — per-carrier API integration (Walnut, PolicyMe first).
- **Phase 5 (Year 2–3):** Full self-serve platform with policy management.
