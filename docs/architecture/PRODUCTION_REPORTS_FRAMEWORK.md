# Production Reports Framework (Layer 1 — universal)

> Universal report definitions + per-recipient generated reports.
> Templates can be universal (vertical_id NULL) or vertical-specific.
> Vertical-specific report generators (insurance, mortgage, etc.) live
> in their own folders and call this framework as the storage layer.

## Why

Insurers and clients both need "production reports": time-bounded views
of activity (premiums written, units sold, conversion rates, etc.).
The shape — recipient + period + content — is universal; only the
contents differ by vertical. This framework owns the shape; verticals
own the contents.

## Tables (db/migrations/production-reports-schema.sql)

| Table | Purpose |
|---|---|
| `production_report_templates` | Definition of a report (name, type, recipient role, metrics_included jsonb, schedule_pattern, delivery_methods). `vertical_id` is NULLABLE (NULL = universal). |
| `production_reports` | Generated instance per recipient per period. `report_data` jsonb holds the rendered content. Soft FK `recipient_account_id` + `recipient_account_type` route the report to non-user recipients (e.g. an `insurer_account`). |

## Workflows (workflows/api/reports/)

| Workflow | Webhook | Trigger |
|---|---|---|
| `clx-production-report-generate-v1` | POST `/webhook/api/reports/generate` | Fetches template, builds skeleton `report_data`, inserts row. Vertical-specific workflows can fetch the row + enrich `report_data` in a follow-up step. |
| `clx-production-report-fetch-v1` | POST `/webhook/api/reports/fetch` | Recipient retrieves their own report; marks viewed_at. |
| `clx-production-report-schedule-v1` | Cron 02:00 daily + manual webhook | Detects which schedule_patterns are due today (monthly=1st, quarterly=Jan/Apr/Jul/Oct 1st, annual=Jan 1st), counts matching templates. Per-template fan-out lives in vertical-specific schedulers (eg `clx-mga-insurance-report-monthly-production-v1`). |

All workflows `active: false`. Universal — no insurance/mga/advisor terms.

## Layer 2 contract

Vertical-specific schedulers (e.g. insurance's monthly production
generator) follow this pattern:

1. Cron on their own schedule.
2. Resolve the right recipient list (e.g. all insurer_accounts with active partner status).
3. For each recipient, POST `/webhook/api/reports/generate` with `template_id` + `recipient_id` + `recipient_account_id` + period dates.
4. Receive `report_id` back.
5. Optionally enrich the row via PATCH (vertical-specific data fill).

This keeps the Layer 1 framework lean while letting verticals own
their data shapes + privacy filters.

## Roadmap

- Async delivery channels: email + Slack/Teams + S3/R2 export.
- PDF rendering: report_data → PDF via Puppeteer side-car.
- Drift detection: alert when a recipient's report deviates ≥ X% from the prior period.
- Insurer dashboard pulls reports via `clx-production-report-fetch-v1` filtered to their `recipient_account_id`.
