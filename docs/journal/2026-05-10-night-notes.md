# 2026-05-10 Night Notes (Continuity)

## Status as of tonight
- Committed: f5a73cf (Layer 2 Part B)
- SQL migrations: all 7 run successfully in Supabase
- Workflow imports: 41 Layer 2 workflows imported into n8n container
- All Layer 2 workflows DORMANT (active=false)
- Lead generation engine still running

## Discovered tonight
- n8n runs in Docker container "n8n" (not systemd)
- n8n data volume: /var/lib/docker/volumes/n8n_data/_data
- Container internal path: /home/node/.n8n
- Workflows imported via: docker exec n8n n8n import:workflow

## Remaining wiring (tomorrow morning)
1. Generate LICENSE_ENCRYPTION_KEY via openssl rand -base64 32
2. Find correct env file location (in n8n_data volume)
3. Add encryption key + restart n8n
4. Promote user to mga_principal in Supabase
5. Seed 12 video templates
6. Deploy insurance-mga-dashboard/ to Cloudflare Pages
7. Smoke test full deployment
8. Send Layer 2 Part C prompt to Claude Code

## Layer 2 Part C scope (next session, 4-6 hours Claude Code)
- Insurer-Facing Mode + Production Reports + Demo Tools
- Insurer dashboard (read-only access for carriers)
- Real-time KPI displays
- Compliance scorecards
- Demo/pitch mode for insurer presentations
- Public capability page

## Future phases (referenced)
- Phase 4: Content Marketing workflows (2-3 weeks, schema already in commit 25c0886)
- Phase 6: Carrier API integrations (12-18 months, business development driven)
- Phase 10: Advanced compliance automation (4-6 weeks, when $5M+ production)

## Architectural decisions tonight
- Multi-vertical architecture with vertical_id tagging
- Phase 4 content marketing schema exists, workflows deferred
- Don't migrate to Node.js services until $300K+ MRR
- Don't think about selling until 100+ paying customers
- 3-4 weeks to first paying customer is realistic

## Strategic positioning vs competitors
- Not like Scoop Insurance (digital brokerage, not platform)
- More like Send (UK), Cogitate (US) MGA platforms
- AI-native vs retrofitted = key moat
- Multi-vertical foundation = expansion moat
- Behavioral intelligence + triggered video reviews = unique
