# Beauty Marketplace — Future Separate Product

**Status:** future roadmap only. Not under construction. Not on any
active branch. No migrations, workflows, or client commitments
associated.

## Vision

A two-sided marketplace connecting beauty service providers with
customers. **Separate from Crystallux B2B** (which sells lead-gen to
salon owners paying $997/mo). This is a different product entirely — a
B2B2C marketplace, not a B2B SaaS.

## Target Providers

- Salon owners (physical location)
- Mobile service providers (travel to customer)
- Home-based stylists (customers come to them)

## Service Categories

- **Hair:** cut, color, styling, extensions, braids
- **Nails:** manicure, pedicure, nail art, gel, acrylic
- **Skin:** facials, peels, microdermabrasion, dermaplaning
- **Body:** massage, body wraps, waxing, sugaring
- **Makeup:** event, bridal, photoshoot, lessons
- **Spa:** sauna, steam, hydrotherapy
- **Brows / Lashes:** extensions, lifts, tints, microblading
- **Other:** eyebrow threading, henna, etc.

## Business Model

- Provider signs up (free, verify license/insurance)
- Customer books + pays via marketplace (Stripe Connect)
- 50% deposit upfront, 50% after service
- Marketplace takes 15-25% commission
- Provider keeps the rest; payout via Stripe

## Technical Differences from Crystallux B2B

| Crystallux B2B | Beauty Marketplace |
|---|---|
| B2B SaaS | B2B2C marketplace |
| Monthly subscription billing | Per-transaction commission |
| Client pays us | Customer pays us, we pay provider |
| Regular Stripe | Stripe Connect (with escrow) |
| One client = one brand | Hundreds of providers, one brand |
| Inbound outreach tool | Consumer-facing booking app |

## Development Estimate

- **6-8 weeks** full-time engineering **OR**
- **3-4 months** as side project alongside Crystallux B2B

Requires:

- New domain / brand
- Consumer app UI
- Stripe Connect integration
- Provider onboarding flow
- Customer reviews system
- Dispute resolution workflow
- Mobile apps eventually

## Prerequisites

- Crystallux B2B generating **$20K+ MRR** (proves the business model is
  real)
- Mary has bandwidth **or** hires first engineer
- Brand name decided
- Legal review for marketplace agreements (provider + customer terms)
- Business insurance upgrade (marketplace liability)

## Revenue Projection

- Month 6: 100 providers × 10 bookings/mo × $80 avg × 20% commission =
  **$16,000/mo**
- Month 12: 500 providers × 15 bookings/mo × $80 avg × 20% commission =
  **$120,000/mo**

## Next Steps (when ready)

1. Validate demand: survey 20 potential providers
2. Pick brand name + domain
3. Design MVP: provider signup → add services → accept bookings → get
   paid
4. Build MVP (Claude Code + Mary + contractor)
5. Soft launch with 10 pilot providers
6. Iterate based on feedback
7. Scale marketing

## Decision Gate

**Do not start building** until Crystallux B2B has $20K MRR and is
operationally stable. This roadmap exists as a parking spot for the
idea, not as an authorization to start work.
