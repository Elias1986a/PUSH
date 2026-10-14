# PUSHTYPE Privacy Policy

> **DRAFT. Not legal advice.** California's Online Privacy Protection Act
> (CalOPPA) requires a commercial website that collects personal information
> from Californians to post a privacy policy. This is it. Review it before launch.

**Effective:** October 13, 2026 · **Who we are:** Elias Atalah, California ("we"). Contact: [support@pushtype.app](mailto:support@pushtype.app)

## The short version

Your voice and your typing stay on your Mac. PUSHTYPE turns speech into text and
suggests what you'll type next on your Mac's own chip. We never receive your audio, your transcripts or what you type, and
there's nothing to opt out of because we don't collect it. PUSHTYPE has no
analytics, no ads and no account.

## What PUSHTYPE does on your Mac

- **Audio** from the microphone is held in memory while you dictate, turned
  into text, and then thrown away. It's never saved to disk or sent anywhere.
- **Transcripts** are pasted where you're typing, through the clipboard. PUSHTYPE
  doesn't keep a history of them.
- **What you type (Type, the autocomplete).** To suggest how your sentence
  goes on, PUSHTYPE reads the text before and around your cursor, and anything you
  copied in the last few minutes, at the moment it makes a suggestion. It's
  held in memory and never saved or sent. Password and sign-in fields are never
  read, and neither is anything a password manager copies.
- **Text on screen (optional).** If you allow Screen Recording, PUSHTYPE reads the
  text of the few apps that only draw it on screen, the same way and for the
  same moment. Nothing is recorded or kept.
- **Learn from my writing and voice (off unless you turn it on).** PUSHTYPE keeps
  what you type and dictate where suggestions are on, so they sound like you.
  It's encrypted with a key in your Mac's Keychain, stored at
  `~/Library/Application Support/PUSH/TypingHistory.sealed`, and never sent to us.
  Each Mac decides for itself whether to learn. Only if you also switch on
  "Share what it learns with my other Macs" (Settings ▸ Personal, per Mac) is a
  copy sent through your own iCloud, compressed and encrypted with a separate key
  held in your iCloud Keychain, which only your Apple Account has (see iCloud
  below). Settings ▸ Personal ▸ Delete All erases it and its key, and on every
  Mac that shares it.
- **A diagnostic log** at `~/Library/Application Support/PUSH/push_debug.log`
  records operational events such as "model loaded" and timings. It never
  records what you said. It stays on your Mac unless you send it to us yourself.

## The network connections PUSHTYPE makes

| When | To whom | What they receive | Why |
|---|---|---|---|
| You press **Download** for a speech or typing model | Hugging Face (huggingface.co) | A standard download request: your IP address and the files requested | To fetch the open model you picked. [Hugging Face privacy policy](https://huggingface.co/privacy) |
| Once a day, if automatic updates are on | Our update feed on GitHub (raw.githubusercontent.com) | A standard web request: your IP address, PUSHTYPE version and macOS version | To check for updates (Sparkle). |
| When you activate a license | Your own iCloud Keychain (end-to-end encrypted by Apple) | Your license key | So your other Macs signed in to the same Apple Account activate without asking. We can't read it. |
| If "Sync across my Macs" is on (Settings ▸ General) | Apple iCloud, through your own iCloud account | Your PUSHTYPE settings (including your name and your About you note) and personal dictionary entries. If you also switch on "Share what it learns with my other Macs": the writing PUSHTYPE has kept, encrypted with a key in your iCloud Keychain | To keep your Macs in step. We can't read this data; it's stored under your Apple Account. Switch it off at any time. |
| When you enter a license key, when you remove a Mac from your license, and at most once a day to confirm the license is still valid | Polar (polar.sh), our merchant of record | Your license key, an activation ID, and your Mac's model (for example "Mac mini (M4)") so you can tell your Macs apart. Like any web request, it also carries your IP address | To check the key is genuine and to count Macs (3 per license). [Polar's privacy policy](https://polar.sh/legal/privacy) |

None of these connections carries audio, transcripts or anything you type.

## When you buy PUSHTYPE

The Buy buttons on our website open Polar's checkout. Polar, our merchant of
record, collects your name, email, billing
details and payment information to process the sale, under
[Polar's privacy policy](https://polar.sh/legal/privacy). We receive your name, email, country and order
details so we can deliver your license, support you and issue refunds. We never
see your full card number.

We use your email only for your purchase and for support. We'll send
occasional product news only if you opt in, and every email lets you
unsubscribe.

## The website

pushtype.app is hosted by Netlify, which keeps standard server logs (IP
address, pages requested) for security and operations.

We use Google Analytics to count visits and see which pages people read. It
sets cookies on pushtype.app and sends Google the page you're on (its path
only, never order numbers or anything after it), your browser and device type,
and your approximate location. Google signals and ad personalization are off,
so we don't use advertising cookies or cross-site tracking. It covers the
website only: the app never sends anything to Google. To opt out, block
cookies for pushtype.app or use Google's opt-out add-on
([tools.google.com/dlpage/gaoptout](https://tools.google.com/dlpage/gaoptout)).
[Google's privacy policy](https://policies.google.com/privacy)

After you buy, the thank-you page asks Polar, through our website, for that
purchase's download link and license key, so you can download and activate in
two clicks. It uses only the order number Polar adds to the page's address,
and nothing is stored.

If you use the form on our support page, Netlify stores what you send (your
email address, the topic and your message) and emails it to us so we can
reply. We use it only to answer you, and delete old messages regularly.

## Your rights

You can ask what we hold about you, ask us to correct or delete it, or opt out
of marketing email by writing to [support@pushtype.app](mailto:support@pushtype.app). We'll answer within 30
days. We don't sell or share personal information for cross-context behavioral
advertising, as the CCPA/CPRA defines it. PUSHTYPE isn't directed at children under
13, and we don't knowingly collect their information.

## Changes

If this policy changes, we'll post the new version here with a new effective
date. If a change would materially affect you, we'll say so in the release
notes.
