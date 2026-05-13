/* Crystallux Financial Services — marketing site JS.
   Plain vanilla. Mobile nav, FAQ accordion, cookie banner, form submit. */

(function () {
  'use strict';

  // ── Mobile nav ──────────────────────────────────────────────────
  function wireNav() {
    var toggle = document.querySelector('.nav-toggle');
    var links = document.querySelector('.nav-links');
    if (!toggle || !links) return;
    toggle.addEventListener('click', function () { links.classList.toggle('open'); });
  }

  // ── FAQ accordion ───────────────────────────────────────────────
  function wireFaq() {
    document.querySelectorAll('.faq-item').forEach(function (item) {
      var q = item.querySelector('.faq-q');
      if (!q) return;
      q.addEventListener('click', function () { item.classList.toggle('open'); });
    });
  }

  // ── Smooth scroll for anchor links ──────────────────────────────
  function wireSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(function (a) {
      a.addEventListener('click', function (e) {
        var target = document.querySelector(a.getAttribute('href'));
        if (!target) return;
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    });
  }

  // ── Cookie consent banner (PIPEDA + Quebec Law 25 friendly) ─────
  function wireCookieBanner() {
    var KEY = 'clx_cookie_consent';
    try { if (localStorage.getItem(KEY)) return; } catch (e) {}
    var banner = document.getElementById('cookieBanner');
    if (!banner) return;
    banner.classList.add('show');
    var accept = banner.querySelector('[data-cookie-accept]');
    if (accept) accept.addEventListener('click', function () {
      try { localStorage.setItem(KEY, 'accepted-' + Date.now()); } catch (e) {}
      banner.classList.remove('show');
    });
    var decline = banner.querySelector('[data-cookie-decline]');
    if (decline) decline.addEventListener('click', function () {
      try { localStorage.setItem(KEY, 'declined-' + Date.now()); } catch (e) {}
      banner.classList.remove('show');
    });
  }

  // ── Lead capture form submit ────────────────────────────────────
  // Forms with data-lead-form posted to the existing Crystallux MGA
  // lead-capture webhook. CASL consent checkbox required.
  var LEAD_ENDPOINT = 'https://automation.crystallux.org/webhook/mga/insurance/lead-capture';
  function wireLeadForms() {
    document.querySelectorAll('form[data-lead-form]').forEach(function (form) {
      var status = form.querySelector('.form-status');
      form.addEventListener('submit', function (e) {
        e.preventDefault();
        if (status) { status.textContent = ''; status.className = 'form-status'; }
        // CASL consent gate
        var consent = form.querySelector('input[name="consent"]');
        if (consent && !consent.checked) {
          if (status) { status.textContent = 'Please confirm consent to be contacted.'; status.className = 'form-status error'; }
          return;
        }
        var btn = form.querySelector('button[type="submit"]');
        if (btn) { btn.disabled = true; btn.dataset.originalText = btn.textContent; btn.textContent = 'Sending…'; }
        // Build payload
        var fd = new FormData(form);
        var body = {
          source: form.dataset.leadSource || (window.location.pathname.replace(/\.html$|^\//g, '') || 'home'),
          submitted_at: new Date().toISOString(),
          page_url: window.location.href,
          referrer: document.referrer || null,
          consent_given: true,
          fields: {}
        };
        fd.forEach(function (v, k) { if (k !== 'consent') body.fields[k] = v; });
        fetch(LEAD_ENDPOINT, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
          mode: 'cors'
        }).then(function (res) {
          if (btn) { btn.disabled = false; btn.textContent = btn.dataset.originalText || 'Submit'; }
          if (res.ok) {
            if (status) { status.textContent = 'Thanks — a licensed advisor will be in touch within one business day.'; status.className = 'form-status success'; }
            form.reset();
          } else {
            res.json().catch(function () { return {}; }).then(function (data) {
              if (status) { status.textContent = (data && data.error) || 'Something went wrong. Please try again or email clients@crystallux.org.'; status.className = 'form-status error'; }
            });
          }
        }).catch(function () {
          if (btn) { btn.disabled = false; btn.textContent = btn.dataset.originalText || 'Submit'; }
          if (status) { status.textContent = 'Network error. Please try again or email clients@crystallux.org.'; status.className = 'form-status error'; }
        });
      });
    });
  }

  // ── Init on DOM ready ───────────────────────────────────────────
  function init() {
    wireNav();
    wireFaq();
    wireSmoothScroll();
    wireCookieBanner();
    wireLeadForms();
    var y = document.getElementById('footerYear');
    if (y) y.textContent = new Date().getFullYear();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
