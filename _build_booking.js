const fs = require('fs');

// ── Parse Interest Response code ─────────────────────────────────────────────
// Rule 11: reads from Claude Detect Interest via $input (it IS the direct predecessor,
// but lead data must always come from $('Split In Batches').item.json)
const parseInterestCode = [
  '// CLX Booking — Phase 9',
  '// Parses Claude interest detection response',
  '',
  'const response = $input.item.json;',
  "const lead = $('Split In Batches').item.json;",
  '',
  'const rawText = response.content[0].text;',
  '',
  'let interest;',
  'try {',
  '  const cleaned = rawText.replace(/```json/gi, \'\').replace(/```/g, \'\').trim();',
  '  interest = JSON.parse(cleaned);',
  '} catch (e) {',
  '  interest = {',
  '    interest_detected: false,',
  "    confidence: 'Low',",
  "    signal_type: 'neutral',",
  "    recommended_action: 'nurture'",
  '  };',
  '}',
  '',
  'return {',
  '  json: {',
  '    ...lead,',
  '    interest_detected: interest.interest_detected === true ? \'true\' : \'false\',',
  '    interest_confidence: interest.confidence || \'Low\',',
  '    signal_type: interest.signal_type || \'neutral\',',
  '    recommended_action: interest.recommended_action || \'nurture\'',
  '  }',
  '};'
].join('\n');

// ── Build Booking Email code ──────────────────────────────────────────────────
// Rule 11: lead from $('Split In Batches'), calendly from $('Get Calendly Link')
const buildBookingEmailCode = [
  '// CLX Booking — Phase 9',
  '// Builds personalized booking email with Calendly link',
  '',
  "const lead = $('Split In Batches').item.json;",
  "const calendlyResponse = $('Get Calendly Link').item.json;",
  '',
  '// Extract scheduling URL from Calendly /user/me response',
  'const calendlyUrl = (calendlyResponse.resource && calendlyResponse.resource.scheduling_url)',
  '  ? calendlyResponse.resource.scheduling_url',
  '  : (calendlyResponse.scheduling_url || \'\');',
  '',
  'const now = new Date();',
  'const firstName = (lead.full_name || \'\').split(\' \')[0];',
  '',
  'const subject = "Let\'s find a time to connect";',
  '',
  'const body = [',
  '  \'Hi \' + firstName + \',\',',
  '  \'\',',
  '  \'Thanks for getting back to me. Really glad it resonated.\',',
  '  \'\',',
  '  \'I\'d love to show you exactly how this works for businesses like \' + (lead.company || \'yours\') + \'. It\'s a quick 15 minutes and you\'ll walk away with a clear picture of what\'s possible.\',',
  '  \'\',',
  '  \'Here\'s my booking link — pick whatever time works best for you:\',',
  '  calendlyUrl,',
  '  \'\',',
  '  \'Looking forward to it.\',',
  '  \'\',',
  '  \'Best\'',
  '].join(\'\\n\');',
  '',
  'return {',
  '  json: {',
  '    ...lead,',
  '    booking_subject: subject,',
  '    booking_body: body,',
  '    calendly_link: calendlyUrl,',
  '    booking_email_sent: true,',
  '    booking_email_sent_at: now.toISOString(),',
  "    lead_status: 'Booking Sent',",
  '    updated_at: now.toISOString()',
  '  }',
  '};'
].join('\n');

const workflow = {
  name: "CLX - Booking",
  nodes: [
    {
      parameters: {
        rule: { interval: [{ field: "minutes", minutesInterval: 30 }] }
      },
      id: "clx09-0000-0000-0000-000000000001",
      name: "Schedule Trigger",
      type: "n8n-nodes-base.scheduleTrigger",
      typeVersion: 1.2,
      position: [200, 300]
    },
    {
      parameters: {
        method: "GET",
        url: "https://zqwatouqmqgkmaslydbr.supabase.co/rest/v1/leads?lead_status=eq.Replied&select=id,full_name,email,company,job_title,reply_text,email_subject,outreach_sent_at&limit=10",
        authentication: "genericCredentialType",
        genericAuthType: "httpHeaderAuth",
        sendHeaders: true,
        headerParameters: {
          parameters: [{ name: "Authorization", value: "" }]
        },
        options: {}
      },
      id: "clx09-0000-0000-0000-000000000002",
      name: "Get Replied Leads",
      type: "n8n-nodes-base.httpRequest",
      typeVersion: 4.2,
      position: [440, 300],
      credentials: { httpHeaderAuth: { id: "1", name: "Supabase Crystallux" } }
    },
    {
      parameters: {
        conditions: {
          options: { caseSensitive: true, leftValue: "", typeValidation: "strict", version: 2 },
          conditions: [
            {
              id: "clx09-cond-string-not-empty-001",
              leftValue: "={{ $json.id }}",
              rightValue: "",
              operator: { type: "string", operation: "notEmpty", singleValue: true }
            }
          ],
          combinator: "and"
        },
        options: {}
      },
      id: "clx09-0000-0000-0000-000000000003",
      name: "IF Replied Leads Found",
      type: "n8n-nodes-base.if",
      typeVersion: 2.2,
      position: [680, 300]
    },
    {
      parameters: { batchSize: 1, options: {} },
      id: "clx09-0000-0000-0000-000000000004",
      name: "Split In Batches",
      type: "n8n-nodes-base.splitInBatches",
      typeVersion: 3,
      position: [920, 300]
    },
    {
      parameters: { amount: 3, unit: "seconds" },
      id: "clx09-0000-0000-0000-000000000005",
      name: "Wait",
      type: "n8n-nodes-base.wait",
      typeVersion: 1.1,
      position: [1160, 300],
      webhookId: "clx09-wait-webhook-001"
    },
    {
      parameters: {
        method: "POST",
        url: "https://api.anthropic.com/v1/messages",
        authentication: "genericCredentialType",
        genericAuthType: "httpHeaderAuth",
        sendHeaders: true,
        headerParameters: {
          parameters: [
            { name: "anthropic-version", value: "2023-06-01" },
            { name: "Content-Type", value: "application/json" }
          ]
        },
        sendBody: true,
        specifyBody: "json",
        jsonBody: "={{ JSON.stringify({ model: \"claude-opus-4-6\", max_tokens: 256, messages: [{ role: \"user\", content: \"You are a sales assistant for the Crystallux Sales Engine.\\n\\nAnalyze this reply from a prospect and determine if they are interested in learning more or booking a meeting.\\n\\nProspect: \" + $json.full_name + \"\\nCompany: \" + $json.company + \"\\nTheir reply: \" + ($json.reply_text || 'No reply text available') + \"\\n\\nReturn ONLY raw JSON no explanation no markdown:\\n{\\n  \\\"interest_detected\\\": true or false,\\n  \\\"confidence\\\": \\\"High\\\" or \\\"Medium\\\" or \\\"Low\\\",\\n  \\\"signal_type\\\": \\\"positive\\\" or \\\"negative\\\" or \\\"neutral\\\",\\n  \\\"recommended_action\\\": \\\"book_meeting\\\" or \\\"nurture\\\" or \\\"remove\\\"\\n}\" }] }) }}",
        options: {}
      },
      id: "clx09-0000-0000-0000-000000000006",
      name: "Claude Detect Interest",
      type: "n8n-nodes-base.httpRequest",
      typeVersion: 4.2,
      position: [1400, 300],
      credentials: { httpHeaderAuth: { id: "2", name: "Claude Anthropic" } }
    },
    {
      parameters: { jsCode: parseInterestCode },
      id: "clx09-0000-0000-0000-000000000007",
      name: "Parse Interest Response",
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [1640, 300]
    },
    {
      parameters: {
        conditions: {
          options: { caseSensitive: true, leftValue: "", typeValidation: "strict", version: 2 },
          conditions: [
            {
              id: "clx09-cond-interest-001",
              leftValue: "={{ $json.interest_detected }}",
              rightValue: "true",
              operator: { type: "string", operation: "equals" }
            }
          ],
          combinator: "and"
        },
        options: {}
      },
      id: "clx09-0000-0000-0000-000000000008",
      name: "IF Interested",
      type: "n8n-nodes-base.if",
      typeVersion: 2.2,
      position: [1880, 300]
    },
    {
      parameters: {
        method: "GET",
        url: "https://api.calendly.com/user/me",
        authentication: "genericCredentialType",
        genericAuthType: "httpHeaderAuth",
        options: {}
      },
      id: "clx09-0000-0000-0000-000000000009",
      name: "Get Calendly Link",
      type: "n8n-nodes-base.httpRequest",
      typeVersion: 4.2,
      position: [2120, 160],
      credentials: { httpHeaderAuth: { id: "4", name: "Calendly" } }
    },
    {
      parameters: { jsCode: buildBookingEmailCode },
      id: "clx09-0000-0000-0000-000000000010",
      name: "Build Booking Email",
      type: "n8n-nodes-base.code",
      typeVersion: 2,
      position: [2360, 160]
    },
    {
      parameters: {
        sendTo: "={{ $('Build Booking Email').item.json.email }}",
        subject: "={{ $('Build Booking Email').item.json.booking_subject }}",
        message: "={{ $('Build Booking Email').item.json.booking_body }}",
        options: {}
      },
      id: "clx09-0000-0000-0000-000000000011",
      name: "Send Booking Email",
      type: "n8n-nodes-base.gmail",
      typeVersion: 2.1,
      position: [2600, 160],
      credentials: { gmailOAuth2: { id: "3", name: "Gmail" } }
    },
    {
      parameters: {
        method: "PATCH",
        url: "={{ \"https://zqwatouqmqgkmaslydbr.supabase.co/rest/v1/leads?id=eq.\" + $('Build Booking Email').item.json.id }}",
        authentication: "genericCredentialType",
        genericAuthType: "httpHeaderAuth",
        sendHeaders: true,
        headerParameters: {
          parameters: [
            { name: "Authorization", value: "" },
            { name: "Content-Type", value: "application/json" },
            { name: "Prefer", value: "return=representation" }
          ]
        },
        sendBody: true,
        specifyBody: "json",
        jsonBody: "={{ JSON.stringify({ interest_detected: true, booking_email_sent: true, booking_email_sent_at: $('Build Booking Email').item.json.booking_email_sent_at, calendly_link: $('Build Booking Email').item.json.calendly_link, lead_status: $('Build Booking Email').item.json.lead_status, updated_at: $('Build Booking Email').item.json.updated_at }) }}",
        options: {}
      },
      id: "clx09-0000-0000-0000-000000000012",
      name: "Update Lead Booked",
      type: "n8n-nodes-base.httpRequest",
      typeVersion: 4.2,
      position: [2840, 160],
      credentials: { httpHeaderAuth: { id: "1", name: "Supabase Crystallux" } }
    },
    {
      parameters: {
        method: "PATCH",
        url: "={{ \"https://zqwatouqmqgkmaslydbr.supabase.co/rest/v1/leads?id=eq.\" + $json.id }}",
        authentication: "genericCredentialType",
        genericAuthType: "httpHeaderAuth",
        sendHeaders: true,
        headerParameters: {
          parameters: [
            { name: "Authorization", value: "" },
            { name: "Content-Type", value: "application/json" },
            { name: "Prefer", value: "return=representation" }
          ]
        },
        sendBody: true,
        specifyBody: "json",
        jsonBody: "={{ JSON.stringify({ interest_detected: false, lead_status: 'Not Interested', updated_at: new Date().toISOString() }) }}",
        options: {}
      },
      id: "clx09-0000-0000-0000-000000000013",
      name: "Update Not Interested",
      type: "n8n-nodes-base.httpRequest",
      typeVersion: 4.2,
      position: [2120, 440],
      credentials: { httpHeaderAuth: { id: "1", name: "Supabase Crystallux" } }
    },
    {
      parameters: {},
      id: "clx09-0000-0000-0000-000000000014",
      name: "No Replied Leads",
      type: "n8n-nodes-base.noOp",
      typeVersion: 1,
      position: [680, 500]
    }
  ],
  connections: {
    "Schedule Trigger": {
      main: [[{ node: "Get Replied Leads", type: "main", index: 0 }]]
    },
    "Get Replied Leads": {
      main: [[{ node: "IF Replied Leads Found", type: "main", index: 0 }]]
    },
    "IF Replied Leads Found": {
      main: [
        [{ node: "Split In Batches", type: "main", index: 0 }],
        [{ node: "No Replied Leads", type: "main", index: 0 }]
      ]
    },
    "Split In Batches": {
      main: [
        [{ node: "Wait", type: "main", index: 0 }],
        []
      ]
    },
    "Wait": {
      main: [[{ node: "Claude Detect Interest", type: "main", index: 0 }]]
    },
    "Claude Detect Interest": {
      main: [[{ node: "Parse Interest Response", type: "main", index: 0 }]]
    },
    "Parse Interest Response": {
      main: [[{ node: "IF Interested", type: "main", index: 0 }]]
    },
    "IF Interested": {
      main: [
        [{ node: "Get Calendly Link", type: "main", index: 0 }],
        [{ node: "Update Not Interested", type: "main", index: 0 }]
      ]
    },
    "Get Calendly Link": {
      main: [[{ node: "Build Booking Email", type: "main", index: 0 }]]
    },
    "Build Booking Email": {
      main: [[{ node: "Send Booking Email", type: "main", index: 0 }]]
    },
    "Send Booking Email": {
      main: [[{ node: "Update Lead Booked", type: "main", index: 0 }]]
    },
    "Update Lead Booked": {
      main: [[{ node: "Split In Batches", type: "main", index: 0 }]]
    },
    "Update Not Interested": {
      main: [[{ node: "Split In Batches", type: "main", index: 0 }]]
    }
  },
  active: false,
  settings: { executionOrder: "v1" },
  versionId: "clx-booking-v090",
  meta: {
    templateCredsSetupCompleted: false,
    instanceId: "3f3f6370fc2e867943491172b687727f653843d554f7415f38ca14c384f12f38"
  },
  id: "clx-booking",
  tags: []
};

fs.writeFileSync(
  'workflows/clx-booking.json',
  JSON.stringify(workflow, null, 2)
);
console.log('Written. Nodes:', workflow.nodes.length, '| Connections:', Object.keys(workflow.connections).length);
