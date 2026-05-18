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

  function statusToMessage(status, body, rawText) {
    var snippet = (body && body.error) ? String(body.error) : '';
    if (status === 401) return 'Session expired. Please sign in again.';
    if (status === 403) return 'You do not have access to this resource.';
    if (status === 404) return 'Endpoint not found. The workflow may not be imported or activated in n8n yet.';
    if (status === 423) return 'Account is locked. Try again later.';
    if (status === 429) return 'Too many requests. Please slow down.';
    if (status >= 500) {
      // n8n itself errors out with an HTML body before the workflow runs;
      // workflow-level errors return JSON. Distinguish so the operator
      // knows whether to look at n8n logs or the workflow's output.
      var looksHtml = rawText && /^\s*<!DOCTYPE|^\s*<html/i.test(rawText);
      if (looksHtml) {
        return 'n8n returned an internal error (HTTP ' + status + '). ' +
               'This is a server-side failure before the workflow ran — ' +
               'check `docker logs n8n` on the VPS.';
      }
      return 'Server error (' + status + '). ' + (snippet || 'Please retry.');
    }
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
    // Display path (e.g. "/maxi/industries") — used by renderError as the
    // small grey line so operators see WHICH call failed without DevTools.
    var displayPath = path[0] === '/' ? path : '/' + path;

    return fetch(url, {
      method: options.method || 'POST',
      headers: authHeaders(),
      body: JSON.stringify(payload || {})
    }).then(function (res) {
      // Read body once as text so 500-from-n8n HTML errors are inspectable;
      // attempt JSON parse without losing the original.
      return res.text().then(function (txt) {
        var data = null;
        try { data = txt ? JSON.parse(txt) : null; } catch (e) { data = null; }
        if (!res.ok) {
          return {
            ok: false, status: res.status,
            data: data || {},
            error: statusToMessage(res.status, data, txt),
            _path: displayPath, _url: url
          };
        }
        return {
          ok: true, status: res.status, data: data || {}, error: null,
          _path: displayPath, _url: url
        };
      });
    }).catch(function (e) {
      // TypeError on fetch is the browser's CORS / DNS / offline / cert
      // signal — it intentionally doesn't tell us which one for security.
      // The shape is the only cue: a thrown TypeError (vs e.g. AbortError)
      // is the "request never made it to the server" case.
      var isNetwork = e && (e.name === 'TypeError' || /Failed to fetch|NetworkError/i.test(String(e && e.message)));
      var msg = isNetwork
        ? 'Could not reach ' + displayPath + '. Likely causes: workflow not imported / not active, CORS blocked (check n8n CORS allowlist), or offline.'
        : ('Request failed: ' + (e && e.message || e));
      return { ok: false, status: 0, data: {}, error: msg, _path: displayPath, _url: url };
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
  // Shows the human message + a small grey line with the path + HTTP
  // status, so operators can self-diagnose without DevTools.
  function renderError(el, result) {
    if (!el) return;
    el.innerHTML = '';
    var div = document.createElement('div');
    div.className = 'clx-error-banner';

    var msg = document.createElement('div');
    msg.textContent = result && result.error ? result.error : 'Request failed.';
    div.appendChild(msg);

    if (result && (result._path || result.status)) {
      var diag = document.createElement('div');
      diag.style.cssText = 'margin-top:6px;font-size:11px;color:#9ca3af;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;';
      var parts = [];
      if (result._path) parts.push(result._path);
      if (result.status) parts.push('HTTP ' + result.status);
      diag.textContent = parts.join(' · ');
      div.appendChild(diag);
    }

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
