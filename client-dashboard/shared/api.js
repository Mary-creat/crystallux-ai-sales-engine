/* ═══ Crystallux Client Dashboard — api.js ═══════════════════════════
   Thin fetch wrapper. ALL data comes from /webhook/client/<resource>
   webhooks. Each webhook reads client_id FROM THE SESSION ROW, never
   from the request body — this is the cross-tenant isolation anchor.

   Browser-side helpers here NEVER pass client_id. If a future panel
   ever needs it (e.g. for link generation), it should pull it from
   clxAuth.user.client_id, NOT pass it in the request body — the
   server will overwrite anything the browser sends anyway.
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
    }).catch(function () {
      return { ok: false, status: 0, data: {}, error: 'Network error. Check your connection.' };
    });
  }

  // Client namespace — POST /client/<resource>
  // We deliberately do NOT take or forward a client_id. The webhook
  // derives it from the session.
  function clientGet(resource, filters) {
    return call('/client/' + resource, { filters: filters || {} });
  }
  function clientPost(resource, body) {
    // Even on writes, we strip any client_id sent by the caller. The
    // server will overwrite, but defence-in-depth.
    var clean = Object.assign({}, body || {});
    delete clean.client_id;
    return call('/client/' + resource, clean);
  }

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
      (icon || '·') + '</span>' + (message || 'Nothing to show yet.') + '</div>';
  }
  function renderLoading(el, label) {
    if (!el) return;
    el.innerHTML = '<div class="clx-loading-row"><span class="clx-spinner"></span> ' +
      (label || 'Loading…') + '</div>';
  }

  global.clxApi = {
    call: call,
    clientGet: clientGet,
    clientPost: clientPost,
    renderError: renderError,
    renderEmpty: renderEmpty,
    renderLoading: renderLoading
  };
})(window);
