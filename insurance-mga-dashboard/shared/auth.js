/* ═══ Crystallux Insurance MGA Dashboard — auth.js ══════════════════
   Session validation + page-load gate for the insurance-vertical
   MGA module. Mirrors admin-dashboard/shared/auth.js but constrains
   the role allowlist to advisor / sub_agent / supervisor /
   mga_principal / compliance_officer / admin (no client / team_member).
   =================================================================== */
(function (global) {
  'use strict';
  var LOGIN_URL = '/login.html';
  var VALIDATE  = 'https://automation.crystallux.org/webhook/auth/validate-session';
  var ALLOWED_ROLES = ['advisor','sub_agent','supervisor','mga_principal','compliance_officer','admin'];

  function getToken()  { try { return localStorage.getItem('clx_session_token') || ''; } catch (e) { return ''; } }
  function getRole()   { try { return localStorage.getItem('clx_user_role')     || ''; } catch (e) { return ''; } }
  function getEmail()  { try { return localStorage.getItem('clx_user_email')    || ''; } catch (e) { return ''; } }
  function getUserId() { try { return localStorage.getItem('clx_user_id')       || ''; } catch (e) { return ''; } }

  function setSession(token, user) {
    try {
      localStorage.setItem('clx_session_token', token);
      if (user) {
        localStorage.setItem('clx_user_email', user.email || '');
        localStorage.setItem('clx_user_role',  user.user_role || user.role || '');
        localStorage.setItem('clx_user_id',    user.id || user.user_id || '');
      }
    } catch (e) {}
  }
  function clearSession() {
    try {
      localStorage.removeItem('clx_session_token');
      localStorage.removeItem('clx_user_email');
      localStorage.removeItem('clx_user_role');
      localStorage.removeItem('clx_user_id');
    } catch (e) {}
  }

  function validate() {
    var token = getToken();
    if (!token) return Promise.resolve(null);
    return fetch(VALIDATE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
      body: JSON.stringify({})
    }).then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) { if (j && j.user) { setSession(token, j.user); return j.user; } return null; })
      .catch(function () { return null; });
  }

  // require(['advisor','mga_principal']) — gate page on role allowlist.
  function require(rolesAllowed) {
    var allowed = Array.isArray(rolesAllowed) ? rolesAllowed : ALLOWED_ROLES;
    return validate().then(function (user) {
      if (!user) { window.location.replace(LOGIN_URL + '?next=' + encodeURIComponent(window.location.pathname)); return null; }
      if (allowed.indexOf(user.user_role || user.role) < 0) {
        window.location.replace(LOGIN_URL + '?error=role_not_permitted');
        return null;
      }
      try { window.dispatchEvent(new CustomEvent('clx:auth:ready', { detail: { user: user } })); } catch (e) {}
      return user;
    });
  }

  global.clxAuth = { getToken: getToken, getRole: getRole, getEmail: getEmail, getUserId: getUserId, setSession: setSession, clearSession: clearSession, validate: validate, require: require, ALLOWED_ROLES: ALLOWED_ROLES };
})(window);
