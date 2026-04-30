/* ═══ Crystallux Admin Dashboard — api.js ════════════════════════════
   Thin fetch wrapper. Every admin page calls clxApi.adminGet('clients')
   instead of fetch(...) so the session token, error handling, and
   404 / 401 / 403 / 5xx mapping live in one place.

   Pattern:
     clxApi.adminGet('clients', { active: true })
       → POST https://automation.crystallux.org/webhook/admin/clients
         body: { filters: { active: true } }
         headers: { Authorization: Bearer <session-token> }

   Why POST for "list" calls? n8n webhook nodes parse JSON bodies
   trivially; query strings need extra parsing. Using POST also keeps
   tokens out of access logs (they live in the Authorization header
   either way, but query strings end up in proxy logs more often).
   =================================================================== */

(function (global) {
  'use strict';

  var BASE = 'https://automation.crystallux.org/webhook';

  function getToken() {
    try { return localStorage.getItem('clx_session_token') || ''; }
    catch (e) { return ''; }
  }

  function authHeaders() {
    var t = getToken();
    var h = { 'Content-Type': 'application/json' };
    if (t) h['Authorization'] = 'Bearer ' + t;
    return h;
  }

  function statusToMessage(status, body) {
    var snippet = (body && body.error) ? String(body.error) : '';
    if (status === 401) return 'Session expired. Please sign in again.';
    if (status === 403) return 'You do not have access to this resource.';
    if (status === 404) return 'Endpoint not found. ' + (snippet || 'API may not be deployed yet.');
    if (status === 423) return 'Account is locked. Try again later.';
    if (status === 429) return 'Too many requests. Please slow down.';
    if (status >= 500)  return 'Server error (' + status + '). ' + (snippet || 'Please retry.');
    return snippet || ('Request failed (' + status + ').');
  }

  /**
   * Base call. Returns { ok, status, data, error } so callers can
   * branch without try/catch noise. On 401 the caller should redirect
   * to login; the auth.js gate handles re-validation on the next
   * navigation, so we don't auto-redirect here (that would mask
   * intermittent token issues during long-running pages).
   */
  function call(path, payload, options) {
    options = options || {};
    var url = BASE + (path[0] === '/' ? path : '/' + path);
    return fetch(url, {
      method: options.method || 'POST',
      headers: authHeaders(),
      body: JSON.stringify(payload || {})
    }).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (data) {
        if (!res.ok) {
          return { ok: false, status: res.status, data: data || {}, error: statusToMessage(res.status, data) };
        }
        return { ok: true, status: res.status, data: data, error: null };
      });
    }).catch(function (e) {
      return { ok: false, status: 0, data: {}, error: 'Network error. Check your connection.' };
    });
  }

  // Admin namespace — POST /admin/<resource>
  function adminGet(resource, filters) {
    return call('/admin/' + resource, { filters: filters || {} });
  }
  function adminPost(resource, body) {
    return call('/admin/' + resource, body || {});
  }

  // Render an error banner inside any container element. Centralises
  // the styling so panels only need: clxApi.renderError(el, result).
  function renderError(el, result) {
    if (!el) return;
    el.innerHTML = '';
    var div = document.createElement('div');
    div.className = 'clx-error-banner';
    div.textContent = result && result.error ? result.error : 'Request failed.';
    el.appendChild(div);
  }
  function renderEmpty(el, message, icon) {
    if (!el) return;
    el.innerHTML = '<div class="clx-empty"><span class="clx-empty-icon">' +
      (icon || '·') + '</span>' + (message || 'No data yet.') + '</div>';
  }
  function renderLoading(el, label) {
    if (!el) return;
    el.innerHTML = '<div class="clx-loading-row"><span class="clx-spinner"></span> ' +
      (label || 'Loading…') + '</div>';
  }

  global.clxApi = {
    call: call,
    adminGet: adminGet,
    adminPost: adminPost,
    renderError: renderError,
    renderEmpty: renderEmpty,
    renderLoading: renderLoading
  };
})(window);
