# Supabase Row Level Security (RLS) Setup Guide

How to enable RLS on Crystallux Supabase tables to restrict data access.

---

## Why RLS Is Critical

Without RLS, anyone with your Supabase **anon key** (which is public in frontend apps) can read, modify, or delete all lead data. RLS ensures only the service role key (used by n8n) can access data.

---

## Step 1 — Enable RLS on the Leads Table

Run in Supabase SQL Editor:

```sql
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
```

This immediately blocks ALL access except for the service role.

---

## Step 2 — Create Service Role Policy for Leads

Allow the service role (used by n8n) full access:

```sql
CREATE POLICY "Service role full access on leads"
  ON leads
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
```

---

## Step 3 — Enable RLS on Pipeline Stats

```sql
ALTER TABLE pipeline_stats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on pipeline_stats"
  ON pipeline_stats
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
```

---

## Step 4 — Enable RLS on MCP Tool Calls

```sql
ALTER TABLE mcp_tool_calls ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on mcp_tool_calls"
  ON mcp_tool_calls
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
```

---

## Step 5 — Verify RLS Is Active

```sql
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('leads', 'pipeline_stats', 'mcp_tool_calls');
```

All three should show `rowsecurity = true`.

---

## Future: Multi-Tenant Policies

When you add client accounts, create tenant-scoped policies:

```sql
-- Example: clients can only see their own leads
CREATE POLICY "Clients see own leads"
  ON leads
  FOR SELECT
  USING (assigned_to = auth.uid()::text);
```

---

## Important Notes

- n8n uses the **service role key** which bypasses RLS — this is correct
- The **anon key** is blocked by RLS — this protects against public access
- Always test after enabling: run a workflow to confirm n8n still works
- If workflows break after enabling RLS, verify n8n is using the service role key (not the anon key)
