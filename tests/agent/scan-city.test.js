#!/usr/bin/env node
/**
 * Tests for the scan_city tool in clx-mcp-tool-gateway, against the jsCode
 * actually shipped.
 *
 * This tool told the truth about nothing. Asked to scan a city it replied
 * "City scan queued. The CLX City Scan Discovery workflow will process
 * <industry> in <city> on next scheduled run" and wrote not one row.
 * Nothing was queued. The caller -- Mary, through the admin Copilot -- was
 * told an action had been taken that had not been taken.
 *
 * The single property under test: **it may only report success when the
 * database actually said so.** Every other outcome, including no outcome,
 * must surface as a failure. A tool that cannot fail is a tool whose
 * success carries no information.
 *
 * Run: node tests/agent/scan-city.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WF = path.join(__dirname, '..', '..', 'workflows', 'clx-mcp-tool-gateway.json');
const wf = JSON.parse(fs.readFileSync(WF, 'utf8'));

function nodeByName(n) {
  const x = wf.nodes.find(k => k.name === n);
  if (!x) throw new Error('node not found: ' + n);
  return x;
}

// rpc === 'ABSENT' means the RPC node produced no item at all.
function run(toolInput, rpc) {
  const src = nodeByName('Handle Scan City').parameters.jsCode;
  const sandbox = {
    $: (name) => {
      if (name === 'Parse Request') {
        return { item: { json: { tool_input: toolInput } } };
      }
      if (name === 'Add Discovery City') {
        if (rpc === 'THROW') throw new Error('node did not execute');
        const items = rpc === 'ABSENT' ? [] : [{ json: rpc }];
        return { all: () => items };
      }
      throw new Error('unexpected node ref: ' + name);
    },
    console: { log: () => {} }
  };
  return vm.runInNewContext('(function(){' + src + '})()', sandbox,
                            { timeout: 5000 }).json;
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

const IN = { city: 'Oakville', product_type: 'eazer_merchant' };

console.log('\nscan_city — the tool must not claim what it did not do\n');

t('SC-01', 'a real insert is reported with its real counts', () => {
  const r = run(IN, { ok: true, product_type: 'eazer_merchant', city: 'Oakville',
                      queries_added: 15, already_present: 0,
                      note: '15 queries added for eazer_merchant in Oakville.' });
  eq(r.ok, true);
  eq(r.queries_added, 15);
  eq(r.city, 'Oakville');
  eq(r.product_type, 'eazer_merchant');
});

t('SC-02', 'success says when it takes effect, not that it already has', () => {
  const r = run(IN, { ok: true, city: 'Oakville', product_type: 'eazer_merchant',
                      queries_added: 15, note: 'added' });
  eq(r.takes_effect, 'on the next discovery run');
  if (/queued|scanning now|processing/i.test(JSON.stringify(r))) {
    throw new Error('implies work already underway: ' + JSON.stringify(r));
  }
});

t('SC-03', 'a zero-row result is success, not a fabricated count', () => {
  const r = run(IN, { ok: true, city: 'Oakville', product_type: 'eazer_merchant',
                      queries_added: 0, already_present: 15,
                      note: 'eazer_merchant already covered "Oakville"' });
  eq(r.ok, true);
  eq(r.queries_added, 0);
  eq(r.already_present, 15);
});

// --- everything below must refuse -------------------------------------
t('SC-04', 'an ambiguous target is refused, and the options are passed on', () => {
  const r = run({ city: 'Oakville', product_type: 'Eazer' },
                { ok: false, error: '"Eazer" is ambiguous - it matches eazer_delivery, eazer_merchant. Name one.',
                  options: ['eazer_delivery', 'eazer_merchant'] });
  eq(r.ok, false);
  eq(Array.isArray(r.options), true, 'options should reach the caller;');
  eq(r.options.length, 2);
});

t('SC-05', 'an unknown vertical is refused', () => {
  const r = run({ city: 'Oakville', product_type: 'nonsense' },
                { ok: false, error: 'no vertical or client matches \'nonsense\'' });
  eq(r.ok, false);
});

t('SC-06', 'a PostgREST error body is a failure, not a result', () => {
  const r = run(IN, { code: '42883', message: 'function add_discovery_city does not exist' });
  eq(r.ok, false);
  if (!/does not exist/.test(r.error)) throw new Error('lost the cause: ' + r.error);
});

t('SC-07', 'no answer at all is a failure', () => {
  eq(run(IN, 'ABSENT').ok, false);
});

t('SC-08', 'a node that never executed is a failure', () => {
  eq(run(IN, 'THROW').ok, false);
});

t('SC-09', 'null, a string and a number are all failures', () => {
  [null, 'ok', 42, true].forEach(function (junk) {
    const r = run(IN, junk);
    if (r.ok === true) throw new Error('accepted junk: ' + JSON.stringify(junk));
  });
});

t('SC-10', 'no failure path ever emits the old reassuring sentence', () => {
  ['ABSENT', 'THROW', null, { ok: false, error: 'refused' },
   { code: 'X', message: 'boom' }].forEach(function (rpc) {
    const s = JSON.stringify(run(IN, rpc));
    if (/will process|queued|next scheduled run/i.test(s)) {
      throw new Error('a failure still reads as queued work: ' + s);
    }
  });
});

t('SC-11', 'the tool description no longer promises a queue', () => {
  const src = nodeByName('Build Tool List').parameters.jsCode;
  const i = src.indexOf("name: 'scan_city'");
  if (i < 0) throw new Error('scan_city missing from the tool list');
  const desc = src.slice(i, i + 600);
  if (/Queue a city scan/i.test(desc)) {
    throw new Error('still described as queueing a scan');
  }
  if (!/next discovery run/i.test(desc)) {
    throw new Error('description must say when it takes effect');
  }
});

t('SC-12', 'the RPC call cannot abort the run before the report', () => {
  const n = nodeByName('Add Discovery City');
  eq(n.alwaysOutputData, true, 'alwaysOutputData:');
  eq(n.onError, 'continueRegularOutput', 'onError:');
});

console.log('\n  ' + pass + ' passed, ' + fail + ' failed\n');
process.exit(fail ? 1 : 0);
