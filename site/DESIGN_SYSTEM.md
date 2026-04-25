# Crystallux Design System

**Owner:** site/assets/site.css
**Last updated:** 2026-04-25 (Phase 8 premium SaaS upgrade)
**Inspirations:** Stripe, Vercel, Notion, DataPilot, Zarex

This document describes the production design system for the public
Crystallux website. It is not a marketing document. It is the source
of truth for new pages, new sections, and any future redesign work.

## Principles

1. **Premium but not flashy.** Confidence through restraint, not motion.
2. **Calm, not loud.** Brand violet appears on accents only.
3. **Conversion-focused.** One primary CTA per section. Every section
   ends pointing somewhere, not nowhere.
4. **Modern but timeless.** Avoids ephemeral 2024 trends.
5. **Light by default.** Dark mode supported via
   `prefers-color-scheme` but never forced.
6. **Mobile-first.** Every component collapses cleanly at 1024 / 768 /
   640px breakpoints.

## Typography

**Family:** Inter, weights 400 / 500 / 600 / 700 / 800. Loaded from
Google Fonts with preconnect.

### Display scale (hero + section headings)

| Token | Size | Usage |
|---|---|---|
| `--text-display-xl` | 4.5rem (72px) | Hero h1 |
| `--text-display-lg` | 3.75rem (60px) | About / industry hero h1 |
| `--text-display-md` | 3rem (48px) | Section h2 |
| `--text-display-sm` | 2.25rem (36px) | Subsection h3 |

Mobile (<=768px) downsizes display-xl to 40px, display-lg to 36px,
display-md to 30px, display-sm to 24px.

### Body scale

| Token | Size | Usage |
|---|---|---|
| `--text-xl` | 1.25rem (20px) | Hero subtitle, section subtitle |
| `--text-lg` | 1.125rem (18px) | Card titles, FAQ questions |
| `--text-base` | 1rem (16px) | Body |
| `--text-sm` | 0.875rem (14px) | Captions, labels, button text |
| `--text-xs` | 0.75rem (12px) | Eyebrows, badges, meta |

### Letter spacing + line height

- `--tracking-display: -0.04em` for hero h1
- `--tracking-headline: -0.02em` for section headings
- `--tracking-body: 0` for everything else
- `--leading-display: 1.05` (hero)
- `--leading-heading: 1.2` (sections)
- `--leading-body: 1.6` (paragraphs)

### Heading rules

- Hero h1: display-xl / weight 700 / tracking-display
- Section h2: display-md / weight 700 / tracking-headline
- Subsection h3: display-sm / weight 600
- Card title h3 / h4: text-lg / weight 600
- Body p: text-base / weight 400 / color text-secondary

## Colour

### Brand violet (used sparingly)

| Token | Hex | Usage |
|---|---|---|
| `--color-brand-50` | #F8F7FF | Subtle accent backgrounds, hero radial |
| `--color-brand-100` | #EDE9FE | Badge backgrounds, icon swatches |
| `--color-brand-200` | #DDD6FE | Featured-card borders, dashed placeholders |
| `--color-brand-300` | #C4B5FD | Featured tier ring |
| `--color-brand-400` | #A78BFA | Quote marks, accent dots |
| `--color-brand-500` | #7C3AED | Primary CTA background |
| `--color-brand-600` | #6D28D9 | Primary CTA hover, active nav |
| `--color-brand-700` | #5B21B6 | CTA active, brand text on light |
| `--color-brand-800` | #4C1D95 | Reserved |
| `--color-brand-900` | #3F1A87 | Reserved |

**Rule:** Brand violet **never** appears as a section background.
Only on CTAs, eyebrows, accent underlines, icon strokes, and the
soft hero radial gradient (top-right corner only, fades to transparent).

### Neutrals (Zinc family)

50 #FAFAFA, 100 #F4F4F5, 200 #E4E4E7, 300 #D4D4D8, 400 #A1A1AA,
500 #71717A, 600 #52525B, 700 #3F3F46, 800 #27272A, 900 #18181B,
950 #09090B.

Both `--color-neutral-*` and `--color-gray-*` aliases exist for the
same values.

### Semantic

- `--color-success` = #10B981 (check icons, ratings)
- `--color-warning` = #F59E0B (rating stars)
- `--color-error` = #EF4444 (reserved for forms)

### Functional aliases

| Token | Value |
|---|---|
| `--bg-default` | white |
| `--bg-subtle` | gray-50 |
| `--bg-elevated` | white (cards) |
| `--text-primary` | gray-900 |
| `--text-secondary` | gray-600 |
| `--text-tertiary` | gray-500 |
| `--text-on-brand` | white |
| `--border-subtle` | gray-200 (cards, dividers) |
| `--border-default` | gray-200 (separators) |
| `--border-emphasis` | gray-300 (hover states) |

## Spacing (8px grid)

`--space-1` through `--space-32` map to 0.25rem (4px) through 8rem
(128px). Section padding uses `--space-32` desktop and `--space-20`
mobile. Card padding uses `--space-8`. Inline gap uses `--space-3` to
`--space-6`.

## Radius + shadow

| Token | Use |
|---|---|
| `--radius-md` (0.5rem) | Buttons, badges |
| `--radius-lg` (0.75rem) | Buttons, FAQ items, small cards |
| `--radius-xl` (1rem) | Hero card, feature cards, industry cards |
| `--radius-2xl` (1.5rem) | Pricing cards, testimonial card, hero mockup |
| `--radius-full` | Pills, badges |

| Shadow | Use |
|---|---|
| `--shadow-xs` | Idle cards |
| `--shadow-sm` | FAQ open state, testimonial card |
| `--shadow-md` | Card hover, KPI cards inside hero mockup |
| `--shadow-lg` | Featured pricing tier ring + lift |
| `--shadow-xl` | Reserved |

## Components

### Hero (`.hero`)
Two-column grid, content on left, mockup on right. Eyebrow badge,
display-xl h1 with `.hero-title-emphasis` (gradient-clipped span on
key phrase), subtitle, primary + link CTAs, trust strip with
checkmark bullets, dashboard mockup SVG.

### Section header (`.section-header`)
Centred. Eyebrow + display-md title + subtitle. Used on every major
section.

### Feature grid (`.features` / `.feature-grid` / `.feature-card`)
3-column grid. Stroked SVG icon in brand-50 swatch, title (text-lg /
weight 600), description, "Learn more" link with arrow. Hover lifts
2px, border darkens, icon swatch gains a gradient.

### Industries grid
Same card pattern with badges (`.industry-badge` brand /
`-muted` gray for waitlist), industry stats block (2 stats with
display-sm values), `.industry-card-featured` for the primary slot,
`.industry-card-waitlist` for muted treatment. Bespoke CTA strip
below the grid (`.industries-bespoke`).

### Pricing tiers (`.pricing-grid` / `.pricing-tier` / `.pricing-tier-featured`)
3 columns. Featured tier translates 8px upward, gains brand-300 ring
+ shadow-lg + "Most popular" badge. Each tier: name, tagline, price
amount + period + note, optional "Everything in [previous], plus:"
heading, feature list with green check SVGs, full-width footer
button.

### Testimonial (`.testimonial-section` / `.testimonial-card`)
Centred. Star rating with one half-star (defs gradient), display-2xl
quote with brand-violet curly quote marks, author figure with avatar
circle (gradient + initial fallback) + name + title.

### FAQ accordion (`.faq` / `.faq-item` / `details`)
Native HTML5 details element, no JavaScript. Closed: border-subtle.
Hover: border-default. Open: border-brand-200 + shadow-sm + 45deg
plus-to-x rotation on toggle icon. Bottom CTA card on bg-subtle.

### Buttons

- `.btn-primary` is brand-500 fill, white text, subtle shadow lift on
  hover, brand-600 background.
- `.btn-secondary` is transparent, brand-700 text, brand-200 border,
  brand-50 background on hover.
- `.btn-link` is text-only with arrow that translates 2px right on
  hover.
- `.btn-lg` is padding bump, font-size up to text-base.
- `.btn-block` is full width, used inside pricing card footers.

### Footer (`.clx-footer`)
4-column grid: brand block (logo + tagline + address) + Product +
Company + Legal. Footer bar at bottom: copyright + compliance line.
Mobile collapses to 2-then-1 columns.

## Accessibility

- `:focus-visible` brand-500 outline + 2px offset on every focusable
  element.
- `prefers-reduced-motion: reduce` kills all transitions, animations,
  and smooth scroll.
- `aria-label` on rating stars and decorative SVGs marked
  `aria-hidden="true"`.
- `<details>`-based accordion keyboard-accessible by default.
- All headings follow logical h1 -> h2 -> h3 hierarchy.

## CSS variable reference

All design tokens live at the top of `site/assets/site.css` inside
`:root`. Both new Phase 8 tokens (`--text-display-*`,
`--color-gray-*`, `--bg-default`, etc.) and legacy
backward-compatible aliases (`--primary`, `--ink`, `--surface`,
etc.) coexist so any existing `.clx-*` selector keeps working.

## Page coverage matrix

| Page | Hero | Feature grid | Industries | Pricing | Testimonial | FAQ | About | Status |
|---|---|---|---|---|---|---|---|---|
| index.html | new | new | teaser |   | new |   |   | **Phase 8 complete** |
| pricing.html |   |   |   | new (3-tier) |   |   |   | **Phase 8 complete** |
| faq.html |   |   |   |   |   | new (accordion) |   | **Phase 8 complete** |
| about.html | new |   |   |   |   |   | new | **Phase 8 complete** |
| industries/index.html |   |   | new (5+2) |   |   |   |   | **Phase 8 complete** |
| industries/insurance-brokers.html | template | template |   | strip | Filip 9.5/10 | template |   | **Phase 8 complete** |
| industries/consulting.html | template | template |   | strip | placeholder | template |   | **Phase 8 complete** |
| industries/real-estate.html | template | template |   | strip | placeholder | template |   | **Phase 8 complete** |
| industries/construction.html | template | template |   | strip | placeholder | template |   | **Phase 8 complete** |
| industries/dental.html | template | template |   | strip | placeholder | template |   | **Phase 8 complete** |
| features.html |   |   |   |   |   |   |   | inherits typography + palette only |
| how-it-works.html |   |   |   |   |   |   |   | inherits typography + palette only |
| contact.html |   |   |   |   |   |   |   | inherits typography + palette only |
| book.html |   |   |   |   |   |   |   | inherits typography + palette only |
| privacy.html / terms.html |   |   |   |   |   |   |   | inherits typography + palette only |

Pages marked "inherits" pick up the refined Inter scale, Zinc neutrals,
and brand-violet token via the legacy `.clx-*` selectors that already
mapped to the new tokens. They still render at production quality.
