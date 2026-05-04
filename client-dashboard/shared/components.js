/* ═══ Crystallux Client Dashboard — components.js ═══════════════════
   Mobile-first helpers. Mirrors the admin-dashboard's components.js
   shape so panels can move between codebases easily, but the table
   helper is replaced by a list-row helper that is friendlier on
   small screens (cards stack, no horizontal scroll for narrow tables).
   =================================================================== */

(function (global) {
  'use strict';

  // ── Hardcoded fallback nav so the sidebar is never empty even if
  //    /shared/nav.html fetch fails. Mirrors client-dashboard/shared/nav.html.
  global.CLX_FALLBACK_NAV =
    '<div class="clx-nav-section">Your Dashboard</div>' +
    '<a class="clx-nav-item" href="/pages/overview.html"><span class="clx-nav-icon">◉</span>Overview</a>' +
    '<a class="clx-nav-item" href="/pages/leads.html"><span class="clx-nav-icon">◍</span>My Leads</a>' +
    '<a class="clx-nav-item" href="/pages/campaigns.html"><span class="clx-nav-icon">⚏</span>Campaigns</a>' +
    '<a class="clx-nav-item" href="/pages/bookings.html"><span class="clx-nav-icon">◨</span>Bookings &amp; Replies</a>' +
    '<a class="clx-nav-item" href="/pages/activity.html"><span class="clx-nav-icon">≣</span>Activity</a>' +
    '<div class="clx-nav-section">Account</div>' +
    '<a class="clx-nav-item" href="/pages/billing.html"><span class="clx-nav-icon">$</span>Billing</a>' +
    '<a class="clx-nav-item" href="/pages/settings.html"><span class="clx-nav-icon">⚙</span>Settings</a>';

  // ── CSS resilience. See admin-dashboard/shared/components.js for the
  //    full rationale; same pattern here.
  function ensureLayoutCss() {
    try {
      var probe = getComputedStyle(document.documentElement)
        .getPropertyValue('--color-brand-500').trim();
      if (probe) return;
    } catch (e) {}
    fetch('/shared/layout.css', { cache: 'no-cache' })
      .then(function (r) { return r.ok ? r.text() : Promise.reject('http-' + r.status); })
      .then(function (css) {
        var s = document.createElement('style');
        s.setAttribute('data-clx-fallback', 'layout');
        s.textContent = css;
        document.head.appendChild(s);
      })
      .catch(function () {
        var s = document.createElement('style');
        s.setAttribute('data-clx-fallback', 'minimal');
        s.textContent = CLX_MINIMAL_CSS;
        document.head.appendChild(s);
      });
  }
  var CLX_MINIMAL_CSS =
    ':root{--color-brand-500:#7C3AED;--color-brand-100:#EDE9FE;--color-brand-700:#5B21B6;' +
    '--bg-page:#FAFAFA;--bg-card:#FFFFFF;--bg-hover:#F4F4F5;--border:#E4E4E7;' +
    '--text-primary:#18181B;--text-secondary:#52525B;--text-muted:#71717A;' +
    '--r-sm:6px;--sidebar-w:240px;--topbar-h:60px}' +
    '*{box-sizing:border-box;margin:0;padding:0}' +
    'body{font-family:Inter,system-ui,sans-serif;font-size:14px;line-height:1.5;' +
    'color:var(--text-primary);background:var(--bg-page);min-height:100vh}' +
    'a{color:inherit;text-decoration:none}' +
    '.clx-topbar{position:sticky;top:0;z-index:50;height:var(--topbar-h);' +
    'background:var(--bg-card);border-bottom:1px solid var(--border);' +
    'display:flex;align-items:center;justify-content:space-between;padding:0 24px;gap:16px}' +
    '.clx-topbar-left,.clx-topbar-right{display:flex;align-items:center;gap:12px}' +
    '.clx-logo{display:inline-flex;align-items:center;gap:10px;font-weight:800;font-size:17px}' +
    '.clx-logo-mark{width:28px;height:28px;border-radius:7px;' +
    'background:linear-gradient(135deg,var(--color-brand-500),var(--color-brand-700));' +
    'color:#fff;font-weight:800;font-size:14px;display:inline-flex;' +
    'align-items:center;justify-content:center}' +
    '.clx-role-pill{font-size:11px;font-weight:600;text-transform:uppercase;' +
    'padding:3px 9px;border-radius:99px;background:var(--color-brand-100);' +
    'color:var(--color-brand-700)}' +
    '.clx-shell{display:flex;align-items:flex-start;min-height:calc(100vh - var(--topbar-h))}' +
    '.clx-sidebar{flex:0 0 var(--sidebar-w);width:var(--sidebar-w);background:var(--bg-card);' +
    'border-right:1px solid var(--border);position:sticky;top:var(--topbar-h);' +
    'height:calc(100vh - var(--topbar-h));overflow-y:auto;padding:16px 12px}' +
    '.clx-nav-section{font-size:10px;font-weight:700;text-transform:uppercase;' +
    'letter-spacing:.08em;color:var(--text-muted);padding:14px 12px 6px}' +
    '.clx-nav-item{display:flex;align-items:center;gap:11px;padding:9px 12px;' +
    'border-radius:var(--r-sm);color:var(--text-secondary);font-size:13.5px;font-weight:500}' +
    '.clx-nav-item:hover{background:var(--bg-hover);color:var(--text-primary)}' +
    '.clx-nav-item.active{background:var(--color-brand-100);color:var(--color-brand-700);' +
    'font-weight:600}' +
    '.clx-nav-icon{width:18px;text-align:center;flex-shrink:0}' +
    '.clx-main{flex:1;min-width:0}' +
    '.clx-content{max-width:1400px;margin:0 auto;padding:24px}' +
    '.clx-page-head{margin-bottom:18px}' +
    '.clx-page-title{font-size:22px;font-weight:700;letter-spacing:-.01em}' +
    '.clx-page-sub{font-size:13px;color:var(--text-muted);margin-top:4px}' +
    '.clx-card{background:var(--bg-card);border:1px solid var(--border);' +
    'border-radius:14px;padding:18px}' +
    '.clx-card-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}' +
    '.clx-card-title{font-size:14px;font-weight:600}' +
    '.clx-stat-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));' +
    'gap:12px;margin-bottom:18px}' +
    '.clx-stat-card{background:var(--bg-card);border:1px solid var(--border);' +
    'border-radius:10px;padding:16px}' +
    '.clx-stat-label{font-size:12px;color:var(--text-muted);margin-bottom:4px}' +
    '.clx-stat-value{font-size:24px;font-weight:700}' +
    '.clx-table-scroll{overflow-x:auto}' +
    '.clx-table{width:100%;border-collapse:collapse;font-size:13px}' +
    '.clx-table th{text-align:left;padding:10px 14px;color:var(--text-muted);' +
    'font-weight:600;border-bottom:1px solid var(--border)}' +
    '.clx-table td{padding:10px 14px;border-bottom:1px solid var(--border)}' +
    '.clx-spinner{display:inline-block;width:14px;height:14px;' +
    'border:2px solid var(--border);border-top-color:var(--color-brand-500);' +
    'border-radius:50%;animation:clx-spin .7s linear infinite}' +
    '@keyframes clx-spin{to{transform:rotate(360deg)}}' +
    '.clx-loading-row{padding:14px 18px;color:var(--text-muted);font-size:13px;' +
    'display:flex;align-items:center;gap:10px}' +
    '.clx-empty{padding:30px;text-align:center;color:var(--text-muted)}' +
    '.clx-btn{display:inline-flex;align-items:center;gap:8px;padding:8px 14px;' +
    'border-radius:8px;border:1px solid var(--border);background:var(--bg-card);' +
    'color:var(--text-primary);font-weight:500;font-size:13px;cursor:pointer}' +
    '.clx-btn:hover{background:var(--bg-hover)}' +
    '.clx-btn-ghost{border-color:transparent;background:transparent;color:var(--text-secondary)}' +
    '.clx-badge{display:inline-block;padding:2px 8px;border-radius:99px;font-size:11px;' +
    'font-weight:600;text-transform:uppercase;letter-spacing:.04em}' +
    '.clx-badge-green{background:#D1FAE5;color:#065F46}' +
    '.clx-badge-red{background:#FEE2E2;color:#991B1B}' +
    '.clx-badge-blue{background:#DBEAFE;color:#1E40AF}' +
    '.clx-badge-yellow{background:#FEF3C7;color:#92400E}' +
    '.clx-badge-purple{background:#EDE9FE;color:#5B21B6}' +
    '.clx-badge-gray{background:#F4F4F5;color:#52525B}';

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', ensureLayoutCss);
  } else {
    ensureLayoutCss();
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function formatDate(d) {
    if (!d) return '—';
    try {
      var x = new Date(d);
      if (isNaN(x.getTime())) return '—';
      return x.toLocaleDateString('en-CA', { year: 'numeric', month: 'short', day: 'numeric' });
    } catch (e) { return '—'; }
  }
  function formatDateTime(d) {
    if (!d) return '—';
    try {
      var x = new Date(d);
      if (isNaN(x.getTime())) return '—';
      return x.toLocaleString('en-CA', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
    } catch (e) { return '—'; }
  }
  function relativeTime(d) {
    if (!d) return '';
    var t = new Date(d).getTime();
    if (isNaN(t)) return '';
    var diff = Date.now() - t;
    var min = Math.floor(diff / 60000);
    if (min < 1)  return 'just now';
    if (min < 60) return min + ' min ago';
    var hr = Math.floor(min / 60);
    if (hr < 24)  return hr + ' hour' + (hr === 1 ? '' : 's') + ' ago';
    var day = Math.floor(hr / 24);
    return day + ' day' + (day === 1 ? '' : 's') + ' ago';
  }
  function formatMoney(amount, currency) {
    if (amount == null) return '—';
    var c = currency || 'CAD';
    try {
      return new Intl.NumberFormat('en-CA', { style: 'currency', currency: c, maximumFractionDigits: 0 }).format(amount);
    } catch (e) { return '$' + Number(amount).toFixed(0); }
  }

  function badgeFor(status) {
    var s = String(status || '').toLowerCase();
    if (['active','paid','succeeded','live','ok','healthy','booked','replied'].indexOf(s) !== -1) return 'green';
    if (['trialing','pending','onboarding','contacted','researched'].indexOf(s) !== -1)         return 'blue';
    if (['past_due','warning','degraded','outreach ready','followup'].indexOf(s) !== -1)        return 'yellow';
    if (['canceled','cancelled','failed','locked','error','lost','no_show'].indexOf(s) !== -1)  return 'red';
    if (['admin','client','team_member','scored'].indexOf(s) !== -1)                            return 'purple';
    return 'gray';
  }

  function renderStatGrid(container, items) {
    if (!container) return;
    if (!items || !items.length) { container.innerHTML = ''; return; }
    container.innerHTML = items.map(function (it) {
      var deltaCls = it.deltaDir === 'up' ? 'up' : (it.deltaDir === 'down' ? 'down' : '');
      var delta = it.delta ? '<div class="clx-stat-delta ' + deltaCls + '">' + escapeHtml(it.delta) + '</div>' : '';
      return '<div class="clx-stat-card">' +
        '<div class="clx-stat-label">' + escapeHtml(it.label) + '</div>' +
        '<div class="clx-stat-value">' + escapeHtml(it.value == null ? '—' : it.value) + '</div>' +
        delta +
      '</div>';
    }).join('');
  }

  /**
   * Render a list of rows as stacked cards (mobile-friendly).
   * Each row spec:
   *   { primary, secondary, right, badge, badgeKind, href }
   * The shape function turns a data row into that spec.
   */
  function renderList(container, rows, shape, options) {
    if (!container) return;
    options = options || {};
    if (!rows || !rows.length) {
      container.innerHTML = '<div class="clx-empty">' +
        (options.emptyIcon ? '<span class="clx-empty-icon">' + options.emptyIcon + '</span>' : '') +
        escapeHtml(options.empty || 'Nothing to show yet.') + '</div>';
      return;
    }
    var html = '<div class="clx-list">' + rows.map(function (row) {
      var s = shape(row) || {};
      var rightHtml = '';
      if (s.badge) rightHtml += '<span class="clx-badge clx-badge-' + (s.badgeKind || badgeFor(s.badge)) + '">' + escapeHtml(s.badge) + '</span>';
      if (s.right) rightHtml += '<div class="clx-list-secondary" style="margin-top:6px">' + escapeHtml(s.right) + '</div>';
      var cls = 'clx-list-row' + (s.href ? ' linkish' : '');
      var attr = s.href ? ' data-href="' + escapeHtml(s.href) + '"' : '';
      return '<div class="' + cls + '"' + attr + '>' +
        '<div style="min-width:0;flex:1">' +
          '<div class="clx-list-primary">' + escapeHtml(s.primary || '—') + '</div>' +
          (s.secondary ? '<div class="clx-list-secondary">' + escapeHtml(s.secondary) + '</div>' : '') +
        '</div>' +
        '<div class="clx-list-right">' + rightHtml + '</div>' +
      '</div>';
    }).join('') + '</div>';
    container.innerHTML = html;
    container.querySelectorAll('.clx-list-row.linkish[data-href]').forEach(function (el) {
      el.addEventListener('click', function () { window.location.href = el.getAttribute('data-href'); });
    });
  }

  // Sidebar / bottom-nav active-item wiring. Matches by ends-with on
  // the current path so /pages/leads.html, /leads, etc. all light up.
  function wireNavActive() {
    var path = window.location.pathname.toLowerCase();
    document.querySelectorAll('.clx-nav-item, .clx-bn-item').forEach(function (a) {
      var href = (a.getAttribute('href') || a.getAttribute('data-href') || '').toLowerCase();
      if (!href) return;
      if (path.endsWith(href) || path.endsWith(href.replace(/^\.\//, ''))) {
        a.classList.add('active');
      }
    });
  }

  function injectNav(target) {
    if (!target) return Promise.resolve();
    return fetch('/shared/nav.html').then(function (r) {
      if (!r.ok) throw new Error('nav fetch failed');
      return r.text();
    }).then(function (html) {
      target.innerHTML = html;
      wireNavActive();
    }).catch(function () {
      target.innerHTML = global.CLX_FALLBACK_NAV || '';
      wireNavActive();
    });
  }

  function injectBottomNav(target) {
    if (!target) return Promise.resolve();
    return fetch('/shared/bottom-nav.html').then(function (r) {
      if (!r.ok) throw new Error('bn fetch failed');
      return r.text();
    }).then(function (html) {
      target.innerHTML = html;
      wireNavActive();
    }).catch(function () {
      target.innerHTML = global.CLX_FALLBACK_BOTTOM_NAV || '';
      wireNavActive();
    });
  }

  function renderTopbarUser(target) {
    if (!target) return;
    var email = (clxAuth.user && clxAuth.user.email) || clxAuth.getEmail() || '';
    target.innerHTML =
      (email ? '<span class="clx-list-secondary" style="font-size:12.5px">' + escapeHtml(email) + '</span>' : '') +
      '<button class="clx-icon-btn" id="clxLogoutBtn" title="Sign out" aria-label="Sign out">⏻</button>';
    var btn = document.getElementById('clxLogoutBtn');
    if (btn) btn.addEventListener('click', function () {
      if (confirm('Sign out of Crystallux?')) clxAuth.logout();
    });
  }

  global.clxComp = {
    escapeHtml: escapeHtml,
    formatDate: formatDate,
    formatDateTime: formatDateTime,
    relativeTime: relativeTime,
    formatMoney: formatMoney,
    badgeFor: badgeFor,
    renderStatGrid: renderStatGrid,
    renderList: renderList,
    injectNav: injectNav,
    injectBottomNav: injectBottomNav,
    renderTopbarUser: renderTopbarUser
  };
})(window);
