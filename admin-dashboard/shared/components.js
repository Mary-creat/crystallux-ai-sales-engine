/* ═══ Crystallux Admin Dashboard — components.js ══════════════════════
   Tiny, framework-free helpers. Imported by every page that renders
   tables / stat cards / sidebars. No build step, no bundle.
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
    } catch (e) {
      return '$' + Number(amount).toFixed(0);
    }
  }

  function badgeFor(status) {
    var s = String(status || '').toLowerCase();
    if (['active','paid','succeeded','live','ok','healthy','booked','replied'].indexOf(s) !== -1)         return 'green';
    if (['trialing','pending','onboarding','contacted','researched'].indexOf(s) !== -1)                  return 'blue';
    if (['past_due','warning','degraded','outreach ready','followup'].indexOf(s) !== -1)                 return 'yellow';
    if (['canceled','cancelled','failed','locked','error','lost','no_show'].indexOf(s) !== -1)           return 'red';
    if (['admin','client','team_member','scored'].indexOf(s) !== -1)                                     return 'purple';
    return 'gray';
  }

  /**
   * Render a list of stat cards into a container. Accepts items
   * shaped { label, value, delta, deltaDir }. delta is a string
   * already formatted; deltaDir is 'up' | 'down' | undefined.
   */
  function renderStatGrid(container, items) {
    if (!container) return;
    if (!items || !items.length) {
      container.innerHTML = '';
      return;
    }
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
   * Build an HTML table from rows + a column spec. Each column is
   * { key, label, format? (row -> string|html), html? (true to skip
   * escaping the format result) }. Pass `wide:true` to keep the
   * outer wrapper but skip the card chrome (e.g. for nested tables).
   */
  function renderTable(container, rows, columns, options) {
    if (!container) return;
    options = options || {};
    if (!rows || !rows.length) {
      container.innerHTML = '<div class="clx-empty">' +
        (options.emptyIcon ? '<span class="clx-empty-icon">' + options.emptyIcon + '</span>' : '') +
        escapeHtml(options.empty || 'No records yet.') + '</div>';
      return;
    }
    var thead = '<tr>' + columns.map(function (c) {
      return '<th>' + escapeHtml(c.label) + '</th>';
    }).join('') + '</tr>';
    var tbody = rows.map(function (row) {
      var tds = columns.map(function (c) {
        var raw = c.format ? c.format(row) : (row[c.key] == null ? '—' : row[c.key]);
        return '<td>' + (c.html ? raw : escapeHtml(raw)) + '</td>';
      }).join('');
      return '<tr' + (row._href ? ' data-href="' + escapeHtml(row._href) + '" style="cursor:pointer"' : '') + '>' + tds + '</tr>';
    }).join('');
    container.innerHTML = '<div class="clx-table-scroll"><table class="clx-table">' +
      '<thead>' + thead + '</thead><tbody>' + tbody + '</tbody></table></div>';
    // Wire row click navigation (for rows that supplied _href)
    container.querySelectorAll('tbody tr[data-href]').forEach(function (tr) {
      tr.addEventListener('click', function () { window.location.href = tr.getAttribute('data-href'); });
    });
  }

  // Sidebar wiring — once nav.html has been injected, mark the active
  // item by matching the current page's path.
  function wireSidebar() {
    var path = window.location.pathname.toLowerCase();
    document.querySelectorAll('.clx-nav-item').forEach(function (a) {
      var href = (a.getAttribute('href') || '').toLowerCase();
      if (!href) return;
      // Match either exact or "ends-with"
      if (path.endsWith(href) || path.endsWith(href.replace(/^\.\//, ''))) {
        a.classList.add('active');
      }
    });
    var burger = document.getElementById('clxBurger');
    var sidebar = document.getElementById('clxSidebar');
    var backdrop = document.getElementById('clxBackdrop');
    function toggle() {
      if (!sidebar) return;
      var open = sidebar.classList.toggle('open');
      if (backdrop) backdrop.classList.toggle('show', open);
    }
    if (burger) burger.addEventListener('click', toggle);
    if (backdrop) backdrop.addEventListener('click', toggle);
  }

  // Inject nav.html into a target element. Falls back to the
  // hardcoded nav-html string when fetch fails (e.g. file://).
  function injectNav(target) {
    if (!target) return Promise.resolve();
    return fetch('shared/nav.html').then(function (r) {
      if (!r.ok) throw new Error('nav fetch failed');
      return r.text();
    }).then(function (html) {
      target.innerHTML = html;
      wireSidebar();
    }).catch(function () {
      // Fallback inline nav so pages still work when fetch is blocked
      target.innerHTML = global.CLX_FALLBACK_NAV || '';
      wireSidebar();
    });
  }

  // Topbar user chip + logout button. Call after auth is ready.
  function renderTopbarUser(target) {
    if (!target) return;
    var email = (clxAuth.user && clxAuth.user.email) || clxAuth.getEmail() || 'admin';
    target.innerHTML =
      '<span class="clx-user-chip">Signed in as <strong>' + escapeHtml(email) + '</strong></span>' +
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
    renderTable: renderTable,
    injectNav: injectNav,
    wireSidebar: wireSidebar,
    renderTopbarUser: renderTopbarUser
  };
})(window);
