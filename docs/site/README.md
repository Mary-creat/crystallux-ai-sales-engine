# docs/site/ — Public Crystallux SaaS website

Static, no-build, plain HTML + CSS + vanilla JS. Separate from `docs/dashboard/`. Deploy the whole `docs/site/` tree to crystallux.org; the dashboard stays at `crystallux.org/dashboard/`.

## Structure

```
docs/site/
├── index.html                         Home
├── features.html                      Features
├── how-it-works.html                  How it works
├── pricing.html                       Pricing
├── about.html                         About + founder
├── contact.html                       Contact
├── book.html                          Book a demo (Calendly embed)
├── faq.html                           FAQ
├── terms.html                         Terms of Service (template — lawyer review needed)
├── privacy.html                       Privacy Policy (template — lawyer review needed)
├── industries/
│   ├── index.html                     Industries hub
│   ├── insurance-brokers.html         Most mature showcase vertical
│   ├── consulting.html
│   ├── real-estate.html
│   ├── construction.html
│   └── dental.html
└── assets/
    ├── site.css                       Shared stylesheet
    └── site.js                        Mobile nav toggle + active-state
```

## Preview locally

Any of the following from the repo root:

```bash
# Python 3 (simplest)
python -m http.server 8080 --directory docs/site

# then open: http://localhost:8080/
```

```bash
# Node (if you have it)
npx -y serve docs/site -p 8080
```

```bash
# PHP (if installed)
php -S localhost:8080 -t docs/site
```

Confirm:
- Home loads at `http://localhost:8080/`
- Industries pages load at `http://localhost:8080/industries/insurance-brokers.html` etc.
- Footer links to `/dashboard/status.html` (will 404 locally unless you're serving the whole `docs/` directory — that's fine, it's absolute-path for production)

To preview the dashboard alongside, serve the whole `docs/` directory:

```bash
python -m http.server 8080 --directory docs
# Public site:  http://localhost:8080/site/
# Dashboard:    http://localhost:8080/dashboard/
# Status page:  http://localhost:8080/dashboard/status.html
```

## Production deployment

The site is fully static; any host that serves HTML works. Recommended:

- **Cloudflare Pages** (free, global CDN, build command: none, output dir: `docs/site`)
- **Netlify** (free, output dir: `docs/site`)
- **Vercel** (output dir: `docs/site`)
- **GitHub Pages** (map `docs/site` to `/` via Actions)

Domain target: `crystallux.org` → serve `docs/site/*`
Dashboard subpath: `crystallux.org/dashboard/*` → serve `docs/dashboard/*`
Public status: `crystallux.org/dashboard/status.html` (already referenced in every footer)

## Placeholder content Mary must customise

- **Calendly URL** in `book.html` and throughout: currently `https://calendly.com/crystallux/discovery`. Replace with the real Calendly event slug once created.
- **Testimonials beyond Filip 9.5/10** on `index.html` and `industries/insurance-brokers.html`. Add named client quotes as they sign written consent.
- **Legal review** on `terms.html` + `privacy.html`. Both carry a yellow banner flagging the template status. Budget $1,000–2,500 for a Canadian small-business lawyer bundle review.
- **Physical address** on `contact.html` and footer: currently "Toronto, Ontario, Canada" (no street). Add street address when incorporated and public-listing is safe.
- **Phone number** on `contact.html`: not included. Add if you want a phone-reachable number.
- **Favicon / logo artwork**: a `C` wordmark is rendered in CSS. Optional: add `favicon.ico` + `og-image.jpg` (1200×630) to `assets/` and reference in each page's `<head>`.
- **Google Analytics / Plausible**: not included. Add tracking tag to `site.js` or directly to each page's `<head>` when you pick an analytics provider.

## What's intentionally not built (scope discipline)

- No case study detail pages yet — wait until first 2–3 paying clients give written consent
- No blog — premature for pre-revenue stage
- No career page — hiring plan is in `docs/operations/HIRING_PLAN.md`; publish a careers page when you start recruiting
- No pricing calculator — the three tiers on `pricing.html` cover 95% of self-serve questions
- No live chat widget — Mary handles enquiries via `info@crystallux.org` for now

## How it ties to existing work

- **Content sources** (most copy already existed as markdown and is used verbatim):
  - `docs/commercial/LANDING_PAGE_COPY.md` → `index.html`
  - `docs/commercial/PRICING_PAGE.md` → `pricing.html`
  - `docs/commercial/SALES_ONE_PAGER.md` → hero sections across the site
  - `docs/verticals/{vertical}/README.md` → `industries/{vertical}.html`
  - `docs/operations/TERMS_OF_SERVICE.md` → `terms.html`
  - `docs/operations/PRIVACY_POLICY.md` → `privacy.html`
- **Dashboard** is completely separate and untouched. Public site links to `/dashboard/status.html` (the one public dashboard page) and `/dashboard` as the "Sign in" destination.
- **Vertical positioning**: insurance brokers is the most mature showcase vertical; the other 4 active verticals (consulting, real estate, construction, dental) each get their own page. Moving, cleaning, and legal are on a waiting-list pattern per the expansion ranking.
