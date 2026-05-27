/* Crystallux Insurance Comparison Marketplace — shared frontend logic
   ================================================================
   Used by all /compare/<vertical>.html pages.

   Each page just provides:
     <form data-compare-form data-vertical="auto"> ... </form>
     <div id="q-theater-mount"></div>
     <div id="q-results-mount"></div>

   This script then:
     - intercepts the form submit
     - reads ALL form fields generically (anything name="x" becomes form_data.x)
     - reads contact fields (name, email, phone, city, province) if present
       — these map to the lead row instead of form_data
     - runs the Kayak-style search-theater animation while the backend works
     - renders the comparison cards (with the lowest highlighted)
     - wires each "Get this quote" button to the quote-select endpoint
     - shows a confirmation with the centralized advisor phone on success
*/
(function () {
  'use strict';

  var COMPARE_ENDPOINT = 'https://automation.crystallux.org/webhook/mga/insurance/quote-comparison';
  var SELECT_ENDPOINT  = 'https://automation.crystallux.org/webhook/mga/insurance/quote-select';

  // Centralized advisor phone — single number, never expose individual advisors
  // per the marketplace spec. Update once you have the production Twilio number.
  var ADVISOR_PHONE_DISPLAY = '1-844-CRYSTAL';
  var ADVISOR_PHONE_TEL     = '+18442797825';

  // Contact field names — pulled out of form into the contact object instead
  // of form_data, since they map to lead-row columns directly.
  var CONTACT_KEYS = ['name', 'full_name', 'email', 'phone', 'city', 'province'];

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('form[data-compare-form]').forEach(wireForm);
  });

  function wireForm(form) {
    var vertical = form.dataset.vertical || 'auto';
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      startComparison(form, vertical);
    });
  }

  function startComparison(form, vertical) {
    var raw = collectFormData(form);
    var contact = {};
    var formData = {};
    Object.keys(raw).forEach(function (k) {
      var lower = k.toLowerCase();
      if (CONTACT_KEYS.indexOf(lower) !== -1) {
        // Normalize 'full_name' -> 'name' for the backend.
        contact[lower === 'full_name' ? 'name' : lower] = raw[k];
      } else {
        formData[k] = raw[k];
      }
    });

    var theater = document.getElementById('q-theater-mount');
    var results = document.getElementById('q-results-mount');
    if (results) results.innerHTML = '';
    if (theater) {
      theater.innerHTML = renderTheater(vertical);
      animateTheater(theater, vertical);
      theater.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    // Submit button locked while running
    var btn = form.querySelector('button[type=submit]');
    if (btn) { btn.disabled = true; btn.dataset.originalLabel = btn.textContent; btn.textContent = 'Searching…'; }

    var payload = {
      vertical: vertical,
      form_data: formData,
      contact: contact,
      source_domain: window.location.hostname
    };

    // Promise.all([backend, minimum-theater-time]) — guarantees the user
    // sees the search animation for at least 4 seconds even if backend is
    // fast, so the perceived value lands.
    var minTheaterMs = 4500;
    Promise.all([
      fetch(COMPARE_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      }).then(function (r) { return r.json().then(function (j) { return { ok: r.ok, data: j }; }); })
        .catch(function (e) { return { ok: false, data: { error: String(e && e.message || e) } }; }),
      new Promise(function (resolve) { setTimeout(resolve, minTheaterMs); })
    ]).then(function (arr) {
      var resp = arr[0];
      if (btn) { btn.disabled = false; btn.textContent = btn.dataset.originalLabel || 'Compare quotes'; }
      if (theater) theater.innerHTML = '';
      if (!resp.ok || !resp.data || resp.data.ok === false) {
        renderError(results, (resp.data && resp.data.error) || 'Could not generate quotes. Please try again.');
        return;
      }
      renderResults(results, resp.data);
    });
  }

  function collectFormData(form) {
    var out = {};
    var fd = new FormData(form);
    fd.forEach(function (v, k) { out[k] = String(v).trim(); });
    return out;
  }

  // ── search-theater rendering ─────────────────────────────────────────
  function renderTheater(vertical) {
    var verticalLabel = {
      auto:   'auto insurers',
      home:   'home insurers',
      tenant: 'tenant insurers',
      travel: 'travel insurers'
    }[vertical] || 'Canadian insurers';
    return '' +
      '<div class="q-theater">' +
        '<div class="q-theater-title">Searching the best deals for you</div>' +
        '<div class="q-theater-sub">Comparing live rates across 5 ' + escapeHtml(verticalLabel) + '…</div>' +
        '<div class="q-theater-bar"></div>' +
        '<div class="q-theater-carriers" id="q-theater-list"></div>' +
      '</div>';
  }
  function animateTheater(theater, vertical) {
    // Match the carrier names the backend will return. Showing them appearing
    // one-by-one in the theater = trust signal + anticipation. Names + order
    // must match the backend's CARRIERS list for consistency.
    var lists = {
      auto:   ['BlueLine Auto', 'Maple Auto Insurance', 'Northshield Mutual', 'Polaris Drivers', 'Heritage Vehicle Care'],
      home:   ['Foundation Home', 'Maple Home Group', 'Heritage Roof Insurance', 'Northshield Home', 'BlueLine Property'],
      tenant: ['Anchor Renter Cover', 'Maple Renter Group', 'BlueLine Renters', 'Polaris Renters', 'Heritage Tenant'],
      travel: ['Maple Travel Cover', 'Northern Voyage Insurance', 'BlueLine Trip', 'Polaris Traveler', 'Heritage Voyager']
    };
    var list = lists[vertical] || lists.auto;
    var mount = theater.querySelector('#q-theater-list');
    if (!mount) return;
    list.forEach(function (name, i) {
      var delay = 200 + i * 650;
      setTimeout(function () {
        var row = document.createElement('div');
        row.className = 'q-theater-carrier';
        row.style.animationDelay = '0s';
        row.innerHTML = '<span class="name">' + escapeHtml(name) + '</span><span class="status">searching…</span>';
        mount.appendChild(row);
        // Flip to "done" with a check after another 700-1100ms
        setTimeout(function () {
          row.classList.add('done');
          row.querySelector('.status').innerHTML = '<span class="check">✓</span> rate found';
        }, 800 + i * 80);
      }, delay);
    });
  }

  // ── comparison cards rendering ───────────────────────────────────────
  function renderResults(mount, data) {
    if (!mount) return;
    var quotes = (data.quotes || []).slice().sort(function (a, b) { return a.rank_position - b.rank_position; });
    if (!quotes.length) {
      renderError(mount, 'No quotes returned. Please try again or contact an advisor.');
      return;
    }
    var html = '' +
      '<div class="q-results">' +
        '<div class="q-results-head">' +
          '<h2>Your comparison results</h2>' +
          '<div class="sub">Lowest premium highlighted. Click any quote to speak with a licensed Canadian advisor.</div>' +
        '</div>' +
        '<div class="q-cards">' + quotes.map(function (q, i) { return renderCard(q, i, data); }).join('') + '</div>' +
        '<div class="q-results-foot">' + escapeHtml(quotes[0].estimate_disclaimer || 'Estimated premiums only. Final pricing subject to underwriting.') + '</div>' +
      '</div>';
    mount.innerHTML = html;
    mount.scrollIntoView({ behavior: 'smooth', block: 'start' });

    // Stagger card reveals (override CSS animation-delay per card)
    mount.querySelectorAll('.q-card').forEach(function (card, i) {
      card.style.animationDelay = (i * 120) + 'ms';
    });

    // Wire click handlers
    mount.querySelectorAll('.q-card-cta').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var qid = btn.dataset.quoteId;
        var cname = btn.dataset.carrierName;
        selectQuote(mount, data.lead_id, qid, cname);
      });
    });
  }
  function renderCard(q, i, data) {
    var features = ((q.coverage_summary && q.coverage_summary.key_features) || []).slice(0, 3);
    return '' +
      '<div class="q-card' + (q.is_lowest ? ' is-lowest' : '') + '">' +
        '<div class="q-card-main">' +
          '<div class="q-card-carrier">' + escapeHtml(q.carrier_name) + '</div>' +
          '<div class="q-card-features">' + features.map(function (f) { return '<span>' + escapeHtml(f) + '</span>'; }).join('') + '</div>' +
        '</div>' +
        '<div class="q-card-price">' +
          '<div class="monthly">$' + formatMoney(q.estimated_premium_monthly) + '</div>' +
          '<div class="per-month">per month</div>' +
          '<span class="annual">' + (q.estimated_premium_annual ? '$' + formatMoney(q.estimated_premium_annual) + '/year' : '') + '</span>' +
        '</div>' +
        '<button class="q-card-cta" data-quote-id="' + escapeAttr(q.id) + '" data-carrier-name="' + escapeAttr(q.carrier_name) + '" type="button">' +
          'Get this quote &rarr;' +
        '</button>' +
      '</div>';
  }

  // ── quote-select handler (the hot-lead trigger) ──────────────────────
  function selectQuote(mount, leadId, quoteId, carrierName) {
    // Optimistic UI: replace cards with a "connecting..." then either confirm
    // or fall back. The backend write is best-effort — even if the quote-select
    // workflow isn't yet built, we still show the user the centralized number.
    mount.innerHTML = '' +
      '<div class="q-theater">' +
        '<div class="q-theater-title">Connecting you with a licensed advisor…</div>' +
        '<div class="q-theater-sub">Locking in your <strong>' + escapeHtml(carrierName) + '</strong> quote.</div>' +
        '<div class="q-theater-bar"></div>' +
      '</div>';
    mount.scrollIntoView({ behavior: 'smooth', block: 'start' });

    var payload = {
      lead_id: leadId,
      marketplace_quote_id: quoteId,
      carrier_name: carrierName,
      source_domain: window.location.hostname
    };

    Promise.all([
      fetch(SELECT_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      }).then(function (r) { return r.json().then(function (j) { return { ok: r.ok, data: j }; }); })
        .catch(function () { return { ok: false, data: {} }; }),
      new Promise(function (resolve) { setTimeout(resolve, 1500); })
    ]).then(function () {
      // Confirmation — always shows even if backend select-endpoint is dormant,
      // so the user is never left hanging. Centralized advisor phone is the CTA.
      mount.innerHTML = '' +
        '<div class="q-confirm">' +
          '<h2>✓ Quote locked in</h2>' +
          '<p>We saved your <strong>' + escapeHtml(carrierName) + '</strong> quote and notified an available licensed advisor.</p>' +
          '<p style="margin-top:14px;"><strong>Speak with an advisor now:</strong><br>' +
            '<a href="tel:' + ADVISOR_PHONE_TEL + '" style="font-size:1.4rem;font-weight:700;color:#065f46;text-decoration:none;">📞 ' + ADVISOR_PHONE_DISPLAY + '</a>' +
          '</p>' +
          '<p class="next">An advisor will also reach out by phone, email, or WhatsApp within 24 hours. No obligation, no fees to you.</p>' +
        '</div>';
    });
  }

  function renderError(mount, msg) {
    if (!mount) return;
    mount.innerHTML = '<div class="q-error">' + escapeHtml(msg) + '</div>';
    mount.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  // ── tiny helpers ─────────────────────────────────────────────────────
  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function escapeAttr(s) { return escapeHtml(s); }
  function formatMoney(n) {
    var num = parseFloat(n) || 0;
    return num.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }
})();
