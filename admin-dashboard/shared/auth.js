/* ═══ Crystallux Admin Dashboard — auth.js ═══════════════════════════
   Session validation + page-load gate. Loaded as the FIRST script on
   every admin page. If the user is not a valid admin session, the
   page is redirected to crystallux.org/login before the rest of the
   page renders.

   Storage:
     localStorage.clx_session_token     opaque 64-char token
     localStorage.clx_session_expires   ISO8601 string (informational)
     localStorage.clx_user_email
     localStorage.clx_user_role         see role inventory below
     localStorage.clx_user_client_id    UUID or empty
     localStorage.clx_user_products     JSON array of product keys
     localStorage.clx_user_is_active    'true' | 'false'
     localStorage.clx_user_email_verified 'true' | 'false'

   Role inventory (what pages actually call `require()` with — keep in
   sync when adding a new role to a page):
     admin              — Mary; full operational access to admin shell
     client             — tenant user on app.crystallux.org
     team_member        — tenant teammate (same shell as client, scoped by client_id)
     supervisor         — training oversight (client-side training pages)
     mga_principal      — MGA dashboard principal view
     compliance_officer — MGA compliance gate
     advisor            — LLQP advisor (MGA dashboard)
     sub_agent          — advisor's sub-agent (MGA dashboard)
     client_admin       — admin within a client tenant (content pages)
     client_user        — non-admin user within a client tenant (content pages)
   `require()` accepts either a single role string ('admin') or an
   array (['admin','mga_principal']); the array form is preferred for
   pages shared across role sets.

   Access gates (added 2026-05-29 — parity with client-dashboard/shared/auth.js):
     - is_active=false → server already 403s; bounced to /account-suspended.html
     - email_verified=false → /verify-email.html for non-admin roles only.
       Admins are exempt (admin signup flow sets email_verified=true; if a
       legacy admin row has it false, we don't want to lock Mary out of admin
       while she's actively fixing things).

   Note on role enforcement:
     The role is also re-checked on every API call by the n8n webhook
     (which trusts only its own validate_session RPC). The role we
     store in localStorage is for UI gating ONLY — never for security.
   =================================================================== */

(function (global) {
  'use strict';

  var LOGIN_URL     = 'https://crystallux.org/login.html';
  var APP_URL       = 'https://app.crystallux.org/';
  var VERIFY_URL    = 'https://crystallux.org/verify-email.html';
  var SUSPENDED_URL = 'https://crystallux.org/account-suspended.html';
  var VALIDATE      = 'https://automation.crystallux.org/webhook/auth/validate-session';

  function getToken()   { try { return localStorage.getItem('clx_session_token') || ''; } catch (e) { return ''; } }
  function getRole()    { try { return localStorage.getItem('clx_user_role')     || ''; } catch (e) { return ''; } }
  function getEmail()   { try { return localStorage.getItem('clx_user_email')    || ''; } catch (e) { return ''; } }
  function getClientId(){ try { return localStorage.getItem('clx_user_client_id')|| ''; } catch (e) { return ''; } }
  function getProducts() {
    try {
      var raw = localStorage.getItem('clx_user_products') || '[]';
      var arr = JSON.parse(raw);
      return Array.isArray(arr) ? arr : [];
    } catch (e) { return []; }
  }

  function clearSession() {
    try {
      localStorage.removeItem('clx_session_token');
      localStorage.removeItem('clx_session_expires');
      localStorage.removeItem('clx_user_email');
      localStorage.removeItem('clx_user_role');
      localStorage.removeItem('clx_user_client_id');
      localStorage.removeItem('clx_user_products');
      localStorage.removeItem('clx_user_email_verified');
      localStorage.removeItem('clx_user_is_active');
      localStorage.removeItem('clx_user_onboarding_status');
      localStorage.removeItem('clx_user_company_name');
    } catch (e) {}
  }

  function redirectToLogin(reason) {
    clearSession();
    var sep = LOGIN_URL.indexOf('?') === -1 ? '?' : '&';
    var next = encodeURIComponent(window.location.href);
    var why  = reason ? '&why=' + encodeURIComponent(reason) : '';
    window.location.replace(LOGIN_URL + sep + 'next=' + next + why);
  }

  function redirectWrongRole() {
    window.location.replace(APP_URL);
  }

  function redirectToVerify() {
    var sep = VERIFY_URL.indexOf('?') === -1 ? '?' : '&';
    var next = encodeURIComponent(window.location.href);
    window.location.replace(VERIFY_URL + sep + 'next=' + next);
  }

  function redirectToSuspended() {
    window.location.replace(SUSPENDED_URL);
  }

  function pageAllowsUnverified() {
    return document.documentElement.getAttribute('data-clx-allow-unverified') === 'true';
  }

  function validate() {
    var token = getToken();
    if (!token) return Promise.reject('no-token');
    return fetch(VALIDATE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
      body: JSON.stringify({})
    }).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (data) {
        if (res.status === 403) { return Promise.reject('suspended'); }
        if (!res.ok || !data.ok) { return Promise.reject(data.error || ('http-' + res.status)); }
        try {
        // The endpoint returns a FLAT object, not { user: {...} }:
        //   { ok, user_id, email, user_role, client_id, expires_at,
        //     is_active, email_verified, products, onboarding_status,
        //     company_name }
        //
        // This code read data.user.role. data.user does not exist, so the
        // whole block was skipped, validate() returned {}, user.role was
        // undefined, and require_() sent the browser back to login --
        // every time, for every account. A successful sign-in looked
        // exactly like a rejected one: session created server-side,
        // bounced client-side, login page again.
        //
        // It also explains docs/audit/client-audit-report.md reporting
        // 0/7 pages passing with every screenshot identical: the Playwright
        // run could not get past this either, and photographed the login
        // page seven times.
        //
        // Both shapes are accepted so a future nested response does not
        // break it back, and user_role/role are both read for the same
        // reason.
        var u = data.user || data;
        var role = u.role || u.user_role || '';
        if (u && (u.email || u.user_id || u.client_id)) {
            localStorage.setItem('clx_user_email',     u.email     || '');
            localStorage.setItem('clx_user_role',      role);
            localStorage.setItem('clx_user_client_id', u.client_id || '');
            localStorage.setItem('clx_user_products',  JSON.stringify(u.products || []));
            localStorage.setItem('clx_user_email_verified',    String(!!u.email_verified));
            localStorage.setItem('clx_user_is_active',         String(u.is_active !== false));
            localStorage.setItem('clx_user_onboarding_status', u.onboarding_status || 'new');
            localStorage.setItem('clx_user_company_name',      u.company_name || '');
          }
          if (data.expires_at) localStorage.setItem('clx_session_expires', data.expires_at);
        } catch (e) {}
        // Normalised on the way out: require_() and every page read
        // user.role, so it must exist whatever the server called it.
        return {
          user_id: u.user_id || u.id || null,
          email: u.email || '',
          role: role,
          client_id: u.client_id || null,
          products: u.products || [],
          is_active: u.is_active !== false,
          email_verified: !!u.email_verified,
          onboarding_status: u.onboarding_status || 'new',
          company_name: u.company_name || null
        };
      });
    }).catch(function (err) {
      return Promise.reject(typeof err === 'string' ? err : 'network');
    });
  }

  function require_(role) {
    document.documentElement.setAttribute('data-clx-gate', 'pending');
    var styleId = 'clx-gate-style';
    if (!document.getElementById(styleId)) {
      var s = document.createElement('style');
      s.id = styleId;
      s.textContent = '[data-clx-gate="pending"] body{visibility:hidden}';
      document.head.appendChild(s);
    }
    return validate().then(function (user) {
      var allowed = role ? (Array.isArray(role) ? role : [role]) : null;
      if (allowed && allowed.indexOf(user.role) === -1) {
        if (user.role === 'client') return redirectWrongRole();
        return redirectToLogin('wrong-role');
      }
      if (user.is_active === false) {
        return redirectToSuspended();
      }
      // Email-verified enforcement: admins are exempt (legacy admin rows may
      // have email_verified=false; we don't want Mary locked out of the admin
      // shell). Every other role is bounced to /verify-email.html.
      if (user.role !== 'admin' && user.email_verified === false && !pageAllowsUnverified()) {
        return redirectToVerify();
      }
      global.clxAuth.user = user;
      document.documentElement.setAttribute('data-clx-gate', 'ok');
      try { window.dispatchEvent(new CustomEvent('clx:auth:ready', { detail: user })); } catch (e) {}
      return user;
    }).catch(function (reason) {
      if (reason === 'suspended') return redirectToSuspended();
      redirectToLogin(reason);
      return new Promise(function () {});
    });
  }

  // Per-product helpers. Admins always pass; other roles consult the
  // products array. Exported for consistency with client-dashboard auth.js.
  function hasProduct(name) {
    if (!name) return true;
    var user = global.clxAuth.user || {};
    if (user.role === 'admin') return true;
    var products = Array.isArray(user.products) ? user.products : getProducts();
    return products.indexOf(name) !== -1;
  }

  function logout() {
    var token = getToken();
    var done = function () {
      clearSession();
      window.location.replace(LOGIN_URL);
    };
    if (!token) { done(); return; }
    fetch('https://automation.crystallux.org/webhook/auth/logout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
      body: JSON.stringify({})
    }).then(done, done);
  }

  global.clxAuth = {
    user: null,
    getToken: getToken,
    getRole: getRole,
    getEmail: getEmail,
    getClientId: getClientId,
    getProducts: getProducts,
    validate: validate,
    require: require_,
    hasProduct: hasProduct,
    logout: logout,
    clearSession: clearSession
  };
})(window);
