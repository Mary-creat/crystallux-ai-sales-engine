#!/usr/bin/env node
/**
 * Reconstruct one lead's journey from the records that already exist.
 *
 * Read-only. GET only, no write, no send.
 *
 * The question this answers is not "should we build an attribution store"
 * -- it is "how far can we get without one". Every hop is resolved against
 * a table already in production and reported as OK, PENDING (a home exists,
 * this lead has not reached it) or NO HOME (nothing can hold it, or nothing
 * writes it). Keeping PENDING and NO HOME apart is the point: collapsing
 * them turns a journey that has not happened yet into a schema gap, and
 * that is how a platform gets rebuilt for no reason.
 *
 * The output is therefore both the attribution proof and the specification
 * for what is actually missing, measured instead of guessed.
 *
 *   node scripts/audit/attribution-trace.js               # best tenant lead
 *   node scripts/audit/attribution-trace.js <lead_id>
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..', '..');

function env() {
  const out = {};
  const p = path.join(ROOT, '.env');
  if (!fs.existsSync(p)) return out;
  fs.readFileSync(p, 'utf8').split(/\r?\n/).forEach(function (line) {
    line = line.trim();
    if (!line || line[0] === '#' || line.indexOf('=') < 0) return;
    const i = line.indexOf('=');
    out[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["']|["']$/g, '');
  });
  return out;
}

const cfg = env();
const KEY = process.env.SUPABASE_SERVICE_KEY || cfg.SUPABASE_SERVICE_KEY;
const PROJECT = process.env.SUPABASE_PROJECT_ID || cfg.SUPABASE_PROJECT_ID;
if (!KEY || !PROJECT) {
  console.error('SUPABASE_PROJECT_ID / SUPABASE_SERVICE_KEY not set');
  process.exit(2);
}
const B = 'https://' + PROJECT + '.supabase.co/rest/v1/';

// A table that does not exist and a table that is empty are different
// findings, and PostgREST reports the first as an object and the second as
// an empty array. Keep them apart.
function get(pathAndQuery) {
  let body;
  try {
    body = execFileSync('curl', [
      '-sS', '--max-time', '45', '-X', 'GET',
      '-H', 'apikey: ' + KEY,
      '-H', 'Authorization: Bearer ' + KEY,
      B + pathAndQuery
    ], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  } catch (e) {
    return { error: 'transport: ' + String(e.message).slice(0, 120) };
  }
  let parsed;
  try { parsed = JSON.parse(body); } catch (e) { return { error: 'unparseable response' }; }
  if (!Array.isArray(parsed)) return { error: parsed.message || JSON.stringify(parsed) };
  return { rows: parsed };
}

const LEAD_FIELDS = [
  'id', 'client_id', 'lead_pool', 'lead_status', 'company', 'industry', 'city',
  'country', 'source', 'source_domain', 'platform_source', 'vertical',
  'full_name', 'email', 'job_title', 'linkedin_url', 'apollo_person_id',
  'research_summary', 'likely_business_need', 'research_angle', 'researched_at',
  'detected_signal', 'signal_confidence', 'outreach_timing',
  'lead_score', 'scoring_reason', 'score_components', 'priority_level',
  'campaign_name', 'campaign_type', 'preferred_channel',
  'email_subject', 'email_body', 'outreach_generated_at',
  'outreach_sent_at', 'total_emails_sent', 'last_email_sent_at',
  'reply_detected', 'reply_text', 'interest_detected',
  'followup_count', 'followup_sent_at', 'next_followup_scheduled_at',
  'meeting_scheduled', 'meeting_datetime', 'booking_email_sent_at',
  'unsubscribed', 'do_not_contact', 'updated_at'
].join(',');

let leadId = process.argv[2];
if (!leadId) {
  // The most advanced tenant lead available: the furthest one is the one
  // whose journey has the most to say.
  const r = get('leads?select=id,lead_score&lead_pool=eq.tenant' +
                '&research_summary=not.is.null&lead_score=not.is.null' +
                '&order=lead_score.desc&limit=1');
  if (r.error || !r.rows.length) {
    console.error('no tenant lead with research and a score: ' + (r.error || 'none found'));
    process.exit(1);
  }
  leadId = r.rows[0].id;
}

const lr = get('leads?select=' + LEAD_FIELDS + '&id=eq.' + leadId);
if (lr.error || !lr.rows.length) {
  console.error('lead not found: ' + (lr.error || leadId));
  process.exit(1);
}
const L = lr.rows[0];

const client = get('clients?select=id,client_name,onboarding_stage,channels_enabled&id=eq.' + L.client_id);
const icp = get('client_icp_profiles?select=id,name,vertical,titles,is_active&client_id=eq.' + L.client_id);
const plays = get('campaigns?select=id,name,channel,status&client_id=eq.' + L.client_id);
const decisions = get('agent_decisions?select=id,decision_type,reasoning,confidence_score,context_used,created_at&lead_id=eq.' + leadId + '&order=created_at.asc');
const actions = get('agent_actions?select=id,decision_id,action_type,channel,status,taken_by_role,taken_at&lead_id=eq.' + leadId);
const touches = get('outreach_log?select=id,channel,channel_status,subject,sent_at&lead_id=eq.' + leadId);
const books = get('bookings?select=id,scheduled_at,status,provider,cal_event_id,source_action_id&lead_id=eq.' + leadId);
const deals = get('deals?select=id,stage,deal_value,close_date&lead_id=eq.' + leadId);

let resolved = 0, pending = 0, homeless = 0;
const gaps = [];
const notYet = [];

// Three states, not two. A hop with no value because this lead has not got
// that far is a different finding from a hop with nowhere to put a value at
// all, and collapsing them overstates the schema gap -- which is exactly the
// error this tool exists to avoid making.
//
//   OK       the value is there
//   PENDING  a column or table exists for it; this lead has not reached it
//   NO HOME  nothing in the schema can hold it, or nothing ever writes it
function hop(n, name, value, where, hasHome) {
  const has = value !== null && value !== undefined && value !== '' &&
              !(Array.isArray(value) && !value.length);
  let mark, note;
  if (has) {
    resolved++; mark = 'OK     '; note = 'from ' + where;
  } else if (hasHome) {
    pending++; mark = 'PENDING'; note = 'lives in ' + where;
    notYet.push(name);
  } else {
    homeless++; mark = 'NO HOME'; note = where;
    gaps.push(name + ' -- ' + where);
  }
  const shown = has ? String(value).replace(/\s+/g, ' ').slice(0, 88) : '';
  console.log('  ' + mark + ' ' + String(n).padStart(2) + '. ' + name.padEnd(20) + shown);
  console.log('          ' + note);
}

function rowsOf(r) { return r.error ? [] : r.rows; }
function errOf(r) { return r.error ? (' [' + r.error + ']') : ''; }

console.log('\nATTRIBUTION TRACE  (read-only: GET only, no write, no send)');
console.log('lead   : ' + L.id);
console.log('company: ' + L.company + '  |  status: ' + L.lead_status +
            '  |  pool: ' + L.lead_pool);
console.log('');

const d0 = rowsOf(decisions);
const a0 = rowsOf(actions);
const c0 = rowsOf(client);
const i0 = rowsOf(icp);
const p0 = rowsOf(plays);
const t0 = rowsOf(touches);
const b0 = rowsOf(books);
const dl = rowsOf(deals);

hop(1, 'tenant', c0.length ? c0[0].client_name : null,
    'leads.client_id -> clients', true);
hop(2, 'objective', null,
    'no objectives table, and no objective id on campaigns or leads', false);
hop(3, 'ICP', null,
    'client_icp_profiles holds ' + i0.length + ' row(s) for this tenant and leads has no ' +
    'icp_profile_id -- the profile exists, nothing points at it', false);
hop(4, 'account', L.company, 'leads.company / industry / city', true);
hop(5, 'person', L.full_name || L.email,
    'leads.full_name / email / job_title', true);
hop(6, 'research', L.researched_at,
    'leads.research_summary + researched_at', true);
hop(7, 'signal / Why Now',
    (d0.find(d => d.context_used && d.context_used.capability_used === 'assess_why_now') || {}).created_at ||
    L.detected_signal,
    'leads.detected_signal, or agent_decisions.context_used.capability_used', true);
hop(8, 'score', L.lead_score, 'leads.lead_score + score_components', true);
hop(9, 'NBA', d0.length ? d0[d0.length - 1].decision_type : null,
    'agent_decisions.decision_type + reasoning', true);
hop(10, 'draft', L.outreach_generated_at,
    'leads.email_subject / email_body -- one slot, overwritten, so no draft history', true);
hop(11, 'approval state',
    a0.length ? (a0[0].status + ' (' + a0[0].taken_by_role + ')') : null,
    'agent_actions.status is the nearest thing; no approved_by / approved_at exists', true);
hop(12, 'send', L.outreach_sent_at || (t0.length ? t0[0].sent_at : null),
    'outreach_log' + errOf(touches) + ' or leads.outreach_sent_at -- note the email sender writes neither', true);
hop(13, 'reply', L.reply_detected ? 'reply_detected' : null,
    'leads.reply_detected + reply_text -- no timestamp, one slot, so no reply history', true);
hop(14, 'follow-up', L.followup_sent_at,
    'leads.followup_count / followup_sent_at -- counters, not rows', true);
hop(15, 'booking', b0.length ? b0[0].scheduled_at : (L.meeting_datetime || null),
    'bookings' + errOf(books) + ', appointment_log, or leads.meeting_scheduled -- three disconnected stores', true);
hop(16, 'opportunity', dl.length ? dl[0].stage : null,
    'deals exists in DDL but no workflow reads or writes it -- an orphaned table is not a home', false);
hop(17, 'outcome', dl.length ? dl[0].close_date : null,
    'depends on deals, which nothing writes; no revenue figure is recorded on the lead path', false);

console.log('\n  resolved ' + resolved + '/17   pending ' + pending +
            '/17   no home ' + homeless + '/17');
if (notYet.length) {
  console.log('  pending -- the schema is ready, the journey is not: ' + notYet.join(', '));
}

console.log('\nORDERING KEY');
console.log('  outreach_log.campaign_id : absent');
console.log('  bookings.campaign_id     : absent');
console.log('  deals.booking_id         : absent');
console.log('  The only join available is lead_id, ordered by heterogeneous');
console.log('  timestamps across tables. There is no journey key.');

console.log('\nTENANT CONTEXT');
console.log('  authorised plays (campaigns, any status): ' + p0.length +
            (p0.length ? '' : '  <- promotion refuses without one'));
console.log('  agent decisions on this lead            : ' + d0.length);
console.log('  agent actions on this lead              : ' + a0.length +
            (a0.length ? '  (' + a0.map(a => a.action_type + '/' + a.status).join(', ') + ')' : ''));
console.log('  outbound touches logged                 : ' + t0.length);

if (gaps.length) {
  console.log('\nTHE ACTUAL SCHEMA GAP (' + gaps.length + ' hops) -- measured, not assumed:');
  gaps.forEach(g => console.log('  * ' + g));
}
console.log('');
