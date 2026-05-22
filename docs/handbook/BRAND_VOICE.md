# Crystallux brand voice

How customer-facing copy should sound. Applies to every email, SMS,
WhatsApp message, voice script, content post, and on-screen text the
platform sends on Mary's behalf.

## The voice in one paragraph

Crystallux speaks like a busy, capable operator who respects the
reader's time. Direct. Specific. No fluff. Warm without being chummy.
We say what we mean and we get to the point. We sound human because
we are — Mary signs the bottom of every message, and the copy reflects
her actual voice, not a marketing template.

## Hard rules

These are violations, not preferences. The audit linter flags them.

| Rule | Why |
|---|---|
| No em-dashes (`—`) | Highest-signal AI tell. Use periods, commas, parentheses, line breaks. |
| No en-dashes (`–`) outside number ranges (e.g. "9-5") | Same reason, secondary tell. |
| No "Hope this finds you well" / "I hope you're doing well" | Generic, dishonest opener. |
| No "I wanted to reach out" / "Just touching base" | Sales-template language. Say WHY you're writing. |
| No "Sincerely" / "Warmest regards" / "Best regards" sign-offs | Stilted. Use "Mary" or "Talk soon" or nothing. |
| No "The Crystallux Team" attribution | Impersonal. Sign as Mary or sign as nobody. |
| No triple-emoji headers (`💎 💎 💎`) | Looks auto-generated. |
| No "As an AI" / "I'm an AI assistant" | We don't pretend, but we don't lead with it either. |
| No "amazing" / "incredible" / "absolutely" as filler | Empty intensifiers. Cut them. |

## Tone calibration

- **First-person singular**: Mary writes as "I," not "we." Even when
  automation sends the message, it's Mary's voice.
- **Names, not labels**: address the recipient by first name. "Hi
  John" not "Hi there" or "Dear customer."
- **One ask per message**: every email should have exactly one next
  action. If there are two, split it.
- **Specific numbers over vague claims**: "8-minute call" not "a
  quick chat." "$2,497/mo" not "competitive pricing."
- **Receipts not promises**: when you say something will happen, say
  when. "I'll send the quote by Tuesday" not "shortly."

## Standard openings (pick one)

These replace generic openers:

- "Quick question — [...]"
- "Following up on [specific thing]."
- "Saw [specific signal] and wanted to flag [...]"
- "Mary here from Crystallux. [...]"
- For cold outreach: skip the opener entirely. Lead with the offer.

## Standard sign-offs (pick one or none)

- "Mary"
- "Talk soon, Mary"
- "Mary | Crystallux Insurance Network"
- For SMS: no sign-off (the From shows the sender).
- For very short messages: no sign-off.

## Footer + unsubscribe

Every commercial email (per CASL):
- Physical mailing address (Mary's business address)
- "If you'd rather not hear from me, just reply STOP."
- Mary's full name + role

No "you are receiving this because..." legalese. Plain words.

## What to do if a template feels off

1. Read it out loud. If you wouldn't say it that way to a friend, rewrite it.
2. Cut the first sentence and see if the message still works (it usually does).
3. Replace every adjective with a specific noun or fact.
4. Run the audit linter (`python scripts/audit/lint-message-templates.py`).

## What this doc is not

- Not a marketing-voice document. We don't have a "marketing voice."
- Not a style guide for the platform UI (that's `docs/design/`).
- Not a guide for internal Slack / docs / commits — those can be
  whatever feels right.

## Owners

Mary writes the canonical templates. The audit linter enforces the
hard rules. The COO Digital Employee (when it ships) flags content
for review before send if it violates any of the rules above.
