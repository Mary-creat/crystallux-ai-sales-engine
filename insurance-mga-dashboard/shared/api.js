/* ═══ Crystallux Insurance MGA Dashboard — api.js ════════════════════
   Thin fetch wrapper for the insurance-vertical Layer 2 webhooks.
   All endpoints under /webhook/mga/insurance/* — vertical_id is in
   the URL path, NOT a query parameter (so cross-vertical isolation
   is enforced at the routing layer).

   Pattern:
     clxApi.mgaPost('advisor/overview')
       → POST https://automation.crystallux.org/webhook/mga/insurance/advisor/overview
         body: {}
         headers: { Authorization: Bearer <session-token> }
   =================================================================== */
(function (global) {
  'use strict';
  var BASE = 'https://automation.crystallux.org/webhook/mga/insurance/';

  function getToken() { try { return localStorage.getItem('clx_session_token') || ''; } catch (e) { return ''; } }
  function authHeaders() { var t = getToken(); var h = { 'Content-Type': 'application/json' }; if (t) h['Authorization'] = 'Bearer ' + t; return h; }

  function statusToMessage(status, body) {
    var snippet = (body && body.error) ? String(body.error) : '';
    if (status === 401) return 'Session expired. Please sign in again.';
    if (status === 403) return 'You do not have access to this resource.';
    if (status === 404) return 'Endpoint not found.';
    if (status === 412) return snippet || 'Precondition failed (incomplete prerequisites).';
    if (status === 429) return 'Too many requests. Please slow down.';
    if (status >= 500)  return 'Server error (' + status + '). ' + (snippet || 'Please retry.');
    return snippet || ('Request failed (' + status + ').');
  }

  function call(action, body) {
    var url = BASE + action;
    return fetch(url, { method: 'POST', headers: authHeaders(), body: JSON.stringify(body || {}) })
      .then(function (r) {
        return r.text().then(function (txt) {
          var data = null; try { data = txt ? JSON.parse(txt) : null; } catch (e) {}
          return { ok: r.ok, status: r.status, data: data, error: r.ok ? null : statusToMessage(r.status, data) };
        });
      })
      .catch(function (err) { return { ok: false, status: 0, data: null, error: 'Network error: ' + (err && err.message || err) }; });
  }

  global.clxApi = {
    mgaPost: call,
    formatMoney: function (cents) { var v = (parseInt(cents) || 0) / 100; return '$' + v.toLocaleString('en-CA', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); },
    formatDate: function (isoOrDate) { if (!isoOrDate) return ''; var d = new Date(isoOrDate); if (isNaN(d.getTime())) return String(isoOrDate); return d.toLocaleDateString('en-CA'); },
    relativeTime: function (iso) { if (!iso) return ''; var d = new Date(iso).getTime(); if (isNaN(d)) return ''; var diff = (Date.now() - d) / 1000; if (diff < 60) return 'just now'; if (diff < 3600) return Math.floor(diff/60) + 'm ago'; if (diff < 86400) return Math.floor(diff/3600) + 'h ago'; return Math.floor(diff/86400) + 'd ago'; },
    escapeHtml: function (s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;'); }
  };
})(window);
