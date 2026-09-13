#!/usr/bin/env node
/**
 * Runs the REAL 'Enforce Access Gates' code out of
 * workflows/api/auth/clx-auth-validate-session.json.
 *
 * THE BUG THIS GUARDS
 *
 * When the access-profile fetch produced nothing, the node used to answer
 * ok:true with email_verified:false, products:[] and company_name:null.
 * That is not a degraded answer, it is a confident wrong one: the dashboard
 * reads email_verified:false as a real fact and redirects to /verify-email,
 * which cannot help, because verifying writes to a database nobody was
 * reading. Every account was affected, admin included -- info@crystallux.org
 * and info@eazer.com both reported verified=false while the row said true.
 *
 * A fetch that did not happen is not the same fact as a field that is false.
 *
 * Run: node tests/agent/validate-session.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WF = path.join(__dirname, '..', '..', 'workflows', 'api', 'auth',
                     'clx-auth-validate-session.json');

const wf = JSON.parse(fs.readFileSync(WF, 'utf8'));
const node = wf.nodes.find(n => n.name === 'Enforce Access Gates');
if (!node) { console.error('Enforce Access Gates node is gone'); process.exit(1); }

const SESSION = {
  user_id: 'bcb819eb-5013-48e0-8ed8-7997b02a3002',
  email: 'info@eazer.com',
  user_role: 'client',
  client_id: '1583b401-0357-4935-a8c7-ba26d48222ad',
  expires_at: '2026-09-20T02:01:22.105384+00:00'
};

// The profile row exactly as v_auth_users_access returns it.
function profile(over) {
  return Object.assign({
    user_id: SESSION.user_id,
    email: 'info@eazer.com',
    user_role: 'client',
    client_id: SESSION.client_id,
    is_active: true,
    email_verified: true,
    products: ['sales_engine'],
    onboarding_status: 'new',
    company_name: 'Eazer'
  }, over || {});
}

function run(raw) {
  const sandbox = {
    $input: { item: { json: raw } },
    $: function (name) {
      if (name === 'Shape Session') return { item: { json: SESSION } };
      throw new Error('unexpected node reference: ' + name);
    },
    Array: Array, Object: Object, JSON: JSON, console: { log() {} }
  };
  vm.createContext(sandbox);
  return vm.runInContext('(function(){' + node.parameters.jsCode + '})()',
                         sandbox, { timeout: 5000 }).json;
}

let pass = 0, fail = 0;
function t(id, name, fn) {
  try { fn(); console.log('  PASS  ' + id + '  ' + name); pass++; }
  catch (e) { console.log('  FAIL  ' + id + '  ' + name + '\n        ' + e.message); fail++; }
}
function eq(a, b, m) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ', got ' + JSON.stringify(a));
  }
}

console.log('\nvalidate-session access gates\n');

t('VS-01', 'a healthy profile passes every field through', () => {
  const r = run(profile());
  eq(r.ok, true);
  eq(r.email_verified, true, 'email_verified;');
  eq(r.products, ['sales_engine']);
  eq(r.company_name, 'Eazer');
  eq(r.user_role, 'client');
  eq(r.client_id, SESSION.client_id);
});

// The regression. Each of these is a way the fetch can come back useless.
[['an empty object',        {}],
 ['null',                   null],
 ['an n8n error envelope',  { error: 'Forbidden' }],
 ['a PGRST116 envelope',    { code: 'PGRST116', message: 'no rows' }],
 ['a row with no is_active',{ user_id: SESSION.user_id, email: 'x@y.z' }]
].forEach(([label, raw], i) => {
  t('VS-0' + (i + 2), 'an absent profile fails loudly, not as unverified (' + label + ')', () => {
    const r = run(raw);
    eq(r.ok, false, 'must not claim success;');
    eq(r.error, 'profile-unavailable');
    eq(r.status, 503);
    // The whole point: never hand back a fabricated false.
    if (r.email_verified === false) throw new Error('still fabricating email_verified:false');
    if (Array.isArray(r.products)) throw new Error('still fabricating an empty products list');
  });
});

t('VS-07', 'a suspended account is refused with 403', () => {
  const r = run(profile({ is_active: false }));
  eq(r.ok, false);
  eq(r.status, 403);
});

t('VS-08', 'a genuinely unverified account still reports unverified', () => {
  const r = run(profile({ email_verified: false }));
  eq(r.ok, true, 'unverified is not an error;');
  eq(r.email_verified, false);
});

// The shape bug that actually locked everyone out. PostgREST echoed the
// vnd.pgrst.object+json Accept header back as the Content-Type, n8n did not
// recognise it as JSON, and the row arrived as a string under `data`.
t('VS-10', 'a row wrapped in { data: "<json>" } is still read', () => {
  const r = run({ data: JSON.stringify(profile()) });
  eq(r.ok, true, 'stringified data;');
  eq(r.email_verified, true);
  eq(r.products, ['sales_engine']);
});

t('VS-11', 'a row wrapped in { data: {...} } is still read', () => {
  const r = run({ data: profile() });
  eq(r.ok, true);
  eq(r.company_name, 'Eazer');
});

t('VS-12', 'a one-element array is still read', () => {
  const r = run([profile()]);
  eq(r.ok, true);
  eq(r.email_verified, true);
});

t('VS-13', 'an empty array is an absent profile, not an unverified one', () => {
  const r = run([]);
  eq(r.ok, false);
  eq(r.error, 'profile-unavailable');
});

t('VS-14', 'unparseable data is an absent profile', () => {
  const r = run({ data: '<html>502 Bad Gateway</html>' });
  eq(r.ok, false);
  eq(r.error, 'profile-unavailable');
});

// The header must not come back. It is the whole cause.
t('VS-15', 'the fetch no longer asks for a content type n8n cannot parse', () => {
  const f = wf.nodes.find(n => n.name === 'Fetch Access Profile');
  const hdrs = JSON.stringify(f.parameters.headerParameters || {});
  if (hdrs.indexOf('vnd.pgrst') !== -1) {
    throw new Error('the vnd.pgrst Accept header is back; the row will arrive as text');
  }
});

t('VS-09', 'the profile fetch tolerates failure instead of killing the run', () => {
  const f = wf.nodes.find(n => n.name === 'Fetch Access Profile');
  if (!f) throw new Error('Fetch Access Profile node is gone');
  eq(f.alwaysOutputData, true, 'alwaysOutputData;');
  eq(f.onError, 'continueRegularOutput', 'onError;');
});

console.log('\n  ' + pass + ' passed, ' + fail + ' failed\n');
process.exit(fail ? 1 : 0);
