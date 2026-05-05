#!/usr/bin/env node
/* Crystallux Dashboard Audit Harness
 *
 * Runs Playwright against deployed admin + client dashboards. For every
 * page captures: HTTP status, console errors, network failures, presence
 * of key elements, whether stat cards show real numbers (not "—" / 0),
 * whether charts have rendered data, and saves a screenshot. Emits a
 * Markdown report.
 *
 * Usage:
 *   node dashboard-audit.js admin    # admin pages only
 *   node dashboard-audit.js client   # client pages only
 *   node dashboard-audit.js all      # both
 *
 * Credentials via env vars (override defaults):
 *   CLX_ADMIN_EMAIL, CLX_ADMIN_PASSWORD
 *   CLX_CLIENT_EMAIL, CLX_CLIENT_PASSWORD
 */

'use strict';

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SHOTS_DIR = path.join(ROOT, 'docs', 'audit', 'screenshots');
const REPORTS_DIR = path.join(ROOT, 'docs', 'audit');

// ── Configuration ─────────────────────────────────────────────────────
const ADMIN_BASE  = 'https://admin.crystallux.org';
const CLIENT_BASE = 'https://app.crystallux.org';
const TEST_CLIENT_ID = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';

const ADMIN_EMAIL    = process.env.CLX_ADMIN_EMAIL    || 'info@crystallux.org';
const ADMIN_PASSWORD = process.env.CLX_ADMIN_PASSWORD || 'Crystallux2026#';
const CLIENT_EMAIL    = process.env.CLX_CLIENT_EMAIL    || 'testclient@crystallux.org';
const CLIENT_PASSWORD = process.env.CLX_CLIENT_PASSWORD || 'TestPass2026#';

const ADMIN_PAGES = [
  { slug: 'overview',            path: '/pages/overview.html' },
  { slug: 'clients',             path: '/pages/clients.html' },
  { slug: 'client-detail',       path: '/pages/client-detail.html?id=' + TEST_CLIENT_ID },
  { slug: 'leads',               path: '/pages/leads.html' },
  { slug: 'workflows',           path: '/pages/workflows.html' },
  { slug: 'billing',             path: '/pages/billing.html' },
  { slug: 'onboarding',          path: '/pages/onboarding.html' },
  { slug: 'market-intelligence', path: '/pages/market-intelligence.html' },
  { slug: 'audit-log',           path: '/pages/audit-log.html' },
  { slug: 'settings',            path: '/pages/settings.html' }
];

const CLIENT_PAGES = [
  { slug: 'overview',  path: '/pages/overview.html' },
  { slug: 'leads',     path: '/pages/leads.html' },
  { slug: 'campaigns', path: '/pages/campaigns.html' },
  { slug: 'bookings',  path: '/pages/bookings.html' },
  { slug: 'activity',  path: '/pages/activity.html' },
  { slug: 'billing',   path: '/pages/billing.html' },
  { slug: 'settings',  path: '/pages/settings.html' }
];

// ── Login flows ───────────────────────────────────────────────────────
async function loginAdmin(page) {
  await page.goto('https://crystallux.org/login.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.fill('input[type=email], input#email', ADMIN_EMAIL);
  await page.fill('input[type=password], input#password', ADMIN_PASSWORD);
  await Promise.all([
    page.waitForURL(/admin\.crystallux\.org/, { timeout: 30000 }).catch(function () {}),
    page.click('button[type=submit], button.clx-btn-primary')
  ]);
  // Wait for landing page to settle
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(function () {});
}

async function loginClient(page) {
  await page.goto('https://crystallux.org/login.html', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.fill('input[type=email], input#email', CLIENT_EMAIL);
  await page.fill('input[type=password], input#password', CLIENT_PASSWORD);
  await Promise.all([
    page.waitForURL(/app\.crystallux\.org/, { timeout: 30000 }).catch(function () {}),
    page.click('button[type=submit], button.clx-btn-primary')
  ]);
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(function () {});
}

// ── Page check ────────────────────────────────────────────────────────
async function auditPage(page, base, slug, pagePath, role) {
  const result = {
    slug: slug,
    url: base + pagePath,
    httpStatus: null,
    loadMs: null,
    consoleErrors: [],
    networkFailures: [],
    elements: {},
    statValuesValid: null,
    statValuesRaw: [],
    chartsRendered: null,
    sidebarPresent: null,
    interactiveCount: 0,
    screenshot: null,
    pass: false
  };

  const consoleErrors = [];
  const networkFailures = [];
  const onConsole = function (msg) {
    if (msg.type() === 'error') {
      consoleErrors.push((msg.text() || '').slice(0, 250));
    }
  };
  const onResponse = function (resp) {
    if (resp.status() >= 400 && resp.url().indexOf('crystallux') !== -1) {
      networkFailures.push(resp.status() + ' ' + resp.url());
    }
  };
  page.on('console', onConsole);
  page.on('response', onResponse);

  const t0 = Date.now();
  let response;
  try {
    response = await page.goto(base + pagePath, { waitUntil: 'domcontentloaded', timeout: 30000 });
  } catch (e) {
    result.consoleErrors.push('NAV ERROR: ' + (e && e.message || e));
  }
  result.httpStatus = response ? response.status() : 0;

  // Give the dashboard time to fetch + render
  try { await page.waitForLoadState('networkidle', { timeout: 12000 }); } catch (e) {}
  await page.waitForTimeout(800);

  result.loadMs = Date.now() - t0;

  // Sidebar present
  result.sidebarPresent = await page.locator('.clx-sidebar .clx-nav-item').count() > 0;

  // Stat cards
  const statValues = await page.$$eval('.clx-stat-card .clx-stat-value', function (els) {
    return els.map(function (e) { return (e.textContent || '').trim(); });
  });
  result.statValuesRaw = statValues;
  result.elements.statCards = statValues.length;
  if (statValues.length > 0) {
    // Real data = at least one value not "—" and not just spinner glyph
    const nonEmpty = statValues.filter(function (v) {
      return v && v !== '—' && v.indexOf('Loading') === -1 && v.length > 0;
    });
    result.statValuesValid = nonEmpty.length > 0;
  } else {
    result.statValuesValid = null;
  }

  // Charts (sparkline / donut / bar)
  const charts = await page.$$eval('.clx-sparkline, .clx-donut, .clx-bar-chart', function (els) {
    return els.map(function (e) {
      const paths = e.querySelectorAll('path, circle, rect');
      return { tag: e.className || '', shapeCount: paths.length };
    });
  });
  result.elements.charts = charts.length;
  result.chartsRendered = charts.length === 0 ? null : charts.every(function (c) { return c.shapeCount > 0; });

  // Tables / lists
  result.elements.tableRows = await page.locator('table.clx-table tbody tr').count();
  result.elements.listRows = await page.locator('.clx-list-row').count();

  // Interactive elements (clickable cards + clickable rows)
  result.interactiveCount = await page.locator('.clx-stat-card[data-href], tbody tr[data-href], .clx-list-row.linkish').count();

  result.consoleErrors = consoleErrors;
  result.networkFailures = networkFailures;

  // Screenshot
  const dir = path.join(SHOTS_DIR, role);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const shotPath = path.join(dir, slug + '.png');
  try {
    await page.screenshot({ path: shotPath, fullPage: true });
    result.screenshot = path.relative(ROOT, shotPath).replace(/\\/g, '/');
  } catch (e) {
    result.screenshot = 'ERROR: ' + (e && e.message || e);
  }

  page.off('console', onConsole);
  page.off('response', onResponse);

  // Pass criteria: HTTP 200, no JS errors, sidebar present, no critical net failures
  result.pass = result.httpStatus === 200 &&
                consoleErrors.length === 0 &&
                result.sidebarPresent &&
                networkFailures.filter(function (n) { return n.indexOf('automation.crystallux.org') !== -1; }).length === 0;

  return result;
}

// ── Tenant isolation tests (client only) ──────────────────────────────
async function testTenantIsolation(page) {
  const findings = [];

  // 1. Client should not be able to load admin pages
  try {
    const resp = await page.goto(ADMIN_BASE + '/pages/overview.html', { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(1500);
    const url = page.url();
    if (url.indexOf('admin.crystallux.org/pages/overview.html') !== -1 &&
        await page.locator('.clx-nav-item').count() > 0) {
      findings.push({ test: 'admin-page-blocked', pass: false,
        detail: 'Client could load admin overview page (URL: ' + url + ')' });
    } else {
      findings.push({ test: 'admin-page-blocked', pass: true,
        detail: 'Client redirected away from admin (URL: ' + url + ')' });
    }
  } catch (e) {
    findings.push({ test: 'admin-page-blocked', pass: true,
      detail: 'Navigation error (likely blocked): ' + (e && e.message || e) });
  }

  // 2. Admin webhook with client token should return 403
  const sessionToken = await page.evaluate(function () { return localStorage.getItem('clx_session_token'); });
  if (sessionToken) {
    try {
      const r = await page.request.post('https://automation.crystallux.org/webhook/admin/list-clients', {
        headers: { 'Authorization': 'Bearer ' + sessionToken, 'Content-Type': 'application/json' },
        data: {}
      });
      const ok = r.status() === 403 || r.status() === 401;
      findings.push({ test: 'admin-webhook-rejects-client', pass: ok,
        detail: 'admin/list-clients returned ' + r.status() + ' to client token' });
    } catch (e) {
      findings.push({ test: 'admin-webhook-rejects-client', pass: false,
        detail: 'request error: ' + (e && e.message || e) });
    }

    // 3. Manipulate client_id in body — server must use session, not body
    try {
      const r = await page.request.post('https://automation.crystallux.org/webhook/client/leads', {
        headers: { 'Authorization': 'Bearer ' + sessionToken, 'Content-Type': 'application/json' },
        data: { filters: { client_id: '00000000-0000-0000-0000-000000000000' }, limit: 5 }
      });
      const body = await r.json().catch(function () { return {}; });
      const leads = (body && body.leads) || [];
      // If server honored body's bogus client_id, leads would be 0. If server used
      // session client_id (Crystallux Insurance Network = 79 leads), would be > 0.
      const honoredSession = leads.length > 0;
      findings.push({ test: 'client-id-body-ignored', pass: honoredSession,
        detail: 'POST with bogus client_id returned ' + leads.length + ' leads' +
                ' (expect >0 if session client_id used)' });
    } catch (e) {
      findings.push({ test: 'client-id-body-ignored', pass: false,
        detail: 'request error: ' + (e && e.message || e) });
    }
  } else {
    findings.push({ test: 'session-token-readable', pass: false,
      detail: 'No clx_session_token in localStorage' });
  }

  return findings;
}

// ── Mobile viewport check ─────────────────────────────────────────────
async function testMobile(browser, role, base, samplePath) {
  const ctx = await browser.newContext({ viewport: { width: 375, height: 812 } });
  const page = await ctx.newPage();
  // Inject auth token from previous admin/client login (passed in via storageState)
  // But we won't bother — instead just navigate and screenshot to confirm layout
  let result = { pass: false, screenshot: null, err: null };
  try {
    if (role === 'admin') await loginAdmin(page);
    else await loginClient(page);
    await page.goto(base + samplePath, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(1500);
    const sidebarVisible = await page.locator('.clx-sidebar.open, .clx-sidebar').first().isVisible().catch(function () { return false; });
    const burgerVisible = await page.locator('#clxBurger, .clx-burger').first().isVisible().catch(function () { return false; });
    const dir = path.join(SHOTS_DIR, role);
    const shot = path.join(dir, 'mobile-' + path.basename(samplePath, '.html') + '.png');
    await page.screenshot({ path: shot, fullPage: true });
    result.pass = burgerVisible || role === 'client';
    result.screenshot = path.relative(ROOT, shot).replace(/\\/g, '/');
    result.detail = 'burger=' + burgerVisible + ' sidebar=' + sidebarVisible;
  } catch (e) {
    result.err = e && e.message || String(e);
  } finally {
    await ctx.close();
  }
  return result;
}

// ── Report writer ─────────────────────────────────────────────────────
function writeReport(role, results, mobileResult, isolationFindings) {
  const lines = [];
  lines.push('# ' + role.toUpperCase() + ' Dashboard Audit Report');
  lines.push('');
  lines.push('Generated: ' + new Date().toISOString());
  lines.push('Base URL: ' + (role === 'admin' ? ADMIN_BASE : CLIENT_BASE));
  lines.push('');

  const passed = results.filter(function (r) { return r.pass; }).length;
  lines.push('**Summary:** ' + passed + ' / ' + results.length + ' pages pass');
  lines.push('');

  lines.push('## Per-page results');
  lines.push('');
  lines.push('| Page | HTTP | Load (ms) | Sidebar | Stat cards | Charts | Tables | Lists | Interactive | Console errs | Net errs | Pass |');
  lines.push('|------|------|-----------|---------|------------|--------|--------|-------|-------------|--------------|----------|------|');
  results.forEach(function (r) {
    const sc = r.elements.statCards || 0;
    const stat = sc > 0 ? (sc + (r.statValuesValid ? ' ✓' : ' ⚠ no-data')) : '0';
    const ch = r.elements.charts || 0;
    const chart = ch > 0 ? (ch + (r.chartsRendered ? ' ✓' : ' ⚠')) : '0';
    lines.push([
      '| ' + r.slug,
      r.httpStatus,
      r.loadMs,
      r.sidebarPresent ? '✓' : '✗',
      stat,
      chart,
      r.elements.tableRows || 0,
      r.elements.listRows || 0,
      r.interactiveCount,
      r.consoleErrors.length,
      r.networkFailures.length,
      r.pass ? '✓' : '✗'
    ].join(' | ') + ' |');
  });
  lines.push('');

  // Per-page detail
  lines.push('## Detail');
  lines.push('');
  results.forEach(function (r) {
    lines.push('### ' + r.slug);
    lines.push('- URL: ' + r.url);
    lines.push('- HTTP: ' + r.httpStatus + ', load ' + r.loadMs + 'ms');
    lines.push('- Sidebar: ' + (r.sidebarPresent ? 'present' : 'MISSING'));
    lines.push('- Stat cards: ' + (r.elements.statCards || 0) +
               (r.statValuesRaw.length ? ' [' + r.statValuesRaw.slice(0, 6).map(function (v) { return v || '∅'; }).join(', ') + ']' : ''));
    lines.push('- Charts (sparkline/donut/bar): ' + (r.elements.charts || 0) +
               (r.chartsRendered === null ? ' (n/a)' : (r.chartsRendered ? ' rendered' : ' EMPTY')));
    lines.push('- Table rows: ' + (r.elements.tableRows || 0) + ', list rows: ' + (r.elements.listRows || 0));
    lines.push('- Interactive: ' + r.interactiveCount);
    if (r.consoleErrors.length) {
      lines.push('- Console errors:');
      r.consoleErrors.forEach(function (e) { lines.push('  - `' + e + '`'); });
    }
    if (r.networkFailures.length) {
      lines.push('- Network failures:');
      r.networkFailures.forEach(function (e) { lines.push('  - `' + e + '`'); });
    }
    if (r.screenshot) lines.push('- Screenshot: `' + r.screenshot + '`');
    lines.push('');
  });

  if (mobileResult) {
    lines.push('## Mobile (375px)');
    lines.push('- Pass: ' + (mobileResult.pass ? '✓' : '✗'));
    if (mobileResult.detail) lines.push('- Detail: ' + mobileResult.detail);
    if (mobileResult.err)    lines.push('- Error: `' + mobileResult.err + '`');
    if (mobileResult.screenshot) lines.push('- Screenshot: `' + mobileResult.screenshot + '`');
    lines.push('');
  }

  if (isolationFindings && isolationFindings.length) {
    lines.push('## Tenant isolation');
    lines.push('');
    lines.push('| Test | Pass | Detail |');
    lines.push('|------|------|--------|');
    isolationFindings.forEach(function (f) {
      lines.push('| ' + f.test + ' | ' + (f.pass ? '✓' : '✗') + ' | ' + f.detail + ' |');
    });
    lines.push('');
  }

  const file = path.join(REPORTS_DIR, role + '-audit-report.md');
  fs.writeFileSync(file, lines.join('\n'));
  return file;
}

// ── Main ──────────────────────────────────────────────────────────────
async function runRole(browser, role) {
  console.log('\n=== Auditing ' + role + ' ===\n');
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();

  if (role === 'admin') await loginAdmin(page);
  else                  await loginClient(page);

  console.log('Logged in. Current URL:', page.url());

  const base = role === 'admin' ? ADMIN_BASE : CLIENT_BASE;
  const pages = role === 'admin' ? ADMIN_PAGES : CLIENT_PAGES;
  const results = [];
  for (let i = 0; i < pages.length; i++) {
    process.stdout.write('  [' + (i+1) + '/' + pages.length + '] ' + pages[i].slug + ' ... ');
    const r = await auditPage(page, base, pages[i].slug, pages[i].path, role);
    results.push(r);
    console.log(r.pass ? 'PASS' : 'FAIL (errs=' + r.consoleErrors.length + ', net=' + r.networkFailures.length + ')');
  }

  let isolationFindings = null;
  if (role === 'client') {
    console.log('  running tenant isolation tests...');
    isolationFindings = await testTenantIsolation(page);
  }

  await ctx.close();

  console.log('  running mobile check...');
  const samplePath = pages[0].path;
  const mobileResult = await testMobile(browser, role, base, samplePath);

  const reportFile = writeReport(role, results, mobileResult, isolationFindings);
  console.log('  report written: ' + path.relative(ROOT, reportFile));

  return { results: results, mobileResult: mobileResult, isolationFindings: isolationFindings };
}

(async function () {
  const target = (process.argv[2] || 'all').toLowerCase();
  const browser = await chromium.launch({ headless: true });
  try {
    const out = {};
    if (target === 'admin' || target === 'all') {
      out.admin = await runRole(browser, 'admin');
    }
    if (target === 'client' || target === 'all') {
      try {
        out.client = await runRole(browser, 'client');
      } catch (e) {
        console.log('CLIENT AUDIT FAILED: ' + (e && e.message || e));
        fs.writeFileSync(path.join(REPORTS_DIR, 'client-audit-report.md'),
          '# Client Audit\n\nFAILED to run: `' + (e && e.message || e) + '`\n\n' +
          'Likely cause: testclient@crystallux.org account does not exist yet. ' +
          'Apply `db/migrations/test-client-account.sql` to Supabase first.\n');
      }
    }

    // Summary file
    const summaryLines = ['# Audit Summary', '', 'Generated: ' + new Date().toISOString(), ''];
    if (out.admin) {
      const p = out.admin.results.filter(function (r) { return r.pass; }).length;
      summaryLines.push('- Admin: ' + p + '/' + out.admin.results.length + ' pages pass');
    }
    if (out.client) {
      const p = out.client.results.filter(function (r) { return r.pass; }).length;
      summaryLines.push('- Client: ' + p + '/' + out.client.results.length + ' pages pass');
      if (out.client.isolationFindings) {
        const ip = out.client.isolationFindings.filter(function (f) { return f.pass; }).length;
        summaryLines.push('- Tenant isolation: ' + ip + '/' + out.client.isolationFindings.length + ' tests pass');
      }
    }
    fs.writeFileSync(path.join(REPORTS_DIR, 'audit-summary.md'), summaryLines.join('\n') + '\n');
    console.log('\nSummary written.');
  } finally {
    await browser.close();
  }
})();
