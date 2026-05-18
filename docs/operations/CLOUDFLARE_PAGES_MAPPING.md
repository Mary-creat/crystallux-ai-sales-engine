# Cloudflare Pages — custom domain → project → repo dir mapping

Source-of-truth for "which Pages project serves which URL." Run by curl + content-fingerprint diff against each candidate `.pages.dev` URL, 2026-05-19.

## Mary's question (and the short answer)

**"Dev preview `crystallux-dashboard.pages.dev` has features that production `admin.crystallux.org` doesn't have."**

Those are **two different applications**, not the same project at different deploy stages:

| URL | Source dir | `index.html` size | Title |
|---|---|---|---|
| `crystallux-dashboard.pages.dev` | `dashboard/` (LEGACY SPA) | **4,578 lines** | "Crystallux — Universal AI Sales Engine" |
| `admin.crystallux.org` | `admin-dashboard/` (new shell) | 60 lines | "Crystallux Admin" |

Per `CLAUDE.md`: *"`dashboard/` — **legacy** single-page dashboard. Source for features being ported into the split admin/client dashboards. Don't develop net-new here."*

So the features Mary sees on dev preview are **legacy app features that haven't been ported to the new split dashboards yet**. Not a deployment sync bug. The fix is "port that feature into the new admin-dashboard," not "change CF Pages settings."

## Confirmed project → custom-domain map (content-verified)

| Custom domain | Pages project | Repo dir | Status |
|---|---|---|---|
| `admin.crystallux.org` | `crystallux-admin-dashboard` *(presumed)* | `admin-dashboard/` | ✓ Current — has MAXI / Avatars / `/auth-check` / etc. |
| `app.crystallux.org` | likely `crystallux-client-dashboard` | `client-dashboard/` | ✓ Current per probe |
| `mga.crystallux.org` | `crystallux-mga` | `insurance-mga-dashboard/` | ✓ Current per probe |
| `portal.crystallux.org` | likely `crystallux-insurer-portal` | `insurer-dashboard/` | ✓ Probed: title "Sign in · Crystallux Insurer Portal" |
| `insurers.crystallux.org` | likely a marketing project | possibly `site/industries/` or separate | ✓ Probed: title "Crystallux for Insurers — AI-native MGA platform partnerships" |
| `crystallux.org` | likely `crystallux-site` | `site/` | ✓ |
| `insurance.crystallux.org` | likely `crystallux-insurance-marketing` | `insurance-marketing/` | ✓ Probed: title "Crystallux Financial Services" |

The "(presumed)" / "likely" labels are because Cloudflare doesn't expose project ↔ custom-domain bindings without an API call — Mary should verify in the dashboard.

## Detected Pages projects (by .pages.dev probing)

Names confirmed to exist (returned HTTP 200):

| `.pages.dev` URL | Title served | Serves repo dir |
|---|---|---|
| `crystallux-dashboard.pages.dev` | "Crystallux — Universal AI Sales Engine" | `dashboard/` (LEGACY) |
| `crystallux-admin-dashboard.pages.dev` | "Crystallux Admin" | `admin-dashboard/` |
| `crystallux-admin.pages.dev` | "Crystallux Admin" | `admin-dashboard/` *(likely duplicate)* |
| `crystallux-mga.pages.dev` | "Crystallux Insurance MGA" | `insurance-mga-dashboard/` |

The other guess names probed (`crystallux-client`, `crystallux-client-dashboard`, `crystallux-portal`, `crystallux-insurer`, `crystallux-site`, `crystallux-marketing`, `crystallux-insurance`, `crystallux-insurance-marketing`, `crystallux-insurers`) all returned no result — but that doesn't mean those projects don't exist; CF Pages projects can have arbitrary names. Mary can confirm by checking the project list in the dashboard.

### Notable: two admin projects

Both `crystallux-admin-dashboard.pages.dev` and `crystallux-admin.pages.dev` exist and serve the same `admin-dashboard/`. One is likely either a duplicate / renamed-project artifact OR a parallel project from a previous setup attempt. Worth checking which one `admin.crystallux.org` is actually bound to — that determines which one to keep "fed" with merges. The other can probably be archived/deleted.

To find out: in the Cloudflare dashboard, open each project → **Custom domains** tab. The one without `admin.crystallux.org` listed is the orphan.

## Mary's action checklist (in the Cloudflare dashboard)

For each of the 6–7 Pages projects:

1. **Custom domains tab** — confirm exactly one custom domain is bound. Note the binding.
2. **Settings → Builds & deployments** — verify:
   - **Production branch** = `scale-sprint-v1` (or `main` if Mary's policy is merge-then-deploy). If different across projects, that's the deploy-skew Mary fears.
   - **Build output directory** matches the correct subdir (`admin-dashboard`, `client-dashboard`, etc.).
3. **Deployments tab** — check the most recent successful production deployment's commit hash. Cross-reference with `git log --oneline -5` to confirm latest work is live.
4. For the orphan project (`crystallux-admin` if the active one is `crystallux-admin-dashboard`, or vice versa): document its existence; consider archiving once confirmed unused.

## Cache-Control header bug discovered while probing (fixed in this commit)

`/shared/nav.html` was returning a duplicated `Cache-Control` header:

```
Cache-Control: public, max-age=86400, must-revalidate, public, max-age=0, must-revalidate
```

Cause: both `/shared/*` (long cache) AND `/*.html` (short cache) rules in `admin-dashboard/_headers` matched `/shared/nav.html`, and CF Pages concatenated rather than choosing one. Browsers' parser behaviour on duplicated values is implementation-defined and usually picks the more-restrictive (max-age=0) — so it worked in practice but is sloppy.

Fix landed this commit: split `/shared/*` into `/shared/*.js` + `/shared/*.css` so it doesn't catch HTML partials. The `/*.html` rule remains the only one that matches `nav.html`. Same pattern should be applied to `client-dashboard/_headers` and `site/_headers` (per CLAUDE.md these are the three canonical `_headers` files) if they have the same overlap — left as a follow-up if Mary wants the sweep.

## Cache purge — when to do it

After a `_headers` change, the new headers only take effect for files that are **served fresh from origin**. Existing cached files keep their old headers until their TTL expires. To force the new Cache-Control to take effect immediately on the affected files:

```
Cloudflare dashboard → caching → Custom Purge → by URL:
  https://admin.crystallux.org/shared/nav.html
```

For broader propagation issues (the kind Mary asked about — "dev has features prod doesn't"), this won't help — the two `.pages.dev` URLs and the custom domain in those cases serve **completely different builds from different projects**, not differently-cached versions of the same build.

## What to read next

- [`blockers.md`](../audit/blockers.md) § `0i` — Cloudflare CDN cache trap on `/shared/*`. Same family of issue, separate incident.
- [`docs/architecture/PLATFORM_ARCHITECTURE.md`](../architecture/PLATFORM_ARCHITECTURE.md) — if it exists. Otherwise CLAUDE.md "Where things live" section is the source of truth for which directory maps to which app.
