#!/usr/bin/env node
/**
 * Tests the dashboard session normaliser against the shape
 * clx-auth-validate-session actually returns.
 *
 * THE BUG THIS GUARDS
 *
 * validate-session returns a FLAT object:
 *   { ok, user_id, email, user_role, client_id, expires_at,
 *     is_active, email_verified, products, onboarding_status, company_name }
 *
 * Both dashboards read `data.user.role`. There is no `data.user`, and the
 * field is `user_role`, not `role`. So the whole block was skipped,
 * validate() returned {}, user.role was undefined, require_() failed its
 * role check and sent the browser back to login. Every time, for every
 * account.
 *
 * A successful sign-in was indistinguishable from a rejected one: the
 * session row was created server-side and the user was bounced
 * client-side, straight back to the login page. Three session rows were
 * written for one person trying to get in.
 *
 * It also explains docs/audit/client-audit-report.md: 0/7 pages passing
 * with seven byte-identical screenshots. The Playwright run could not get
 * past this either, and photographed the login page seven times.
 *
 * Run: node tests/agent/dashboard-auth.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const FILES = [
  ['client', path.join(__dirname, '..', '..', 'client-dashboard', 'shared', 'auth.js')],
  ['admin',  path.join(__dirname, '..', '..', 'admin-dashboard',  'shared', 'auth.js')]
];

// Exactly what the live endpoint returns, copied from the shipped
// 'Enforce Access Gates' node in clx-auth-validate-session.
function liveResponse(over) {
  return Object.assign({
    ok: true,
    user_id: 'u-1',
    email: 'info@eazer.com',
    user_role: 'client',
    client_id: '1583b401-0357-4935-a8c7-ba26d48222ad',
    expires_at: '2026-09-20T01:49:39+00:00',
    is_active: true,
    email_verified: true,
    products: ['sales_engine'],
    onboarding_status: 'new',
    company_name: 'Eazer'
  }, over || {});
}

// Load auth.js into a browser-ish sandbox and run validate() against a
// stubbed fetch. Nothing is reimplemented -- this exercises the shipped file.
function loadAuth(file, response, status) {
  const store = {};
  // The client dashboard registers listeners at load time; the admin one
  // does not. Stub enough of window that loading either file is inert.
  const win = { addEventListener: function () {}, removeEventListener: function () {},
                dispatchEvent: function () { return true; },
                setTimeout: function () { return 0; }, clearTimeout: function () {} };
  const sandbox = {
    window: win,
    document: {
      documentElement: { setAttribute() {}, getAttribute() { return null; } },
      getElementById() { return null; },
      createElement() { return { style: {}, setAttribute() {} }; },
      head: { appendChild() {} }
    },
    localStorage: {
      getItem(k) { return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null; },
      setItem(k, v) { store[k] = String(v); },
      removeItem(k) { delete store[k]; }
    },
    fetch: function () {
      return Promise.resolve({
        ok: (status || 200) < 400,
        status: status || 200,
        json: function () { return Promise.resolve(response); }
      });
    },
    console: { log() {}, warn() {}, error() {} },
    addEventListener: function () {}, setTimeout: function () { return 0; },
    clearTimeout: function () {},
    Promise: Promise, JSON: JSON, Array: Array, Object: Object,
    String: String, Boolean: Boolean, Date: Date, CustomEvent: function () {}
  };
  sandbox.globalThis = sandbox;
  sandbox.window.location = { href: 'https://app.crystallux.org/pages/overview.html',
                              replace() {}, hash: '' };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox, { timeout: 5000 });
  return { auth: sandbox.window.clxAuth, store: store };
}

let pass = 0, fail = 0;
function t(id, name, fn) {
  return Promise.resolve()
    .then(fn)
    .then(function () { console.log('  PASS  ' + id + '  ' + name); pass++; })
    .catch(function (e) {
      console.log('  FAIL  ' + id + '  ' + name + '\n        ' + (e && e.message));
      fail++;
    });
}
function eq(a, b, m) {
  if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) +
                               ', got ' + JSON.stringify(a));
}

const tests = [];

FILES.forEach(function (f) {
  const label = f[0], file = f[1];

  tests.push(function () {
    return t('AUTH-01 ' + label, 'the FLAT response yields a usable role', function () {
      const ctx = loadAuth(file, liveResponse());
      ctx.store['clx_session_token'] = 'tok';
      return ctx.auth.validate().then(function (user) {
        eq(user.role, 'client', 'role must survive user_role;');
        eq(user.client_id, '1583b401-0357-4935-a8c7-ba26d48222ad');
        eq(user.is_active, true);
        eq(user.email_verified, true);
        eq(Array.isArray(user.products) && user.products[0], 'sales_engine');
      });
    });
  });

  tests.push(function () {
    return t('AUTH-02 ' + label, 'role is persisted for the next page load', function () {
      const ctx = loadAuth(file, liveResponse());
      ctx.store['clx_session_token'] = 'tok';
      return ctx.auth.validate().then(function () {
        eq(ctx.store['clx_user_role'], 'client', 'clx_user_role;');
        eq(ctx.store['clx_user_products'], '["sales_engine"]');
      });
    });
  });

  tests.push(function () {
    return t('AUTH-03 ' + label, 'a NESTED response still works', function () {
      // Defensive: if the endpoint is ever changed to nest, this must not
      // break back to the loop.
      const flat = liveResponse();
      const ctx = loadAuth(file, { ok: true, user: { role: 'client',
        email: flat.email, client_id: flat.client_id, products: flat.products,
        is_active: true, email_verified: true } });
      ctx.store['clx_session_token'] = 'tok';
      return ctx.auth.validate().then(function (user) {
        eq(user.role, 'client');
      });
    });
  });

  tests.push(function () {
    return t('AUTH-04 ' + label, 'an admin is recognised as admin', function () {
      const ctx = loadAuth(file, liveResponse({ user_role: 'admin', client_id: null }));
      ctx.store['clx_session_token'] = 'tok';
      return ctx.auth.validate().then(function (user) {
        eq(user.role, 'admin');
      });
    });
  });

  tests.push(function () {
    return t('AUTH-05 ' + label, 'a rejected session still rejects', function () {
      const ctx = loadAuth(file, { ok: false, error: 'Invalid or expired session' }, 401);
      ctx.store['clx_session_token'] = 'tok';
      return ctx.auth.validate().then(function () {
        throw new Error('should have rejected');
      }, function (err) {
        eq(typeof err === 'string' || err instanceof Error, true);
      });
    });
  });

  tests.push(function () {
    return t('AUTH-06 ' + label, 'no token rejects without calling the server', function () {
      const ctx = loadAuth(file, liveResponse());
      return ctx.auth.validate().then(function () {
        throw new Error('should have rejected');
      }, function (err) { eq(err, 'no-token'); });
    });
  });
});

console.log('\nDashboard session normaliser\n');
tests.reduce(function (p, fn) { return p.then(fn); }, Promise.resolve())
  .then(function () {
    console.log('\n  ' + pass + ' passed, ' + fail + ' failed\n');
    process.exit(fail ? 1 : 0);
  });
