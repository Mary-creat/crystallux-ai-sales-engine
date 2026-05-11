# Session 2 — Layer 1 universal additions

> Closes Phase 4 (Content Marketing) infrastructure + AdvisorAssist gaps
> (pre-meeting briefing, training coach, file-completeness scoring,
> universal supervisor + multi-attempt rebook) + multi-vertical
> archetype seeds for 6 additional verticals.

## What landed (Layer 1 / universal)

### Schemas (3 new, all idempotent)

| File | Tables / RPCs | Purpose |
|---|---|---|
| `db/migrations/pre-meeting-briefing-schema.sql` | `pre_meeting_briefings` | F6 closing-pitch prep. AI generates client_context, key_facts, talking_points, anticipated_objections, recommended_products, competitive_positioning, closing_techniques 1-2h before each meeting. |
| `db/migrations/training-coach-schema.sql` | `training_topics`, `training_sessions` | Universal coach framework. `training_topics.vertical_id` is NULLABLE (NULL = universal). Insurance + future verticals add their own topics via seed workflows. |
| `db/migrations/file-completeness-schema.sql` | `file_completeness_rules`, `file_completeness_scores` | Universal scoring engine. Rule precedence: client-specific > vertical-specific > platform default. Scores are `incomplete | needs_work | nearly_ready | ready_for_review`. |

### Workflows (32 new, all `active: false`)

| Folder | Count | Purpose |
|---|---|---|
| `workflows/api/content/` | 14 | Phase 4 content marketing pipeline — topic generator (cron 06:00), script writer, video render (delegates to existing HeyGen pipeline), HeyGen callback, 6 platform publishers (LinkedIn, Instagram, Facebook, YouTube, TikTok, X — all STUBS pending external API approvals), engagement poller (every 6h), attribution loop (cron 02:00), comment monitor (every 2h), comment response (Claude reply or escalate). |
| `workflows/api/archetype-seeds/` | 6 | Multi-vertical seed workflows: mortgage, real_estate, logistics, beauty, dental, consulting. INTERNAL_EMAIL_SECRET / MARY_MASTER_TOKEN auth. Idempotent (`UNIQUE(niche_name, archetype_name)` + `resolution=ignore-duplicates`). Reuses existing `signal_archetypes` table. |
| `workflows/api/supervisor/` | 1 | `clx-supervisor-overview-v1` — universal supervisor dashboard. Reads `team_members.reports_to_user_id` hierarchy + open lead counts + `user_goals` achievement + flags (no_open_leads / low_goal_achievement / inactive). |
| `workflows/api/rebook/` | 2 | `clx-no-show-multi-attempt-v1` (cron 09:00) — Day 1 SMS → Day 3 WhatsApp → Day 7 Email → Day 14 Video → cold. `clx-cold-lead-mark-v1` — marks lead status='cold', sets do_not_contact_automated=true, audit-logs the cool-down. |
| `workflows/api/briefing/` | 3 | Generator (cron every 30m), fetch (session-scoped), effectiveness (post-meeting rating feeds learning loop). |
| `workflows/api/training/` | 3 | Coach chat (Claude Sonnet, session-history-aware, derives competency_score from `[SCORE: N]` line), topic list (filtered by vertical_id + completion status), progress tracker (per-category competency + remediation flags + next suggestions). |
| `workflows/api/completeness/` | 3 | Calculate (per-file, applies rule precedence), rules-update (admin/principal/supervisor edits a rule), bulk-refresh (cron 03:00 stub — per-file_type recalc loops live in domain workflows). |

### Frontend pages (7 new, plain HTML+JS, no framework)

| Path | Purpose |
|---|---|
| `client-dashboard/pages/training-coach.html` | Universal training chat — topic picker + AI coach conversation. |
| `client-dashboard/pages/training-progress.html` | Per-category competency + remediation + next topics. |
| `admin-dashboard/pages/training-topics.html` | Admin view of all topics (universal + per-vertical). |
| `client-dashboard/pages/content-calendar.html` | Content calendar (Phase 4 — placeholder until platform API approvals complete). |
| `client-dashboard/pages/content-preferences.html` | Brand voice + vertical + posting cadence + platforms (saves to localStorage until backend endpoint lands). |
| `client-dashboard/pages/content-engagement.html` | Comments + engagement (placeholder until engagement poller activates). |
| `admin-dashboard/pages/content-library.html` + `content-performance.html` | Admin content overview + platform attribution. |

## Layer 1 purity audit

- ✅ Zero `vertical_id` columns on Layer 1 tables (except nullable universal-with-filter on `training_topics` + `file_completeness_rules`).
- ✅ Zero insurance / mga / advisor terminology in Layer 1 workflow names or business logic.
- ✅ All Layer 1 webhooks at `/webhook/api/...` or `/webhook/<universal-name>` (no `/mga/insurance/`).
- ✅ Workflow folders categorized: `content/`, `archetype-seeds/`, `supervisor/`, `rebook/`, `briefing/`, `training/`, `completeness/`.
- ✅ `mga_principal` appears only in role allowlists (it's an existing universal role enum value, not business logic).

## Mary's deployment steps

See `docs/audit/blockers.md` sections 17-21:

1. Apply 3 new schemas in any order (independent).
2. Re-import 32 new workflows.
3. Optionally seed non-insurance verticals (`POST /webhook/api/seed-archetypes-mortgage` etc with MARY_MASTER_TOKEN).
4. Activate scheduled workflows when ready: topic-generator (06:00), engagement-poller (every 6h), attribution-loop (02:00), comment-monitor (every 2h), briefing-generator (every 30m), no-show-multi-attempt (09:00), file-completeness-bulk-refresh (03:00).
5. Apply for external platform APIs in parallel (LinkedIn Developer, Meta for Developers, YouTube Data, TikTok Business, X Developer). Each publisher workflow is a stub that responds 202 + logs a `content_publications` row until those approvals complete.

## Roadmap (deferred)

- **Content publisher API integrations** — STUB → real implementation per platform once developer apps approved.
- **Engagement poller real metrics** — STUB. Each platform's metrics endpoint differs (LinkedIn `/socialActivity`, Meta Graph `/insights`, YouTube `statistics`, TikTok `business/video/list`, X `public_metrics`).
- **Attribution loop precision** — currently coarse per-platform count. Future version joins `content_publications.external_post_id` to `leads.source_referrer` with recency weighting.
- **File completeness bulk-refresh** — heartbeat only. Per-file_type recalc loops belong in domain workflows (e.g. `clx-insurance-application-completeness-refresh-v1`).
- **Pluggable metric aggregators for goals** — see `KPI_GOALS_FRAMEWORK.md` roadmap.
