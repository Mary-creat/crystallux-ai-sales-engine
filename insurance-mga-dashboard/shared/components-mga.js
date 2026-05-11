/* ═══ Crystallux Insurance MGA Dashboard — components-mga.js ════════
   The 7 insurance-MGA-specific UI helpers required by Layer 2 Part B.
   All return HTML strings (not DOM nodes) — pages compose with
   .innerHTML for simplicity.
   =================================================================== */
(function (global) {
  'use strict';
  var esc = function (s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;'); };

  // 1. VerticalBadge — small "INSURANCE MGA" pill in the topbar
  function verticalBadge(label) {
    return '<span class="clx-vertical-badge">' + esc(label || 'Insurance MGA') + '</span>';
  }

  // 2. LicenseStatusIndicator — color-coded by renewal_status
  function licenseStatusIndicator(license) {
    if (!license) return '';
    var status = license.renewal_status || 'current';
    var labels = { current: 'Current', expiring_60d: 'Expires in 60d', expiring_30d: 'Expires in 30d', expiring_14d: 'Expires in 14d', expiring_7d: 'Expires in 7d', expired: 'EXPIRED' };
    var classes = { current: 'clx-badge-success', expiring_60d: 'clx-badge-info', expiring_30d: 'clx-badge-warning', expiring_14d: 'clx-badge-warning', expiring_7d: 'clx-badge-danger', expired: 'clx-badge-danger' };
    return '<span class="clx-badge ' + (classes[status] || 'clx-badge-neutral') + '">' + esc(labels[status] || status) + '</span>';
  }

  // 3. ComplianceScoreBadge — shows AI compliance review score 0-100
  function complianceScoreBadge(review) {
    if (!review || review.ai_score == null) return '<span class="clx-badge clx-badge-neutral">Pending</span>';
    var s = parseInt(review.ai_score) || 0;
    var cls = s >= 85 ? 'clx-badge-success' : (s >= 60 ? 'clx-badge-info' : (s >= 40 ? 'clx-badge-warning' : 'clx-badge-danger'));
    return '<span class="clx-badge ' + cls + '">' + s + ' / 100</span>';
  }

  // 4. ReviewTypeIcon — small icon + label per review_type
  function reviewTypeIcon(type) {
    var map = {
      annual: { icon: '📅', label: 'Annual' },
      triggered_event: { icon: '⚡', label: 'Triggered' },
      renewal: { icon: '🔄', label: 'Renewal' },
      claim: { icon: '🩹', label: 'Claim' },
      compliance_audit: { icon: '🧮', label: 'Audit' },
      complaint: { icon: '⚠️', label: 'Complaint' },
      pre_issuance: { icon: '📝', label: 'Pre-issue' }
    };
    var entry = map[type] || { icon: '·', label: esc(type || 'Review') };
    return '<span title="' + esc(entry.label) + '" style="margin-right:4px">' + entry.icon + '</span>' + esc(entry.label);
  }

  // 5. TriggerSourceBadge — where did this review come from?
  function triggerSourceBadge(source) {
    var map = {
      scheduled:           { label: 'Scheduled',         cls: 'clx-badge-neutral' },
      behavioral_signal:   { label: 'Life Event',        cls: 'clx-badge-info' },
      market_signal:       { label: 'Market Signal',     cls: 'clx-badge-info' },
      client_request:      { label: 'Client Request',    cls: 'clx-badge-warning' },
      carrier_request:     { label: 'Carrier Request',   cls: 'clx-badge-warning' },
      regulator_request:   { label: 'Regulator Request', cls: 'clx-badge-danger' }
    };
    var entry = map[source] || { label: esc(source || '—'), cls: 'clx-badge-neutral' };
    return '<span class="clx-badge ' + entry.cls + '">' + esc(entry.label) + '</span>';
  }

  // 6. VideoEngagementStatus — color-coded video lifecycle
  function videoEngagementStatus(status) {
    var map = {
      not_sent:        { label: 'Not Sent',        cls: 'clx-badge-neutral' },
      sent:            { label: 'Sent',            cls: 'clx-badge-info' },
      viewed:          { label: 'Viewed',          cls: 'clx-badge-warning' },
      replied:         { label: 'Replied',         cls: 'clx-badge-success' },
      meeting_booked:  { label: 'Booked Meeting!', cls: 'clx-badge-success' }
    };
    var entry = map[status] || { label: esc(status || '—'), cls: 'clx-badge-neutral' };
    return '<span class="clx-badge ' + entry.cls + '">' + esc(entry.label) + '</span>';
  }

  // 7. PriorityIndicator — left-edge color bar by priority
  function priorityIndicator(priority) {
    var cls = 'clx-priority-' + (priority || 'medium');
    return '<span class="clx-priority-bar ' + cls + '" title="Priority: ' + esc(priority || 'medium') + '"></span>';
  }

  // 8. PerformanceProgressBar — horizontal bar with achievement % overlay
  function performanceProgressBar(current, target) {
    var c = parseFloat(current) || 0;
    var t = parseFloat(target)  || 0;
    var pct = t > 0 ? Math.min(100, (c / t) * 100) : 0;
    var cls = pct >= 100 ? 'clx-bar-success' : (pct >= 70 ? 'clx-bar-info' : (pct >= 40 ? 'clx-bar-warning' : 'clx-bar-danger'));
    return '<div class="clx-progress"><div class="clx-progress-fill ' + cls + '" style="width:' + pct.toFixed(1) + '%"></div><div class="clx-progress-label">' + c + ' / ' + t + ' (' + Math.round(pct) + '%)</div></div>';
  }

  // 9. CapacityIndicator — team load: green <70%, amber 70-90%, red >90%
  function capacityIndicator(used, capacity) {
    var u = parseInt(used) || 0;
    var c = parseInt(capacity) || 0;
    var pct = c > 0 ? (u / c) * 100 : 0;
    var cls = pct >= 90 ? 'clx-badge-danger' : (pct >= 70 ? 'clx-badge-warning' : 'clx-badge-success');
    return '<span class="clx-badge ' + cls + '">' + u + ' / ' + c + ' (' + Math.round(pct) + '%)</span>';
  }

  // 10. CarrierStatusBadge — active / inactive / pending / api_offline
  function carrierStatusBadge(carrier) {
    if (!carrier) return '';
    if (!carrier.active) return '<span class="clx-badge clx-badge-neutral">Inactive</span>';
    if (carrier.api_endpoint && carrier.sync_status === 'error') return '<span class="clx-badge clx-badge-danger">API Offline</span>';
    if (carrier.ai_compliance_ready) return '<span class="clx-badge clx-badge-success">AI Ready</span>';
    return '<span class="clx-badge clx-badge-info">Active</span>';
  }

  // Helper: render an empty / loading / error state
  function renderState(kind, message) {
    if (kind === 'loading') return '<div class="clx-empty"><span class="clx-spinner"></span> Loading…</div>';
    if (kind === 'empty')   return '<div class="clx-empty">' + esc(message || 'Nothing to show.') + '</div>';
    if (kind === 'error')   return '<div class="clx-error-box">' + esc(message || 'An error occurred.') + '</div>';
    return '';
  }

  // Helper: simple table renderer
  function renderTable(rows, columns) {
    if (!rows || rows.length === 0) return renderState('empty', 'No rows.');
    var head = '<thead><tr>' + columns.map(function (c) { return '<th>' + esc(c.label) + '</th>'; }).join('') + '</tr></thead>';
    var body = '<tbody>' + rows.map(function (r) {
      return '<tr>' + columns.map(function (c) {
        var raw = c.cell ? c.cell(r) : (r[c.key] != null ? esc(r[c.key]) : '');
        return '<td>' + raw + '</td>';
      }).join('') + '</tr>';
    }).join('') + '</tbody>';
    return '<table class="clx-table">' + head + body + '</table>';
  }

  global.clxComp = global.clxComp || {};
  global.clxComp.verticalBadge          = verticalBadge;
  global.clxComp.licenseStatusIndicator = licenseStatusIndicator;
  global.clxComp.complianceScoreBadge   = complianceScoreBadge;
  global.clxComp.reviewTypeIcon         = reviewTypeIcon;
  global.clxComp.triggerSourceBadge     = triggerSourceBadge;
  global.clxComp.videoEngagementStatus  = videoEngagementStatus;
  global.clxComp.priorityIndicator      = priorityIndicator;
  global.clxComp.performanceProgressBar = performanceProgressBar;
  global.clxComp.capacityIndicator      = capacityIndicator;
  global.clxComp.carrierStatusBadge     = carrierStatusBadge;
  global.clxComp.renderState            = renderState;
  global.clxComp.renderTable            = renderTable;
})(window);
