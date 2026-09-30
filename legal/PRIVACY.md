# PUSH Privacy Policy

> **DRAFT. Not legal advice.** California's Online Privacy Protection Act
> (CalOPPA) requires a commercial website that collects personal information
> from Californians to post a privacy policy. This is it. Review it before launch.

**Effective:** [date] · **Who we are:** Elias Atalah, California ("we"). Contact: [support@yourdomain]

## The short version

Your voice stays on your Mac. PUSH turns speech into text on your Mac's own
chip. We never receive your audio, your transcripts or what you type, and
there's nothing to opt out of because we don't collect it. PUSH has no
analytics, no ads and no account.

## What PUSH does on your Mac

- **Audio** from the microphone is held in memory while you dictate, turned
  into text, and then thrown away. It's never saved to disk or sent anywhere.
- **Transcripts** are pasted where you're typing, through the clipboard. PUSH
  doesn't keep a history of them.
- **A diagnostic log** at `~/Library/Application Support/PUSH/push_debug.log`
  records operational events such as "model loaded" and timings. It never
  records what you said. It stays on your Mac unless you send it to us yourself.

## The network connections PUSH makes

| When | To whom | What they receive | Why |
|---|---|---|---|
| You press **Download** for a speech model | Hugging Face (huggingface.co) | A standard download request: your IP address and the files requested | To fetch the open model you picked. [Hugging Face privacy policy](https://huggingface.co/privacy) |
| Once a day, if automatic updates are on | Our update feed at [yourdomain] | A standard web request: your IP address, PUSH version and macOS version | To check for updates (Sparkle). |
| If "Sync settings and dictionary across my Macs" is on (Settings ▸ General) | Apple iCloud, through your own iCloud account | Your PUSH settings and personal dictionary entries | To keep your Macs in step. We can't read this data; it's stored under your Apple Account. Switch it off at any time. |
| When you activate a licence [once the licence check ships] | [Polar/Paddle] | Your licence key and an anonymous device identifier | To count seats (3 Macs per licence). |

None of these connections carries audio or transcripts.

## When you buy PUSH

[Polar/Paddle], our merchant of record, collects your name, email, billing
details and payment information to process the sale, under
[their privacy policy](link). We receive your name, email, country and order
details so we can deliver your licence, support you and issue refunds. We never
see your full card number.

We use your email only for your purchase and for support. We'll send
occasional product news only if you opt in, and every email lets you
unsubscribe.

## The website

[yourdomain] is hosted by Netlify, which keeps standard server logs (IP
address, pages requested) for security and operations. We don't use
advertising cookies or cross-site tracking. [If you add privacy-friendly
analytics, name the tool here.]

## Your rights

You can ask what we hold about you, ask us to correct or delete it, or opt out
of marketing email by writing to [support@yourdomain]. We'll answer within 30
days. We don't sell or share personal information for cross-context behavioural
advertising, as the CCPA/CPRA defines it. PUSH isn't directed at children under
13, and we don't knowingly collect their information.

## Changes

If this policy changes, we'll post the new version here with a new effective
date. If a change would materially affect you, we'll say so in the release
notes.
