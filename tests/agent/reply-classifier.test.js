#!/usr/bin/env node
/**
 * Tests for Classify Reply in clx-reply-ingestion-v1, against the shipped code.
 *
 * The property that matters most is not classification accuracy. It is that
 * **a person who asks to be left alone is left alone.**
 *
 * Before this node existed, nothing in the estate ever set a suppression
 * flag. Both outbound templates print "reply STOP to unsubscribe"; no code
 * read a reply looking for it. A reply saying STOP was written as
 * lead_status 'Replied', which made the lead ELIGIBLE for the booking
 * sweep, which could email it a Calendly link. We promised a way out and
 * built the opposite. Under CASL that is not a bug, it is an offence.
 *
 * So the suppression tests below are the point, and the category tests are
 * support. Precedence is tested explicitly: "not interested, remove me" is
 * an unsubscribe first and a rejection second.
 *
 * Run: node tests/agent/reply-classifier.test.js
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WF = path.join(__dirname, '..', '..', 'workflows', 'clx-reply-ingestion-v1.json');
const wf = JSON.parse(fs.readFileSync(WF, 'utf8'));

function nodeByName(n) {
  const x = wf.nodes.find(k => k.name === n);
  if (!x) throw new Error('node not found: ' + n);
  return x;
}

const SRC = nodeByName('Classify Reply').parameters.jsCode;

function classify(snippet, subject) {
  const sandbox = {
    $input: { item: { json: {
      snippet: snippet, subject: subject || '',
      from_email: 'someone@example.com', lead_id: 'lead-1'
    } } },
    console: { log: () => {} }
  };
  return vm.runInNewContext('(function(){' + SRC + '})()', sandbox,
                            { timeout: 5000 }).json;
}

let pass = 0, fail = 0;
function t(id, name, fn) {
  try { fn(); console.log('  PASS  ' + id + '  ' + name); pass++; }
  catch (e) { console.log('  FAIL  ' + id + '  ' + name + '\n        ' + e.message); fail++; }
}
function eq(a, b, m) {
  if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) +
                               ', got ' + JSON.stringify(a));
}

console.log('\nReply classifier — suppression is the point\n');

// ---- THE ONES THAT MATTER -------------------------------------------
const STOPS = [
  'STOP',
  'stop',
  'Please unsubscribe me',
  'unsubscribe',
  'Please remove me from your list',
  'take me off your list',
  'do not email me again',
  "don't contact me",
  'opt out please',
  'I no longer wish to receive these',
  'Please delete my data'
];
STOPS.forEach(function (s, i) {
  t('SUP-' + String(i + 1).padStart(2, '0'), 'suppresses: "' + s + '"', () => {
    const r = classify(s);
    eq(r.reply_category, 'UNSUBSCRIBE');
    eq(r.suppress, true, 'must suppress;');
    eq(r.new_status, 'Do Not Contact');
  });
});

t('SUP-12', 'unsubscribe beats rejection when both are present', () => {
  // The most common real phrasing, and the one a naive classifier
  // gets wrong: it reads "not interested" first and never suppresses.
  const r = classify('Not interested, please remove me from your list');
  eq(r.reply_category, 'UNSUBSCRIBE', 'precedence;');
  eq(r.suppress, true);
});

t('SUP-13', 'unsubscribe beats a question', () => {
  eq(classify('Can you tell me how to unsubscribe?').suppress, true);
});

t('SUP-14', 'a stop request in the SUBJECT line still suppresses', () => {
  eq(classify('thanks', 'STOP').suppress, true);
});

t('SUP-15', 'nothing else sets do_not_contact', () => {
  ['Interested, tell me more', 'How much does it cost?',
   'Not interested', 'wrong person', 'already have a provider',
   'call me next quarter', ''].forEach(function (s) {
    eq(classify(s).suppress, false, 'should not suppress "' + s + '";');
  });
});

// ---- CATEGORIES ------------------------------------------------------
const CASES = [
  ['WRONG_PERSON',         'You have the wrong person, I left the company'],
  ['WRONG_PERSON',         'Please speak to our operations manager'],
  ['ALREADY_HAS_PROVIDER', 'We already have a provider for this'],
  ['ALREADY_HAS_PROVIDER', "We're happy with our current supplier"],
  ['BOOK_MEETING',         'Happy to book a call - what times work?'],
  ['PRICING',              'How much does this cost?'],
  ['PRICING',              'Can you send me a quote'],
  ['SEND_INFORMATION',     'Send me more information please'],
  ['CALL_LATER',           'Not right now, check back next quarter'],
  ['NOT_INTERESTED',       'Not interested, thanks'],
  ['NOT_INTERESTED',       'No thanks, not a fit for us'],
  ['INTERESTED',           'This sounds good, tell me more'],
  ['QUESTION',             'Which cities do you cover']
];
CASES.forEach(function (c, i) {
  t('CAT-' + String(i + 1).padStart(2, '0'),
    c[0] + ': "' + c[1].slice(0, 34) + '"', () => {
    eq(classify(c[1]).reply_category, c[0]);
  });
});

t('CAT-14', 'an unreadable reply is UNCLEAR, not a guess', () => {
  // A pipeline failure must never come back as intent about the prospect.
  const r = classify('...');
  eq(r.reply_category, 'UNCLEAR');
  eq(r.suppress, false);
  eq(r.new_status, 'Replied');
});

t('CAT-15', 'an empty reply is UNCLEAR and stays contactable', () => {
  eq(classify('').reply_category, 'UNCLEAR');
  eq(classify('').new_status, 'Replied');
});

t('CAT-16', 'a rejection stops the funnel without suppressing consent', () => {
  // "Not interested" is not "never contact me". It stops this campaign,
  // it does not revoke permission for all time.
  const r = classify('Not interested');
  eq(r.new_status, 'Not Interested');
  eq(r.suppress, false);
});

// ---- THE WRITE -------------------------------------------------------
t('WRITE-01', 'the update writes do_not_contact only when suppressing', () => {
  const body = nodeByName('Mark Lead Replied').parameters.jsonBody;
  if (body.indexOf('do_not_contact') < 0) {
    throw new Error('the write never sets do_not_contact');
  }
  if (body.indexOf('$json.suppress') < 0) {
    throw new Error('do_not_contact is not gated on the suppress verdict');
  }
  if (body.indexOf('$json.new_status') < 0) {
    throw new Error('status is not taken from the classification');
  }
});

t('WRITE-02', 'the classifier runs before the write, not after', () => {
  const c = wf.connections;
  const afterCheck = (c['Check Match'].main[0] || []).map(x => x.node);
  if (afterCheck.indexOf('Classify Reply') < 0) {
    throw new Error('Check Match does not feed Classify Reply');
  }
});

console.log('\n  ' + pass + ' passed, ' + fail + ' failed\n');
process.exit(fail ? 1 : 0);
