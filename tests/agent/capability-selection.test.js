#!/usr/bin/env node
/**
 * Tests for the capability-selection stage in clx-agent-decision-engine-v1.
 *
 * This stage lets the agent go and look something up before recommending an
 * action. It runs against the jsCode actually shipped in the workflow.
 *
 * The properties worth protecting are all refusals. A model that names a
 * tool which does not exist, answers with prose, or reaches for a lead that
 * is not the one under discussion must end up making NO tool call -- never
 * a guess, and never a business decision built on a parse failure. That is
 * the same rule already enforced in scoring, signals and the final decision.
 *
 * Run: node tests/agent/capability-selection.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WF = path.join(__dirname, '..', '..', 'workflows', 'api', 'agent',
                     'clx-agent-decision-engine-v1.json');
const wf = JSON.parse(fs.readFileSync(WF, 'utf8'));
const byName = (n) => {
  const x = wf.nodes.find(k => k.name === n);
  if (!x) throw new Error('node not found: ' + n);
  return x;
};

const TENANT = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';
const LEAD = '64c151f5-33ae-440e-894e-4d096fe26448';

const CARRY = {
  client_id: TENANT,
  correlation_id: 'corr-1',
  trigger: { lead_id: LEAD, composite_score: 62, context: {} },
  personality: { vertical_context: 'construction', escalation_rules: { autonomy_level: 'recommend_only' } }
};

function parseChoice(modelText, carry) {
  const src = byName('Parse Tool Choice').parameters.jsCode;
  const sandbox = {
    $input: { item: { json: modelText === null ? {} : { content: [{ type: 'text', text: modelText }] } } },
    $: (n) => {
      if (n === 'Build Tool Prompt') return { item: { json: { _carry: carry || CARRY } } };
      throw new Error('unexpected ref ' + n);
    },
    console
  };
  return vm.runInNewContext('(function(){' + src + '})()', sandbox, { timeout: 5000 }).json;
}

function absorb(sel, mcpItems) {
  const src = byName('Absorb Tool Result').parameters.jsCode;
  const sandbox = {
    $: (n) => {
      if (n === 'Parse Tool Choice') return { item: { json: sel } };
      if (n === 'Call MCP Agent Tools') {
        if (mcpItems === undefined) throw new Error('node did not execute');
        return { all: () => mcpItems.map(j => ({ json: j })) };
      }
      throw new Error('unexpected ref ' + n);
    },
    console
  };
  return vm.runInNewContext('(function(){' + src + '})()', sandbox, { timeout: 5000 }).json;
}

let pass = 0, fail = 0;
const t = (id, name, fn) => {
  try { fn(); console.log('  PASS  ' + id + '  ' + name); pass++; }
  catch (e) { console.log('  FAIL  ' + id + '  ' + name + '\n        ' + e.message); fail++; }
};
const eq = (a, b, m) => { if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ', got ' + JSON.stringify(a)); };
const ok = (v, m) => { if (!v) throw new Error(m || 'expected truthy'); };

console.log('\nTOOL SELECTION — fail closed\n');

t('T1', 'a valid allowed tool is selected', () => {
  const r = parseChoice(JSON.stringify({
    needs_tool: true, tool: 'assess_why_now', reason: 'need timing',
    arguments: { lead_id: LEAD } }));
  eq(r.needs_tool, true);
  eq(r.tool, 'assess_why_now');
  eq(r.tool_arguments.lead_id, LEAD);
});

t('T2', 'a tool outside the allow-list is refused', () => {
  const r = parseChoice(JSON.stringify({
    needs_tool: true, tool: 'send_email', arguments: { lead_id: LEAD } }));
  eq(r.needs_tool, false);
  ok(/tool_not_allowed/.test(r.selection_error), 'must record refusal');
});

t('T3', 'an invented tool name is refused', () => {
  const r = parseChoice(JSON.stringify({
    needs_tool: true, tool: 'read_everything', arguments: {} }));
  eq(r.needs_tool, false);
  ok(/tool_not_allowed/.test(r.selection_error));
});

t('T4', 'unparseable output makes no tool call', () => {
  const r = parseChoice('I think we should probably look at the memory first.');
  eq(r.needs_tool, false);
  eq(r.selection_error, 'tool_choice_unparseable');
});

t('T5', 'an empty model response makes no tool call', () => {
  const r = parseChoice(null);
  eq(r.needs_tool, false);
  eq(r.selection_error, 'tool_selection_no_content');
});

t('T6', 'needs_tool false is a normal outcome, not an error', () => {
  const r = parseChoice(JSON.stringify({ needs_tool: false, reason: 'context sufficient' }));
  eq(r.needs_tool, false);
  eq(r.selection_error, null, 'must not be an error');
  ok(r.tool_reason, 'reason carried');
});

t('T7', 'missing tenant context refuses', () => {
  const r = parseChoice(JSON.stringify({
    needs_tool: true, tool: 'assess_why_now', arguments: { lead_id: LEAD } }),
    Object.assign({}, CARRY, { client_id: null }));
  eq(r.needs_tool, false);
  eq(r.selection_error, 'missing_tenant_context');
});

t('T8', 'reaching for a different lead is refused', () => {
  const r = parseChoice(JSON.stringify({
    needs_tool: true, tool: 'assess_why_now',
    arguments: { lead_id: '00000000-0000-0000-0000-000000000000' } }));
  eq(r.needs_tool, false);
  eq(r.selection_error, 'lead_mismatch_refused');
});

t('T9', 'arguments are rebuilt, not trusted', () => {
  const r = parseChoice(JSON.stringify({
    needs_tool: true, tool: 'next_best_action',
    arguments: { lead_id: LEAD, client_id: 'someone-else', limit: 9999 } }));
  eq(r.needs_tool, true);
  eq(Object.keys(r.tool_arguments).join(','), 'lead_id', 'only lead_id passes through');
});

console.log('\nTOOL RESULT — a failure is never a finding\n');

t('A1', 'a successful result is carried into the decision', () => {
  const sel = { _carry: CARRY, needs_tool: true, tool: 'assess_why_now', tool_reason: 'timing' };
  const r = absorb(sel, [{ success: true, data: { why_now: 'VERIFIED_SIGNAL' } }]);
  eq(r.tool_used, 'assess_why_now');
  eq(r.tool_result.why_now, 'VERIFIED_SIGNAL');
  eq(r.tool_error, null);
});

t('A2', 'a refused MCP call becomes an error, not a result', () => {
  const sel = { _carry: CARRY, needs_tool: true, tool: 'assess_why_now' };
  const r = absorb(sel, [{ success: false, error: 'internal secret required' }]);
  eq(r.tool_result, null, 'must not present a result');
  ok(/mcp_refused/.test(r.tool_error));
});

t('A3', 'no MCP response is an error, not silence', () => {
  const sel = { _carry: CARRY, needs_tool: true, tool: 'assess_why_now' };
  const r = absorb(sel, []);
  eq(r.tool_result, null);
  eq(r.tool_error, 'mcp_no_response');
});

t('A4', 'no tool selected still produces a usable decision context', () => {
  const sel = { _carry: CARRY, needs_tool: false, tool: null, selection_error: null };
  const r = absorb(sel);
  eq(r.tool_used, null);
  eq(r.tool_result, null);
  eq(r.client_id, TENANT, 'carry preserved');
});

t('A5', 'a selection error is carried forward, not dropped', () => {
  const sel = { _carry: CARRY, needs_tool: false, tool: null, selection_error: 'tool_not_allowed:send_email' };
  const r = absorb(sel);
  ok(/tool_not_allowed/.test(r.tool_error), 'must surface the refusal');
});

console.log('\nWIRING\n');

t('W1', 'the READ stage goes through canonical mcp/agent-tools', () => {
  const url = byName('Call MCP Agent Tools').parameters.url;
  ok(/mcp\/agent-tools/.test(url), 'must use the canonical gateway');
});

t('W2', 'the engine calls no provider or sender endpoint directly', () => {
  const bad = /postmark|twilio|sendgrid|vapi|whatsapp|telnyx|graph\.facebook/i;
  wf.nodes.forEach((n) => {
    const u = String((n.parameters || {}).url || '');
    if (bad.test(u)) throw new Error(n.name + ' calls a provider directly: ' + u);
  });
});

t('W3', 'no sending capability is offered at the READ stage', () => {
  const src = byName('Build Tool Prompt').parameters.jsCode;
  ['send_email', 'send_sms', 'send_whatsapp', 'book_meeting', 'place_outbound_call']
    .forEach((c) => {
      if (new RegExp("name:\\s*'" + c + "'").test(src)) {
        throw new Error('offers a sending capability: ' + c);
      }
    });
});

t('W4', 'selection failure still reaches the decision stage', () => {
  const c = wf.connections;
  const outs = c['IF Needs Tool'].main.map(br => br.map(x => x.node));
  ok(outs[1].indexOf('Absorb Tool Result') >= 0, 'false branch must continue');
});

console.log('\n' + pass + ' passed, ' + fail + ' failed\n');
process.exit(fail ? 1 : 0);
