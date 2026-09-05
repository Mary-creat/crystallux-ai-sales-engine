#!/usr/bin/env node
/**
 * One action vocabulary, asserted across every component that speaks it.
 *
 * Three vocabularies were live at once and no send could ever complete:
 *
 *   decision engine emits        send_email / phone_call / ...
 *   MCP hands over               email / voice / book
 *   Switch Action Type routes on send_email / phone_call / book
 *   the risk registry keyed on   email / voice / book
 *
 * An agent decision (send_email) missed the registry and was denied as
 * UNKNOWN -- fail-closed, but never a policy decision. An MCP handover
 * (email) classified correctly and then matched no Switch route. Both
 * halves refused for the wrong reason, which looked like safety and was
 * actually two bugs cancelling out.
 *
 * These tests fail if the vocabularies drift apart again.
 *
 * Run: node tests/agent/action-taxonomy.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const dir = path.join(__dirname, '..', '..', 'workflows', 'api', 'agent');
const EXEC = JSON.parse(fs.readFileSync(path.join(dir, 'clx-agent-action-executor-v1.json'), 'utf8'));
const ENGINE = JSON.parse(fs.readFileSync(path.join(dir, 'clx-agent-decision-engine-v1.json'), 'utf8'));
const MCP = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'workflows', 'api', 'mcp',
                                                 'clx-mcp-agent-tools-v1.json'), 'utf8'));

const node = (wf, n) => {
  const x = wf.nodes.find(k => k.name === n);
  if (!x) throw new Error('node not found: ' + n);
  return x;
};

const GATE_SRC = node(EXEC, 'Policy Gate').parameters.jsCode;
const TENANT = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';

// Pull the two maps out of the shipped gate source so the tests read what
// actually deploys rather than a restatement of it.
function gateMaps() {
  const sandbox = {};
  const alias = /var ALIAS = \{[\s\S]*?\n\};/.exec(GATE_SRC)[0];
  const risk = /var RISK = \{[\s\S]*?\n\};/.exec(GATE_SRC)[0];
  vm.runInNewContext(alias + '\n' + risk + '\nthis.A = ALIAS; this.R = RISK;', sandbox);
  return { ALIAS: sandbox.A, RISK: sandbox.R };
}

function runGate(ctx, personality) {
  // Same harness shape as policy-gate.test.js: the gate reads the policy row
  // from $input and the action context from $('Carry Action ID').
  const sandbox = {
    $: (name) => {
      if (name === 'Carry Action ID') return { item: { json: ctx } };
      // Armed on purpose: this file tests the action vocabulary, not the
      // switch. See tests/agent/outbound-arming.test.js for the off case.
      if (name === 'Check Outbound Arming') return { all: () => [{ json: true }] };
      throw new Error('unexpected $() for ' + name);
    },
    $input: { item: { json: personality } },
    Date, JSON, Array, Object, String, Boolean, console
  };
  return vm.runInNewContext('(function(){' + GATE_SRC + '})()', sandbox, { timeout: 5000 }).json;
}

let pass = 0, fail = 0;
const t = (id, name, fn) => {
  try { fn(); console.log('  PASS  ' + id + '  ' + name); pass++; }
  catch (e) { console.log('  FAIL  ' + id + '  ' + name + '\n        ' + e.message); fail++; }
};
const ok = (v, m) => { if (!v) throw new Error(m || 'expected truthy'); };
const eq = (a, b, m) => { if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ', got ' + JSON.stringify(a)); };

const { ALIAS, RISK } = gateMaps();
const canonical = (v) => (ALIAS[String(v).toLowerCase()] || String(v).toLowerCase());

console.log('\nCANONICAL VOCABULARY\n');

t('X1', 'send_email is registered and classifies CONTACT_HUMAN', () => {
  eq(RISK[canonical('send_email')], 'CONTACT_HUMAN');
});

t('X2', 'every synonym for an email send lands on one canonical action', () => {
  ['email', 'send_email', 'email_send', 'outreach_send'].forEach((v) => {
    eq(canonical(v), 'send_email', v);
  });
});

t('X3', 'every contact channel classifies CONTACT_HUMAN', () => {
  ['send_email', 'send_sms', 'send_whatsapp', 'phone_call', 'book_meeting'].forEach((a) => {
    eq(RISK[a], 'CONTACT_HUMAN', a);
  });
});

t('X4', 'MCP handover values normalise into the registry', () => {
  const src = node(MCP, 'Parse Request').parameters.jsCode;
  const m = /const ACTION_TYPE = \{[\s\S]*?\};/.exec(src)[0];
  const box = {};
  vm.runInNewContext(m + '\nthis.M = ACTION_TYPE;', box);
  Object.keys(box.M).forEach((tool) => {
    const c = canonical(box.M[tool]);
    ok(RISK.hasOwnProperty(c), 'MCP maps ' + tool + ' -> ' + box.M[tool] + ' -> ' + c + ', unregistered');
    eq(RISK[c], 'CONTACT_HUMAN', tool);
  });
});

t('X5', 'the decision engine emits only values the registry knows', () => {
  const src = node(ENGINE, 'Build Claude Prompt').parameters.jsCode;
  const schema = /"action_type":\s*([^,]+),/.exec(src)[1];
  const emitted = (schema.match(/"([a-z_]+)"/g) || []).map(s => s.replace(/"/g, ''));
  ok(emitted.length >= 5, 'schema not found');
  emitted.forEach((a) => {
    if (a === 'wait') return;            // never reaches the executor
    const c = canonical(a);
    ok(RISK.hasOwnProperty(c), 'engine emits ' + a + ' -> ' + c + ', unregistered');
  });
});

t('X6', 'every CONTACT_HUMAN action has a Switch route to execute it', () => {
  const sw = node(EXEC, 'Switch Action Type').parameters.rules.values
    .map(r => canonical(r.conditions.conditions[0].rightValue));
  Object.keys(RISK).filter(k => RISK[k] === 'CONTACT_HUMAN').forEach((a) => {
    if (a === 'publish_social') return;  // no executor branch by design
    ok(sw.indexOf(a) >= 0, a + ' classifies CONTACT_HUMAN but no Switch route executes it');
  });
});

t('X7', 'the Switch routes only on canonical values', () => {
  node(EXEC, 'Switch Action Type').parameters.rules.values.forEach((r) => {
    const v = r.conditions.conditions[0].rightValue;
    eq(canonical(v), v, 'switch route ' + v + ' is a synonym, not canonical');
  });
});

console.log('\nGATE DECISIONS\n');

const PERSONA = {
  id: 'p1',
  client_id: TENANT,
  prohibited_topics: [],
  escalation_rules: {
    autonomy_level: 'recommend_only',
    auto_allowed: ['research_lead', 'score_lead', 'send_email'],   // deliberately over-permissive
    require_human_approval: ['send_email']
  }
};

function gate(actionType, extra) {
  return runGate(Object.assign({
    action_type: actionType, client_id: TENANT,
    lead_id: '64c151f5-33ae-440e-894e-4d096fe26448',
    correlation_id: 'tax-1'
  }, extra || {}), PERSONA);
}

t('X8', 'canonical email send under recommend_only is refused', () => {
  const r = gate('send_email');
  if (!r) throw new Error('gate did not evaluate');
  eq(r.policy_result.risk_class, 'CONTACT_HUMAN');
  eq(r.policy_result.allowed, false);
  eq(r.policy_result.approval_required, true);
  eq(r.policy_result.autonomy_level, 'recommend_only');
});

t('X9', 'the MCP synonym is refused identically, not as UNKNOWN', () => {
  const r = gate('email');
  if (!r) throw new Error('gate did not evaluate');
  eq(r.policy_result.risk_class, 'CONTACT_HUMAN');
  eq(r.policy_result.allowed, false);
});

t('X10', 'auto_allowed cannot smuggle a CONTACT_HUMAN action through', () => {
  const r = gate('send_email');
  if (!r) throw new Error('gate did not evaluate');
  eq(r.policy_result.allowed, false, 'auto_allowed listed send_email and must not win');
});

t('X11', 'an unknown action is UNKNOWN and denied', () => {
  const r = gate('exfiltrate_database');
  if (!r) throw new Error('gate did not evaluate');
  eq(r.policy_result.allowed, false);
  eq(r.policy_result.risk_class, 'UNKNOWN');
});

t('X12', 'a malformed action is denied', () => {
  [null, '', '   ', 12345].forEach((v) => {
    const r = gate(v);
    if (!r) throw new Error('gate did not evaluate');
    eq(r.policy_result.allowed, false, JSON.stringify(v));
  });
});

t('X13', 'no denial routes to a provider node', () => {
  const c = EXEC.connections;
  const denied = (c['IF Policy Allows'].main[1] || []).map(x => x.node);
  denied.forEach((n) => {
    if (/^Call |Generate Video/.test(n)) throw new Error('denial reaches executor node ' + n);
  });
  ok(denied.indexOf('Record Blocked') >= 0, 'denial must be recorded');
});

console.log('\n' + pass + ' passed, ' + fail + ' failed\n');
process.exit(fail ? 1 : 0);
