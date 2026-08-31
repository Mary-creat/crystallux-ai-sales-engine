#!/usr/bin/env node
/**
 * Tests for the two reasoning capabilities added to clx-mcp-agent-tools-v1:
 * assess_why_now and next_best_action.
 *
 * Both run against the jsCode actually shipped in the workflow, not a copy,
 * so a change to the deployed logic that breaks a guarantee fails here.
 *
 * The property under test is narrow and it is the one that matters: a
 * failure in our own pipeline must never come back as evidence about the
 * prospect. The signal table currently holds 284 rows that were exactly
 * that before it was fixed -- provider errors stored as detected signals --
 * so this is a regression guard for a bug that really happened.
 *
 * Run: node tests/agent/why-now-nba.test.js
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

const TENANT = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';

function run(nodeName, lead) {
  const src = nodeByName(nodeName).parameters.jsCode;
  const items = lead === null ? [] : [{ json: lead }];
  const sandbox = {
    $input: { all: () => items },
    $: (name) => {
      if (name === 'Parse Request') {
        return { item: { json: { correlation_id: 'corr-test-1', client_id: TENANT,
                                 tool_input: { lead_id: 'lead-1' } } } };
      }
      throw new Error('unexpected node ref: ' + name);
    },
    console: console
  };
  const out = vm.runInNewContext('(function(){' + src + '})()', sandbox, { timeout: 5000 });
  return out[0].json.result;
}

const whyNow = (lead) => run('Classify Why Now', lead);
const nba = (lead) => run('Decide Next Best Action', lead);

let pass = 0, fail = 0;
function t(id, name, fn) {
  try {
    fn();
    console.log('  PASS  ' + id + '  ' + name);
    pass++;
  } catch (e) {
    console.log('  FAIL  ' + id + '  ' + name + '\n        ' + e.message);
    fail++;
  }
}
function eq(a, b, m) {
  if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) +
                               ', got ' + JSON.stringify(a));
}
function ok(v, m) { if (!v) throw new Error(m || 'expected truthy'); }

const base = {
  id: 'lead-1', client_id: TENANT, lead_status: 'Scored', lead_score: 72,
  research_summary: 'Mid-size GTA contractor, 30 staff, commercial fit-outs.',
  updated_at: new Date().toISOString()
};

console.log('\nWHY NOW\n');

t('W1', 'a provider failure is UNKNOWN_ERROR, never a signal', () => {
  const r = whyNow(Object.assign({}, base, {
    detected_signal: 'Request failed with status code 500',
    signal_confidence: 'Unavailable'
  }));
  eq(r.why_now, 'UNKNOWN_ERROR');
  eq(r.safe_to_treat_as_intent, false);
});

t('W2', 'an error carries no urgency at all', () => {
  const r = whyNow(Object.assign({}, base, { signal_confidence: 'Unavailable' }));
  eq(r.urgency, null, 'urgency');
  ok(!r.signal, 'must not surface a signal field');
});

t('W3', 'no signal is NO_VERIFIED_SIGNAL, distinct from an error', () => {
  const r = whyNow(Object.assign({}, base, { detected_signal: null, signal_confidence: null }));
  eq(r.why_now, 'NO_VERIFIED_SIGNAL');
  eq(r.urgency, 'none');
  eq(r.safe_to_treat_as_intent, false);
});

t('W4', 'a High-confidence recent signal verifies', () => {
  const r = whyNow(Object.assign({}, base, {
    detected_signal: 'Posted 3 site-supervisor roles', signal_confidence: 'High'
  }));
  eq(r.why_now, 'VERIFIED_SIGNAL');
  eq(r.urgency, 'high');
  eq(r.safe_to_treat_as_intent, true);
  ok(r.evidence, 'evidence must be present');
});

t('W5', 'Low confidence does not count as verified', () => {
  const r = whyNow(Object.assign({}, base, {
    detected_signal: 'Maybe expanding', signal_confidence: 'Low'
  }));
  eq(r.why_now, 'NO_VERIFIED_SIGNAL');
  eq(r.safe_to_treat_as_intent, false);
});

t('W6', 'an old verified signal loses urgency but stays verified', () => {
  const old = new Date(Date.now() - 200 * 86400000).toISOString();
  const r = whyNow(Object.assign({}, base, {
    detected_signal: 'Won a municipal contract', signal_confidence: 'High', updated_at: old
  }));
  eq(r.why_now, 'VERIFIED_SIGNAL');
  eq(r.recency, 'stale');
  eq(r.urgency, 'low');
});

t('W7', 'observed_at is labelled a proxy rather than claimed as fact', () => {
  const r = whyNow(Object.assign({}, base, {
    detected_signal: 'Hiring', signal_confidence: 'Medium'
  }));
  eq(r.observed_at_is_proxy, true);
});

t('W8', 'a lead outside the tenant is an error, not an absence of signal', () => {
  const r = whyNow(null);
  eq(r.why_now, 'UNKNOWN_ERROR');
  eq(r.reason, 'lead_not_found_for_tenant');
});

t('W9', 'correlation id is carried through for tracing', () => {
  const r = whyNow(base);
  eq(r.correlation_id, 'corr-test-1');
});

console.log('\nNEXT BEST ACTION\n');

t('N1', 'unsubscribed always stops, whatever else is true', () => {
  const r = nba(Object.assign({}, base, {
    unsubscribed: true, lead_score: 99,
    detected_signal: 'Actively buying', signal_confidence: 'High'
  }));
  eq(r.action, 'stop');
  eq(r.approval_required, false);
  eq(r.risk_class, 'READ');
});

t('N2', 'no research means research, never contact', () => {
  const r = nba(Object.assign({}, base, { research_summary: null }));
  eq(r.action, 'research');
  eq(r.risk_class, 'READ');
});

t('N3', 'a signal error asks for information, not outreach', () => {
  const r = nba(Object.assign({}, base, { signal_confidence: 'Unavailable' }));
  eq(r.action, 'collect_information');
  eq(r.approval_required, false);
});

t('N4', 'verified signal + research + score recommends contact', () => {
  const r = nba(Object.assign({}, base, {
    detected_signal: 'Hiring supervisors', signal_confidence: 'High'
  }));
  eq(r.action, 'contact');
  eq(r.urgency, 'high');
});

t('N5', 'any contact is CONTACT_HUMAN and needs approval', () => {
  const r = nba(Object.assign({}, base, {
    detected_signal: 'Hiring', signal_confidence: 'High'
  }));
  eq(r.risk_class, 'CONTACT_HUMAN');
  eq(r.approval_required, true);
});

t('N6', 'already contacted becomes follow_up, still gated', () => {
  const r = nba(Object.assign({}, base, {
    last_email_sent_at: new Date().toISOString()
  }));
  eq(r.action, 'follow_up');
  eq(r.risk_class, 'CONTACT_HUMAN');
  eq(r.approval_required, true);
});

t('N7', 'a weak lead waits rather than being contacted', () => {
  const r = nba(Object.assign({}, base, { lead_score: 20 }));
  eq(r.action, 'wait');
  eq(r.risk_class, 'READ');
});

t('N8', 'strong fit with no signal contacts without claiming urgency', () => {
  const r = nba(Object.assign({}, base, { lead_score: 80 }));
  eq(r.action, 'contact');
  eq(r.urgency, 'low');
});

t('N9', 'every recommendation cites evidence', () => {
  const r = nba(base);
  ok(Array.isArray(r.evidence) && r.evidence.length > 0, 'evidence must be non-empty');
});

t('N10', 'approval_required is advisory, deferring to the policy gate', () => {
  const r = nba(Object.assign({}, base, {
    detected_signal: 'Hiring', signal_confidence: 'High'
  }));
  ok(/policy gate decides/i.test(r.autonomy_note), 'must defer to the gate');
});

console.log('\nCAPABILITY REGISTRATION\n');

t('C1', 'both capabilities carry a risk class in the allow-list', () => {
  const src = nodeByName('Parse Request').parameters.jsCode;
  ok(/assess_why_now\s*:\s*'READ'/.test(src), 'why_now must be READ');
  ok(/next_best_action\s*:\s*'REASONING'/.test(src), 'nba must be REASONING');
});

t('C2', 'both map to a product, or MCP refuses them', () => {
  const src = nodeByName('Parse Request').parameters.jsCode;
  ok(/assess_why_now:\s*'sales_engine'/.test(src), 'why_now product');
  ok(/next_best_action:\s*'sales_engine'/.test(src), 'nba product');
});

t('C3', 'neither is routed to a sender', () => {
  const c = wf.connections;
  ['Tool: Why Now Fetch', 'Tool: NBA Fetch'].forEach((n) => {
    const outs = (c[n].main[0] || []).map(x => x.node);
    outs.forEach((o) => {
      if (/Voice|WhatsApp|SMS|Email|Book/.test(o)) {
        throw new Error(n + ' reaches a sender: ' + o);
      }
    });
  });
});

t('C4', 'both fetch scoped by client_id, so tenants cannot read each other', () => {
  ['Tool: Why Now Fetch', 'Tool: NBA Fetch'].forEach((n) => {
    const url = nodeByName(n).parameters.url;
    ok(/client_id=eq\./.test(url), n + ' must scope by client_id');
  });
});

console.log('\n' + pass + ' passed, ' + fail + ' failed\n');
process.exit(fail ? 1 : 0);
