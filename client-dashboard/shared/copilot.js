/* ═══════════════════════════════════════════════════════════════════
   Crystallux Client Assistant — read-only chat + voice surface,
   tenant-scoped to the signed-in client.

   Differences from the admin copilot:
   - Auth: session bearer token (clxAuth.getToken()) — NOT MARY_MASTER_TOKEN.
     The backend webhook validates the session, derives client_id from
     the session row, and scopes every Claude prompt to that tenant.
   - One mode only (Q&A about my own pipeline). No SQL display, no
     troubleshoot, no full-DB query — those are admin surfaces by design.
   - Voice input via the same Whisper backend (the workflow accepts
     either MARY_MASTER_TOKEN or a valid session token).
   - FAB lives above the mobile bottom-nav (z-index + bottom offset).

   Boots only when clxAuth.require('client') resolves.
   =================================================================== */

(function (global) {
  'use strict';

  var N8N_BASE = global.CLX_N8N_BASE || 'https://automation.crystallux.org';

  // Endpoints (TODO: workflow JSON pending — see docs/audit/blockers.md
  // "Client Assistant workflow"). Until the workflow exists in n8n, the
  // FAB will return a friendly "not yet activated" message instead of
  // erroring out.
  var ASK_ENDPOINT       = '/webhook/client/copilot/ask';
  var TRANSCRIBE_ENDPOINT = '/webhook/client/copilot/transcribe';

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function bearerHeader() {
    var t = (global.clxAuth && global.clxAuth.getToken && global.clxAuth.getToken()) || '';
    return t ? ('Bearer ' + t) : '';
  }

  var SUGGESTIONS = [
    'How many leads do I have?',
    'Which leads replied this week?',
    'What\'s my conversion rate?',
    'Show me upcoming bookings.',
    'Which campaigns are performing best?'
  ];

  var copilot = {
    history: [],
    recorder: null,
    chunks: [],

    mount: function () {
      if (document.getElementById('clxCopilotFab')) {
        global.__clxCopilotState = 'already-mounted';
        return;
      }
      // Inline critical positioning — same belt-and-suspenders pattern as
      // admin: the FAB renders correctly even if the stylesheet's
      // cascade is shadowed somewhere. Mobile breakpoint (<640px) bumps
      // the bottom offset above the bottom-nav via the CSS rule; inline
      // styles guarantee the desktop default.
      var fab = document.createElement('button');
      fab.className = 'clx-copilot-fab show';
      fab.id = 'clxCopilotFab';
      fab.type = 'button';
      fab.setAttribute('aria-label', 'Open Crystallux Assistant');
      fab.title = 'Crystallux Assistant';
      fab.textContent = '✦';
      var fabBottom = (window.innerWidth <= 640) ? '78px' : '24px';
      fab.style.cssText = [
        'position:fixed','bottom:' + fabBottom,'right:24px','z-index:120',
        'width:56px','height:56px','border-radius:50%','cursor:pointer',
        'background:linear-gradient(135deg,#7C3AED,#5B21B6)',
        'border:none','color:#fff','font-size:22px',
        'box-shadow:0 6px 20px rgba(124,58,237,0.45)',
        'display:flex','align-items:center','justify-content:center',
        'transition:transform .15s ease','line-height:1','font-family:inherit'
      ].join(';');
      fab.addEventListener('click', function () { copilot.toggle(); });
      fab.addEventListener('mouseenter', function () { fab.style.transform = 'scale(1.06)'; });
      fab.addEventListener('mouseleave', function () { fab.style.transform = ''; });
      document.body.appendChild(fab);

      var panel = document.createElement('aside');
      panel.className = 'clx-copilot-panel';
      panel.id = 'clxCopilotPanel';
      panel.setAttribute('aria-label', 'Crystallux Assistant');
      panel.style.cssText = [
        'position:fixed','top:0','right:0','height:100vh',
        'width:420px','max-width:100vw','z-index:130',
        'background:#fff','border-left:1px solid #E4E4E7',
        'box-shadow:-8px 0 30px rgba(0,0,0,0.10)',
        'transform:translateX(100%)','transition:transform .25s ease',
        'display:flex','flex-direction:column'
      ].join(';');
      panel.innerHTML =
        '<div class="clx-copilot-header">' +
          '<div class="clx-copilot-title"><span class="star">✦</span> Crystallux Assistant</div>' +
          '<button class="clx-copilot-close" aria-label="Close" id="clxCopilotClose">×</button>' +
        '</div>' +
        '<div class="clx-copilot-body" id="clxCopilotBody"></div>' +
        '<div class="clx-copilot-input-row">' +
          '<button class="clx-copilot-voice" id="clxCopilotVoice" title="Voice (max 60s)" type="button">🎤</button>' +
          '<input class="clx-copilot-input" id="clxCopilotInput" type="text" placeholder="Ask about your pipeline…" />' +
          '<button class="clx-copilot-send" id="clxCopilotSend" type="button">Send</button>' +
        '</div>';
      document.body.appendChild(panel);

      document.getElementById('clxCopilotClose').addEventListener('click', function () { copilot.toggle(); });
      document.getElementById('clxCopilotSend').addEventListener('click', function () { copilot.send(); });
      document.getElementById('clxCopilotVoice').addEventListener('click', function () { copilot.toggleVoice(); });
      document.getElementById('clxCopilotInput').addEventListener('keydown', function (e) {
        if (e.key === 'Enter') copilot.send();
      });

      // Restore prior session history
      try {
        var raw = sessionStorage.getItem('clx_client_copilot_history');
        if (raw) copilot.history = JSON.parse(raw) || [];
      } catch (e) {}
      copilot.renderHistory();
    },

    toggle: function (forceOpen) {
      var panel = document.getElementById('clxCopilotPanel');
      if (!panel) return;
      var isOpen;
      if (forceOpen === true) {
        panel.classList.add('open');
        isOpen = true;
      } else {
        isOpen = panel.classList.toggle('open');
      }
      panel.style.transform = isOpen ? 'translateX(0)' : 'translateX(100%)';
      if (isOpen) {
        setTimeout(function () {
          var inp = document.getElementById('clxCopilotInput');
          if (inp) inp.focus();
        }, 100);
      }
    },

    renderHistory: function () {
      var body = document.getElementById('clxCopilotBody');
      if (!body) return;
      var html = '';
      if (!copilot.history.length) {
        html = '<div class="clx-copilot-msg assistant">' +
          '<div class="role">Assistant</div>' +
          'Hi! I can answer questions about <strong>your pipeline</strong>: leads, replies, bookings, campaigns. ' +
          'I never see other clients\' data. Try one of these:' +
          '<div class="clx-copilot-suggestions">' +
            SUGGESTIONS.map(function (s) {
              return '<button class="clx-copilot-suggestion" data-q="' + escapeHtml(s) + '">' + escapeHtml(s) + '</button>';
            }).join('') +
          '</div>' +
        '</div>';
      } else {
        html = copilot.history.map(function (m) {
          var role = m.role === 'user' ? 'You' : 'Assistant';
          var cls  = m.role === 'user' ? 'user' : 'assistant';
          var content = escapeHtml(m.text || '');
          if (m.rows && Array.isArray(m.rows) && m.rows.length) {
            content += '<pre>' + escapeHtml(JSON.stringify(m.rows.slice(0, 10), null, 2)) + '</pre>';
          }
          return '<div class="clx-copilot-msg ' + cls + '"><div class="role">' + role + '</div>' + content + '</div>';
        }).join('');
      }
      body.innerHTML = html;
      // Wire suggestion chips
      body.querySelectorAll('.clx-copilot-suggestion').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var inp = document.getElementById('clxCopilotInput');
          if (inp) {
            inp.value = btn.getAttribute('data-q') || '';
            copilot.send();
          }
        });
      });
      body.scrollTop = body.scrollHeight;
    },

    persist: function () {
      try { sessionStorage.setItem('clx_client_copilot_history', JSON.stringify(copilot.history)); } catch (e) {}
    },

    send: function () {
      var inp = document.getElementById('clxCopilotInput');
      if (!inp) return;
      var question = (inp.value || '').trim();
      if (!question) return;

      var auth = bearerHeader();
      if (!auth) {
        copilot.history.push({ role: 'assistant', text: 'Please sign in again — your session has expired.' });
        copilot.renderHistory();
        return;
      }

      inp.value = '';
      copilot.history.push({ role: 'user', text: question });
      copilot.history.push({ role: 'assistant', text: 'Thinking…' });
      copilot.renderHistory();
      copilot.persist();

      fetch(N8N_BASE + ASK_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': auth },
        body: JSON.stringify({ question: question })
      })
        .then(function (r) {
          if (r.status === 404) {
            return { _not_activated: true };
          }
          return r.json().catch(function () { return { ok: false, error: 'invalid response' }; });
        })
        .then(function (data) {
          copilot.history.pop(); // remove "Thinking…"
          if (data && data._not_activated) {
            copilot.history.push({
              role: 'assistant',
              text: 'The Assistant isn\'t activated yet for your account. Crystallux is finalising the rollout — you\'ll be notified by email when it goes live. Until then, every dashboard panel works as normal.'
            });
          } else if (data && data._unauthorized) {
            copilot.history.push({ role: 'assistant', text: 'Session expired — please sign in again.' });
          } else if (data && data.ok === false) {
            copilot.history.push({ role: 'assistant', text: 'Sorry, I couldn\'t answer that: ' + (data.error || 'unknown error') + '.' });
          } else {
            copilot.history.push({
              role: 'assistant',
              text: (data && (data.answer || data.explanation)) || 'No result.',
              rows: (data && data.rows) || null
            });
          }
          copilot.renderHistory();
          copilot.persist();
        })
        .catch(function (e) {
          copilot.history.pop();
          copilot.history.push({
            role: 'assistant',
            text: 'Network error: ' + (e && e.message || String(e)) + '. Try again in a moment.'
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
      var auth = bearerHeader();
      if (!auth) { alert('Session expired — sign in again.'); return; }
      var form = new FormData();
      form.append('audio', blob, 'recording.webm');
      fetch(N8N_BASE + TRANSCRIBE_ENDPOINT, {
        method: 'POST',
        headers: { 'Authorization': auth },
        body: form
      })
        .then(function (r) {
          if (r.status === 404) return { _not_activated: true };
          return r.json().catch(function () { return { ok: false, error: 'invalid response' }; });
        })
        .then(function (data) {
          if (data && data._not_activated) {
            alert('Voice input isn\'t activated yet for client accounts. Coming soon.');
            return;
          }
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

  global.__clxCopilotState = 'pre-boot';

  function boot() {
    global.__clxCopilotState = 'booting';
    if (!global.clxAuth || typeof global.clxAuth.require !== 'function') {
      global.__clxCopilotState = 'no-clxAuth';
      return;
    }
    var resolved = false;
    var ALLOWED = ['client', 'team_member', 'advisor', 'supervisor', 'mga_principal'];
    var onAuthReady = function (e) {
      if (resolved) return;
      resolved = true;
      var user = e && e.detail;
      if (user && ALLOWED.indexOf(user.role) !== -1) {
        global.__clxCopilotState = 'mounting-via-event';
        try { copilot.mount(); global.__clxCopilotState = 'mounted'; }
        catch (err) { global.__clxCopilotState = 'mount-error: ' + err.message; }
      } else {
        global.__clxCopilotState = 'event-non-tenant';
      }
    };
    window.addEventListener('clx:auth:ready', onAuthReady);

    setTimeout(function () {
      if (resolved) return;
      global.clxAuth.require('client').then(function (user) {
        if (resolved) return;
        resolved = true;
        if (!user || ALLOWED.indexOf(user.role) === -1) {
          global.__clxCopilotState = 'require-non-tenant';
          return;
        }
        global.__clxCopilotState = 'mounting-via-require';
        try { copilot.mount(); global.__clxCopilotState = 'mounted'; }
        catch (err) { global.__clxCopilotState = 'mount-error: ' + err.message; }
      }).catch(function (err) {
        global.__clxCopilotState = 'require-rejected: ' + (err && err.message || err);
      });
    }, 200);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  global.clxClientCopilot = copilot;
})(window);
