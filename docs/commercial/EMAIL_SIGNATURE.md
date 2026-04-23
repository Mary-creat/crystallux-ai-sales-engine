# Email Signature — Mary Akintunde

**Purpose:** unified email signature for info@crystallux.org (Mary's primary business email going forward). HTML + plain-text versions included.

**Email account guidance:**

- Use `info@crystallux.org` for all Crystallux business email going forward. Route personal inbox to a separate address.
- Gmail supports two signatures: "new email" and "reply/forward". Use the HTML version for both.
- Check rendering on Gmail desktop, Gmail mobile, Outlook desktop, Apple Mail, and iPhone Mail before adopting.

---

## HTML version (Gmail / most web clients)

Paste into Gmail → Settings → General → Signature → Create new. Name it "Crystallux".

```html
<table cellpadding="0" cellspacing="0" border="0" style="font-family: Arial, Helvetica, sans-serif; font-size: 13px; line-height: 1.5; color: #1a202c;">
  <tr>
    <td style="padding: 0 0 6px 0;">
      <strong style="font-size: 14px; color: #1a202c;">Mary Akintunde</strong><br>
      <span style="color: #2563eb; font-weight: 600;">Founder, Crystallux</span>
    </td>
  </tr>
  <tr>
    <td style="padding: 2px 0; color: #1a202c; font-size: 12px;">
      <a href="mailto:info@crystallux.org" style="color: #1a202c; text-decoration: none;">info@crystallux.org</a>
      &nbsp;·&nbsp;
      <a href="https://crystallux.org" style="color: #1a202c; text-decoration: none;">crystallux.org</a>
    </td>
  </tr>
  <tr>
    <td style="padding: 2px 0; color: #1a202c; font-size: 12px;">
      <a href="https://www.linkedin.com/in/maryakintunde" style="color: #1a202c; text-decoration: none;">LinkedIn</a>
      &nbsp;·&nbsp;
      <a href="https://calendly.com/crystallux/discovery" style="color: #2563eb; text-decoration: none; font-weight: 600;">Book a 20-min demo →</a>
    </td>
  </tr>
  <tr>
    <td style="padding: 8px 0 0 0; color: #718096; font-size: 11px; border-top: 1px solid #e2e8f0;">
      Toronto, Canada &nbsp;·&nbsp; CASL-compliant &nbsp;·&nbsp; PIPEDA-aligned
    </td>
  </tr>
</table>
```

### Rendering notes

- **Mobile-safe:** uses a table (Outlook and Apple Mail render tables reliably; flexbox breaks on Outlook).
- **Font fallback:** Arial/Helvetica. If branded typography matters, add web-safe inline CSS `style="font-family: 'Inter', Arial, sans-serif;"` but Inter won't render in many mail clients — don't rely on it.
- **Colour accessibility:** the indigo `#2563eb` on white passes WCAG AA for the link text. The muted grey `#718096` is AAA for the footnote.
- **Image-free:** intentionally. Email signatures with embedded images get flagged by corporate spam filters, and images don't render by default in many clients.

### Update fields before adopting

- [ ] Verify LinkedIn URL (`in/maryakintunde`) matches Mary's actual profile slug
- [ ] Verify Calendly URL (`crystallux/discovery`) matches the actual event
- [ ] Confirm `info@crystallux.org` is live and monitored (see `docs/operations/SUPPORT_FLOW.md` for auto-responder)

---

## Plain-text version (under 6 lines)

For clients that strip HTML, for BBM-style short replies, for mailing-list opt-outs:

```
Mary Akintunde · Founder, Crystallux
info@crystallux.org · crystallux.org
Book a 20-min demo: calendly.com/crystallux/discovery
Toronto, Canada · CASL-compliant · PIPEDA-aligned
```

4 lines, no wasted words. Passes CASL footer requirements (sender name, sender business, physical location).

---

## Short reply signature (optional — for conversational threads 3+ replies deep)

Once an email thread is 3+ replies deep, full signatures become noisy. Use this truncated version for replies-within-threads:

```
— Mary
Crystallux · info@crystallux.org
```

---

## Rollout checklist

- [ ] Apply HTML version to Gmail → Settings → Signature → "new email"
- [ ] Apply HTML version to Gmail → Settings → Signature → "reply/forward"
- [ ] Test send to Mary's personal email; verify rendering on Gmail desktop + mobile
- [ ] Test send to a Yahoo/Outlook/Apple Mail account; verify rendering
- [ ] If rendering is off on any target client, roll back to plain-text fallback
- [ ] Add signature rollout note to Support auto-responder (see `docs/operations/SUPPORT_FLOW.md`)
- [ ] Update the Mary-personal LinkedIn profile with the new email address in Contact Info
- [ ] Set Gmail auto-forwarding: any email hitting the old `maryakintunde@gmail.com` forwards to `info@crystallux.org` for the first 90 days of transition

---

## When to retire or update

Update this signature when:

- Calendly URL changes
- LinkedIn handle changes
- Crystallux adopts a physical business address (add it to the footer line)
- Phone number becomes published (add to the second row)
- A second team member joins (decide: individual signatures per person, or shared "Crystallux Team" sig)

Do **not** add:

- Marketing tag lines ("AI lead gen for Canada!") — feels like a banner, not a signature
- Quotation from famous person — dated
- Animated GIFs — breaks in Outlook
- Social icons image — replace with text links (see HTML above)
- Disclaimer paragraphs — leave formal disclaimers to contracts and privacy policies, not signatures
