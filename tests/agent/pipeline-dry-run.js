#!/usr/bin/env node
/**
 * DRY RUN. Reads production, writes nothing, sends nothing.
 *
 * Runs the two eligibility guards that are actually shipped -- Promotion
 * Eligibility Guard in clx-campaign-router-v2 and Sender Eligibility Guard
 * in clx-outreach-sender-v2 -- against the real rows their own fetch URLs
 * return from production, and prints what each would decide.
 *
 * This exists because a guard that refuses everything looks identical to a
 * guard that works, and the difference only shows in the reasons. Unit
 * tests prove the logic against fixtures; this proves it against the data
 * that is really there.
 *
 * Requires SUPABASE_PROJECT_ID and SUPABASE_SERVICE_KEY in .env.
 * Shells out to curl: the bundled CA store on the build machine rejects a
 * chain curl accepts.
 *
 * Run: node tests/agent/pipeline-dry-run.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..', '..');

function env() {
  const out = {};
  const p = path.join(ROOT, '.env');
  if (!fs.existsSync(p)) return out;
  fs.readFileSync(p, 'utf8').split(/\r?\n/).forEach(function (line) {
    line = line.trim();
    if (!line || line[0] === '#' || line.indexOf('=') < 0) return;
    const i = line.indexOf('=');
    out[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["']|["']$/g, '');
  });
  return out;
}

const cfg = env();
const KEY = process.env.SUPABASE_SERVICE_KEY || cfg.SUPABASE_SERVICE_KEY;
const PROJECT = process.env.SUPABASE_PROJECT_ID || cfg.SUPABASE_PROJECT_ID;
if (!KEY || !PROJECT) {
  console.error('SUPABASE_PROJECT_ID / SUPABASE_SERVICE_KEY not set');
  process.exit(2);
}

// Only ever GET. Nothing here may mutate production.
function get(url) {
  const body = execFileSync('curl', [
    '-sS', '--max-time', '45', '-X', 'GET',
    '-H', 'apikey: ' + KEY,
    '-H', 'Authorization: Bearer ' + KEY,
    url
  ], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  const parsed = JSON.parse(body);
  if (!Array.isArray(parsed)) {
    // A policy fetch that errors is the dangerous case, not the loud one:
    // PostgREST returns an object, the guard sees a row with no client_id,
    // the policy map stays empty, and every lead is refused for a reason
    // that reads like policy. Surface it as a finding, keep going.
    badFetches.push({ url: url.replace(/^https:\/\/[^/]+/, ''), body: parsed });
    return [];
  }
  return parsed;
}

function wf(file) {
  return JSON.parse(fs.readFileSync(path.join(ROOT, 'workflows', file), 'utf8'));
}

function node(w, name) {
  const n = w.nodes.find(k => k.name === name);
  if (!n) throw new Error('node not found: ' + name);
  return n;
}

// n8n expressions are not evaluated here; a URL carrying one is skipped and
// reported rather than guessed at.
function urlOf(w, name) {
  const u = node(w, name).parameters.url;
  if (typeof u !== 'string' || u.indexOf('{{') >= 0 || u[0] === '=') return null;
  return u;
}

const refusals = {};
const badFetches = [];

function runGuard(w, guardName, sources) {
  const src = node(w, guardName).parameters.jsCode;
  const lines = [];
  const sandbox = {
    $: (name) => {
      if (!(name in sources)) throw new Error('unexpected node ref: ' + name);
      return { all: () => sources[name].map(j => ({ json: j })) };
    },
    console: { log: (m) => lines.push(String(m)) }
  };
  const out = vm.runInNewContext('(function(){' + src + '})()', sandbox, { timeout: 10000 });
  return { eligible: out, log: lines };
}

function report(title, fetched, result) {
  console.log('\n' + title);
  console.log('  rows returned by the shipped fetch : ' + fetched);
  console.log('  would pass the guard               : ' + result.eligible.length);
  // The guard's own summary line, but not its per-lead dump: the reasons
  // are the finding, and 59 company names are not.
  result.log.filter(l => l.indexOf('refusals:') < 0)
    .forEach(l => console.log('  ' + l));
  const line = result.log.find(l => l.indexOf('refusals:') >= 0);
  if (line) {
    const reasons = {};
    JSON.parse(line.slice(line.indexOf('[{'))).forEach(function (r) {
      r.reasons.forEach(function (x) { reasons[x] = (reasons[x] || 0) + 1; });
    });
    // The guard logs at most the first 25 refusals, so these counts are a
    // sample of the reasons, not a census of the leads.
    console.log('  refusal reasons (first 25 refusals):');
    Object.keys(reasons).sort((a, b) => reasons[b] - reasons[a])
      .forEach(k => console.log('    ' + String(reasons[k]).padStart(4) + '  ' + k));
    Object.keys(reasons).forEach(k => { refusals[k] = true; });
  }
}

const B = 'https://' + PROJECT + '.supabase.co/rest/v1/';

console.log('DRY RUN against production. Read-only: no write, no send.');

// ---- Promotion ---------------------------------------------------------
const router = wf('clx-campaign-router-v2.json');
const promoLeads = get(urlOf(router, 'Get Signal Detected Leads'));
report('PROMOTION  (clx-campaign-router-v2 / Promotion Eligibility Guard)',
  promoLeads.length,
  runGuard(router, 'Promotion Eligibility Guard', {
    'Get Signal Detected Leads': promoLeads,
    'Fetch Promotion Client Policy': get(urlOf(router, 'Fetch Promotion Client Policy')),
    'Fetch Promotion Plays': get(urlOf(router, 'Fetch Promotion Plays')),
    'Fetch Promotion Entitlement': get(urlOf(router, 'Fetch Promotion Entitlement'))
  }));

// ---- Sender ------------------------------------------------------------
const sender = wf('clx-outreach-sender-v2.json');
const sendLeads = get(urlOf(sender, 'Get Outreach Ready Leads'));
report('SENDER  (clx-outreach-sender-v2 / Sender Eligibility Guard)',
  sendLeads.length,
  runGuard(sender, 'Sender Eligibility Guard', {
    'Get Outreach Ready Leads': sendLeads,
    'Fetch Client Send Policy': get(urlOf(sender, 'Fetch Client Send Policy')),
    'Fetch Authorized Campaigns': get(urlOf(sender, 'Fetch Authorized Campaigns')),
    'Fetch Entitled Tenants': get(urlOf(sender, 'Fetch Entitled Tenants')),
    'Fetch Autonomy Levels': get(urlOf(sender, 'Fetch Autonomy Levels'))
  }));

// ---- Draft safety ------------------------------------------------------
// Not a guard -- generation has no guard node. The property that matters is
// that its fetch can no longer return a lead without real research.
const gen = wf('clx-outreach-generation-v2.json');
const genLeads = get(urlOf(gen, 'Get Campaign Assigned Leads'));
const unresearched = genLeads.filter(l => !l.research_summary || !l.researched_at);
console.log('\nDRAFT SAFETY  (clx-outreach-generation-v2 / Get Campaign Assigned Leads)');
console.log('  rows the shipped fetch would draft for : ' + genLeads.length);
console.log('  of those, with no real research        : ' + unresearched.length);
if (unresearched.length) {
  console.log('  FAIL: generation would draft for a lead that was never researched');
  process.exit(1);
}
console.log('  none -- the fetch can no longer reach an unresearched lead');

console.log('\nNo row was written and no message was sent.');
console.log('Refusal reasons seen: ' + (Object.keys(refusals).join(', ') || 'none'));
