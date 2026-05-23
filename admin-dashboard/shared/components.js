/* ═══ Crystallux Admin Dashboard — components.js ══════════════════════
   Tiny, framework-free helpers. Imported by every page that renders
   tables / stat cards / sidebars. No build step, no bundle.
   =================================================================== */

(function (global) {
  'use strict';

  // ── Hardcoded fallback nav. Used by injectNav's catch path so the
  //    sidebar is never empty even if /shared/nav.html fetch fails OR
  //    Cloudflare Pages serves the SPA index.html as a 404 fallback.
  //
  //    KEEP IN SYNC with shared/nav.html. When a nav item is added or
  //    moved there, mirror it here. Stale fallback = if the network
  //    blip hits, Mary sees the old menu and concludes new pages don't
  //    exist when they do.
  global.CLX_FALLBACK_NAV =
    '<div class="clx-nav-section">Admin</div>' +
    '<a class="clx-nav-item" href="/pages/overview.html"><span class="clx-nav-icon">◉</span>Overview</a>' +
    '<a class="clx-nav-item" href="/pages/clients.html"><span class="clx-nav-icon">▤</span>Clients</a>' +
    '<a class="clx-nav-item" href="/pages/leads.html"><span class="clx-nav-icon">◍</span>Leads</a>' +
    '<a class="clx-nav-item" href="/pages/workflows.html"><span class="clx-nav-icon">⚙</span>Workflows</a>' +
    '<a class="clx-nav-item" href="/pages/billing.html"><span class="clx-nav-icon">$</span>Billing</a>' +
    '<a class="clx-nav-item" href="/pages/carriers/overview.html"><span class="clx-nav-icon">⌂</span>Carriers</a>' +
    '<div class="clx-nav-section">Platform</div>' +
    '<a class="clx-nav-item" href="/pages/sales-engine.html"><span class="clx-nav-icon">⚡</span>Sales Engine</a>' +
    '<a class="clx-nav-item" href="/pages/onboarding.html"><span class="clx-nav-icon">◐</span>Onboarding</a>' +
    '<a class="clx-nav-item" href="/pages/sentinel.html"><span class="clx-nav-icon">◆</span>Sentinel</a>' +
    '<a class="clx-nav-item" href="/pages/audit-log.html"><span class="clx-nav-icon">◔</span>Audit Log</a>' +
    '<a class="clx-nav-item" href="/pages/market-intelligence.html"><span class="clx-nav-icon">✦</span>Market Intelligence</a>' +
    '<div class="clx-nav-section">Avatars</div>' +
    '<a class="clx-nav-item" href="/pages/avatars.html"><span class="clx-nav-icon">◉</span>All avatars</a>' +
    '<a class="clx-nav-item" href="/pages/avatars/ava/index.html"><span class="clx-nav-icon">A</span>AVA — Insurance</a>' +
    '<a class="clx-nav-item" href="/pages/avatars/luxi/index.html"><span class="clx-nav-icon">★</span>LUXI — Live Commerce</a>' +
    '<a class="clx-nav-item" href="/pages/avatars/maxi/index.html"><span class="clx-nav-icon">↗</span>MAXI — SMB Growth</a>' +
    '<a class="clx-nav-item" href="/pages/avatars/lumi/index.html"><span class="clx-nav-icon">☾</span>LUMI — Wellness</a>' +
    '<a class="clx-nav-item" href="/pages/avatars/luma/index.html"><span class="clx-nav-icon">☆</span>LUMA — Entertainment</a>' +
    '<a class="clx-nav-item" href="/pages/avatars/lety/index.html"><span class="clx-nav-icon">☉</span>LETY — Education</a>' +
    '<a class="clx-nav-item" href="/pages/avatars/eaza/index.html"><span class="clx-nav-icon">⊟</span>EAZA — Logistics</a>' +
    '<a class="clx-nav-item" href="/pages/avatars/ciro/index.html"><span class="clx-nav-icon">⚒</span>CIRO — Ops Manager</a>' +
    '<div class="clx-nav-section">CIRO</div>' +
    '<a class="clx-nav-item" href="/pages/ciro/communications.html"><span class="clx-nav-icon">✉</span>Communications</a>' +
    '<a class="clx-nav-item" href="/pages/ciro/alerts.html"><span class="clx-nav-icon">⚠</span>Alerts</a>' +
    '<div class="clx-nav-section">Smart Quote</div>' +
    '<a class="clx-nav-item" href="/pages/smart-quote/index.html"><span class="clx-nav-icon">$</span>Estimator</a>' +
    '<div class="clx-nav-section">Diagnostics</div>' +
    '<a class="clx-nav-item" href="/pages/system/auth-check.html"><span class="clx-nav-icon">✓</span>Auth check</a>' +
    '<a class="clx-nav-item" href="/pages/system/dev-console.html"><span class="clx-nav-icon">›_</span>Dev console</a>' +
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
    // Highlight the current page's nav item. Safe to re-run — adds the
    // `.active` class idempotently. Walks every match because some pages
    // (e.g. /pages/avatars/maxi/industry.html?slug=construction) want
    // multiple breadcrumb-style highlights.
    var path = window.location.pathname.toLowerCase();
    document.querySelectorAll('.clx-nav-item').forEach(function (a) {
      var href = (a.getAttribute('href') || '').toLowerCase();
      if (!href) return;
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

    // Idempotent: every page used to call this twice (once explicitly,
    // once from injectNav's success/catch). Without this guard, each
    // burger click toggled the drawer TWICE (open then immediately
    // close) — making it look like the burger button didn't work.
    // Sentinel attribute survives DOM-mutation; addEventListener is
    // NOT idempotent, so we have to guard at the JS level.
    if (burger && !burger.dataset.clxWired) {
      burger.dataset.clxWired = '1';
      burger.addEventListener('click', toggle);
    }
    if (backdrop && !backdrop.dataset.clxWired) {
      backdrop.dataset.clxWired = '1';
      backdrop.addEventListener('click', toggle);
    }
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

  /* ───────────────────────────────────────────────────────────────
     Polish v2 primitives — toast / dialog / dropdown / tabs.
     Pure vanilla, no framework. All styles live in layout.css under
     the `.clx-toast`, `.clx-dialog`, `.clx-dropdown`, `.clx-tabs`
     classes. Each function returns a control object (e.g. dismiss(),
     close()) so callers can drive the lifecycle.
     ─────────────────────────────────────────────────────────────── */

  // toast(message, opts?) — top-right stacked notifications with auto-dismiss.
  //   opts: { variant: 'success'|'error'|'warning'|'info' (default 'info'),
  //           durationMs: number (default 4000, 0 = persist),
  //           action: { label, onClick } }
  // Returns { dismiss() }.
  function ensureToastStack() {
    var stack = document.querySelector('.clx-toast-stack');
    if (stack) return stack;
    stack = document.createElement('div');
    stack.className = 'clx-toast-stack';
    document.body.appendChild(stack);
    return stack;
  }

  function toast(message, opts) {
    opts = opts || {};
    var variant = opts.variant || 'info';
    var duration = (opts.durationMs == null) ? 4000 : opts.durationMs;
    var stack = ensureToastStack();
    var el = document.createElement('div');
    el.className = 'clx-toast clx-toast-' + variant;
    el.setAttribute('role', variant === 'error' ? 'alert' : 'status');
    var msgSpan = document.createElement('span');
    msgSpan.className = 'clx-toast-msg';
    msgSpan.textContent = String(message == null ? '' : message);
    el.appendChild(msgSpan);
    if (opts.action && opts.action.label) {
      var actionBtn = document.createElement('button');
      actionBtn.type = 'button';
      actionBtn.className = 'clx-toast-action';
      actionBtn.textContent = opts.action.label;
      actionBtn.addEventListener('click', function () {
        try { opts.action.onClick && opts.action.onClick(); } catch (e) {}
        dismiss();
      });
      el.appendChild(actionBtn);
    }
    var closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'clx-toast-close';
    closeBtn.setAttribute('aria-label', 'Dismiss');
    closeBtn.innerHTML = '&times;';
    closeBtn.addEventListener('click', function () { dismiss(); });
    el.appendChild(closeBtn);
    stack.appendChild(el);
    // Trigger CSS enter transition on next frame.
    requestAnimationFrame(function () { el.classList.add('clx-toast-in'); });
    var timer = null;
    if (duration > 0) {
      timer = setTimeout(function () { dismiss(); }, duration);
    }
    function dismiss() {
      if (timer) { clearTimeout(timer); timer = null; }
      el.classList.remove('clx-toast-in');
      el.classList.add('clx-toast-out');
      setTimeout(function () {
        if (el.parentNode) el.parentNode.removeChild(el);
      }, 200);
    }
    return { dismiss: dismiss };
  }

  // dialog({ title, body, actions, dismissable }) — modal with backdrop +
  // focus trap + ESC close. body may be a string (rendered as HTML) or a
  // DOM node. actions is an array of { label, variant ('primary'|'danger'
  // |'ghost'), onClick (return false to keep open, anything else closes) }.
  // Returns { close(value), promise } — promise resolves with the value
  // passed to close() (or null on backdrop / ESC dismiss).
  function dialog(opts) {
    opts = opts || {};
    var dismissable = opts.dismissable !== false;
    var backdrop = document.createElement('div');
    backdrop.className = 'clx-dialog-backdrop';
    var box = document.createElement('div');
    box.className = 'clx-dialog';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-modal', 'true');
    if (opts.title) box.setAttribute('aria-label', String(opts.title));
    var html = '';
    if (opts.title) {
      html += '<div class="clx-dialog-head"><div class="clx-dialog-title">' + escapeHtml(opts.title) + '</div>';
      if (dismissable) html += '<button type="button" class="clx-dialog-x" aria-label="Close">&times;</button>';
      html += '</div>';
    }
    html += '<div class="clx-dialog-body"></div>';
    if (opts.actions && opts.actions.length) {
      html += '<div class="clx-dialog-actions"></div>';
    }
    box.innerHTML = html;
    var bodyEl = box.querySelector('.clx-dialog-body');
    if (opts.body instanceof Node) bodyEl.appendChild(opts.body);
    else bodyEl.innerHTML = String(opts.body == null ? '' : opts.body);
    var actionsEl = box.querySelector('.clx-dialog-actions');
    var resolveFn = null;
    var promise = new Promise(function (r) { resolveFn = r; });
    function close(value) {
      backdrop.classList.add('clx-dialog-out');
      setTimeout(function () {
        if (backdrop.parentNode) backdrop.parentNode.removeChild(backdrop);
        document.removeEventListener('keydown', onKey, true);
        if (prevFocus && prevFocus.focus) { try { prevFocus.focus(); } catch (e) {} }
      }, 180);
      resolveFn(value == null ? null : value);
    }
    if (actionsEl && opts.actions) {
      opts.actions.forEach(function (a) {
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'clx-dialog-btn clx-dialog-btn-' + (a.variant || 'ghost');
        btn.textContent = a.label || '';
        btn.addEventListener('click', function () {
          var result = a.onClick ? a.onClick() : undefined;
          if (result === false) return; // caller wants to keep open
          close(a.value != null ? a.value : a.label);
        });
        actionsEl.appendChild(btn);
      });
    }
    var xBtn = box.querySelector('.clx-dialog-x');
    if (xBtn) xBtn.addEventListener('click', function () { close(null); });
    if (dismissable) {
      backdrop.addEventListener('click', function (e) {
        if (e.target === backdrop) close(null);
      });
    }
    function onKey(e) {
      if (e.key === 'Escape' && dismissable) { e.stopPropagation(); close(null); }
      if (e.key === 'Tab') {
        // Simple focus trap: cycle focus within the dialog.
        var focusables = box.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
        if (!focusables.length) return;
        var first = focusables[0], last = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    }
    var prevFocus = document.activeElement;
    backdrop.appendChild(box);
    document.body.appendChild(backdrop);
    requestAnimationFrame(function () { backdrop.classList.add('clx-dialog-in'); });
    document.addEventListener('keydown', onKey, true);
    // Focus first action (typically the primary).
    var firstBtn = box.querySelector('.clx-dialog-btn-primary, .clx-dialog-btn-danger, .clx-dialog-btn, .clx-dialog-x');
    if (firstBtn) setTimeout(function () { firstBtn.focus(); }, 50);
    return { close: close, promise: promise };
  }

  // confirm(message, opts?) — convenience wrapper around dialog() that
  // returns a promise<boolean>. Drop-in for window.confirm.
  //   opts: { title, confirmLabel ('Confirm'), cancelLabel ('Cancel'),
  //           variant ('primary' | 'danger') }
  function confirmDialog(message, opts) {
    opts = opts || {};
    var d = dialog({
      title: opts.title || 'Confirm',
      body: '<div style="font-size:14px;color:var(--text-secondary);line-height:1.5;">' + escapeHtml(message) + '</div>',
      actions: [
        { label: opts.cancelLabel || 'Cancel', variant: 'ghost',   value: false },
        { label: opts.confirmLabel || 'Confirm', variant: opts.variant || 'primary', value: true }
      ]
    });
    return d.promise.then(function (v) { return v === true; });
  }

  // dropdown(triggerEl, items, opts?) — anchored popover menu with
  // keyboard navigation. items: [{ label, onClick, variant?, disabled? }]
  // or { separator: true }. Returns { open(), close(), toggle() }.
  function dropdown(triggerEl, items, opts) {
    opts = opts || {};
    var menu = null;
    function close() {
      if (!menu) return;
      menu.classList.remove('clx-dropdown-in');
      var m = menu;
      menu = null;
      setTimeout(function () { if (m.parentNode) m.parentNode.removeChild(m); }, 120);
      document.removeEventListener('keydown', onKey, true);
      document.removeEventListener('mousedown', onOutside, true);
    }
    function onOutside(e) {
      if (menu && !menu.contains(e.target) && e.target !== triggerEl) close();
    }
    function onKey(e) {
      if (!menu) return;
      if (e.key === 'Escape') { e.preventDefault(); close(); return; }
      var focusables = Array.prototype.slice.call(menu.querySelectorAll('button.clx-dropdown-item:not([disabled])'));
      if (!focusables.length) return;
      var idx = focusables.indexOf(document.activeElement);
      if (e.key === 'ArrowDown') { e.preventDefault(); focusables[(idx + 1) % focusables.length].focus(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); focusables[(idx - 1 + focusables.length) % focusables.length].focus(); }
    }
    function open() {
      close();
      menu = document.createElement('div');
      menu.className = 'clx-dropdown';
      menu.setAttribute('role', 'menu');
      items.forEach(function (it) {
        if (it.separator) {
          var sep = document.createElement('div');
          sep.className = 'clx-dropdown-sep';
          menu.appendChild(sep);
          return;
        }
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'clx-dropdown-item' + (it.variant ? ' clx-dropdown-item-' + it.variant : '');
        if (it.disabled) btn.disabled = true;
        btn.setAttribute('role', 'menuitem');
        btn.textContent = it.label || '';
        btn.addEventListener('click', function () {
          if (it.disabled) return;
          try { it.onClick && it.onClick(); } catch (e) {}
          close();
        });
        menu.appendChild(btn);
      });
      // Position below the trigger, right-aligned by default.
      var rect = triggerEl.getBoundingClientRect();
      menu.style.position = 'fixed';
      menu.style.top  = (rect.bottom + 6) + 'px';
      var align = opts.align || 'right';
      if (align === 'left') menu.style.left = rect.left + 'px';
      else                  menu.style.right = (window.innerWidth - rect.right) + 'px';
      document.body.appendChild(menu);
      requestAnimationFrame(function () { menu.classList.add('clx-dropdown-in'); });
      document.addEventListener('keydown', onKey, true);
      document.addEventListener('mousedown', onOutside, true);
      var first = menu.querySelector('button.clx-dropdown-item:not([disabled])');
      if (first) setTimeout(function () { first.focus(); }, 30);
    }
    function toggle() { menu ? close() : open(); }
    triggerEl.addEventListener('click', function (e) { e.preventDefault(); toggle(); });
    return { open: open, close: close, toggle: toggle };
  }

  // tabs(container, tabsDef, opts?) — formalize the tab pattern already
  // sprinkled across sentinel.html / market-intelligence.html. Renders
  // the tab strip + manages active state. The caller still owns the
  // pane content; this function only manipulates display:none on the
  // pane elements identified by `paneId`.
  //
  //   tabsDef: [{ key, label, paneId, onActivate? }]
  //   opts: { initialKey, onChange }
  // Returns { setActive(key), getActive() }.
  function tabs(container, tabsDef, opts) {
    opts = opts || {};
    if (!container || !tabsDef || !tabsDef.length) return null;
    container.classList.add('clx-tabs');
    container.innerHTML = '';
    var current = opts.initialKey || tabsDef[0].key;
    tabsDef.forEach(function (t) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'clx-tab-btn' + (t.key === current ? ' clx-tab-active' : '');
      btn.setAttribute('data-tab-key', t.key);
      btn.setAttribute('role', 'tab');
      btn.textContent = t.label;
      btn.addEventListener('click', function () { setActive(t.key); });
      container.appendChild(btn);
    });
    function syncPanes() {
      tabsDef.forEach(function (t) {
        if (!t.paneId) return;
        var pane = document.getElementById(t.paneId);
        if (!pane) return;
        pane.style.display = (t.key === current) ? '' : 'none';
      });
    }
    function setActive(key) {
      if (key === current) return;
      current = key;
      var btns = container.querySelectorAll('.clx-tab-btn');
      btns.forEach(function (b) {
        b.classList.toggle('clx-tab-active', b.getAttribute('data-tab-key') === key);
      });
      syncPanes();
      var def = tabsDef.find(function (t) { return t.key === key; });
      if (def && def.onActivate) { try { def.onActivate(); } catch (e) {} }
      if (opts.onChange) { try { opts.onChange(key); } catch (e) {} }
    }
    syncPanes();
    return { setActive: setActive, getActive: function () { return current; } };
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
    sectionHead: sectionHead,
    injectChat: injectChat,
    injectNavArrows: injectNavArrows,
    /* Polish v2 primitives */
    toast: toast,
    dialog: dialog,
    confirm: confirmDialog,
    dropdown: dropdown,
    tabs: tabs
  };

  /* ───────────────────────────────────────────────────────────────
     Browser-style back/forward arrows in the admin topbar.
     Injects next to the burger button. Wires history.back / history.forward
     and disables each button when at the end of the history stack.
     Auto-injects on DOMContentLoaded.
     ─────────────────────────────────────────────────────────────── */
  function injectNavArrows() {
    var topbarLeft = document.querySelector('.clx-topbar-left');
    if (!topbarLeft) return;
    if (topbarLeft.querySelector('.clx-nav-arrows')) return;

    var wrap = document.createElement('div');
    wrap.className = 'clx-nav-arrows';
    wrap.innerHTML =
      '<button type="button" id="clxNavBack" aria-label="Back">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"></polyline></svg>' +
      '</button>' +
      '<button type="button" id="clxNavFwd" aria-label="Forward">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"></polyline></svg>' +
      '</button>';

    // Insert right after the burger (or at start if no burger)
    var burger = topbarLeft.querySelector('.clx-burger');
    if (burger) {
      burger.insertAdjacentElement('afterend', wrap);
    } else {
      topbarLeft.insertAdjacentElement('afterbegin', wrap);
    }

    var backBtn = document.getElementById('clxNavBack');
    var fwdBtn  = document.getElementById('clxNavFwd');

    function updateState() {
      // history.length includes the current page. If it's 1, no back possible.
      // There is no clean API to detect forward availability; we leave it
      // enabled and rely on the browser to no-op when there's nothing forward.
      if (backBtn) backBtn.disabled = (history.length <= 1);
    }

    if (backBtn) backBtn.addEventListener('click', function () { history.back(); });
    if (fwdBtn)  fwdBtn.addEventListener('click',  function () { history.forward(); });

    updateState();
    window.addEventListener('popstate', updateState);
  }

  // Auto-inject arrows once auth resolves + topbar is in DOM
  if (window.CLX_AUTO_NAV_ARROWS !== false) {
    var arrowTries = 0;
    var arrowTimer = setInterval(function () {
      arrowTries++;
      if (document.querySelector('.clx-topbar-left')) {
        clearInterval(arrowTimer);
        injectNavArrows();
      } else if (arrowTries > 20) {
        clearInterval(arrowTimer);
      }
    }, 250);
  }

  // ───────────────────────────────────────────────────────────────
  // Floating chat widget — Mary's MCP-style assistant. Lives bottom-right
  // on every admin page; opens a panel that POSTs to admin/chat.
  // v1: text Q&A. v2 adds tool execution + action confirmation.
  // ───────────────────────────────────────────────────────────────
  function injectChat() {
    if (document.getElementById('clxChatRoot')) return;
    var root = document.createElement('div');
    root.id = 'clxChatRoot';
    root.innerHTML = ''
      + '<style>'
      + '#clxChatBtn{position:fixed;bottom:24px;right:24px;width:56px;height:56px;border-radius:50%;background:#0f4c81;color:#fff;border:none;cursor:pointer;box-shadow:0 6px 24px rgba(15,76,129,0.4);z-index:9998;display:flex;align-items:center;justify-content:center;transition:transform 0.15s;}'
      + '#clxChatBtn:hover{transform:scale(1.06);}'
      + '#clxChatBtn svg{width:24px;height:24px;}'
      + '#clxChatPanel{position:fixed;bottom:92px;right:24px;width:380px;max-width:calc(100vw - 48px);height:560px;max-height:calc(100vh - 120px);background:#fff;border:1px solid #e5e7eb;border-radius:12px;box-shadow:0 12px 48px rgba(0,0,0,0.18);z-index:9999;display:none;flex-direction:column;overflow:hidden;}'
      + '#clxChatPanel.open{display:flex;}'
      + '.clx-chat-head{padding:14px 16px;border-bottom:1px solid #e5e7eb;display:flex;align-items:center;justify-content:space-between;background:linear-gradient(135deg,#0f4c81 0%,#1a6fa5 100%);color:#fff;}'
      + '.clx-chat-head-title{font-size:14px;font-weight:700;}'
      + '.clx-chat-head-sub{font-size:11px;opacity:0.85;margin-top:2px;}'
      + '.clx-chat-close{background:none;border:none;color:#fff;cursor:pointer;font-size:20px;line-height:1;opacity:0.9;}'
      + '.clx-chat-close:hover{opacity:1;}'
      + '.clx-chat-body{flex:1;overflow-y:auto;padding:14px;background:#f9fafb;}'
      + '.clx-chat-msg{margin-bottom:10px;display:flex;}'
      + '.clx-chat-msg.user{justify-content:flex-end;}'
      + '.clx-chat-bubble{max-width:80%;padding:8px 12px;border-radius:12px;font-size:13px;line-height:1.45;white-space:pre-wrap;word-wrap:break-word;}'
      + '.clx-chat-msg.user .clx-chat-bubble{background:#0f4c81;color:#fff;border-bottom-right-radius:4px;}'
      + '.clx-chat-msg.assistant .clx-chat-bubble{background:#fff;color:#0f172a;border:1px solid #e5e7eb;border-bottom-left-radius:4px;}'
      + '.clx-chat-msg.system .clx-chat-bubble{background:#fef3c7;color:#92400e;font-size:12px;border:1px solid #fde68a;}'
      + '.clx-chat-typing{display:inline-block;}'
      + '.clx-chat-typing span{display:inline-block;width:6px;height:6px;border-radius:50%;background:#9ca3af;margin:0 2px;animation:clx-bounce 1.2s infinite ease-in-out;}'
      + '.clx-chat-typing span:nth-child(2){animation-delay:0.15s;}'
      + '.clx-chat-typing span:nth-child(3){animation-delay:0.3s;}'
      + '@keyframes clx-bounce{0%,80%,100%{opacity:0.3;transform:translateY(0);}40%{opacity:1;transform:translateY(-4px);}}'
      + '.clx-chat-foot{border-top:1px solid #e5e7eb;padding:10px 12px;background:#fff;}'
      + '.clx-chat-input{width:100%;border:1px solid #d1d5db;border-radius:8px;padding:8px 12px;font-size:13px;font-family:inherit;resize:none;outline:none;min-height:40px;max-height:120px;}'
      + '.clx-chat-input:focus{border-color:#0f4c81;}'
      + '.clx-chat-foot-actions{display:flex;justify-content:space-between;align-items:center;margin-top:6px;}'
      + '.clx-chat-hint{font-size:10px;color:#6b7280;}'
      + '.clx-chat-send{background:#0f4c81;color:#fff;border:none;padding:6px 14px;border-radius:6px;font-size:12px;font-weight:600;cursor:pointer;}'
      + '.clx-chat-send:disabled{background:#9ca3af;cursor:not-allowed;}'
      + '</style>'
      + '<button id="clxChatBtn" aria-label="Open assistant">'
      +   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
      +     '<path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"></path>'
      +   '</svg>'
      + '</button>'
      + '<div id="clxChatPanel" role="dialog" aria-label="Crystallux assistant">'
      +   '<div class="clx-chat-head">'
      +     '<div>'
      +       '<div class="clx-chat-head-title">Crystallux Assistant</div>'
      +       '<div class="clx-chat-head-sub">Ask anything about your platform</div>'
      +     '</div>'
      +     '<button class="clx-chat-close" id="clxChatClose" aria-label="Close">&times;</button>'
      +   '</div>'
      +   '<div class="clx-chat-body" id="clxChatBody"></div>'
      +   '<div class="clx-chat-foot">'
      +     '<textarea class="clx-chat-input" id="clxChatInput" placeholder="Ask me anything…" rows="1"></textarea>'
      +     '<div class="clx-chat-foot-actions">'
      +       '<div class="clx-chat-hint">Press Enter to send · Shift+Enter for newline</div>'
      +       '<button class="clx-chat-send" id="clxChatSend">Send</button>'
      +     '</div>'
      +   '</div>'
      + '</div>';
    document.body.appendChild(root);

    var btn      = document.getElementById('clxChatBtn');
    var panel    = document.getElementById('clxChatPanel');
    var closeBtn = document.getElementById('clxChatClose');
    var body     = document.getElementById('clxChatBody');
    var input    = document.getElementById('clxChatInput');
    var sendBtn  = document.getElementById('clxChatSend');

    var history = [];
    var sending = false;
    var historyLoaded = false;

    function open() {
      panel.classList.add('open');
      setTimeout(function () { input.focus(); }, 100);
      if (historyLoaded) return;
      historyLoaded = true;
      // Load persisted history from server. Empty -> greeting.
      clxApi.adminPost('chat/history', {}).then(function (res) {
        if (res.ok && res.data && Array.isArray(res.data.messages) && res.data.messages.length) {
          res.data.messages.forEach(function (m) { appendMsg(m.role, m.content); });
        } else {
          appendMsg('assistant', 'Hi Mary. I can help you understand what is happening on the platform, suggest next steps, or explain how to use features. What is on your mind?');
        }
      }).catch(function () {
        appendMsg('assistant', 'Hi Mary. I can help you understand what is happening on the platform, suggest next steps, or explain how to use features. What is on your mind?');
      });
    }
    function close() { panel.classList.remove('open'); }
    btn.addEventListener('click', function () {
      if (panel.classList.contains('open')) close(); else open();
    });
    closeBtn.addEventListener('click', close);

    function appendMsg(role, text) {
      history.push({ role: role, content: text });
      var msg = document.createElement('div');
      msg.className = 'clx-chat-msg ' + role;
      var bub = document.createElement('div');
      bub.className = 'clx-chat-bubble';
      bub.textContent = text;
      msg.appendChild(bub);
      body.appendChild(msg);
      body.scrollTop = body.scrollHeight;
    }

    function appendTyping() {
      var msg = document.createElement('div');
      msg.className = 'clx-chat-msg assistant';
      msg.id = 'clxChatTyping';
      var bub = document.createElement('div');
      bub.className = 'clx-chat-bubble';
      bub.innerHTML = '<span class="clx-chat-typing"><span></span><span></span><span></span></span>';
      msg.appendChild(bub);
      body.appendChild(msg);
      body.scrollTop = body.scrollHeight;
    }
    function removeTyping() {
      var t = document.getElementById('clxChatTyping');
      if (t) t.parentNode.removeChild(t);
    }

    function send() {
      if (sending) return;
      var text = input.value.trim();
      if (!text) return;
      input.value = '';
      appendMsg('user', text);
      sending = true;
      sendBtn.disabled = true;
      appendTyping();
      clxApi.adminPost('chat', { message: text }).then(function (res) {
        removeTyping();
        sending = false;
        sendBtn.disabled = false;
        if (res.ok && res.data && res.data.response) {
          appendMsg('assistant', res.data.response);
        } else {
          appendMsg('system', res.error || (res.data && res.data.error) || 'Something went wrong. Please try again.');
        }
      }).catch(function () {
        removeTyping();
        sending = false;
        sendBtn.disabled = false;
        appendMsg('system', 'Could not reach the assistant. Check network or n8n.');
      });
    }

    sendBtn.addEventListener('click', send);
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        send();
      }
    });
  }

  // Auto-inject after auth resolves. Each admin page calls
  // clxAuth.require(...) which populates window.clxAuth.user; we poll
  // briefly for that to land, then inject once. Pages that don't want the
  // chat can set window.CLX_AUTO_CHAT = false before loading components.js.
  if (window.CLX_AUTO_CHAT !== false) {
    var injectTries = 0;
    var injectTimer = setInterval(function () {
      injectTries++;
      if (window.clxAuth && window.clxAuth.user && window.clxAuth.user.user_role === 'admin') {
        clearInterval(injectTimer);
        injectChat();
      } else if (injectTries > 20) {
        // Stop polling after ~10 seconds; non-admin pages just don't get the widget
        clearInterval(injectTimer);
      }
    }, 500);
  }
})(window);
