# LUXI Live Interactive — build plan (the 24/7 AI selling-host vision)

> Mary's vision: **LUXI is a full-body AI avatar host who live-streams 24/7 across socials, runs auctions + outright sales, answers commenters by name out loud in real time, and shows products on her body (try-on) so buyers see how good they look.**
>
> This doc is the honest map: what's already built (the foundation), and the 3 frontier builds that turn it into the real-time interactive host. Written 2026-05-31.

---

## ✅ What's ALREADY built (the foundation — verified in code)

| Piece | Where |
|---|---|
| LUXI persona, look, wardrobe, **bright-showroom background**, brand colors, voice tone, 24/7 live schedule + channels | `avatars` table (LUXI seed in `db/migrations/avatars-platform-schema.sql`) |
| Pre-recorded avatar **video pipeline** (script → HeyGen render → store in R2 → ready) | `workflows/api/video/clx-video-*` + `clx-content-*` |
| **Comment AI brain** — reads a comment + handle, Claude writes a personalized on-brand reply *addressing that person*, routes complaints to a human, turns questions into leads | `clx-content-comment-monitor-v1` + `clx-content-comment-response-v1` |
| **Auction + outright sales engine** — bid, auto-bid, Buy Now, anti-snipe, Stripe capture, payment holds | LUXI workflows + `luxi_*` RPCs (live in production) |
| **Streaming session layer** — Go Live, target platforms, LIVE badge, link the auction | `clx-admin-luxi-stream-manage` + `clx-luxi-public-stream` + `luxi-streaming.sql` |
| Product photos on a listing | `auctions.item_photos` |

**The hard, valuable parts already exist.** What's missing is the real-time "live mouth + body" and the try-on.

---

## 🔴 The 3 frontier builds for the full vision

### Build 1 — LUXI speaks LIVE (real-time interactive avatar)
**The gap:** today the avatar makes *pre-recorded* videos. To stream live and talk on the fly, we need **HeyGen Interactive / Streaming Avatar** (a real-time, full-body, talking avatar fed text to speak in the moment).

- **What it is:** a real-time avatar session (WebRTC/streaming) where we send text → LUXI speaks it live, on stream.
- **What it takes:** HeyGen Interactive Avatar API + a small always-on bridge service (keeps the session live, pushes the stream to Restream → all platforms).
- **Effort:** meaningful — ~1–2 weeks. New always-on component (not just n8n workflows).
- **Cost:** HeyGen Interactive is a higher tier (real-time streaming minutes) — budget for per-minute streaming.
- **Dependency:** HeyGen Interactive plan + the full-body avatar generated.

### Build 2 — She answers commenters by name, LIVE (comment → speech loop)
**The gap:** the comment brain (Build A above) writes text replies; it isn't connected to a live mouth.
- **What it takes:** poll each platform's **live** comments → feed to the existing comment brain (Claude) → send the reply text into the live HeyGen session so LUXI *says it out loud* ("Great question, Sarah — it's at $50!").
- **Effort:** ~3–5 days **once Build 1 exists** (the brain is already built; this is the wiring + live-comment ingestion per platform).
- **Dependency:** Build 1 (live avatar) + platform comment access (the social developer apps — same ones the publishers are waiting on).

### Build 3 — LUXI wears/shows the product (virtual try-on)
**The gap:** LUXI can't put the auctioned shirt on her body. This is **virtual try-on (VTON)** — genuinely advanced AI.
- **Two feasible versions:**
  - **(a) Pre-rendered try-on (achievable now-ish):** before/at listing time, run the product image + the LUXI avatar through a **VTON model** (e.g. a hosted try-on API) → a still or short clip of LUXI *wearing it* → show that in the stream / on the bid page. ~1 week + a VTON API subscription.
  - **(b) Real-time try-on on the live avatar (frontier):** LUXI changes outfits live per item, in real time. This is bleeding-edge; not reliably available off-the-shelf yet. Defer.
- **Recommendation:** do **(a)** — pre-rendered "LUXI wearing it" images/clips per product. Big conversion win, realistic build.

---

## Honest phased path

| Phase | What you get | Status / effort |
|---|---|---|
| **0 — now** | Full-body LUXI avatar generated; **pre-recorded** selling videos; text comment-replies by name on posted content; auctions + Buy Now taking money | ✅ built — needs your HeyGen Avatar ID + R2 storage |
| **1 — Live host** | LUXI streams live and talks (HeyGen Interactive) to all platforms via Restream | 🔴 Build 1 (~1–2 wks, HeyGen Interactive plan) |
| **2 — Answers by name live** | Connect the comment brain → live mouth; she greets + answers commenters in real time | 🔴 Build 2 (~3–5 days after Phase 1) |
| **3 — Try-on** | "LUXI wearing it" per product (pre-rendered) on the bid page / stream | 🔴 Build 3a (~1 wk + VTON API) |

## What's needed from Mary (inputs / keys)
- **HeyGen Avatar ID** (full-body LUXI) — for Phase 0 today.
- **HeyGen Interactive plan** — for Phase 1 (real-time).
- **Cloudflare R2** (bucket + keys) — to store/serve finished videos.
- **Social developer apps** (TikTok/Meta/YT) — for live comment access (Phase 2) + auto-posting.
- **A VTON API** (chosen later) — for Phase 3 try-on.

## Bottom line
The **brain, persona, look, commerce, and video generation are built.** The full "24/7 live AI host who talks to buyers by name and models the products" is **3 real builds** on top — led by **HeyGen Interactive** (the live mouth + body). It's achievable and well-scoped; it's a project, not a switch. Start Phase 0 today (generate full-body LUXI), build Phase 1–3 deliberately.
