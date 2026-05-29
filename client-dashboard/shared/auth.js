/* ═══ Crystallux Client Dashboard — auth.js ══════════════════════════
   Session validation + page-load gate for app.crystallux.org.
   Identical interface to the admin dashboard's auth.js, but:
     - require('client') redirects ADMINS to admin.crystallux.org
       rather than to login (Mary's not stuck in a loop if she
       lands here by mistake).
     - exposes clxAuth.user.client_id for use by every page (the
       server-side webhook still re-derives client_id from session,
       but having it client-side avoids extra round-trips for
       link generation, etc.)

   Access gates (added 2026-05-29 after Paul's first signup):
     - is_active=false → server already 403s; we surface a clean
       /suspended.html page instead of dumping to login.
     - email_verified=false → redirect to /verify-email.html unless
       the page itself opts out (data-clx-allow-unverified="true" on <html>).
     - requireProduct('sentinel') / hasProduct('sales_engine') gate
       per-product sections so a Starter customer can't see Ava etc.
   =================================================================== */

(function (global) {
  'use strict';

  var LOGIN_URL     = 'https://crystallux.org/login.html';
  var ADMIN_URL     = 'https://admin.crystallux.org/';
  var VERIFY_URL    = 'https://crystallux.org/verify-email.html';
  var SUSPENDED_URL = 'https://crystallux.org/account-suspended.html';
  var VALIDATE      = 'https://automation.crystallux.org/webhook/auth/validate-session';

  function getToken()    { try { return localStorage.getItem('clx_session_token')    || ''; } catch (e) { return ''; } }
  function getRole()     { try { return localStorage.getItem('clx_user_role')        || ''; } catch (e) { return ''; } }
  function getEmail()    { try { return localStorage.getItem('clx_user_email')       || ''; } catch (e) { return ''; } }
  function getClientId() { try { return localStorage.getItem('clx_user_client_id')   || ''; } catch (e) { return ''; } }
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

  function redirectAdmin() {
    window.location.replace(ADMIN_URL);
  }

  function redirectToVerify() {
    var sep = VERIFY_URL.indexOf('?') === -1 ? '?' : '&';
    var next = encodeURIComponent(window.location.href);
    window.location.replace(VERIFY_URL + sep + 'next=' + next);
  }

  function redirectToSuspended() {
    window.location.replace(SUSPENDED_URL);
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
          if (data.user) {
            localStorage.setItem('clx_user_email',     data.user.email     || '');
            localStorage.setItem('clx_user_role',      data.user.role      || '');
            localStorage.setItem('clx_user_client_id', data.user.client_id || '');
            localStorage.setItem('clx_user_products',  JSON.stringify(data.user.products || []));
            localStorage.setItem('clx_user_email_verified',    String(!!data.user.email_verified));
            localStorage.setItem('clx_user_is_active',         String(data.user.is_active !== false));
            localStorage.setItem('clx_user_onboarding_status', data.user.onboarding_status || 'new');
            localStorage.setItem('clx_user_company_name',      data.user.company_name || '');
          }
          if (data.expires_at) localStorage.setItem('clx_session_expires', data.expires_at);
        } catch (e) {}
        return data.user || {};
      });
    }).catch(function (err) {
      return Promise.reject(typeof err === 'string' ? err : 'network');
    });
  }

  function pageAllowsUnverified() {
    return document.documentElement.getAttribute('data-clx-allow-unverified') === 'true';
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
        if (user.role === 'admin') return redirectAdmin();
        return redirectToLogin('wrong-role');
      }
      if ((user.role === 'client' || user.role === 'team_member') && !user.client_id) {
        return redirectToLogin('no-client-id');
      }
      if (user.is_active === false) {
        return redirectToSuspended();
      }
      if (user.email_verified === false && !pageAllowsUnverified()) {
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

  // Per-product gating helpers. `products` is a jsonb array on auth_users.
  // Canonical product keys: 'sales_engine', 'sentinel', 'mga', 'insurance_compare',
  // 'smart_quote', 'ava', 'luxi', 'ciro'. Admins are treated as having every
  // product (so Mary's admin sessions can preview the full dashboard).
  function hasProduct(name) {
    if (!name) return true;
    var user = global.clxAuth.user || {};
    if (user.role === 'admin') return true;
    var products = Array.isArray(user.products) ? user.products : getProducts();
    return products.indexOf(name) !== -1;
  }

  // Page-level guard: call from a page that should only render for a specific
  // product. Hides the body and redirects to /overview.html (the always-visible
  // landing) if the user doesn't have it.
  function requireProduct(name) {
    return new Promise(function (resolve) {
      window.addEventListener('clx:auth:ready', function () {
        if (hasProduct(name)) {
          resolve(global.clxAuth.user);
        } else {
          window.location.replace('/overview.html?denied=' + encodeURIComponent(name));
        }
      }, { once: true });
    });
  }

  // Convenience: hide every element tagged `data-clx-product="<name>"` if the
  // user doesn't own that product. Use on the nav and dashboard tiles.
  function applyProductGates(root) {
    var scope = root || document;
    var nodes = scope.querySelectorAll('[data-clx-product]');
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      var key = n.getAttribute('data-clx-product');
      if (key && !hasProduct(key)) {
        n.setAttribute('hidden', 'hidden');
        n.style.display = 'none';
      }
    }
  }

  // Wire applyProductGates to run automatically after auth resolves so pages
  // don't have to remember.
  window.addEventListener('clx:auth:ready', function () { applyProductGates(); });

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
    requireProduct: requireProduct,
    hasProduct: hasProduct,
    applyProductGates: applyProductGates,
    logout: logout,
    clearSession: clearSession
  };
})(window);
