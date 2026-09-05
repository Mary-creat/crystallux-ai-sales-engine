#!/usr/bin/env node
/**
 * Tests for the owner arming switch, against the jsCode actually shipped in
 * all four prospect-facing send paths.
 *
 * The switch exists because "outbound is off" had been resting on n8n's
 * `active` flag: unreadable from the build machine, and not what the repo
 * says — 1 of 326 files carries active:true while three others were observed
 * running in production. A safety claim nobody can read is not a control.
 *
 * The property under test is one sentence: **nothing but an explicit, live
 * `true` may permit a send.** Every other outcome — a missing node, an empty
 * response, a string, a null, an error object, a thrown exception — must
 * refuse. A kill switch that fails open is worse than no kill switch, because
 * it is trusted.
 *
 * Run: node tests/agent/outbound-arming.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..', '..');
const GATE = 'Check Outbound Arming';

// Every send path that can reach a prospect, and the node in each that makes
// the decision. If a path is added and not listed here, PATHS-05 fails.
const PATHS = [
  ['workflows/clx-outreach-sender-v2.json', 'Sender Eligibility Guard'],
  ['workflows/clx-follow-up-v2.json', 'Build Follow Up Email'],
  ['workflows/clx-booking-v2.json', 'Build Booking Email'],
  ['workflows/api/agent/clx-agent-action-executor-v1.json', 'Policy Gate']
];

function wf(rel) {
  return JSON.parse(fs.readFileSync(path.join(ROOT, rel), 'utf8'));
}

function nodeByName(d, n) {
  const x = d.nodes.find(k => k.name === n);
  if (!x) throw new Error('node not found: ' + n);
  return x;
}

// Pull the shipped outboundArmed() out of a node and run it against a given
// gate response. Nothing is reimplemented here — if the deployed helper
// changes, these tests exercise the change.
function armedWith(rel, nodeName, gateItems) {
  const src = nodeByName(wf(rel), nodeName).parameters.jsCode;
  const start = src.indexOf('function outboundArmed()');
  if (start < 0) throw new Error('no outboundArmed() in ' + nodeName);
  let depth = 0, i = src.indexOf('{', start), end = -1;
  for (let j = i; j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') { depth--; if (depth === 0) { end = j + 1; break; } }
  }
  const fn = src.slice(start, end);
  const sandbox = {
    $: (name) => {
      if (name !== GATE) throw new Error('unexpected node ref: ' + name);
      if (gateItems === 'THROW') throw new Error('node did not execute');
      return { all: () => gateItems.map(j => ({ json: j })) };
    },
    console: { log: () => {} }
  };
  return vm.runInNewContext('(function(){' + fn + '\nreturn outboundArmed();})()',
                            sandbox, { timeout: 5000 });
}

let pass = 0, fail = 0;
function t(id, name, fn) {
  try { fn(); console.log('  PASS  ' + id + '  ' + name); pass++; }
  catch (e) { console.log('  FAIL  ' + id + '  ' + name + '\n        ' + e.message); fail++; }
}
function eq(a, b, m) {
  if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) +
                               ', got ' + JSON.stringify(a));
}

console.log('\nOutbound arming switch\n');

// The only thing that permits.
PATHS.forEach(function (p) {
  const label = path.basename(p[0], '.json');
  t('ARM-01 ' + label, 'a live true arms this path', () => {
    eq(armedWith(p[0], p[1], [true]), true);
  });
});

// Everything else refuses. Run against the sender; the helper is identical
// in all four and ARM-06 proves that.
const S = PATHS[0];
const REFUSALS = [
  ['explicit false', [false]],
  ['PostgREST object wrapper, false', [{ outbound_is_armed: false }]],
  ['no rows at all', []],
  ['null', [null]],
  ['the string "true"', ['true']],
  ['the number 1', [1]],
  ['an empty object', [{}]],
  ['a PostgREST error body', [{ code: '42883', message: 'function does not exist' }]],
  ['an unrelated object', [{ armed: true }]],
  ['the node never ran', 'THROW']
];
REFUSALS.forEach(function (r, i) {
  t('ARM-' + String(2 + i).padStart(2, '0'), 'refuses: ' + r[0], () => {
    eq(armedWith(S[0], S[1], r[1]), false);
  });
});

t('ARM-12', 'the object wrapper arms only on a real boolean true', () => {
  eq(armedWith(S[0], S[1], [{ outbound_is_armed: true }]), true);
  eq(armedWith(S[0], S[1], [{ outbound_is_armed: 'true' }]), false);
});

t('ARM-13', 'a single-item array wrapper is unwrapped', () => {
  eq(armedWith(S[0], S[1], [[true]]), true);
  eq(armedWith(S[0], S[1], [[false]]), false);
});

// Structural guarantees.
t('ARM-14', 'every send path carries the gate node', () => {
  PATHS.forEach(function (p) {
    const names = wf(p[0]).nodes.map(n => n.name);
    if (names.indexOf(GATE) < 0) {
      throw new Error(p[0] + ' has no ' + GATE + ' node');
    }
  });
});

t('ARM-15', 'the gate asks about its own workflow, not another', () => {
  PATHS.forEach(function (p) {
    const d = wf(p[0]);
    const body = JSON.parse(nodeByName(d, GATE).parameters.jsonBody);
    eq(body.p_workflow_id, d.id, p[0] + ' gate id mismatch:');
  });
});

t('ARM-16', 'the gate cannot abort the run and skip the check', () => {
  // onError must let the flow continue, otherwise a Supabase blip aborts the
  // execution before the decision node runs -- which is safe by accident
  // today and unsafe the moment someone adds a retry.
  PATHS.forEach(function (p) {
    const n = nodeByName(wf(p[0]), GATE);
    eq(n.alwaysOutputData, true, p[0] + ' gate must alwaysOutputData:');
    eq(n.onError, 'continueRegularOutput', p[0] + ' gate onError:');
  });
});

t('ARM-17', 'the decision node checks the switch before anything else', () => {
  PATHS.forEach(function (p) {
    const src = nodeByName(wf(p[0]), p[1]).parameters.jsCode;
    const check = src.indexOf('if (!outboundArmed())');
    if (check < 0) throw new Error(p[0] + ' never calls outboundArmed()');
    // Nothing that sends may appear before the refusal.
    const head = src.slice(0, check);
    ['gmail', 'messages/send', 'api.twilio', 'api.vapi'].forEach(function (bad) {
      if (head.toLowerCase().indexOf(bad) >= 0) {
        throw new Error(p[0] + ' references ' + bad + ' before the check');
      }
    });
  });
});

t('ARM-18', 'transactional mail is NOT under the switch', () => {
  // Disarming outbound must never lock a customer out of their own account.
  ['workflows/api/email/clx-email-send.json',
   'workflows/api/auth/clx-auth-magic-link.json',
   'workflows/api/auth/clx-auth-password-reset-request.json'].forEach(function (f) {
    const names = wf(f).nodes.map(n => n.name);
    if (names.indexOf(GATE) >= 0) {
      throw new Error(f + ' is transactional and must not be gated');
    }
  });
});

console.log('\n  ' + pass + ' passed, ' + fail + ' failed\n');
process.exit(fail ? 1 : 0);
