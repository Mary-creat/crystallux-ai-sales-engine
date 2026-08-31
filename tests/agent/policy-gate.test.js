#!/usr/bin/env node
/**
 * Tests for the fail-closed policy gate in clx-agent-action-executor-v1.
 *
 * The gate is a Code node, so the test extracts the actual jsCode from the
 * workflow JSON and runs it against synthetic inputs with n8n's $() and
 * $input stubbed. That way the test exercises what ships, not a copy that
 * can drift away from it.
 *
 * No network, no database, no n8n. Run:  node tests/agent/policy-gate.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WF = path.join(__dirname, '..', '..', 'workflows', 'api', 'agent',
                     'clx-agent-action-executor-v1.json');

function gateSource() {
  const wf = JSON.parse(fs.readFileSync(WF, 'utf8'));
  const node = wf.nodes.find(n => n.name === 'Policy Gate');
  if (!node) throw new Error('Policy Gate node not found in the workflow');
  return node.parameters.jsCode;
}

const SRC = gateSource();
const TENANT = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';
const OTHER_TENANT = '11111111-2222-3333-4444-555555555555';

/** Run the real gate code with stubbed n8n globals. */
function runGate(ctx, policyRow) {
  const sandbox = {
    $: name => {
      if (name === 'Carry Action ID') return { item: { json: ctx } };
      throw new Error('unexpected $() for ' + name);
    },
    $input: { item: { json: policyRow === null ? [] : policyRow } },
    Date, JSON, Array, Object, String, Boolean, console
  };
  const wrapped = '(function(){' + SRC + '})()';
  return vm.runInNewContext(wrapped, sandbox, { timeout: 2000 }).json;
}

const basePolicy = {
  id: 'p1',
  client_id: TENANT,
  prohibited_topics: ['refund_payment'],
  escalation_rules: {
    autonomy_level: 'recommend_only',
    require_human_approval: ['email', 'sms', 'whatsapp', 'voice', 'create_order', 'update_lead_status'],
    auto_allowed: ['research_lead', 'score_lead', 'get_vertical_context', 'log_decision', 'draft_outreach', 'draft_quote']
  }
};

const ctxFor = (action_type, extra) =>
  Object.assign({ decision_id: 'd1', agent_action_id: 'a1', client_id: TENANT, action_type }, extra || {});

let pass = 0, fail = 0;
function check(label, cond, detail) {
  if (cond) { pass++; console.log('  PASS  ' + label); }
  else { fail++; console.log('  FAIL  ' + label + (detail ? '  -> ' + JSON.stringify(detail) : '')); }
}

console.log('Policy gate — fail-closed behaviour\n');

// A. READ under recommend_only executes
let r = runGate(ctxFor('research_lead'), basePolicy);
check('A  READ + recommend_only executes', r._allowed === true && r.policy_result.risk_class === 'READ', r.policy_result);

r = runGate(ctxFor('get_vertical_context'), basePolicy);
check('A2 READ get_vertical_context executes', r._allowed === true, r.policy_result);

// REASONING executes
r = runGate(ctxFor('recommend'), basePolicy);
check('A3 REASONING executes', r._allowed === true && r.policy_result.risk_class === 'REASONING', r.policy_result);

// B. Draft preparation is permitted
r = runGate(ctxFor('draft_outreach'), basePolicy);
check('B  outreach draft is produced', r._allowed === true && r.policy_result.risk_class === 'WRITE_INTERNAL', r.policy_result);

r = runGate(ctxFor('draft_quote'), basePolicy);
check('B2 quote draft is produced', r._allowed === true, r.policy_result);

// C-E. Sensitive actions blocked without approval
[['email', 'CONTACT_HUMAN'], ['sms', 'CONTACT_HUMAN'], ['whatsapp', 'CONTACT_HUMAN'],
 ['voice', 'CONTACT_HUMAN'], ['publish_social', 'CONTACT_HUMAN'],
 ['charge_payment', 'FINANCIAL'], ['capture_payment', 'FINANCIAL'],
 ['refund_payment', 'FINANCIAL'], ['finalize_auction', 'FINANCIAL'],
 ['cancel_order', 'DESTRUCTIVE'], ['adjust_inventory', 'DESTRUCTIVE'],
 ['delete_record', 'DESTRUCTIVE'],
 ['finalize_policy', 'REGULATED'], ['bind_coverage', 'REGULATED'],
 ['book', 'CONTACT_HUMAN'], ['book_meeting', 'CONTACT_HUMAN']
].forEach(([action, expected]) => {
  const g = runGate(ctxFor(action), basePolicy);
  check('C/D/E  ' + action + ' blocked without approval (' + expected + ')',
        g._allowed === false && g._status !== 'executing', g.policy_result);
});

// F. A valid approval is still refused under recommend_only, and the reason
//    says so -- the autonomy ceiling is not something an approver can lift.
const approval = { approval_id: 'ap1', approved_by: 'mary@crystallux.org',
                   approved_at: new Date().toISOString(), client_id: TENANT, action_type: 'email' };
r = runGate(ctxFor('email', { approval }), basePolicy);
check('F  approved CONTACT_HUMAN still blocked under recommend_only',
      r._allowed === false && r.policy_result.reason === 'autonomy_forbids', r.policy_result);

// F2. Same approval at a higher autonomy level does execute.
const supervised = JSON.parse(JSON.stringify(basePolicy));
supervised.escalation_rules.autonomy_level = 'supervised';
r = runGate(ctxFor('email', { approval }), supervised);
check('F2 approved CONTACT_HUMAN executes at supervised autonomy',
      r._allowed === true && r.policy_result.approval_state === 'valid', r.policy_result);

// F3. An incomplete approval object is not trusted.
r = runGate(ctxFor('email', { approval: { approval_id: 'ap1' } }), supervised);
check('F3 incomplete approval object rejected', r._allowed === false, r.policy_result);

// F4. An approval issued for a different action does not transfer.
r = runGate(ctxFor('charge_payment', { approval }), supervised);
check('F4 approval for another action does not transfer', r._allowed === false, r.policy_result);

// G. Unknown risk class blocked
r = runGate(ctxFor('launch_missiles'), basePolicy);
check('G  unknown action_type blocked', r._allowed === false && r.policy_result.reason === 'unknown_action_type', r.policy_result);

r = runGate(ctxFor(''), basePolicy);
check('G2 empty action_type blocked', r._allowed === false, r.policy_result);

// H. Missing policy metadata blocked
r = runGate(ctxFor('research_lead'), null);
check('H  missing personality blocks even a READ', r._allowed === false && r.policy_result.reason === 'missing_policy', r.policy_result);

const noAutonomy = { id: 'p2', client_id: TENANT, escalation_rules: {} };
r = runGate(ctxFor('research_lead'), noAutonomy);
check('H2 missing autonomy_level blocked', r._allowed === false && r.policy_result.reason === 'missing_autonomy_level', r.policy_result);

// I. Tenant mismatch blocked regardless of approval
const crossApproval = Object.assign({}, approval, { client_id: OTHER_TENANT, action_type: 'research_lead' });
r = runGate(ctxFor('research_lead', { client_id: OTHER_TENANT, approval: crossApproval }), basePolicy);
check('I  tenant mismatch blocked even with an approval', r._allowed === false && r.policy_result.reason === 'tenant_mismatch', r.policy_result);

r = runGate(ctxFor('research_lead', { client_id: null }), basePolicy);
check('I2 missing client_id blocked', r._allowed === false, r.policy_result);

// Explicit prohibition wins over everything
const supervisedRefund = JSON.parse(JSON.stringify(supervised));
const refundApproval = Object.assign({}, approval, { action_type: 'refund_payment' });
r = runGate(ctxFor('refund_payment', { approval: refundApproval }), supervisedRefund);
check('J  prohibited_topics wins over a valid approval',
      r._allowed === false && r.policy_result.reason === 'prohibited_action', r.policy_result);

// WRITE_INTERNAL not in auto_allowed is refused
r = runGate(ctxFor('update_lead_status'), basePolicy);
check('K  WRITE_INTERNAL outside auto_allowed blocked', r._allowed === false, r.policy_result);

// Audit completeness on a denial
r = runGate(ctxFor('email'), basePolicy);
const pr = r.policy_result || {};
check('L  denial audit carries risk, autonomy, approval state, correlation id',
      pr.risk_class && pr.autonomy_level && pr.approval_state && pr.correlation_id && pr.evaluated_at, pr);

// No secrets in the emitted payload
const blob = JSON.stringify(r);
check('M  no secret-looking values in the audit payload',
      !/api[_-]?key|secret|password|bearer /i.test(blob));

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail === 0 ? 0 : 1);
