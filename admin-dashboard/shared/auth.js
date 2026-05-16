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

   Note on role enforcement:
     The role is also re-checked on every API call by the n8n webhook
     (which trusts only its own validate_session RPC). The role we
     store in localStorage is for UI gating ONLY — never for security.
   =================================================================== */

(function (global) {
  'use strict';

  var LOGIN_URL = 'https://crystallux.org/login.html';
  var APP_URL   = 'https://app.crystallux.org/';
  var VALIDATE  = 'https://automation.crystallux.org/webhook/auth/validate-session';

  function getToken()   { try { return localStorage.getItem('clx_session_token') || ''; } catch (e) { return ''; } }
  function getRole()    { try { return localStorage.getItem('clx_user_role')     || ''; } catch (e) { return ''; } }
  function getEmail()   { try { return localStorage.getItem('clx_user_email')    || ''; } catch (e) { return ''; } }
  function getClientId(){ try { return localStorage.getItem('clx_user_client_id')|| ''; } catch (e) { return ''; } }

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

  function redirectWrongRole() {
    // Admin shell, but the user is logged in as a client. Send them to
    // the client app rather than dropping them at the login screen.
    window.location.replace(APP_URL);
  }

  /**
   * Validate the session against n8n. Resolves with the user object
   * on success, or rejects with a string reason. The window-level
   * gate (require()) ALWAYS redirects on failure — pages should use
   * require(), and only call validate() directly when they want the
   * raw promise.
   */
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
        // Refresh local user fields in case role/client_id changed server-side
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

  /**
   * Page gate. Call as the first thing in <body>:
   *   <script>clxAuth.require('admin')</script>          single role
   *   <script>clxAuth.require(['admin','mga_principal'])</script>  allowlist
   * Hides the page (visibility:hidden via <html data-clx-gate>) until
   * the session is confirmed. On success the body becomes visible and
   * `clxAuth.user` is populated. On failure → redirect.
   */
  function require_(role) {
    // Hide content until validated to prevent UI flash
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
      global.clxAuth.user = user;
      document.documentElement.setAttribute('data-clx-gate', 'ok');
      // Notify pages that auth is ready
      try { window.dispatchEvent(new CustomEvent('clx:auth:ready', { detail: user })); } catch (e) {}
      return user;
    }).catch(function (reason) {
      redirectToLogin(reason);
      // Resolve with a never-settling promise so subsequent .then chains
      // don't fire while the redirect is in flight.
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
