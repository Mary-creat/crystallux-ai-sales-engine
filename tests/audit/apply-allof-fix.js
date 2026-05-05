#!/usr/bin/env node
/* One-shot helper: replace the buggy `Array.isArray($input.item.json) ?
 * $input.item.json : []` Shape Response pattern with the `allOf(name)`
 * helper that handles both n8n auto-split and non-split shapes. Also
 * flips `runOnceForEachItem` → `runOnceForAllItems`.
 *
 * Run once after audit; not part of the deploy pipeline.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const fixes = [
  { file: 'workflows/api/client/clx-client-performance.json', queryNode: 'Query Leads' },
  { file: 'workflows/api/client/clx-client-replies.json',     queryNode: 'Query Replies' },
  { file: 'workflows/api/client/clx-client-activity.json',    queryNode: 'Query Activity' },
  { file: 'workflows/api/client/clx-client-billing.json',     queryNode: 'Query Billing' },
  { file: 'workflows/api/admin/clx-admin-onboarding-pipeline.json', queryNode: 'Query Onboarding' }
];

const ROOT = path.resolve(__dirname, '..', '..');

const ALLOF_HELPER =
  'const allOf = function (name) {\\n' +
  '  try {\\n' +
  '    const items = $(name).all().map(function (i) { return i.json; });\\n' +
  '    if (items.length === 1 && Array.isArray(items[0])) return items[0];\\n' +
  '    return items;\\n' +
  '  } catch (e) { return []; }\\n' +
  '};\\n';

fixes.forEach(function (fix) {
  const file = path.join(ROOT, fix.file);
  let s = fs.readFileSync(file, 'utf8');
  const oldRows = 'const rows = Array.isArray($input.item.json) ? $input.item.json : [];';
  const newRows = ALLOF_HELPER + "const rows = allOf('" + fix.queryNode + "');";
  if (s.indexOf(oldRows) === -1) {
    console.log('SKIP (already fixed or pattern missing): ' + fix.file);
    return;
  }
  s = s.replace(oldRows, newRows);
  // Flip mode just for the Shape Response (not Extract Token / Check Admin etc.).
  // Heuristic: only the FIRST occurrence after we apply the rows fix is the
  // Shape Response — replace its trailing mode declaration. Both occurrences
  // would also be fine since runOnceForAllItems is harmless for single-item
  // upstream contexts, but be precise.
  s = s.replace(
    /("jsCode": "[^"]*allOf\(.[^"]*"\s*,\s*"mode": ")runOnceForEachItem(")/,
    '$1runOnceForAllItems$2'
  );
  fs.writeFileSync(file, s);
  console.log('OK: ' + fix.file);
});
