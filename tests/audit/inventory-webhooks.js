#!/usr/bin/env node
/* Walks workflows/ and prints every webhook path + active flag.
   One-shot tool, no deps. */
'use strict';
const fs = require('fs');
const path = require('path');

function walk(d, results) {
  fs.readdirSync(d, { withFileTypes: true }).forEach(function (ent) {
    var p = path.join(d, ent.name);
    if (ent.isDirectory()) return walk(p, results);
    if (!ent.name.endsWith('.json')) return;
    try {
      var wf = JSON.parse(fs.readFileSync(p, 'utf8'));
      var nodes = wf.nodes || [];
      var webhooks = nodes.filter(function (n) { return n.type === 'n8n-nodes-base.webhook'; });
      var sched    = nodes.filter(function (n) { return n.type === 'n8n-nodes-base.scheduleTrigger' || n.type === 'n8n-nodes-base.cron'; });
      var rel = path.relative('workflows', p).split(path.sep).join('/');

      if (webhooks.length) {
        webhooks.forEach(function (w) {
          var params = w.parameters || {};
          results.push({
            file: rel,
            name: wf.name || '(no name)',
            active: !!wf.active,
            method: params.httpMethod || 'POST',
            wpath: params.path || '?',
            scheduled: sched.length > 0
          });
        });
      } else if (sched.length) {
        results.push({
          file: rel,
          name: wf.name || '(no name)',
          active: !!wf.active,
          method: 'SCHEDULE',
          wpath: '(no webhook)',
          scheduled: true
        });
      } else {
        results.push({
          file: rel,
          name: wf.name || '(no name)',
          active: !!wf.active,
          method: '(other)',
          wpath: '(no webhook)',
          scheduled: false
        });
      }
    } catch (e) {
      console.log('ERROR ' + p + ': ' + e.message);
    }
  });
}

var out = [];
walk('workflows', out);
out.sort(function (a, b) { return a.file.localeCompare(b.file); });
out.forEach(function (x) {
  var pad = function (s, n) { return (String(s) + ' '.repeat(n)).slice(0, n); };
  console.log([
    pad(x.method, 8),
    pad(x.wpath, 48),
    x.active ? 'ACTIVE  ' : 'dormant ',
    x.scheduled ? '+sched' : '      ',
    x.file
  ].join(' | '));
});
console.log('---');
console.log('total entries: ' + out.length);
console.log('active: ' + out.filter(function (x) { return x.active; }).length);
console.log('dormant: ' + out.filter(function (x) { return !x.active; }).length);
console.log('webhook-only: ' + out.filter(function (x) { return x.wpath !== '(no webhook)'; }).length);
console.log('schedule-only: ' + out.filter(function (x) { return x.wpath === '(no webhook)'; }).length);
