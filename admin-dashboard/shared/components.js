/* ═══ Crystallux Admin Dashboard — components.js ══════════════════════
   Tiny, framework-free helpers. Imported by every page that renders
   tables / stat cards / sidebars. No build step, no bundle.
   =================================================================== */

(function (global) {
  'use strict';

  // ── Hardcoded fallback nav. Used by injectNav's catch path so the
  //    sidebar is never empty even if /shared/nav.html fetch fails OR
  //    Cloudflare Pages serves the SPA index.html as a 404 fallback.
  global.CLX_FALLBACK_NAV =
    '<div class="clx-nav-section">Admin</div>' +
    '<a class="clx-nav-item" href="/pages/overview.html"><span class="clx-nav-icon">◉</span>Overview</a>' +
    '<a class="clx-nav-item" href="/pages/clients.html"><span class="clx-nav-icon">▤</span>Clients</a>' +
    '<a class="clx-nav-item" href="/pages/leads.html"><span class="clx-nav-icon">◍</span>Leads</a>' +
    '<a class="clx-nav-item" href="/pages/workflows.html"><span class="clx-nav-icon">⚙</span>Workflows</a>' +
    '<a class="clx-nav-item" href="/pages/billing.html"><span class="clx-nav-icon">$</span>Billing</a>' +
    '<div class="clx-nav-section">Platform</div>' +
    '<a class="clx-nav-item" href="/pages/onboarding.html"><span class="clx-nav-icon">◐</span>Onboarding</a>' +
    '<a class="clx-nav-item" href="/pages/market-intelligence.html"><span class="clx-nav-icon">✦</span>Market Intelligence</a>' +
    '<a class="clx-nav-item" href="/pages/audit-log.html"><span class="clx-nav-icon">◔</span>Audit Log</a>' +
    '<div class="clx-nav-section">Account</div>' +
    '<a class="clx-nav-item" href="/pages/settings.html"><span class="clx-nav-icon">⚒</span>Settings</a>';

  // ── CSS resilience. The dashboard pages link /shared/layout.css via
  //    a <link> tag, but if that request gets canceled (Cloudflare edge
  //    cache lag, mid-load navigation, MIME mismatch from a SPA-fallback
  //    response), the .clx-sidebar pane collapses to 0 width and the
  //    correctly-loaded nav links inside it become invisible. We probe
  //    for a known custom property and, if missing, fetch the stylesheet
  //    and inject it via JS. Final fallback is a minimal inline ruleset
  //    that keeps the page laid-out even if both paths fail.
  function ensureLayoutCss() {
    try {
      var probe = getComputedStyle(document.documentElement)
        .getPropertyValue('--color-brand-500').trim();
      if (probe) return; // layout.css already applied via <link>
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
   * Render a list of stat cards into a container. Accepts items shaped
   *   { label, value, delta?, deltaDir?, icon?, variant?, href? }.
   * - icon: name from the ICONS table → renders inline-SVG in a tinted box
   * - variant: 'leads'|'revenue'|'activity'|'errors'|'bookings'|'neutral'
   *   → applies the matching .clx-stat-card.--<variant> class for color
   * - href: makes the card clickable → navigates on click + hover lift
   * Backward-compatible: omitting all new keys yields the old plain card.
   */
  function renderStatGrid(container, items) {
    if (!container) return;
    if (!items || !items.length) { container.innerHTML = ''; return; }
    container.innerHTML = items.map(function (it) {
      var variantCls = it.variant ? ' --' + it.variant : '';
      var iconHtml = it.icon ? '<span class="clx-stat-icon">' + icon(it.icon, 'lg') + '</span>' : '';
      var hrefAttr = it.href ? ' data-href="' + escapeHtml(it.href) + '"' : '';
      var deltaCls = it.deltaDir === 'up' ? 'up' : (it.deltaDir === 'down' ? 'down' : '');
      var delta = it.delta ? '<div class="clx-stat-delta ' + deltaCls + '">' + escapeHtml(it.delta) + '</div>' : '';
      return '<div class="clx-stat-card' + variantCls + '"' + hrefAttr + '>' +
        iconHtml +
        '<div class="clx-stat-label">' + escapeHtml(it.label) + '</div>' +
        '<div class="clx-stat-value">' + escapeHtml(it.value == null ? '—' : it.value) + '</div>' +
        delta +
      '</div>';
    }).join('');
    container.querySelectorAll('.clx-stat-card[data-href]').forEach(function (el) {
      el.addEventListener('click', function () {
        window.location.href = el.getAttribute('data-href');
      });
    });
  }

  /**
   * Render a polished empty state. Backward-compatible:
   *   renderEmpty(el, message)               → plain text
   *   renderEmpty(el, message, iconName)     → illustrated with icon
   *   renderEmpty(el, message, iconName, ctaHtml) → with CTA button HTML
   */
  function renderEmpty(el, message, iconName, ctaHtml) {
    if (!el) return;
    if (iconName && ICONS[iconName]) {
      el.innerHTML = '<div class="clx-empty-illustrated">' +
        '<div class="clx-empty-icon-wrap">' + icon(iconName, 'lg') + '</div>' +
        '<h4>' + escapeHtml(message || 'Nothing here yet') + '</h4>' +
        (ctaHtml ? '<div>' + ctaHtml + '</div>' : '') +
      '</div>';
    } else {
      el.innerHTML = '<div class="clx-empty">' +
        escapeHtml(message || 'No records yet.') + '</div>';
    }
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
    return fetch('/shared/nav.html').then(function (r) {
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

  // ════════════════════════════════════════════════════════════════════
  // Polish helpers — inline SVG icons, skeletons, charts, avatars, score
  // bars. Hand-rolled so we don't ship an icon library or fight CSP.
  // ════════════════════════════════════════════════════════════════════

  // Lucide-style strokes. All icons share a 24×24 viewBox and 2px stroke.
  var ICONS = {
    'overview':         '<polyline points="3 12 7 4 11 12 14 8 17 14 21 6"></polyline>',
    'users':            '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M22 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path>',
    'user':             '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle>',
    'user-plus':        '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><line x1="20" y1="8" x2="20" y2="14"></line><line x1="23" y1="11" x2="17" y2="11"></line>',
    'building':         '<rect x="4" y="2" width="16" height="20" rx="2"></rect><path d="M9 22v-4h6v4"></path><circle cx="12" cy="8" r="0.6"></circle><circle cx="12" cy="12" r="0.6"></circle><circle cx="8" cy="8" r="0.6"></circle><circle cx="16" cy="8" r="0.6"></circle><circle cx="8" cy="12" r="0.6"></circle><circle cx="16" cy="12" r="0.6"></circle>',
    'target':           '<circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="12" r="6"></circle><circle cx="12" cy="12" r="2"></circle>',
    'trending-up':      '<polyline points="22 7 13.5 15.5 8.5 10.5 2 17"></polyline><polyline points="16 7 22 7 22 13"></polyline>',
    'dollar-sign':      '<line x1="12" y1="1" x2="12" y2="23"></line><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path>',
    'activity':         '<polyline points="22 12 18 12 15 21 9 3 6 12 2 12"></polyline>',
    'clock':            '<circle cx="12" cy="12" r="10"></circle><polyline points="12 6 12 12 16 14"></polyline>',
    'calendar':         '<rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect><line x1="16" y1="2" x2="16" y2="6"></line><line x1="8" y1="2" x2="8" y2="6"></line><line x1="3" y1="10" x2="21" y2="10"></line>',
    'mail':             '<path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"></path><polyline points="22 6 12 13 2 6"></polyline>',
    'message-square':   '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path>',
    'check-circle':     '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline>',
    'x-circle':         '<circle cx="12" cy="12" r="10"></circle><line x1="15" y1="9" x2="9" y2="15"></line><line x1="9" y1="9" x2="15" y2="15"></line>',
    'alert-triangle':   '<path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line>',
    'settings':         '<circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"></path>',
    'search':           '<circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line>',
    'filter':           '<polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"></polygon>',
    'eye':              '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle>',
    'chevron-right':    '<polyline points="9 18 15 12 9 6"></polyline>',
    'chevron-down':     '<polyline points="6 9 12 15 18 9"></polyline>',
    'arrow-right':      '<line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline>',
    'refresh':          '<polyline points="23 4 23 10 17 10"></polyline><polyline points="1 20 1 14 7 14"></polyline><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path>',
    'sparkles':         '<path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1"></path><circle cx="12" cy="12" r="2"></circle>',
    'layers':           '<polygon points="12 2 2 7 12 12 22 7 12 2"></polygon><polyline points="2 17 12 22 22 17"></polyline><polyline points="2 12 12 17 22 12"></polyline>',
    'bar-chart':        '<line x1="12" y1="20" x2="12" y2="10"></line><line x1="18" y1="20" x2="18" y2="4"></line><line x1="6" y1="20" x2="6" y2="16"></line>',
    'pie-chart':        '<path d="M21.21 15.89A10 10 0 1 1 8 2.83"></path><path d="M22 12A10 10 0 0 0 12 2v10z"></path>',
    'log-out':          '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path><polyline points="16 17 21 12 16 7"></polyline><line x1="21" y1="12" x2="9" y2="12"></line>',
    'log-in':           '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"></path><polyline points="10 17 15 12 10 7"></polyline><line x1="15" y1="12" x2="3" y2="12"></line>',
    'shield':           '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path>',
    'zap':              '<polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"></polygon>',
    'play':             '<polygon points="5 3 19 12 5 21 5 3"></polygon>',
    'plus-circle':      '<circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="16"></line><line x1="8" y1="12" x2="16" y2="12"></line>',
    'edit':             '<path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>',
    'trash':            '<polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>',
    'inbox':            '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"></polyline><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"></path>',
    'briefcase':        '<rect x="2" y="7" width="20" height="14" rx="2" ry="2"></rect><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"></path>',
    'home':             '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path><polyline points="9 22 9 12 15 12 15 22"></polyline>'
  };

  function icon(name, size) {
    var path = ICONS[name];
    if (!path) return '';
    var sizeCls = '';
    if (size === 'sm') sizeCls = ' --sm';
    else if (size === 'lg') sizeCls = ' --lg';
    else if (size === 'xl') sizeCls = ' --xl';
    return '<span class="clx-icon' + sizeCls + '" aria-hidden="true">' +
      '<svg viewBox="0 0 24 24">' + path + '</svg></span>';
  }

  function skeleton(rows, cols) {
    rows = rows || 5; cols = cols || 4;
    var html = '<div class="clx-skeleton-table">';
    for (var i = 0; i < rows; i++) {
      html += '<div class="clx-skeleton-row">';
      for (var j = 0; j < cols; j++) {
        var w = (40 + Math.floor(Math.random() * 50)) + '%';
        html += '<span class="clx-skeleton" style="max-width:' + w + '"></span>';
      }
      html += '</div>';
    }
    html += '</div>';
    return html;
  }

  function skeletonStat(count) {
    count = count || 4;
    var html = '<div class="clx-stat-grid">';
    for (var i = 0; i < count; i++) {
      html += '<div class="clx-stat-card">' +
        '<span class="clx-skeleton" style="width:50%; height:10px"></span>' +
        '<div style="height:10px"></div>' +
        '<span class="clx-skeleton" style="width:40%; height:24px"></span>' +
        '</div>';
    }
    html += '</div>';
    return html;
  }

  // Sparkline. values = number[]. options: { width, height, strokeColor, fillColor }
  function sparkline(values, options) {
    options = options || {};
    if (!values || values.length === 0) values = [0];
    var w = options.width || 200, h = options.height || 48, pad = 2;
    var min = Math.min.apply(null, values), max = Math.max.apply(null, values);
    if (max === min) max = min + 1;
    var n = values.length;
    var stepX = n > 1 ? (w - pad * 2) / (n - 1) : 0;
    var pts = values.map(function (v, i) {
      var x = pad + i * stepX;
      var y = pad + (1 - (v - min) / (max - min)) * (h - pad * 2);
      return x.toFixed(1) + ',' + y.toFixed(1);
    });
    var firstX = pad.toFixed(1);
    var lastX = (pad + (n - 1) * stepX).toFixed(1);
    var bottom = (h - pad).toFixed(1);
    var fillPath = 'M' + firstX + ',' + bottom + ' L' + pts.join(' L') + ' L' + lastX + ',' + bottom + ' Z';
    var strokePath = 'M' + pts.join(' L');
    var stroke = options.strokeColor || '#7C3AED';
    var fill = options.fillColor || stroke;
    var gradId = 'clx-spark-' + Math.random().toString(36).slice(2, 9);
    return '<span class="clx-sparkline" aria-hidden="true">' +
      '<svg viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none">' +
      '<defs><linearGradient id="' + gradId + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0%" stop-color="' + fill + '" stop-opacity="0.35"/>' +
      '<stop offset="100%" stop-color="' + fill + '" stop-opacity="0"/>' +
      '</linearGradient></defs>' +
      '<path class="fill" fill="url(#' + gradId + ')" d="' + fillPath + '"/>' +
      '<path class="stroke" style="stroke:' + stroke + '" d="' + strokePath + '"/>' +
      '</svg></span>';
  }

  // Donut. slices = [{label, value, color?}]. options: { centerLabel, centerSub, emptyColor }
  function donut(slices, options) {
    options = options || {}; slices = slices || [];
    var total = slices.reduce(function (s, sl) { return s + (sl.value || 0); }, 0);
    if (total <= 0) {
      return '<span class="clx-donut" aria-hidden="true"><svg viewBox="0 0 100 100">' +
        '<circle cx="50" cy="50" r="35" fill="none" stroke="' + (options.emptyColor || '#E4E4E7') + '" stroke-width="14"/>' +
        '</svg></span>';
    }
    var palette = ['#7C3AED', '#3B82F6', '#10B981', '#F59E0B', '#EF4444', '#A78BFA', '#1D4ED8', '#047857'];
    var radius = 35, circ = 2 * Math.PI * radius, offset = 0;
    var arcs = slices.map(function (s, i) {
      var frac = (s.value || 0) / total;
      var len = circ * frac;
      var color = s.color || palette[i % palette.length];
      var arc = '<circle cx="50" cy="50" r="' + radius + '" fill="none" stroke="' + color +
        '" stroke-width="14"' +
        ' stroke-dasharray="' + len.toFixed(2) + ' ' + (circ - len).toFixed(2) + '"' +
        ' stroke-dashoffset="' + (-offset).toFixed(2) + '" transform="rotate(-90 50 50)"/>';
      offset += len;
      return arc;
    }).join('');
    var center = '';
    if (options.centerLabel != null) {
      center += '<text class="center-label" x="50" y="50" text-anchor="middle" dominant-baseline="central">' +
        escapeHtml(String(options.centerLabel)) + '</text>';
      if (options.centerSub) {
        center += '<text class="center-sub" x="50" y="63" text-anchor="middle" dominant-baseline="central">' +
          escapeHtml(String(options.centerSub)) + '</text>';
      }
    }
    return '<span class="clx-donut" aria-hidden="true"><svg viewBox="0 0 100 100">' +
      arcs + center + '</svg></span>';
  }

  function donutLegend(slices) {
    slices = slices || [];
    var palette = ['#7C3AED', '#3B82F6', '#10B981', '#F59E0B', '#EF4444', '#A78BFA', '#1D4ED8', '#047857'];
    return '<div class="clx-chart-legend">' + slices.map(function (s, i) {
      var color = s.color || palette[i % palette.length];
      return '<span><i class="swatch" style="background:' + color + '"></i>' +
        escapeHtml(s.label || '') + ' (' + (s.value || 0) + ')</span>';
    }).join('') + '</div>';
  }

  function barChart(values, options) {
    options = options || {};
    if (!values || values.length === 0) return '<span class="clx-bar-chart"></span>';
    var w = options.width || 200, h = options.height || 80, pad = 2;
    var max = Math.max.apply(null, values);
    if (max <= 0) max = 1;
    var n = values.length;
    var bw = (w - pad * 2) / n;
    var gap = bw * 0.2;
    var bars = values.map(function (v, i) {
      var barH = ((v / max) * (h - pad * 2));
      var x = pad + i * bw + gap / 2;
      var y = h - pad - barH;
      return '<rect class="bar" x="' + x.toFixed(1) + '" y="' + y.toFixed(1) +
        '" width="' + (bw - gap).toFixed(1) + '" height="' + barH.toFixed(1) + '" rx="2"/>';
    }).join('');
    return '<span class="clx-bar-chart" aria-hidden="true">' +
      '<svg viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none">' + bars + '</svg></span>';
  }

  function progressBar(value, max, options) {
    options = options || {};
    max = max || 100;
    value = Math.max(0, Math.min(value || 0, max));
    var pct = max > 0 ? (value / max * 100) : 0;
    var variant = options.variant ? ' --' + options.variant : '';
    return '<span class="clx-progress' + variant + '">' +
      '<i class="clx-progress-fill" style="width:' + pct.toFixed(1) + '%"></i></span>';
  }

  function avatar(seed, size) {
    var s = String(seed || '?').trim();
    var initials = s.split(/[\s@.\-_]+/).filter(Boolean).slice(0, 2)
      .map(function (p) { return p[0]; }).join('').toUpperCase() || '?';
    var sizeCls = size === 'lg' ? ' --lg' : (size === 'sm' ? ' --sm' : '');
    return '<span class="clx-avatar' + sizeCls + '">' + escapeHtml(initials) + '</span>';
  }

  function scoreBar(score) {
    var s = Math.max(0, Math.min(Number(score) || 0, 100));
    var band = s < 35 ? 'low' : s < 65 ? 'medium' : s < 90 ? 'high' : 'critical';
    return '<span class="clx-score-bar --' + band + '" title="Score: ' + s + '">' +
      '<i style="width:' + s + '%"></i></span>';
  }

  function sectionHead(title, actionHtml) {
    return '<div class="clx-section-head">' +
      '<div class="clx-section-title">' + escapeHtml(title) + '</div>' +
      (actionHtml ? '<div class="clx-section-action">' + actionHtml + '</div>' : '') +
      '</div>';
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
    renderEmpty: renderEmpty,
    injectNav: injectNav,
    wireSidebar: wireSidebar,
    renderTopbarUser: renderTopbarUser,
    icon: icon,
    skeleton: skeleton,
    skeletonStat: skeletonStat,
    sparkline: sparkline,
    donut: donut,
    donutLegend: donutLegend,
    barChart: barChart,
    progressBar: progressBar,
    avatar: avatar,
    scoreBar: scoreBar,
    sectionHead: sectionHead
  };
})(window);
