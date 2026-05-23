# Crystallux Design System

> **Status:** Living. Updated as `components.js` / `layout.css` evolve.
> **Audience:** anyone building or modifying a page in `admin-dashboard/` or `client-dashboard/`.

The Crystallux dashboards are deliberately **plain HTML + plain JS** (per `CLAUDE.md` and `ARCHITECTURE_DOCTRINE.md`). No build pipeline, no framework, no bundler. Shared design tokens + helper functions deliver the modern SaaS feel without the rewrite tax.

This doc is the single source of truth for tokens + components. Reach for an existing helper before writing new CSS or DOM by hand.

---

## Source files

| File | Purpose |
|---|---|
| `admin-dashboard/shared/layout.css` | Design tokens + every shared CSS class (admin) |
| `admin-dashboard/shared/components.js` | Helper functions exposed via `window.clxComp` (admin) |
| `client-dashboard/shared/layout.css` | Same tokens, lighter ramp (client) |
| `client-dashboard/shared/components.js` | Same primitives, client-specific helpers (client) |

The admin + client surfaces deliberately share the token names so a component built for one Just Works in the other.

---

## Tokens

All tokens are CSS custom properties on `:root`. **Use the token, not the literal value.** If you write `#7C3AED`, you're locking the brand to a specific hex; if you write `var(--color-brand-500)`, you inherit any future re-ramp for free.

### Color ramps

- `--color-brand-50` → `--color-brand-700` — purple ramp, brand identity
- `--color-accent-100` → `--color-accent-700` — emerald ramp, positive movement
- `--gray-0` → `--gray-900` — slate neutral ramp (slightly cooler than zinc, feels more "premium B2B")

### Semantic

- `--success` (emerald), `--warning` (amber), `--error` (red), `--info` (blue)

### Surface

- `--bg-page`, `--bg-card`, `--bg-sidebar`, `--bg-hover`
- `--border`, `--border-strong`
- `--text-primary`, `--text-secondary`, `--text-muted`, `--text-inverse`

### Elevation (shadow)

- `--shadow-xs`, `--shadow-sm`, `--shadow-md`, `--shadow-lg`

Use `--shadow-md` on hover for cards (the global rule already does this for `.clx-card`). `--shadow-lg` is reserved for floating surfaces (toasts, dialogs, dropdowns, command palette).

### Motion

- `--motion-fast: 120ms`, `--motion-base: 180ms`, `--motion-slow: 280ms`
- `--ease-out: cubic-bezier(0.16, 1, 0.3, 1)` — preferred for entrances + most interactions
- `--ease-in-out: cubic-bezier(0.4, 0, 0.2, 1)` — preferred for state transitions

The global motion baseline already applies these to every interactive element via the wildcard selector at the top of `layout.css`. You only need to write transitions for novel CSS properties.

### Radius

- `--r-sm: 6px` (buttons, pills), `--r-md: 10px` (most surfaces), `--r-lg: 14px` (modals, large cards), `--r-xl: 20px` (hero surfaces)

### Layout

- `--sidebar-w: 240px`, `--topbar-h: 60px`, `--content-max: 1400px`

---

## Components — `window.clxComp.*`

Every helper documented here is exposed on `window.clxComp`. They're framework-free vanilla JS. Most return either a DOM string (for use with `.innerHTML =`) or a control object (for primitives with lifecycle).

### Formatting / utility

| Function | What it does |
|---|---|
| `escapeHtml(s)` | HTML-escape a string. **Always** use before interpolating user data into innerHTML. |
| `formatDate(d)` | ISO string → `YYYY-MM-DD` |
| `formatDateTime(d)` | ISO string → `YYYY-MM-DD HH:mm` |
| `relativeTime(d)` | "2m ago", "3d ago" |
| `formatMoney(amount, currency)` | Cents → `$1,234.56` |
| `badgeFor(status)` | Returns the appropriate badge HTML for common statuses |

### Rendering helpers

| Function | What it does |
|---|---|
| `renderStatGrid(container, items)` | Stat-card grid (used on every overview page) |
| `renderTable(container, rows, columns, options)` | Admin: full sortable/filterable table |
| `renderList(container, items, options)` | Client: simplified card list (mobile-first) |
| `renderEmpty(el, message, iconName, ctaHtml)` | Standardized empty state |
| `sectionHead(title, actionHtml)` | Section heading with optional right-aligned action |

### Visual primitives

| Function | What it does |
|---|---|
| `sparkline(values, options)` | Tiny inline trend line |
| `donut(slices, options)` + `donutLegend(slices)` | Donut chart + matching legend |
| `barChart(values, options)` | Mini bar chart |
| `progressBar(value, max, options)` | Linear progress |
| `scoreBar(score)` | Color-coded 0-100 score bar |
| `avatar(seed, size)` | Generated avatar from a string seed |
| `icon(name, size)` | Inline SVG icon lookup |
| `skeleton(rows, cols)` / `skeletonStat(count)` | Shimmer skeleton placeholders |

### Layout primitives

| Function | What it does |
|---|---|
| `injectNav(target)` | Inject sidebar HTML (with `CLX_FALLBACK_NAV` as recovery) |
| `wireSidebar()` (admin) | Wire mobile burger + collapse |
| `injectBottomNav(target)` (client) | Mobile-first bottom nav |
| `renderTopbarUser(target)` | Right-aligned user chip with menu |
| `injectNavArrows()` (admin) | Browser-style back/forward arrows in topbar |
| `injectChat()` (admin) | Floating bottom-right MCP chat widget |

---

## Polish v2 primitives

Added 2026-05-23. shadcn-equivalent components implemented in vanilla. Each returns a control object so the lifecycle is callable.

### `toast(message, opts)`

Stacked top-right notifications.

```js
clxComp.toast('Saved successfully', { variant: 'success' });
clxComp.toast('Network blip — retrying…', { variant: 'warning', durationMs: 6000 });
clxComp.toast('Undo?', {
  variant: 'info',
  durationMs: 0,           // 0 = persist until dismissed
  action: { label: 'Undo', onClick: () => restoreLastChange() }
});
```

Variants: `'success'` (emerald), `'error'` (red), `'warning'` (amber), `'info'` (slate, default).
Returns `{ dismiss() }`.

**Use instead of:** inline "Saved. Refreshing…" status text, `window.alert()`.

### `dialog({title, body, actions})`

Modal with backdrop blur, focus trap, ESC + outside-click close. Returns `{ close(value), promise }` — `promise` resolves with the value of the action button clicked (or `null` on dismiss).

```js
const d = clxComp.dialog({
  title: 'Delete lead',
  body: '<p>This cannot be undone.</p>',
  actions: [
    { label: 'Cancel', variant: 'ghost', value: false },
    { label: 'Delete', variant: 'danger', value: true }
  ]
});
const confirmed = await d.promise;
```

Action `variant` values: `'primary'` (brand purple), `'danger'` (red), `'ghost'` (subtle).

### `confirm(message, opts)`

Promise-based drop-in for `window.confirm`. Returns `Promise<boolean>`.

```js
const ok = await clxComp.confirm('Approve this action? It will execute now.', {
  title: 'Approve remediation',
  confirmLabel: 'Approve',
  variant: 'primary'
});
if (!ok) return;
// proceed
```

**Use instead of:** `window.confirm()` anywhere.

### `dropdown(triggerEl, items, opts)`

Anchored popover with keyboard nav.

```js
clxComp.dropdown(triggerBtn, [
  { label: 'Edit',    onClick: () => editLead(id) },
  { label: 'Archive', onClick: () => archiveLead(id) },
  { separator: true },
  { label: 'Delete',  variant: 'danger', onClick: () => deleteLead(id) }
], { align: 'right' });
```

### `tabs(container, defs, opts)`

Formalizes the ad-hoc tab pattern.

```js
clxComp.tabs(document.getElementById('tabsHolder'), [
  { key: 'overview', label: 'Overview',  paneId: 'pane-overview' },
  { key: 'health',   label: 'Health',    paneId: 'pane-health', onActivate: loadHealth },
  { key: 'security', label: 'Security',  paneId: 'pane-security' }
], { initialKey: 'overview' });
```

The function manages active state + show/hide on pane elements identified by `paneId`. Caller still owns pane content.

### `openCommandPalette()` + Cmd+K hotkey

Globally auto-wired on every page. Press **Cmd+K** (mac) or **Ctrl+K** (win/linux) anywhere in admin or client.

- Parses `CLX_FALLBACK_NAV` for navigable entries.
- Page-level quick actions: set `window.CLX_PALETTE_ACTIONS = [{label, run}]` **before** `components.js` loads (or on DOM ready, before first hotkey press).
- Disable on a specific page: `window.CLX_AUTO_PALETTE = false`.

---

## Patterns

### "Save + feedback" pattern

Before polish v2:
```js
btn.disabled = true;
statusEl.textContent = 'Saving…';
api.call(...).then(res => {
  if (res.ok) { statusEl.textContent = 'Saved.'; setTimeout(reload, 700); }
  else        { statusEl.textContent = res.error; }
});
```

After polish v2:
```js
btn.disabled = true;
api.call(...).then(res => {
  btn.disabled = false;
  if (res.ok) {
    clxComp.toast('Saved', { variant: 'success' });
    setTimeout(reload, 700);
  } else {
    clxComp.toast(res.error, { variant: 'error', durationMs: 6000 });
  }
});
```

### "Destructive action" pattern

Before:
```js
if (!window.confirm('Delete this lead?')) return;
api.delete(id);
```

After:
```js
const ok = await clxComp.confirm('Delete this lead?', {
  title: 'Delete lead', confirmLabel: 'Delete', variant: 'danger'
});
if (!ok) return;
api.delete(id);
```

### Page-load fade + staggered cards

Automatic. Any `.clx-content` block fades up on load. Any direct children of `.clx-stat-grid` reveal with a 40ms stagger. Honors `prefers-reduced-motion`. No JS required.

### Focus ring

Automatic. Every `button`, `a`, `input`, `select`, `textarea`, `[tabindex]` gets a brand-purple ring on keyboard focus only (via `:focus-visible`). Mouse clicks don't trigger it.

---

## Rules

1. **Never add a build pipeline / framework / bundler.** Per `CLAUDE.md`. The repo is intentionally plain HTML + plain JS.
2. **Use tokens, not literals.** `var(--color-brand-500)` not `#7C3AED`.
3. **Extend `components.js` before writing one-off DOM.** If you write the same pattern twice across two pages, promote it to a helper.
4. **Keep admin + client component parity where it makes sense.** The two surfaces share token names so anything client-applicable should land in both `components.js` files.
5. **Mirror CSS changes to both `layout.css` files.** Different vars (admin is fuller) but matching class names.
6. **Test in the dev server before claiming "looks good."** UI changes need eyeball verification, not just `bash -n` syntax.
7. **`prefers-reduced-motion` is honored.** Don't add animations that ignore it.

---

## Roadmap (not yet built)

Things that would extend the system if the need arises:

- `clxComp.popover(triggerEl, content, opts)` — generic tooltip-style anchor (heavier than dropdown, lighter than dialog)
- `clxComp.combobox(inputEl, items, opts)` — type-ahead select (for "assign to advisor" patterns)
- Inline edit pattern (click a cell, edit in place, blur to save) — currently every page rolls its own
- Empty-state illustrations (today `renderEmpty` uses text only)
- Dark mode — tokens are structured for it but not wired

Don't pre-build any of these. Add them when a real page needs the second instance.

---

*Last updated: 2026-05-23 (polish v2 commits `19bed4b` + `4c55b64`).*
