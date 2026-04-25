# Phase 9: Client Success Framework Integration

**Branch:** scale-sprint-v1
**Date completed:** 2026-04-25
**Built on top of:** Phase 8 premium SaaS visual system

This phase adds the emotional truth layer of the Client Success
Framework to the public site without disturbing the Phase 8 visual
work. Three strategic integrations: hero refinement, "Our promise"
section on the homepage, and a new `/what-to-expect` page documenting
the 30-day client journey.

## Commits in Phase 9

```
bbc88a4 Site: add /what-to-expect page with 30-day journey timeline (Phase 9.3)
6e39367 Site: add "Our promise" section to homepage (Phase 9.2)
4f32778 Site: refine homepage hero around emotional client truth (Phase 9.1)
```

Phase 9.4 (this audit + nav + sitemap updates) ships in a fourth
commit.

## What changed

### 9.1 Hero
The homepage h1 moved from a metric ("books 20+ qualified meetings
every month") to an emotional truth: "Focus on what you do best. We
handle the pipeline." The gradient-clipped emphasis lands on "We
handle the pipeline." Subtitle rewrites from outcome-statistic into
peer-advisor copy that captures the framework's core promise.

### 9.2 Our promise
New homepage section between the Industries teaser and the Guarantee
block. Three cards on a soft white-to-brand-50 gradient panel:
- "You stop chasing prospects" (less effort)
- "You always know what is happening" (more clarity)
- "You see real conversations" (better results)

Below the cards, a `.promise-journey` card carries the 30-day
commitment language and a `btn-link` arrow CTA pointing to the new
`/what-to-expect` page.

### 9.3 What-to-expect page
New page at `/what-to-expect.html` showing the day-by-day
client journey. Five timeline phases with brand-violet numbered
markers:
- Days 0 to 3: Activation
- Days 4 to 7: First visibility (with brand-50 quote callout)
- Days 8 to 14: Early traction
- Days 15 to 21: Pattern building
- Days 22 to 30: Retention lock

Followed by a 7-card weekly scorecard grid (leads sourced, leads
researched, outreach sent, replies received, meetings booked,
best-performing angle, one recommended improvement) and a final CTA
section.

### 9.4 Internal wiring
- Added "What to expect" link to the main nav between "How it works"
  and "Industries" on all 16 pages
- Added the page to `sitemap.xml` with priority 0.8
- Added the page to footer Product column (visible from
  `what-to-expect.html` itself; other pages keep the Phase 8 footer
  exactly to minimise diff surface)
- Promise-journey CTA on homepage links to the new page

## CSS additions

All new selectors are additive on top of Phase 8 tokens:
- `.promise` / `.promise-grid` / `.promise-card` / `.promise-icon` /
  `.promise-title` / `.promise-description` / `.promise-journey` /
  `.journey-headline`
- `.page-hero` / `.journey-timeline` / `.timeline` (with vertical
  rule via `::before`) / `.timeline-phase` / `.timeline-marker` /
  `.timeline-number` / `.timeline-period` / `.timeline-content` /
  `.timeline-title` / `.timeline-goal` / `.timeline-list` /
  `.timeline-quote`
- `.weekly-scorecard` / `.scorecard-grid` / `.scorecard-item` /
  `.scorecard-icon` / `.scorecard-label`
- `.cta-section`

All inherit the design tokens from Phase 8 (Inter scale, Zinc
neutrals, brand-violet ramp, 8px spacing grid, radii, shadows).

## DO-NOT-BREAK verification

- Phase 8 visual system preserved (no token edits, no component
  selectors removed or modified destructively)
- `dashboard/`, `docs/`, `workflows/` untouched
- All URL slugs preserved (only `/what-to-expect.html` added new)
- Em / en dashes: 0 across the new page + the homepage diff
- `info@crystallux.org` unchanged everywhere
- Sign-in link unchanged on every page
- "Book a demo" remains the only primary CTA above the fold on the
  homepage
- Mobile responsive at 640 / 768 / 1024 breakpoints (timeline
  marker shrinks to 38px, scorecard grid drops to 1 column,
  promise grid stacks)
- Disk: 14G free at end of phase

## Phase 9 close

Phase 9 complete. Client Success Framework essence lives in three
strategic locations on the public site: the hero promise, the
"Our promise" homepage section, and the dedicated
`/what-to-expect` page. Conversion-strengthening content layered on
top of the Phase 8 premium visual system without disturbing it.
