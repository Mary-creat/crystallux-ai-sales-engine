/* ═══ Crystallux Client Dashboard — components.js ═══════════════════
   Mobile-first helpers. Mirrors the admin-dashboard's components.js
   shape so panels can move between codebases easily, but the table
   helper is replaced by a list-row helper that is friendlier on
   small screens (cards stack, no horizontal scroll for narrow tables).
   =================================================================== */

(function (global) {
  'use strict';

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
