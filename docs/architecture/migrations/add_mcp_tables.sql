-- Crystallux Phase 12: MCP Tool Gateway Tables
-- Run this in Supabase SQL Editor before activating clx-mcp-tool-gateway workflow

-- Create mcp_tool_calls table for logging all AI agent tool calls
CREATE TABLE IF NOT EXISTS mcp_tool_calls (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tool_name           TEXT NOT NULL,
  tool_input          JSONB,
  tool_output         JSONB,
  success             BOOLEAN,
  execution_time_ms   INTEGER,
  called_at           TIMESTAMPTZ DEFAULT now(),
  called_by           TEXT DEFAULT 'ai_agent'
);

-- Index for querying tool call history
CREATE INDEX IF NOT EXISTS idx_mcp_tool_calls_name ON mcp_tool_calls (tool_name);
CREATE INDEX IF NOT EXISTS idx_mcp_tool_calls_date ON mcp_tool_calls (called_at DESC);
CREATE INDEX IF NOT EXISTS idx_mcp_tool_calls_success ON mcp_tool_calls (success) WHERE success = false;

-- Verify table exists
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'mcp_tool_calls'
ORDER BY ordinal_position;
