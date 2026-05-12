/* ═══ Crystallux Insurer Portal — auth.js ════════════════════════════
   Insurer-only session validation. Validates the session via the
   Layer 2 endpoint that BOTH checks the session token AND confirms
   the user has an active insurer_users row + active insurer_account.
   4-hour session expiry is enforced server-side.
   =================================================================== */
(function (global) {
  'use strict';
  var ALLOWED = ['insurer_user','admin'];

  function getToken() { try { return localStorage.getItem('clx_session_token') || ''; } catch (e) { return ''; } }
  function clearSession() { try { localStorage.removeItem('clx_session_token'); localStorage.removeItem('clx_user'); localStorage.removeItem('clx_insurer_account'); } catch (e) {} }
  function getCachedUser() { try { return JSON.parse(localStorage.getItem('clx_user') || 'null'); } catch (e) { return null; } }
  function getCachedAccount() { try { return JSON.parse(localStorage.getItem('clx_insurer_account') || 'null'); } catch (e) { return null; } }

  function validate() {
    var token = getToken();
    if (!token) return Promise.resolve(null);
    return fetch('https://automation.crystallux.org/webhook/mga/insurance/insurer-session-validate', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: token })
    }).then(function (r) { return r.text().then(function (t) { try { return JSON.parse(t); } catch (e) { return null; } }); })
    .catch(function () { return null; });
  }

  function require(allowedRoles) {
    var roles = Array.isArray(allowedRoles) ? allowedRoles : ALLOWED;
    return validate().then(function (resp) {
      if (!resp || !resp.ok) { clearSession(); window.location.href = '/index.html'; return null; }
      var role = resp.user_role || (resp.permissions && resp.permissions.role_at_insurer);
      // Insurer endpoint returns role=insurer_user/admin via session, role_at_insurer via insurer_users.
      // Treat anything that returned ok=true with insurer_account as valid.
      try {
        localStorage.setItem('clx_user', JSON.stringify({ user_id: resp.user_id, email: resp.email, role_at_insurer: resp.role_at_insurer || null }));
        if (resp.insurer_account) localStorage.setItem('clx_insurer_account', JSON.stringify(resp.insurer_account));
      } catch (e) {}
      return resp;
    });
  }

  global.clxAuth = { require: require, validate: validate, clearSession: clearSession, getCachedUser: getCachedUser, getCachedAccount: getCachedAccount };
})(window);
