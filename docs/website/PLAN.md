# PUSH website — research and design plan

*2026-09-30. Status: plan for review, nothing built yet.*

## 1. The one-paragraph pitch

**Push to talk. Nothing leaves your Mac.** PUSH is the vintage desk
microphone from the icon, rebuilt for 2026: hold a key, speak, let go, and
your words land wherever you were typing, faster than Wispr Flow's servers can
answer. It costs **$19, once**, for three Macs, with every update included.
There's also a switch that takes the "like" out of your sentences, because we
live here too. 🌴

## 2. What the market looks like (Sept 2026)

| App | Where speech is processed | Price | What their site leans on |
|---|---|---|---|
| **Wispr Flow** | **Cloud only**: audio to Baseten, text to OpenAI, Anthropic or Cerebras; no offline mode | Free for 2,000 words/week, then **$15/mo or $144/yr** | "Don't type, just speak." Minimal cream/serif look, "every app, every device", social proof |
| Willow Voice | Cloud | Free for 2,000 words/week, then $15/mo or $144/yr | Same playbook as Wispr |
| Aqua Voice | Cloud | Free, then $8/mo annual | Speed and AI formatting |
| Superwhisper | Local or cloud | $8.49/mo, $84.99/yr, **$249.99 lifetime** | Power-user modes, model choice |
| MacWhisper | Local | €59–64 once | File transcription more than dictation |
| VoiceInk | Local (GPL, open source) | **$25 for 1 Mac, $39 for 2, $49 for 3**, once | Open source, lifetime |
| Voibe | Local | $7.50/mo or $149 lifetime | Private and offline |
| SpeakMac | Local | $19 once | Price |
| Spokenly, Handy | Local | Free (Spokenly has a $9.99/mo Pro) | Free |

What this tells us:

1. **The big brands are all cloud subscriptions at $144 a year.** Wispr Flow
   also carries baggage from a 2025 incident: users found it sending audio and
   screenshots to servers, and a user who raised it was banned before the CTO
   apologised. We don't need to mention that. It's enough to be the
   architecture that makes the question pointless.
2. **The local apps sell on "private".** None of them sells on "faster than
   the cloud". We can, because we have a published benchmark behind it (§5).
3. **Price.** $19 for 3 Macs undercuts VoiceInk's 3-Mac tier by $30 and costs
   less than two months of Wispr Flow. Free local apps exist, so we don't win on
   price alone. We win on price plus speed plus polish.
   **Recommendation: $19 for up to 3 Macs, +$10 per extra Mac, 14-day
   no-questions refund.** A launch-week price of $15 is an option if you want
   urgency on Product Hunt.
4. **No competitor has a personality.** Every site is cream, gradients and
   "AI". California mode and the push-to-talk mic give us one.

## 3. Positioning and message hierarchy

Three claims, in this order, everywhere:

1. **Fast.** Your words are there the moment you let go. (0.17 s, 4.6× Wispr Flow.)
2. **Private.** Your voice never leaves your Mac. No account, no cloud, works on a plane.
3. **Yours.** $19 once for 3 Macs. Every update included. No subscription, ever.

The personality comes from push-to-talk (the mic, the button, the "on air"
light) and from California mode.

**Taglines to try out:**
- "Push to talk. Nothing leaves your Mac."
- "Hold. Speak. Done."
- "Dictation that doesn't phone home."
- For the Wispr comparison: "Your voice shouldn't need a round trip."

## 4. The page, section by section

One long landing page plus `/legal`, `/privacy` and `/benchmark`. There is no
blog at launch.

1. **Nav.** PUSH wordmark · Features · California mode · Pricing · FAQ ·
   **Buy — $19** (pill button).
2. **Hero.** A big headline ("Push to talk. / Nothing leaves your Mac.") and a
   sub ("Hold a key, speak, let go. Your words appear in any app, transcribed
   on your Mac in under a fifth of a second."). CTAs: **Buy for $19** and
   **Download free trial** (drop the second one if there's no trial). The visual
   is a looping recording of a real Mac: a Slack or Mail window, the PUSH pill
   appearing with its voice glow, text landing. Caption chip: "Recorded live,
   not sped up."
3. **Speed strip.** Two bars race. *PUSH, on your Mac: 0.17 s* against
   *Wispr Flow, cloud: 0.79 s + network*. It animates once on scroll. Beneath:
   "Median of three readings of the same 25-second passage, 29 Sept 2026. See
   how we measured →" linking `/benchmark`.
4. **Private by design.** Three cards: *No cloud* ("The speech model runs on
   your Mac's Neural Engine"), *No account* ("No sign-up, no login, no
   tracking"), *Works offline* ("On a plane, in a basement, on hotel Wi-Fi").
   Illustration idea: a Mac with a little padlock "on air" light.
5. **California mode 🌴.** The playful centrepiece; see §6.
6. **It cleans up after you.** Short before/after pairs, typed live:
   - "The red car, I mean the blue car" → *the blue car*
   - Fillers, times and money: "um", "uh" gone; "four thirty PM" → *4:30 p.m.*; "five million dollars" → *$5 million*
   - "new paragraph", "bullet point", "number one… number two…" → formatted text
   - Personal dictionary: *"Priya", "Zürich", "Kubernetes"* spelled right
7. **Works everywhere you type.** An icon strip of Mail, Slack, Notes, Docs,
   VS Code and Messages. Use generic app glyphs or screenshots, not other
   companies' logos (see §5).
8. **Speaks your language.** English plus about 25 European languages detected
   automatically; Chinese, Japanese, Arabic, Hindi and more with the
   multilingual model. A marquee of "hello" in 20 languages.
9. **Pricing.** One card, no tiers:
   **$19, once.** · Up to 3 Macs · Every future update included · No
   subscription, ever · 14-day refund, no questions · +$10 per extra Mac.
   Beside it, a small, factual "vs. a year of Wispr Flow Pro: $144" line.
10. **FAQ.** Does it need internet? (Only to download a model once.) · What
    Macs? (Apple silicon, macOS 15+.) · How accurate? · Is it really private? ·
    What does "every update" mean? · Refunds? · Team/volume licences?
11. **About, a small band above the footer.** "PUSH is made by one person in
    California. Yes, California mode was built by a Californian, for
    Californians, with love. 🌴" Keep it to two lines, with a photo or
    signature if you want one.
12. **Footer.** Privacy · Terms · EULA · Third-party notices · contact email ·
    "Speech models by NVIDIA and Moondream, used under their open licences."

## 5. Claims we can make, and how to phrase them

Comparative advertising is legal in the U.S. when it's **true and backed by
evidence**. Keep to these rules:

- **Name Wispr Flow in plain text, never their logo** (nominative fair use).
  Don't imply they endorse us.
- **Every number links to `/benchmark`**, which publishes the passage, the
  hardware, the date, the three runs and the method, as in the README. Say
  "4.6× faster than Wispr Flow's processing (5.4× counting network), measured
  29 Sept 2026". Never write a bare "5× faster than Wispr".
  Re-measure before each marketing push; their numbers can change.
- **"Your voice never leaves your Mac."** True: audio and transcripts stay
  local. Avoid "PUSH never connects to the internet". It does, to download
  models, check for updates and sync your dictionary through iCloud if you
  turn that on. The privacy page lists exactly those.
- **Don't mention the Wispr privacy incident** on our site. The architecture
  comparison makes the point without the risk.
- **"Every update included"** matches the EULA: every PUSH for macOS update,
  no promised schedule, and a future Windows version can be sold separately.
- **Model credit in the footer:** "Parakeet by NVIDIA, Parakeet Ultra by
  Moondream". Plain text, no logos.

## 6. California mode, the fun part

**The interaction:** a sentence in a big speech bubble:

> "So like I went to the store and like bought milk. It was, like, amazing. We should like totally go back."

Below it is a chunky toggle styled like a surfboard or a sunset: **California
mode: OFF / ON**. Switch it on and every filler "like" pops out with a little
confetti puff:

> "So I went to the store and bought milk. It was amazing. We should totally go back."

Every clause above is a case in `CaliforniaLikeTests`, so the demo shows what
the app really does. Keep it that way: **every before/after on the site must
be copied from a passing unit test.**

Then a caption with a wink: **"It knows the difference."** Four chips that
don't pop, all from the tests: *"I like it."*, *"It looks like rain."*,
*"Like I said, we're done."*, *"He was like, no way."*

**Tone rule:** we laugh with Valley-speak, not at it. The copy is written by
someone who says "like" a lot, and the About band confirms it: "Built in
California by a Californian."

Visual treatment: this section alone can go sunset gradient (peach to coral to
violet), a palm silhouette, and the one place we allow a handwritten or rounded
display font.

## 7. Visual direction: "Broadcast booth"

This comes straight from the app icon, a chrome desk mic with a push button on
a walnut desk.

- **Palette:** warm paper `#F6F1E7` (background), ink `#1B1A17`, walnut
  `#6B4A2F`, brushed chrome greys `#C9CCD1` / `#8A8F98`, and one accent,
  **"on air" red `#E5372B`**, reserved for Buy buttons and the recording dot.
  The pill's voice-glow colours (pink, sky, violet, green, orange) appear only
  in the demo glow. Dark mode: ink background, paper text, the same red.
- **Type:** a confident grotesk for headlines (e.g. *Inter Tight* or
  *Space Grotesk*) and a monospace (*JetBrains Mono*) for numbers, timings and
  the benchmark. The mono gives the "measured, not claimed" feel.
- **Motif:** a round, physical "push" button. The Buy CTA is a tactile red
  button that depresses on click, and the pill appears on hover.
- **Imagery:** real screen recordings; the icon illustration as the hero's
  supporting art.
- **Motion:** the text-landing demo, the speed race, the California toggle.
  Everything else stays still. Respect `prefers-reduced-motion`.
- **Differentiation check:** Wispr is pale cream and serif, and the rest are
  purple AI gradients. Warm paper plus chrome plus an on-air red is ours.

## 8. Assets to capture (on your Mac, with the real `.app`)

1. Hero loop, about 8 s: hold key → pill with glow → text lands in Slack or Mail.
   1440×900, recorded with Screen Studio or QuickTime, then trimmed.
2. Streaming model drawing words live, about 6 s.
3. Self-correction ("red car, I mean blue car"), about 5 s.
4. Settings window screenshots: Text (California mode toggle), Models, Dictionary.
5. The pill on its own, transparent PNG, light and dark.
6. The icon at 1024 px (we have 512 px; export 1024 from the source).

## 9. How Claude Design works, and how we'll start from scratch

**Claude Design** makes a *Design* artifact: a canvas of live artboards
(desktop, mobile and so on) built as real HTML/CSS. You iterate on it by
chatting ("make the hero bolder", "try the California section in dark").
It asks for a **design system** because it wants tokens: colours, type,
spacing, components. Your account has none yet, which is why it felt like it
wanted something you didn't have.

The fix is to make the design system *first*, from what PUSH already is:

1. **Design system (I can do this).** A "PUSH Broadcast" design system artifact
   holding the palette, type, buttons (including the red push-button CTA), the
   pill component, cards and the California-mode sunset variant, all from §7.
   It becomes reusable for the website, App Store-style screenshots, the Product
   Hunt gallery and social posts.
2. **Landing page design (I can do this).** A Design artifact using that
   system, with desktop and mobile artboards following §4, placeholders where
   the §8 recordings go, and the copy from §3.
3. **You review on the canvas.** Comment on artboards or tell me what to change.
4. **Ship to Netlify.** The Netlify connector here can import a Claude Design
   URL straight into a Netlify site, giving you a `*.netlify.app` URL to share
   until you buy a domain. Then point the domain at it.

## 10. Launch checklist (in order)

**Legal and business** (drafts are in `legal/`):
- [ ] Decide the name. "PUSH" alone is generic, and Ableton owns "Push" for
      music hardware and software (Class 9). The risk is moderate: different
      market, but the same class. Search USPTO (tmsearch.uspto.gov) for "PUSH"
      in Class 9 and 42. Using a compound for the domain and brand helps
      ("PUSH Dictation", getpush.app, pushtotalk.app, pushdictate.com).
      A trademark attorney consult (~$150–300 flat) is worth it before you
      spend on a domain.
- [ ] Sell under your own legal name, "Elias Atalah". Then no DBA is needed.
      If you want the storefront to say "PUSH" as the business name, file a
      Fictitious Business Name with your county (about $30–50 plus newspaper
      publication).
- [ ] Merchant of record: **Polar** (5% + 50¢, accepts individuals, built-in
      licence keys with **activation limits**, which gives the 3-Mac rule for
      free) or **Paddle** (5% + 50¢, all-in, very established; needs your legal
      name in the T&Cs; licence keys only through webhooks). Avoid Lemon Squeezy
      for now: it's winding down into Stripe Managed Payments.
- [ ] Attorney review of EULA, Terms of Sale and Privacy, then fill the `[placeholders]`.
- [ ] Confirm each model licence on its Hugging Face card (see the note in
      `legal/THIRD_PARTY_NOTICES.md`).
- [ ] **Replace `nextel_chirp.mp3`.** The Nextel chirp isn't a registered
      trademark (Motorola's application was refused), but we don't know where
      this recording came from, and "Nextel" is a brand. A paid product needs a
      sound we own. The `push_chime.wav` stash from 2026-09-04 is a candidate.
- [ ] Add an "Acknowledgements" link in Settings ▸ About that opens
      `Contents/Resources/Legal` or the website's `/legal` page.

**App changes needed before charging:**
- [ ] Licence-key entry and activation (Polar or Paddle API), with a trial if
      you want one.
- [ ] **Move the update feed off GitHub before making the repo private.**
      `SUFeedURL` points at `raw.githubusercontent.com/Elias1986a/PUSH/main/appcast.xml`,
      and every `<enclosure>` at GitHub Releases. Making the repo private breaks
      updates for every installed copy. Order: host `appcast.xml` and the ZIPs on
      the Netlify site → ship one release whose `SUFeedURL` points there → wait
      for users to update → then make the repo private.

**Site:**
- [ ] Design system → landing page in Claude Design → Netlify import.
- [ ] `/benchmark` page from the README's benchmark section.
- [ ] `/legal` page rendering the EULA, Terms, Privacy and Third-party notices.
- [ ] Launch on **Product Hunt** (this is probably the "site for new ideas"
      you remembered), Hacker News "Show HN", and r/macapps.

## Sources

- Wispr Flow pricing: [wisprflow.ai/pricing](https://wisprflow.ai/pricing), [eesel.ai](https://www.eesel.ai/blog/wispr-flow-pricing)
- Wispr Flow privacy: [modelpiper.com](https://modelpiper.com/blog/wispr-flow-privacy-incident), [getvoibe.com review](https://www.getvoibe.com/resources/wispr-flow-review/), [Wispr security FAQ](https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq)
- Wispr design and tagline: [wisprflow.ai](https://wisprflow.ai/), [design post](https://wisprflow.ai/post/designing-a-natural-and-useful-voice-interface)
- Superwhisper: [superwhisper.com/docs/billing/plans](https://superwhisper.com/docs/billing/plans)
- VoiceInk: [tryvoiceink.com/pricing](https://tryvoiceink.com/pricing)
- MacWhisper: [getvoibe.com](https://www.getvoibe.com/resources/macwhisper-pricing/)
- Voibe, Spokenly, Willow, Aqua: [getvoibe.com/pricing](https://www.getvoibe.com/pricing/), [spokenly.app/pricing](https://spokenly.app/pricing), [willowvoice.com/pricing](https://willowvoice.com/pricing), [spokenly.app Aqua](https://spokenly.app/blog/aqua-voice-pricing), [SpeakMac comparison](https://spokenly.app/comparison/speakmac)
- Merchants of record: [Polar fees](https://polar.sh/docs/merchant-of-record/fees), [Paddle Mac licensing](https://www.paddle.com/help/start/intro-to-paddle/selling-a-mac-app-with-trials-and-licensing), [Lemon Squeezy 2026 update](https://www.lemonsqueezy.com/blog/2026-update)
- California DBA: [FindLaw](https://www.findlaw.com/smallbusiness/starting-a-business/how-to-file-a-dba-in-california-in-3-steps.html)
- Ableton trademarks: [ableton.com/en/legal/trademark-list](https://www.ableton.com/en/legal/trademark-list/)
- Nextel chirp sound mark: [TTABlog](http://thettablog.blogspot.com/2008/03/ttab-rules-that-motorolas-911-hz-chirp.html)
- Model licences: [moondream/parakeet-ultra](https://huggingface.co/moondream/parakeet-ultra), [nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [nvidia/parakeet-unified-en-0.6b](https://huggingface.co/nvidia/parakeet-unified-en-0.6b), [kzos/verbatim#4 on Nemotron licences](https://github.com/kzos/verbatim/pull/4), [OpenMDW-1.1](https://openmdw.ai/license/1-1/), [NVIDIA Open Model License (June 2024 PDF)](https://developer.download.nvidia.com/licenses/nvidia-open-model-license-agreement-june-2024.pdf)
