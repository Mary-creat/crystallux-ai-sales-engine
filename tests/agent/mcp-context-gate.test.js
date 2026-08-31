#!/usr/bin/env node
/**
 * Tests for the MCP context pre-gate in clx-mcp-agent-tools-v1.
 *
 * Division of responsibility, and the tests reflect it:
 *   this node   -> AUTHORIZATION: who is asking, for which tenant, with
 *                  what entitlement, and does the capability have a
 *                  declared risk class
 *   Policy Gate -> APPROVAL: autonomy level, approval object, tenant match
 *
 * MCP does not decide approval. It refuses to execute sensitive tools at
 * all, handing them to agent/action-execute instead, so there is exactly
 * one place where approval is decided. These tests prove the handover
 * happens and that nothing sensitive resolves to a direct sender.
 *
 * Run: node tests/agent/mcp-context-gate.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WF = path.join(__dirname, '..', '..', 'workflows', 'api', 'mcp',
                     'clx-mcp-agent-tools-v1.json');
const wf = JSON.parse(fs.readFileSync(WF, 'utf8'));

function nodeByName(n) {
  const x = wf.nodes.find(k => k.name === n);
  if (!x) throw new Error('node not found: ' + n);
  return x;
}

const SRC = nodeByName('Parse Request').parameters.jsCode;
const TENANT = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';
const SECRET = 'test-internal-secret';

function runParse(body, env) {
  const sandbox = {
    $input: { item: { json: { body } } },
    $env: Object.assign({ INTERNAL_EMAIL_SECRET: SECRET }, env || {}),
    Date, JSON, Array, Object, String, Boolean, console
  };
  return vm.runInNewContext('(function(){' + SRC + '})()', sandbox, { timeout: 2000 }).json;
}

const req = (tool, input, extra) => Object.assign({
  internal_secret: SECRET,
  tool_name: tool,
  tool_input: Object.assign({ client_id: TENANT }, input || {}),
  agent_id: 'agent-1',
  correlation_id: 'corr-1'
}, extra || {});

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + label); }
  else { fail++; console.log('  FAIL  ' + label + (detail ? '  -> ' + JSON.stringify(detail) : '')); }
};

console.log('MCP context pre-gate — fail-closed authorization\n');

// 1. READ with tenant + agent + entitlement is allowed through
let r = runParse(req('retrieve_lead_memory', { lead_id: 'l1' }));
check('1  READ with full context allowed', r.valid === true && r.risk_class === 'READ', r);

// 2-5. Sensitive tools are never executed by MCP; they are handed over.
['send_email', 'send_sms', 'send_whatsapp', 'place_outbound_call', 'book_meeting'].forEach(t => {
  const g = runParse(req(t, { message: 'hi' }));
  check('2-5  ' + t + ' handed to executor, not executed by MCP',
        g.valid === true && g.via_executor === true && g.executor_action_type, g);
});

// 6. Every routed tool must physically point at the executor, not a sender.
const REROUTED = { 'Tool: Voice': 1, 'Tool: WhatsApp': 1, 'Tool: SMS': 1, 'Tool: Email': 1, 'Tool: Book': 1 };
Object.keys(REROUTED).forEach(nm => {
  const url = String(nodeByName(nm).parameters.url || '');
  check('6  ' + nm + ' targets agent/action-execute',
        url.indexOf('/webhook/agent/action-execute') !== -1, url);
});

// 6b. No MCP node may call a deterministic sender directly any more.
const BANNED = ['messaging/whatsapp-send', 'messaging/sms-send', 'email/send', 'agent/voice-outbound', 'booking/create'];
const allUrls = wf.nodes.map(n => String((n.parameters || {}).url || '')).join(' ');
BANNED.forEach(b => check('6b no direct call to ' + b, allUrls.indexOf('/webhook/' + b) === -1));

// 9. Missing tenant blocked
r = runParse({ internal_secret: SECRET, tool_name: 'send_email', tool_input: {}, agent_id: 'agent-1' });
check('9  missing client_id blocked', r.valid === false && /client_id required/.test(r.error), r);

// 9b. Missing agent identity blocked
r = runParse({ internal_secret: SECRET, tool_name: 'send_email', tool_input: { client_id: TENANT } });
check('9b missing agent_id blocked', r.valid === false && /agent_id required/.test(r.error), r);

// 11. Unknown tool blocked
r = runParse(req('exfiltrate_everything'));
check('11 unknown tool blocked', r.valid === false && /unknown tool/.test(r.error), r);

// 12. Missing risk metadata is structurally impossible: the risk table is the
//     allow-list, so an unclassified capability is an unknown tool.
r = runParse(req('some_new_capability'));
check('12 unclassified capability blocked', r.valid === false, r);

// 15. Authentication failures
r = runParse(Object.assign(req('retrieve_lead_memory'), { internal_secret: 'wrong' }));
check('15 wrong secret blocked', r.valid === false && /internal secret/.test(r.error), r);

r = runParse(req('retrieve_lead_memory'), { INTERNAL_EMAIL_SECRET: '' });
check('15b unset server secret blocks (never open)', r.valid === false, r);

// 14. Audit fields present on an allowed request
r = runParse(req('retrieve_lead_memory', { lead_id: 'l1' }));
check('14 audit context carries tenant, agent, product, risk, correlation',
      r.client_id && r.agent_id && r.product && r.risk_class && r.correlation_id, r);

// 15c. No secrets echoed back
const blob = JSON.stringify(runParse(req('send_email', { message: 'x' })));
check('15c secret not echoed into the response', blob.indexOf(SECRET) === -1);

// 13. recommend_only cannot be bypassed via MCP: MCP never executes a
//     sensitive tool itself, so the executor's autonomy ceiling always applies.
r = runParse(req('send_email', { message: 'x' }));
check('13 recommend_only unreachable via MCP (handover, no local execution)',
      r.via_executor === true && r.valid === true, r);

// The executor must have somewhere for book_meeting to land, or routing it
// would silently succeed while doing nothing.
const exe = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'workflows', 'api',
  'agent', 'clx-agent-action-executor-v1.json'), 'utf8'));
const keys = exe.nodes.find(n => n.name === 'Switch Action Type')
  .parameters.rules.values.map(v => v.outputKey);
check('X  executor routes book', keys.indexOf('book') !== -1, keys);
check('X2 executor has a Call Booking node', exe.nodes.some(n => n.name === 'Call Booking'));
check('X3 executor still gates everything through Policy Gate',
      exe.connections['Carry Action ID'].main[0][0].node === 'Fetch Agent Policy');

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
