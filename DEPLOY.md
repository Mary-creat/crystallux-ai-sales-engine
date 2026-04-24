# DEPLOY.md — Cloudflare Pages setup for crystallux.org

Deploys two trees from one repo: the public marketing site at root + the dashboard at `/dashboard/*`, on Cloudflare's global CDN, free tier. Total setup time: ~30 minutes.

**Final structure:**

```
Repo root
├── site/          → served at crystallux.org/*
├── dashboard/     → served at crystallux.org/dashboard/*
├── workflows/     → not deployed (kept in repo for version control)
├── docs/          → not deployed (internal documentation)
└── DEPLOY.md      → this file
```

## 1. Cloudflare Pages project setup

### 1.1 Prerequisites

- Cloudflare account with `crystallux.org` nameservers already pointed at Cloudflare (or able to point DNS there)
- Git repo pushed to GitHub, GitLab, or Bitbucket (Cloudflare Pages pulls from Git)
- 10 minutes

### 1.2 Create the Pages project

1. Log in to Cloudflare dashboard → **Workers & Pages** → **Create application** → **Pages** → **Connect to Git**
2. Select your Git provider and authorise Cloudflare
3. Pick the `crystallux-ai-sales-engine` repo
4. On the **Set up builds and deployments** screen:
   - **Production branch:** `scale-sprint-v1` (or `main` once you merge)
   - **Framework preset:** None
   - **Build command:** *(leave empty — static, no build)*
   - **Build output directory:** `site`
   - **Root directory (advanced):** `/` *(leave default — we need access to both `site/` and `dashboard/` via redirects)*
5. Click **Save and Deploy**

At this point the public site deploys at `<project>.pages.dev`. The dashboard is **not yet reachable**. Next step wires it in.

### 1.3 Add redirects for the dashboard tree

Cloudflare Pages serves the configured build output (`site/`) at root. To serve `dashboard/` at `/dashboard/*` from the same deployment, we use a `_redirects` file.

Create `site/_redirects` (or add these lines to it if it already exists):

```
# Serve dashboard tree from /dashboard/* (sibling directory in repo)
# Cloudflare Pages 200 = rewrite (URL path stays, content swapped)
/dashboard       /dashboard/index.html   200
/dashboard/      /dashboard/index.html   200
```

Problem: the `dashboard/` tree is **outside** the `site/` build output directory by default, so Pages won't find it. Two clean fixes:

**Option A (recommended) — combine both trees under a single build dir:**

1. Change the Pages project **Build output directory** from `site` to a new combined directory
2. Add a one-line build command that symlinks or copies both trees into the combined dir:

   Set **Build command** to:
   ```
   mkdir -p .build && cp -r site/. .build/ && mkdir -p .build/dashboard && cp -r dashboard/. .build/dashboard/
   ```

3. Change **Build output directory** to `.build`
4. Re-deploy. Now `<project>.pages.dev/` serves the public site and `<project>.pages.dev/dashboard/` serves the dashboard.

**Option B — use Cloudflare Worker for routing:**

Skip if Option A is working. Worker-based routing is more flexible but adds complexity. Document only if needed later.

### 1.4 Custom domain

1. In the Pages project → **Custom domains** → **Set up a custom domain**
2. Enter `crystallux.org`
3. Cloudflare auto-creates the DNS record (if your domain's nameservers are on Cloudflare)
4. Enable "Always use HTTPS" and "Automatic HTTPS rewrites" in SSL/TLS settings
5. Wait 1-5 min for the domain to go live

Optionally add `www.crystallux.org` as an additional custom domain; configure a redirect from `www` to apex in Cloudflare's Rules.

---

## 2. Verification checklist

After deploy, check each URL in an incognito window:

- [ ] `https://crystallux.org/` → public home page loads
- [ ] `https://crystallux.org/features.html` → features page
- [ ] `https://crystallux.org/pricing.html` → pricing page
- [ ] `https://crystallux.org/industries/insurance-brokers.html` → vertical page
- [ ] `https://crystallux.org/terms.html` → Terms of Service
- [ ] `https://crystallux.org/privacy.html` → Privacy Policy
- [ ] `https://crystallux.org/book.html` → Calendly embed loads (may need JS)
- [ ] `https://crystallux.org/dashboard/` → dashboard loads, shows access-denied (no token)
- [ ] `https://crystallux.org/dashboard/status.html` → public status page loads
- [ ] `https://crystallux.org/dashboard/?token=<test_admin_token>` → admin banner + sidebar render
- [ ] SSL certificate valid, no mixed-content warnings
- [ ] Mobile: Chrome devtools responsive mode → hamburger menu works at <820px

If any URL 404s, re-check the build command and output directory settings.

---

## 3. Environment variables

Cloudflare Pages does NOT need any environment variables for this deployment — the site is pure static HTML/CSS/JS. All secrets live in:

- **n8n** (self-hosted): MARY_MASTER_TOKEN, ANTHROPIC_API_KEY, OPENAI_API_KEY, STRIPE_SECRET_KEY, APOLLO_API_KEY, TAVUS_API_KEY, UNIPILE_API_KEY, TWILIO_*, VAPI_*, OPENWEATHER_KEY, NEWSAPI_KEY
- **Supabase** (managed): SUPABASE_SERVICE_KEY (not client-accessible; server-side only)
- **Stripe** (managed): webhook signing secret (configured in Stripe dashboard)

The dashboard browser-side code prompts Mary to paste her Supabase anon key in Settings on first load; it's stored in `sessionStorage` and cleared on browser close.

---

## 4. Continuous deployment

Every `git push` to the production branch triggers a new Cloudflare Pages build automatically:

1. Edit files locally
2. `git add .` + `git commit -m "..."` + `git push origin scale-sprint-v1` (or `main`)
3. Cloudflare detects the push → rebuilds → deploys within 1-2 min
4. Cache-busting: Cloudflare auto-invalidates CDN edges on new deploy

**Preview deploys:** every non-production branch gets its own `<branch>.<project>.pages.dev` URL. Use for staging changes before merging.

---

## 5. Rollback

If a deploy breaks production:

1. Cloudflare Pages → **Deployments** tab → find the previous green deploy
2. Click **···** → **Rollback to this deployment**
3. Active within 30 seconds

Git history remains intact — rollback only affects what's served.

---

## 6. Cost

- **Cloudflare Pages:** free for up to 500 builds/month, unlimited bandwidth, unlimited requests on the free tier. Crystallux's deploy cadence (weekly-ish) is well under the limit.
- **DNS:** included with Cloudflare account (free)
- **SSL:** free via Cloudflare-issued Let's Encrypt equivalents
- **Custom domain:** no charge from Cloudflare; whatever your registrar charges for `crystallux.org` renewal (~$15-20/year)

**Total: $0/month for the deployment infrastructure.**

---

## 7. Post-deploy tasks for Mary

- [ ] Replace Calendly placeholder URL in `site/book.html` (and multiple pages — search for `calendly.com/crystallux/discovery`) with the real event slug
- [ ] Submit `terms.html` and `privacy.html` to a Canadian lawyer for review (yellow banners on both pages flag this)
- [ ] Add Plausible Analytics (or equivalent) tracking snippet to `site/assets/site.js` or each page's `<head>`
- [ ] Upload `favicon.ico` and `og-image.jpg` to `site/assets/`, reference in every page's `<head>`
- [ ] Verify the dashboard URL pattern `crystallux.org/dashboard/?token=<MARY_MASTER_TOKEN>` loads admin mode correctly
- [ ] Run the 7-test isolation protocol in `dashboard/CLIENT_ISOLATION_TEST.md` before onboarding the first client on production

---

## 8. Alternative hosts

If Cloudflare Pages isn't available:

- **Netlify** — same workflow. Build output `.build`, same build command, custom domain via DNS.
- **Vercel** — same. Set `outputDirectory` in `vercel.json`.
- **GitHub Pages** — possible but clunky for two-tree layout; needs an Actions workflow that runs the same `cp -r` command and pushes to `gh-pages` branch.
- **Static server behind Nginx/Caddy** — Mary's n8n host could serve both trees; adds ops burden and not free.

**Recommendation:** stay on Cloudflare Pages unless you have a specific reason to move.

---

## 9. Known limitations

- **Cloudflare Pages free tier has no server-side code execution.** Any dynamic behaviour (contact form handling, custom auth) must run via n8n webhooks or a separate Cloudflare Worker.
- **No edge middleware for token verification** on free tier. The `clx-verify-dashboard-access-v1` workflow handles this server-side at n8n.
- **Build command timeout: 20 minutes.** Our build is ~5 seconds; no risk.
- **Cache invalidation on deploy:** usually automatic, but purge manually from Cloudflare → Caching → Purge Everything if stale content appears.
