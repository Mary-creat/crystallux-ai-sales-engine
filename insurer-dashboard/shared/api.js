/* ═══ Crystallux Insurer Portal — api.js ════════════════════════════
   READ-ONLY API surface for insurers. All endpoints under
   /webhook/mga/insurance/* with insurer-session auth. Session token
   is in localStorage. The server validates 4-hour expiry on every
   call.
   =================================================================== */
(function (global) {
  'use strict';
  var BASE = 'https://automation.crystallux.org/webhook/mga/insurance/';

  function getToken() { try { return localStorage.getItem('clx_session_token') || ''; } catch (e) { return ''; } }
  function authHeaders() { var t = getToken(); var h = { 'Content-Type': 'application/json' }; if (t) h['Authorization'] = 'Bearer ' + t; return h; }

  function statusToMessage(status, body) {
    var snippet = (body && body.error) ? String(body.error) : '';
    if (status === 401) return 'Your session has expired. Please sign in again.';
    if (status === 403) return 'Your account does not have access to this resource.';
    if (status === 404) return 'Endpoint not found.';
    if (status >= 500)  return 'Server error (' + status + '). ' + (snippet || 'Please retry.');
    return snippet || ('Request failed (' + status + ').');
  }

  function post(action, body) {
    return fetch(BASE + action, { method: 'POST', headers: authHeaders(), body: JSON.stringify(body || {}) })
      .then(function (r) { return r.text().then(function (t) {
        var data = null; try { data = t ? JSON.parse(t) : null; } catch (e) {}
        return { ok: r.ok, status: r.status, data: data, error: r.ok ? null : statusToMessage(r.status, data) };
      }); })
      .catch(function (err) { return { ok: false, status: 0, data: null, error: 'Network error: ' + (err && err.message || err) }; });
  }

  global.clxApi = {
    post: post,
    formatMoney: function (cents) { var v = (parseFloat(cents) || 0) / 100; return '$' + v.toLocaleString('en-CA', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); },
    formatDate: function (iso) { if (!iso) return ''; var d = new Date(iso); if (isNaN(d.getTime())) return String(iso); return d.toLocaleDateString('en-CA'); },
    escapeHtml: function (s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;'); }
  };
})(window);
