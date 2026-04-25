# site/ — Public Crystallux SaaS website

Static, no-build, plain HTML + CSS + vanilla JS. Separate from `dashboard/`. Deploy the whole `site/` tree to crystallux.org; the dashboard stays at `crystallux.org/dashboard/` (served from the sibling `dashboard/` directory).

## Structure

```
site/
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
python -m http.server 8080 --directory site

# then open: http://localhost:8080/
```

```bash
# Node (if you have it)
npx -y serve site -p 8080
```

```bash
# PHP (if installed)
php -S localhost:8080 -t site
```

Confirm:
- Home loads at `http://localhost:8080/`
- Industries pages load at `http://localhost:8080/industries/insurance-brokers.html` etc.
- Footer links to `/dashboard/status.html` (will 404 locally unless you serve the repo root — that's fine, the link is an absolute path for production where `site/` and `dashboard/` are both deployed under the same domain)

To preview the dashboard alongside, serve the repo root:

```bash
python -m http.server 8080
# Public site:  http://localhost:8080/site/
# Dashboard:    http://localhost:8080/dashboard/
# Status page:  http://localhost:8080/dashboard/status.html
```

## Production deployment (Cloudflare Pages recommended)

See top-level `DEPLOY.md` for step-by-step Cloudflare Pages setup that deploys `site/` at root and `dashboard/` at `/dashboard/*` from a single repo.

Alternative hosts:

- **Netlify** (free, build output dir: `site`)
- **Vercel** (output dir: `site`)
- **GitHub Pages** (Actions workflow mapping `site` to `/`)

Domain target: `crystallux.org` → serve `site/*` at root
Dashboard subpath: `crystallux.org/dashboard/*` → serve `dashboard/*`
Public status: `crystallux.org/dashboard/status.html` (already referenced in every footer)

## Email aliases to create before launch

All four addresses can forward to the same inbox:

- `info@crystallux.org` (general inquiries, website footer, contact page)
- `support@crystallux.org` (existing client support)
- `security@crystallux.org` (responsible disclosure per `/.well-known/security.txt`)
- `careers@crystallux.org` (careers inquiries from About page)

## Placeholder assets to replace before production launch

- **Calendly URL.** `book.html` and several CTAs point to `https://calendly.com/crystallux/discovery`. Swap for the real event slug.
- **Legal review.** `terms.html` and `privacy.html` carry yellow template banners. Review with an Ontario-licensed lawyer. Budget $1,000 to $2,500 for a bundle.
- **Testimonials.** Only the anonymised 9.5-out-of-10 insurance broker quote is live. Add named client quotes with written consent.
- **favicon.ico + apple-touch-icon.png.** Generate via favicon.io and place in `site/assets/`.
- **og-image.png (1200x630).** Branded social card referenced from every page's `<head>`. Currently points to `assets/og-image.png`.
- **logo.svg.** Hero wordmark for the header. Inline CSS mark is the current fallback.
- **founder-mary.jpg (800x800).** Professional headshot, referenced from `about.html` if Mary decides to add a photo block.
- **Analytics.** Plausible or Google Analytics snippet not yet added. Add to `site.js` or individual page heads once a provider is chosen.

## SEO + security files (managed per deploy)

- `site/sitemap.xml` — 16 URLs, update `<lastmod>` on meaningful page edits.
- `site/robots.txt` — allows all crawlers except `/dashboard/`.
- `site/.well-known/security.txt` — responsible disclosure contact; update `Expires:` before 2027-04-25.
- `site/_headers` — Cloudflare Pages security headers + CSP + cache directives.

## What's intentionally not built (scope discipline)

- No case study detail pages yet. Wait until the first 2 or 3 paying clients give written consent.
- No blog. Premature for pre-revenue stage.
- No career page. Hiring plan is in `docs/operations/HIRING_PLAN.md`. Publish a careers page when recruiting begins.
- No pricing calculator. The three tiers on `pricing.html` cover 95 percent of self-serve questions.
- No live chat widget. We handle inquiries via `info@crystallux.org` for now.

## How it ties to existing work

- **Content sources** (most copy already existed as markdown and is used verbatim):
  - `docs/commercial/LANDING_PAGE_COPY.md` → `index.html`
  - `docs/commercial/PRICING_PAGE.md` → `pricing.html`
  - `docs/commercial/SALES_ONE_PAGER.md` → hero sections across the site
  - `docs/verticals/{vertical}/README.md` → `industries/{vertical}.html`
  - `docs/operations/TERMS_OF_SERVICE.md` → `terms.html`
  - `docs/operations/PRIVACY_POLICY.md` → `privacy.html`
- **Dashboard** is completely separate in `../dashboard/` and untouched. Public site links to `/dashboard/status.html` (the one public dashboard page) and `/dashboard` as the "Sign in" destination.
- **Vertical positioning**: insurance brokers is the most mature showcase vertical; the other 4 active verticals (consulting, real estate, construction, dental) each get their own page. Moving, cleaning, and legal are on a waiting-list pattern per the expansion ranking.
