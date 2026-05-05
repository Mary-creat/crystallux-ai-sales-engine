/* ═══════════════════════════════════════════════════════════════════
   Crystallux Copilot — admin-only chat / MCP / voice surface.
   Auto-mounts on every admin page that loads this script. Hidden for
   non-admin sessions. Backend: clx-copilot-{query,troubleshoot,
   platform,whisper}-v1 + clx-mcp-tool-gateway. Spec: OPERATIONS_HANDBOOK §22.

   Usage: just add `<script src="/shared/copilot.js"></script>` after
   /shared/auth.js + /shared/api.js + /shared/components.js. The script
   waits for clxAuth to resolve, checks the role, then injects DOM.
   =================================================================== */

(function (global) {
  'use strict';

  var N8N_BASE = global.CLX_N8N_BASE || 'https://automation.crystallux.org';

  // The 4 copilot workflows + the whisper transcribe path validate
  // body.token against MARY_MASTER_TOKEN env var (per the legacy
  // dashboard contract). The new dashboards don't have access to env
  // vars, so the master token is stored in localStorage on first use
  // (admin enters it once via the FAB prompt). It's NOT the per-session
  // dashboard auth token — the two are separate by design.
  var TOKEN_KEY = 'clx_mary_master_token';

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function readToken()  { try { return localStorage.getItem(TOKEN_KEY) || ''; } catch (e) { return ''; } }
  function writeToken(t) { try { localStorage.setItem(TOKEN_KEY, t); } catch (e) {} }
  function clearToken() { try { localStorage.removeItem(TOKEN_KEY); } catch (e) {} }

  var copilot = {
    history: [],
    recorder: null,
    chunks: [],

    mount: function () {
      // FAB
      var fab = document.createElement('button');
      fab.className = 'clx-copilot-fab show';
      fab.id = 'clxCopilotFab';
      fab.setAttribute('aria-label', 'Open Copilot (Ctrl+K)');
      fab.title = 'Open Copilot (Ctrl+K)';
      fab.textContent = '✦';
      fab.addEventListener('click', function () { copilot.toggle(); });
      document.body.appendChild(fab);

      // Slide-out panel
      var panel = document.createElement('aside');
      panel.className = 'clx-copilot-panel';
      panel.id = 'clxCopilotPanel';
      panel.setAttribute('aria-label', 'Crystallux Copilot');
      panel.innerHTML =
        '<div class="clx-copilot-header">' +
          '<div class="clx-copilot-title"><span class="star">✦</span> Crystallux Copilot</div>' +
          '<button class="clx-copilot-close" aria-label="Close" id="clxCopilotClose">×</button>' +
        '</div>' +
        '<div class="clx-copilot-mode">' +
          '<span>Mode</span>' +
          '<select id="clxCopilotMode">' +
            '<option value="auto">Auto-detect</option>' +
            '<option value="query">Database query</option>' +
            '<option value="troubleshoot">Troubleshoot error</option>' +
            '<option value="platform">Platform Q&amp;A</option>' +
          '</select>' +
        '</div>' +
        '<div class="clx-copilot-body" id="clxCopilotBody"></div>' +
        '<div class="clx-copilot-input-row">' +
          '<button class="clx-copilot-voice" id="clxCopilotVoice" title="Record voice (max 60s)" type="button">🎤</button>' +
          '<input class="clx-copilot-input" id="clxCopilotInput" type="text" placeholder="Ask anything… (Ctrl+K)" />' +
          '<button class="clx-copilot-send" id="clxCopilotSend" type="button">Send</button>' +
        '</div>';
      document.body.appendChild(panel);

      document.getElementById('clxCopilotClose').addEventListener('click', function () { copilot.toggle(); });
      document.getElementById('clxCopilotSend').addEventListener('click', function () { copilot.send(); });
      document.getElementById('clxCopilotVoice').addEventListener('click', function () { copilot.toggleVoice(); });
      document.getElementById('clxCopilotInput').addEventListener('keydown', function (e) {
        if (e.key === 'Enter') copilot.send();
      });

      // Ctrl+K / Cmd+K
      window.addEventListener('keydown', function (e) {
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
          e.preventDefault();
          copilot.toggle(true);
        }
      });

      // Restore prior session history
      try {
        var raw = sessionStorage.getItem('clx_copilot_history');
        if (raw) copilot.history = JSON.parse(raw) || [];
      } catch (e) {}
      copilot.renderHistory();
    },

    toggle: function (forceOpen) {
      var panel = document.getElementById('clxCopilotPanel');
      if (!panel) return;
      if (forceOpen === true) panel.classList.add('open');
      else panel.classList.toggle('open');
      if (panel.classList.contains('open')) {
        setTimeout(function () {
          var inp = document.getElementById('clxCopilotInput');
          if (inp) inp.focus();
        }, 100);
        // First-open token check
        if (!readToken()) copilot.promptForToken();
      }
    },

    promptForToken: function () {
      var body = document.getElementById('clxCopilotBody');
      if (!body) return;
      // Only show if not already on screen
      if (document.getElementById('clxCopilotTokenPrompt')) return;
      var div = document.createElement('div');
      div.className = 'clx-copilot-token-prompt';
      div.id = 'clxCopilotTokenPrompt';
      div.innerHTML =
        '<strong>Master token required.</strong><br>' +
        'Copilot uses the <code>MARY_MASTER_TOKEN</code> from n8n env. ' +
        'Paste it once below and we\'ll cache it in this browser.' +
        '<input type="password" id="clxCopilotTokenInput" placeholder="MARY_MASTER_TOKEN…" />' +
        '<button id="clxCopilotTokenSave">Save</button>';
      body.insertBefore(div, body.firstChild);
      document.getElementById('clxCopilotTokenSave').addEventListener('click', function () {
        var v = (document.getElementById('clxCopilotTokenInput').value || '').trim();
        if (!v) return;
        writeToken(v);
        div.parentNode.removeChild(div);
      });
    },

    renderHistory: function () {
      var body = document.getElementById('clxCopilotBody');
      if (!body) return;
      // Preserve any token prompt that may be open
      var tokenPrompt = document.getElementById('clxCopilotTokenPrompt');
      var html = '';
      if (!copilot.history.length) {
        html = '<div class="clx-copilot-msg assistant"><div class="role">Copilot</div>' +
               'Hi Mary. Ask a database question, describe an error, or ask about Crystallux platform capabilities. ' +
               'Press <code>Ctrl+K</code> from anywhere to open me. Voice input — click 🎤.</div>';
      } else {
        html = copilot.history.map(function (m) {
          var role = m.role === 'user' ? 'You' : 'Copilot';
          var cls  = m.role === 'user' ? 'user' : 'assistant';
          var content = escapeHtml(m.text || '');
          if (m.sql)  content += '<pre>' + escapeHtml(m.sql) + '</pre>';
          if (m.rows && Array.isArray(m.rows) && m.rows.length) {
            content += '<pre>' + escapeHtml(JSON.stringify(m.rows.slice(0, 10), null, 2)) + '</pre>';
          }
          return '<div class="clx-copilot-msg ' + cls + '">' +
                 '<div class="role">' + role + '</div>' + content + '</div>';
        }).join('');
      }
      body.innerHTML = html;
      if (tokenPrompt) body.insertBefore(tokenPrompt, body.firstChild);
      body.scrollTop = body.scrollHeight;
    },

    persist: function () {
      try { sessionStorage.setItem('clx_copilot_history', JSON.stringify(copilot.history)); } catch (e) {}
    },

    detectMode: function (q) {
      var s = (q || '').toLowerCase();
      if (/(how many|count|show me|list|top \d+|sum|average|which clients|which leads)/.test(s)) return 'query';
      if (/(error|broke|broken|failing|failed|fix|troubleshoot|stuck)/.test(s)) return 'troubleshoot';
      return 'platform';
    },

    send: function () {
      var inp = document.getElementById('clxCopilotInput');
      var modeEl = document.getElementById('clxCopilotMode');
      if (!inp || !modeEl) return;
      var question = (inp.value || '').trim();
      if (!question) return;

      var token = readToken();
      if (!token) { copilot.promptForToken(); return; }

      var mode = modeEl.value || 'auto';
      var effectiveMode = (mode === 'auto') ? copilot.detectMode(question) : mode;

      inp.value = '';
      copilot.history.push({ role: 'user', text: question });
      copilot.history.push({ role: 'assistant', text: 'Thinking (mode: ' + effectiveMode + ')…' });
      copilot.renderHistory();
      copilot.persist();

      var endpoint = {
        query:        '/webhook/copilot/query',
        troubleshoot: '/webhook/copilot/troubleshoot',
        platform:     '/webhook/copilot/platform'
      }[effectiveMode];

      var hash = (window.location.pathname || '').split('/').pop().replace('.html', '') || 'overview';
      var payload = (effectiveMode === 'troubleshoot')
        ? { token: token, description: question }
        : { token: token, question: question, panel_context: hash };

      fetch(N8N_BASE + endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
        .then(function (r) { return r.json().catch(function () { return { ok: false, error: 'invalid response' }; }); })
        .then(function (data) {
          // Replace placeholder
          copilot.history.pop();
          if (data && data._unauthorized) {
            copilot.history.push({ role: 'assistant', text: 'Master token rejected. Close + reopen the Copilot panel to re-enter it, or reset it from the Settings page.' });
            clearToken();
          } else if (effectiveMode === 'query') {
            copilot.history.push({
              role: 'assistant',
              text: data.explanation || data.answer || 'No result.',
              sql:  data.sql || null,
              rows: data.rows || []
            });
          } else if (effectiveMode === 'troubleshoot') {
            var d = (data && data.diagnosis) || {};
            copilot.history.push({
              role: 'assistant',
              text: (d.root_cause ? ('Root cause: ' + d.root_cause + '\n\n') : '') +
                    (d.suggested_fix || data.answer || 'No diagnosis returned.'),
              sql:  d.sql_to_execute_if_any || null
            });
          } else {
            copilot.history.push({ role: 'assistant', text: (data && data.answer) || JSON.stringify(data) });
          }
          copilot.renderHistory();
          copilot.persist();
        })
        .catch(function (e) {
          copilot.history.pop();
          copilot.history.push({
            role: 'assistant',
            text: 'Copilot error: ' + (e && e.message || String(e)) +
                  '. Confirm the 4 copilot workflows are active in n8n and the Anthropic credential is bound.'
          });
          copilot.renderHistory();
          copilot.persist();
        });
    },

    toggleVoice: function () {
      var btn = document.getElementById('clxCopilotVoice');
      if (!btn) return;
      if (copilot.recorder && copilot.recorder.state === 'recording') {
        copilot.recorder.stop();
        btn.classList.remove('recording');
        return;
      }
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        alert('Voice input requires a browser with microphone API support.');
        return;
      }
      navigator.mediaDevices.getUserMedia({ audio: true }).then(function (stream) {
        copilot.recorder = new MediaRecorder(stream);
        copilot.chunks = [];
        copilot.recorder.ondataavailable = function (e) { copilot.chunks.push(e.data); };
        copilot.recorder.onstop = function () {
          var blob = new Blob(copilot.chunks, { type: copilot.recorder.mimeType || 'audio/webm' });
          stream.getTracks().forEach(function (t) { t.stop(); });
          copilot.transcribeAndFill(blob);
        };
        copilot.recorder.start();
        btn.classList.add('recording');
        // Auto-stop at 60s
        setTimeout(function () {
          if (copilot.recorder && copilot.recorder.state === 'recording') {
            copilot.recorder.stop();
            btn.classList.remove('recording');
          }
        }, 60000);
      }).catch(function (e) {
        alert('Microphone access denied or unavailable: ' + (e && e.message || e));
      });
    },

    transcribeAndFill: function (blob) {
      var token = readToken();
      if (!token) { copilot.promptForToken(); return; }
      var form = new FormData();
      form.append('audio', blob, 'recording.webm');
      form.append('token', token);
      fetch(N8N_BASE + '/webhook/copilot/transcribe', { method: 'POST', body: form })
        .then(function (r) { return r.json().catch(function () { return { ok: false, error: 'invalid response' }; }); })
        .then(function (data) {
          if (data && data.ok && data.text) {
            var inp = document.getElementById('clxCopilotInput');
            if (inp) { inp.value = data.text; inp.focus(); }
          } else {
            alert('Transcription failed: ' + ((data && data.error) || 'unknown error'));
          }
        })
        .catch(function (e) { alert('Transcription error: ' + (e && e.message || e)); });
    }
  };

  // Boot only when admin is authenticated. clxAuth.require resolves
  // with the user object; .role is the gate. Defer until DOMContent
  // so document.body exists.
  function boot() {
    if (!global.clxAuth || typeof global.clxAuth.require !== 'function') return;
    global.clxAuth.require('admin').then(function (user) {
      if (!user || user.role !== 'admin') return;
      copilot.mount();
    }).catch(function () { /* not authenticated, do nothing */ });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  // Expose for debugging / Settings page (e.g., reset master token)
  global.clxCopilot = copilot;
})(window);
