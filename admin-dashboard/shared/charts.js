/* Crystallux Admin — Chart.js wrapper.
   Loads Chart.js from CDN once, exposes clxCharts.line / bar / donut /
   sparkline helpers. Every admin page can drop a chart in 5 lines.

   Usage:
     <canvas id="mychart" height="180"></canvas>
     <script src="/shared/charts.js"></script>
     <script>
       clxCharts.line('mychart', {
         labels: ['Mon','Tue','Wed','Thu','Fri'],
         datasets: [{ label:'Leads', data:[10,14,8,22,18] }]
       });
     </script>

   Theme-aware: pulls --color-brand-500 and friends from CSS variables
   so charts stay in palette automatically. */

(function (global) {
  'use strict';

  var CHARTJS_URL = 'https://cdn.jsdelivr.net/npm/chart.js@4.4.4/dist/chart.umd.min.js';
  var ready = false;
  var pending = [];

  function cssVar(name, fallback) {
    var v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return v || fallback;
  }

  function palette() {
    return {
      brand:   cssVar('--color-brand-500', '#7C3AED'),
      brand2:  cssVar('--color-brand-300', '#C4B5FD'),
      accent:  cssVar('--color-accent-500', '#10B981'),
      info:    cssVar('--info',    '#3B82F6'),
      warning: cssVar('--warning', '#F59E0B'),
      error:   cssVar('--error',   '#EF4444'),
      muted:   cssVar('--gray-400', '#94A3B8'),
      gridLine:cssVar('--gray-200', '#E2E8F0'),
      text:    cssVar('--gray-700', '#334155')
    };
  }

  function loadChartJs(cb) {
    if (global.Chart) { ready = true; cb(); return; }
    if (document.getElementById('clx-chartjs-loader')) {
      pending.push(cb); return;
    }
    var s = document.createElement('script');
    s.id = 'clx-chartjs-loader';
    s.src = CHARTJS_URL;
    s.async = true;
    s.onload = function () { ready = true; cb(); pending.splice(0).forEach(function (p) { p(); }); };
    s.onerror = function () { console.error('Chart.js failed to load from CDN'); };
    document.head.appendChild(s);
  }

  function defaults() {
    var p = palette();
    return {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: true, position: 'bottom', labels: { color: p.text, font: { size: 12 } } },
        tooltip: {
          backgroundColor: 'rgba(15, 23, 42, 0.92)',
          titleColor: '#fff', bodyColor: '#fff',
          padding: 10, cornerRadius: 8, displayColors: true
        }
      },
      scales: {
        x: { ticks: { color: p.muted, font: { size: 11 } }, grid: { color: p.gridLine, drawBorder: false } },
        y: { ticks: { color: p.muted, font: { size: 11 } }, grid: { color: p.gridLine, drawBorder: false }, beginAtZero: true }
      },
      animation: { duration: 600, easing: 'easeOutQuart' }
    };
  }

  function autoColor(i) {
    var p = palette();
    var seq = [p.brand, p.info, p.accent, p.warning, p.error, p.brand2, p.muted];
    return seq[i % seq.length];
  }

  function line(canvasId, data, opts) {
    loadChartJs(function () {
      var ctx = document.getElementById(canvasId);
      if (!ctx) return;
      var datasets = (data.datasets || []).map(function (d, i) {
        return Object.assign({
          borderColor: d.color || autoColor(i),
          backgroundColor: (d.color || autoColor(i)) + '22',
          fill: true, tension: 0.35, borderWidth: 2,
          pointRadius: 0, pointHoverRadius: 5, pointHoverBackgroundColor: d.color || autoColor(i)
        }, d);
      });
      new global.Chart(ctx, { type: 'line', data: { labels: data.labels || [], datasets: datasets }, options: Object.assign(defaults(), opts || {}) });
    });
  }

  function bar(canvasId, data, opts) {
    loadChartJs(function () {
      var ctx = document.getElementById(canvasId);
      if (!ctx) return;
      var datasets = (data.datasets || []).map(function (d, i) {
        return Object.assign({
          backgroundColor: d.color || autoColor(i),
          borderRadius: 6, maxBarThickness: 36
        }, d);
      });
      new global.Chart(ctx, { type: 'bar', data: { labels: data.labels || [], datasets: datasets }, options: Object.assign(defaults(), opts || {}) });
    });
  }

  function donut(canvasId, data, opts) {
    loadChartJs(function () {
      var ctx = document.getElementById(canvasId);
      if (!ctx) return;
      var colors = (data.labels || []).map(function (_, i) { return autoColor(i); });
      var d = defaults();
      d.scales = undefined;
      d.cutout = '68%';
      new global.Chart(ctx, {
        type: 'doughnut',
        data: { labels: data.labels || [], datasets: [{ data: data.values || [], backgroundColor: colors, borderColor: '#fff', borderWidth: 2 }] },
        options: Object.assign(d, opts || {})
      });
    });
  }

  function sparkline(canvasId, values, color) {
    loadChartJs(function () {
      var ctx = document.getElementById(canvasId);
      if (!ctx) return;
      var c = color || autoColor(0);
      new global.Chart(ctx, {
        type: 'line',
        data: {
          labels: values.map(function (_, i) { return i; }),
          datasets: [{ data: values, borderColor: c, backgroundColor: c + '20', fill: true, tension: 0.35, borderWidth: 1.5, pointRadius: 0 }]
        },
        options: {
          responsive: true, maintainAspectRatio: false,
          plugins: { legend: { display: false }, tooltip: { enabled: false } },
          scales: { x: { display: false }, y: { display: false, beginAtZero: true } },
          animation: { duration: 400 }
        }
      });
    });
  }

  global.clxCharts = { line: line, bar: bar, donut: donut, sparkline: sparkline, palette: palette };
})(window);
