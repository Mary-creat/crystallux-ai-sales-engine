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
   =================================================================== */

(function (global) {
  'use strict';

  var LOGIN_URL = 'https://crystallux.org/login.html';
  var ADMIN_URL = 'https://admin.crystallux.org/';
  var VALIDATE  = 'https://automation.crystallux.org/webhook/auth/validate-session';

  function getToken()    { try { return localStorage.getItem('clx_session_token')    || ''; } catch (e) { return ''; } }
  function getRole()     { try { return localStorage.getItem('clx_user_role')        || ''; } catch (e) { return ''; } }
  function getEmail()    { try { return localStorage.getItem('clx_user_email')       || ''; } catch (e) { return ''; } }
  function getClientId() { try { return localStorage.getItem('clx_user_client_id')   || ''; } catch (e) { return ''; } }

  function clearSession() {
    try {
      localStorage.removeItem('clx_session_token');
      localStorage.removeItem('clx_session_expires');
      localStorage.removeItem('clx_user_email');
      localStorage.removeItem('clx_user_role');
      localStorage.removeItem('clx_user_client_id');
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
    // Admin landed on the client dashboard — punt to admin.
    window.location.replace(ADMIN_URL);
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
        if (!res.ok || !data.ok) { return Promise.reject(data.error || ('http-' + res.status)); }
        try {
          if (data.user) {
            localStorage.setItem('clx_user_email',     data.user.email     || '');
            localStorage.setItem('clx_user_role',      data.user.role      || '');
            localStorage.setItem('clx_user_client_id', data.user.client_id || '');
          }
          if (data.expires_at) localStorage.setItem('clx_session_expires', data.expires_at);
        } catch (e) {}
        return data.user || {};
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
      if (role && user.role !== role) {
        if (user.role === 'admin') return redirectAdmin();
        return redirectToLogin('wrong-role');
      }
      // Client/team_member must have a client_id; if missing, treat
      // as a corrupted session.
      if ((user.role === 'client' || user.role === 'team_member') && !user.client_id) {
        return redirectToLogin('no-client-id');
      }
      global.clxAuth.user = user;
      document.documentElement.setAttribute('data-clx-gate', 'ok');
      try { window.dispatchEvent(new CustomEvent('clx:auth:ready', { detail: user })); } catch (e) {}
      return user;
    }).catch(function (reason) {
      redirectToLogin(reason);
      return new Promise(function () {});
    });
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
    validate: validate,
    require: require_,
    logout: logout,
    clearSession: clearSession
  };
})(window);
