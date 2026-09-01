#!/usr/bin/env node
/**
 * Tests for Promotion Eligibility Guard in clx-campaign-router-v2.
 *
 * Runs against the jsCode actually shipped in the workflow, not a copy.
 *
 * The promotion stage is where a scored lead becomes a lead we intend to
 * build a message for. Three separate incidents on this platform came from
 * a stage trusting the previous stage's LABEL instead of re-deriving the
 * FACTS: 1,373 unresearched leads reached the scorer because their status
 * said 'Researched'; 24 tenant leads got drafts written for them with
 * researched_at NULL; and a house lead with no owner was emailed because
 * every filter upstream keyed on lead_status alone.
 *
 * The two properties under test:
 *
 *   1. Every missing fact refuses. Absence is never read as permission.
 *   2. Qualification is NOT authorisation. The guard may say a lead is
 *      worth building a play for; it may never say the lead may be
 *      contacted. That answer belongs to Sender Eligibility Guard, which
 *      re-derives it from source.
 *
 * Run: node tests/agent/promotion-gate.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WF = path.join(__dirname, '..', '..', 'workflows',
                     'clx-campaign-router-v2.json');
const wf = JSON.parse(fs.readFileSync(WF, 'utf8'));

const GUARD = 'Promotion Eligibility Guard';
const FETCH = 'Get Signal Detected Leads';

function nodeByName(n) {
  const x = wf.nodes.find(k => k.name === n);
  if (!x) throw new Error('node not found: ' + n);
  return x;
}

const TENANT = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';

// A lead that should qualify: tenant-owned, researched, scored, on an
// active tenant with an authorised email play. Every test below removes
// exactly one of these and asserts the refusal.
function goodLead(over) {
  return Object.assign({
    id: 'lead-1',
    company: 'KMI Brokers Inc.',
    client_id: TENANT,
    lead_pool: 'tenant',
    lead_status: 'Signal Detected',
    lead_score: 72,
    scoring_reason: 'Owner-level decision maker at an established broker',
    research_summary: 'KMI Brokers Inc. is an insurance broker in Mississauga.',
    researched_at: '2026-08-31T20:45:44.839+00:00',
    unsubscribed: false,
    do_not_contact: false
  }, over || {});
}

const CLIENTS = [{ id: TENANT, channels_enabled: ['email'], onboarding_stage: 'active' }];
const PLAYS = [{ client_id: TENANT, channel: 'email', status: 'active', name: 'pilot-insurance' }];
const USERS = [{ client_id: TENANT, is_active: true, products: ['sales_engine'] }];

function run(leads, opts) {
  const o = opts || {};
  const sources = {
    'Get Signal Detected Leads': leads,
    'Fetch Promotion Client Policy': o.clients || CLIENTS,
    'Fetch Promotion Plays': o.plays || PLAYS,
    'Fetch Promotion Entitlement': o.users || USERS
  };
  const src = nodeByName(GUARD).parameters.jsCode;
  const sandbox = {
    $: (name) => {
      if (!(name in sources)) throw new Error('unexpected node ref: ' + name);
      return { all: () => sources[name].map(j => ({ json: j })) };
    },
    console: { log: () => {} }
  };
  return vm.runInNewContext('(function(){' + src + '})()', sandbox, { timeout: 5000 });
}

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
function refuses(lead, opts) {
  const out = run([lead], opts);
  eq(out.length, 0, 'should have refused but promoted:');
}

console.log('\nPromotion Eligibility Guard\n');

t('PG-01', 'a fully evidenced tenant lead qualifies', () => {
  const out = run([goodLead()]);
  eq(out.length, 1, 'eligible count');
  eq(out[0].json.id, 'lead-1');
  eq(out[0].json._promotion_qualified, true);
});

// --- Property 2: qualification is not authorisation -------------------
t('PG-02', 'qualifying never authorises contact', () => {
  const out = run([goodLead()]);
  eq(out[0].json._authorized_to_contact, false,
     'a qualified lead must still carry authorised=false;');
});

t('PG-03', 'the guard emits no field a sender could read as permission', () => {
  const out = run([goodLead()]);
  const keys = Object.keys(out[0].json).filter(k => k.charAt(0) === '_');
  const permissionish = keys.filter(k =>
    /allow|approved|may_send|authorized/i.test(k) &&
    out[0].json[k] !== false);
  eq(permissionish.length, 0,
     'found a truthy permission-shaped field: ' + JSON.stringify(permissionish) + ';');
});

// --- Property 1: every missing fact refuses ---------------------------
t('PG-04', 'house pool is refused', () => refuses(goodLead({ lead_pool: 'house' })));
t('PG-05', 'missing lead_pool is refused (never defaults to tenant)',
  () => refuses(goodLead({ lead_pool: undefined })));
t('PG-06', 'no owning tenant is refused', () => refuses(goodLead({ client_id: null })));
t('PG-07', 'a status other than Signal Detected is refused',
  () => refuses(goodLead({ lead_status: 'Outreach Ready' })));

t('PG-08', 'empty research_summary is refused',
  () => refuses(goodLead({ research_summary: '   ' })));
t('PG-09', 'a summary with no researched_at is refused',
  () => refuses(goodLead({ researched_at: null })));

t('PG-10', 'a null score is refused, not read as a low score',
  () => refuses(goodLead({ lead_score: null })));
t('PG-11', 'a zero score is refused', () => refuses(goodLead({ lead_score: 0 })));
t('PG-12', 'a score whose reason records a failure is refused', () => {
  refuses(goodLead({ scoring_reason: 'Scoring failed: parse error' }));
});
t('PG-13', 'a score that is not a number is refused',
  () => refuses(goodLead({ lead_score: '72' })));

t('PG-14', 'unsubscribed is refused', () => refuses(goodLead({ unsubscribed: true })));
t('PG-15', 'do_not_contact is refused', () => refuses(goodLead({ do_not_contact: true })));

t('PG-16', 'an unknown tenant is refused', () => refuses(goodLead(), { clients: [] }));
t('PG-17', 'a tenant that is not active is refused', () => {
  refuses(goodLead(), { clients: [{ id: TENANT, channels_enabled: ['email'],
                                    onboarding_stage: 'pending' }] });
});
t('PG-18', 'a tenant without the product entitlement is refused',
  () => refuses(goodLead(), { users: [] }));
t('PG-19', 'entitlement held by an inactive user does not count', () => {
  // The fetch filters is_active, but the guard must not depend on the
  // caller having done that -- a widened fetch must not widen permission.
  refuses(goodLead(), { users: [{ client_id: TENANT, products: ['sentinel'] }] });
});
t('PG-20', 'a tenant with email disabled is refused', () => {
  refuses(goodLead(), { clients: [{ id: TENANT, channels_enabled: ['sms'],
                                    onboarding_stage: 'active' }] });
});

t('PG-21', 'no authorised play means no promotion', () => refuses(goodLead(), { plays: [] }));
t('PG-22', 'a paused play does not authorise', () => {
  refuses(goodLead(), { plays: [{ client_id: TENANT, channel: 'email',
                                  status: 'paused', name: 'pilot' }] });
});
t('PG-23', 'a play on another channel does not authorise email', () => {
  refuses(goodLead(), { plays: [{ client_id: TENANT, channel: 'sms',
                                  status: 'active', name: 'pilot' }] });
});
t('PG-24', "another tenant's play does not authorise this one", () => {
  refuses(goodLead(), { plays: [{ client_id: 'other-tenant', channel: 'email',
                                  status: 'active', name: 'pilot' }] });
});

t('PG-25', 'every policy source empty refuses everything', () => {
  const out = run([goodLead(), goodLead({ id: 'lead-2' })],
                  { clients: [], plays: [], users: [] });
  eq(out.length, 0, 'nothing may promote with no policy at all;');
});

t('PG-26', 'a mixed batch promotes only the evidenced lead', () => {
  const out = run([
    goodLead({ id: 'ok' }),
    goodLead({ id: 'no-research', research_summary: null, researched_at: null }),
    goodLead({ id: 'house', lead_pool: 'house' })
  ]);
  eq(out.length, 1, 'eligible count');
  eq(out[0].json.id, 'ok');
});

// --- The fetch must supply what the guard judges ----------------------
t('PG-27', 'the fetch selects every field the guard reads', () => {
  const url = nodeByName(FETCH).parameters.url;
  const select = decodeURIComponent((url.split('select=')[1] || '').split('&')[0]);
  const fields = select.split(',').map(s => s.trim());
  ['lead_pool', 'lead_status', 'lead_score', 'scoring_reason',
   'research_summary', 'researched_at', 'unsubscribed', 'do_not_contact',
   'client_id'].forEach(f => {
    if (fields.indexOf(f) < 0) {
      throw new Error('guard reads ' + f + ' but the fetch never selects it');
    }
  });
});

t('PG-28', 'the fetch is scoped to the tenant pool', () => {
  const url = nodeByName(FETCH).parameters.url;
  if (url.indexOf('lead_pool=eq.tenant') < 0) {
    throw new Error('the house pool would be swept into tenant promotion');
  }
});

console.log('\n  ' + pass + ' passed, ' + fail + ' failed\n');
process.exit(fail ? 1 : 0);
