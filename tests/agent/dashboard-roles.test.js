#!/usr/bin/env node
/**
 * Every role a dashboard page gates on must be a role the system can issue.
 *
 * THE BUG THIS GUARDS
 *
 * Five client pages required 'client_admin' or 'client_user'. Neither has
 * ever existed: not in auth_users.user_role, not in the signup flow, not in
 * any workflow. Production issues exactly three roles -- admin, client,
 * mga_principal.
 *
 * A gate on a role nobody holds is not a permission, it is a locked door.
 * And require_() does not fail politely: a wrong-role is bounced off the
 * dashboard origin entirely, to crystallux.org/login.html, so to the person
 * clicking it looks like being signed out mid-session. Step 3 of the welcome
 * checklist -- the one we ask every new customer to click -- pointed at one
 * of these pages.
 *
 * Run: node tests/agent/dashboard-roles.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

// Roles the platform can actually issue. 'client'/'team_member' are the
// tenant-side pair; the MGA set is provisioned and reachable. Anything a
// page asks for that is not here can never be satisfied.
const ISSUABLE = [
  'admin', 'client', 'team_member', 'mga_principal', 'supervisor',
  'compliance_officer', 'advisor', 'sub_agent'
];

// Confirmed live 2026-09-12: SELECT DISTINCT user_role FROM auth_users.
const IN_PRODUCTION = ['admin', 'client', 'mga_principal'];

const DIRS = [
  path.join(__dirname, '..', '..', 'client-dashboard', 'pages'),
  path.join(__dirname, '..', '..', 'admin-dashboard', 'pages')
];

let pass = 0, fail = 0;
function t(id, name, fn) {
  try { fn(); console.log('  PASS  ' + id + '  ' + name); pass++; }
  catch (e) { console.log('  FAIL  ' + id + '  ' + name + '\n        ' + e.message); fail++; }
}

function walk(dir, out) {
  if (!fs.existsSync(dir)) return out;
  fs.readdirSync(dir).forEach(function (f) {
    const p = path.join(dir, f);
    if (fs.statSync(p).isDirectory()) return walk(p, out);
    if (f.endsWith('.html')) out.push(p);
  });
  return out;
}

const files = DIRS.reduce(function (a, d) { return walk(d, a); }, []);

console.log('\nDashboard role gates\n');

t('ROLE-01', 'no page gates on a role the system cannot issue', function () {
  const bad = [];
  files.forEach(function (f) {
    const src = fs.readFileSync(f, 'utf8');
    const re = /clxAuth\.require\(\s*(\[[^\]]*\]|'[^']*'|"[^"]*")/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      (m[1].match(/['"]([^'"]+)['"]/g) || []).forEach(function (q) {
        const role = q.slice(1, -1);
        if (ISSUABLE.indexOf(role) === -1) {
          bad.push(path.basename(f) + ' requires "' + role + '"');
        }
      });
    }
  });
  if (bad.length) throw new Error('unreachable gate(s):\n        ' + bad.join('\n        '));
});

t('ROLE-02', 'every client page is reachable by a plain client', function () {
  const dir = path.join(__dirname, '..', '..', 'client-dashboard', 'pages');
  const bad = [];
  walk(dir, []).forEach(function (f) {
    const src = fs.readFileSync(f, 'utf8');
    const m = /clxAuth\.require\(\s*(\[[^\]]*\]|'[^']*'|"[^"]*")/.exec(src);
    if (!m) return;
    const roles = (m[1].match(/['"]([^'"]+)['"]/g) || []).map(function (q) { return q.slice(1, -1); });
    // A page on the client dashboard that a client cannot open is a page
    // that only ever shows them the login screen.
    if (roles.indexOf('client') === -1) {
      bad.push(path.basename(f) + ' allows [' + roles.join(', ') + ']');
    }
  });
  if (bad.length) throw new Error('client-locked page(s):\n        ' + bad.join('\n        '));
});

t('ROLE-03', 'the welcome checklist only links to pages a new client can open', function () {
  const ov = path.join(__dirname, '..', '..', 'client-dashboard', 'pages', 'overview.html');
  const src = fs.readFileSync(ov, 'utf8');
  const banner = src.slice(src.indexOf('welcomeBanner'), src.indexOf('clx-stat-grid'));
  const targets = (banner.match(/href="\/pages\/([a-z-]+)\.html"/g) || [])
    .map(function (h) { return h.replace(/.*\/pages\/|\.html"/g, ''); });
  if (!targets.length) throw new Error('found no checklist links to check');
  const bad = [];
  targets.forEach(function (name) {
    const f = path.join(__dirname, '..', '..', 'client-dashboard', 'pages', name + '.html');
    if (!fs.existsSync(f)) { bad.push(name + ' (page does not exist)'); return; }
    const m = /clxAuth\.require\(\s*(\[[^\]]*\]|'[^']*'|"[^"]*")/.exec(fs.readFileSync(f, 'utf8'));
    if (!m) return;
    const roles = (m[1].match(/['"]([^'"]+)['"]/g) || []).map(function (q) { return q.slice(1, -1); });
    if (roles.indexOf('client') === -1) bad.push(name + ' allows [' + roles.join(', ') + ']');
  });
  if (bad.length) throw new Error('checklist step(s) a client cannot open:\n        ' + bad.join('\n        '));
});

t('ROLE-04', 'the production role set is a subset of what pages expect', function () {
  IN_PRODUCTION.forEach(function (r) {
    if (ISSUABLE.indexOf(r) === -1) {
      throw new Error('"' + r + '" exists in auth_users but no page knows about it');
    }
  });
});

t('ROLE-05', 'customer-facing dashboard copy does not name the founder', function () {
  const dir = path.join(__dirname, '..', '..', 'client-dashboard');
  const bad = [];
  walk(dir, []).forEach(function (f) {
    if (/Mary/.test(fs.readFileSync(f, 'utf8'))) bad.push(path.relative(dir, f));
  });
  if (bad.length) throw new Error('names Mary: ' + bad.join(', '));
});

console.log('\n  ' + pass + ' passed, ' + fail + ' failed\n');
process.exit(fail ? 1 : 0);
