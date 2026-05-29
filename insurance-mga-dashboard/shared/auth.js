/* ═══ Crystallux Insurance MGA Dashboard — auth.js ══════════════════
   Session validation + page-load gate for the insurance-vertical
   MGA module. Mirrors admin-dashboard/shared/auth.js but constrains
   the role allowlist to advisor / sub_agent / supervisor /
   mga_principal / compliance_officer / admin (no client / team_member).

   Access gates (added 2026-05-29 — parity with client/admin auth.js):
     - is_active=false → crystallux.org/account-suspended.html
     - email_verified=false → crystallux.org/verify-email.html for non-admin roles
   =================================================================== */
(function (global) {
  'use strict';
  var LOGIN_URL     = '/login.html';
  var VERIFY_URL    = 'https://crystallux.org/verify-email.html';
  var SUSPENDED_URL = 'https://crystallux.org/account-suspended.html';
  var VALIDATE      = 'https://automation.crystallux.org/webhook/auth/validate-session';
  var ALLOWED_ROLES = ['advisor','sub_agent','supervisor','mga_principal','compliance_officer','admin'];

  function getToken()  { try { return localStorage.getItem('clx_session_token') || ''; } catch (e) { return ''; } }
  function getRole()   { try { return localStorage.getItem('clx_user_role')     || ''; } catch (e) { return ''; } }
  function getEmail()  { try { return localStorage.getItem('clx_user_email')    || ''; } catch (e) { return ''; } }
  function getUserId() { try { return localStorage.getItem('clx_user_id')       || ''; } catch (e) { return ''; } }
  function getProducts() {
    try {
      var raw = localStorage.getItem('clx_user_products') || '[]';
      var arr = JSON.parse(raw);
      return Array.isArray(arr) ? arr : [];
    } catch (e) { return []; }
  }

  function setSession(token, user) {
    try {
      localStorage.setItem('clx_session_token', token);
      if (user) {
        localStorage.setItem('clx_user_email',  user.email || '');
        localStorage.setItem('clx_user_role',   user.user_role || user.role || '');
        localStorage.setItem('clx_user_id',     user.id || user.user_id || '');
        localStorage.setItem('clx_user_products',       JSON.stringify(user.products || []));
        localStorage.setItem('clx_user_email_verified', String(!!user.email_verified));
        localStorage.setItem('clx_user_is_active',      String(user.is_active !== false));
      }
    } catch (e) {}
  }
  function clearSession() {
    try {
      localStorage.removeItem('clx_session_token');
      localStorage.removeItem('clx_user_email');
      localStorage.removeItem('clx_user_role');
      localStorage.removeItem('clx_user_id');
      localStorage.removeItem('clx_user_products');
      localStorage.removeItem('clx_user_email_verified');
      localStorage.removeItem('clx_user_is_active');
    } catch (e) {}
  }

  function pageAllowsUnverified() {
    return document.documentElement.getAttribute('data-clx-allow-unverified') === 'true';
  }

  function validate() {
    var token = getToken();
    if (!token) return Promise.resolve(null);
    return fetch(VALIDATE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
      body: JSON.stringify({})
    }).then(function (r) {
      if (r.status === 403) {
        window.location.replace(SUSPENDED_URL);
        return new Promise(function () {});
      }
      return r.ok ? r.json() : null;
    })
      .then(function (j) { if (j && j.user) { setSession(token, j.user); return j.user; } return null; })
      .catch(function () { return null; });
  }

  // require(['advisor','mga_principal']) — gate page on role allowlist.
  function require(rolesAllowed) {
    var allowed = Array.isArray(rolesAllowed) ? rolesAllowed : ALLOWED_ROLES;
    return validate().then(function (user) {
      if (!user) { window.location.replace(LOGIN_URL + '?next=' + encodeURIComponent(window.location.pathname)); return null; }
      var role = user.user_role || user.role;
      if (allowed.indexOf(role) < 0) {
        window.location.replace(LOGIN_URL + '?error=role_not_permitted');
        return null;
      }
      if (user.is_active === false) {
        window.location.replace(SUSPENDED_URL);
        return null;
      }
      if (role !== 'admin' && user.email_verified === false && !pageAllowsUnverified()) {
        var sep = VERIFY_URL.indexOf('?') === -1 ? '?' : '&';
        window.location.replace(VERIFY_URL + sep + 'next=' + encodeURIComponent(window.location.href));
        return null;
      }
      global.clxAuth.user = user;
      try { window.dispatchEvent(new CustomEvent('clx:auth:ready', { detail: { user: user } })); } catch (e) {}
      return user;
    });
  }

  function hasProduct(name) {
    if (!name) return true;
    var user = global.clxAuth.user || {};
    var role = user.user_role || user.role;
    if (role === 'admin') return true;
    var products = Array.isArray(user.products) ? user.products : getProducts();
    return products.indexOf(name) !== -1;
  }

  global.clxAuth = {
    user: null,
    getToken: getToken, getRole: getRole, getEmail: getEmail, getUserId: getUserId,
    getProducts: getProducts, setSession: setSession, clearSession: clearSession,
    validate: validate, require: require, hasProduct: hasProduct,
    ALLOWED_ROLES: ALLOWED_ROLES
  };
})(window);
