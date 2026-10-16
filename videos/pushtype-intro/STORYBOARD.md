---
format: 1920x1080
duration: 10s
message: "PUSH to talk. Tab to TYPE."
arc: Demo Loop (product intro → demo 1 → demo 2 → CTA), compressed to three beats
audience: Mac users who write a lot
mode: autonomous
music: none
captions: skipped (no narration; the on-screen headlines carry the words)
---

## Video direction

- **Palette (frame.md, dark register only):** ground `ink-black` #08080A; text `cream` #EFEDE8; secondary text `cream-muted` #BDB9B1; `fire-orange` #FF5A45 is the one accent (brand dot, key-cap highlight). Hairlines `border-dark` #2A2B30.
- **Ground (identical in every frame, so cuts never jump):** a full-duration background clip filled #08080A with two soft radial glows: violet `radial-gradient(ellipse 55% 60% at 10% 6%, rgba(84,52,128,0.30), transparent 70%)` and coral `radial-gradient(ellipse 50% 55% at 92% 96%, rgba(255,90,69,0.12), transparent 70%)`. No other gradients, no textures, no bokeh.
- **Type:** headline = Archivo 800, `font-stretch: 112%`, 112px (≈ 680px wide for "PUSH to talk."), line-height 0.95, letter-spacing -0.02em, cream. Kicker = JetBrains Mono 400, 18px, uppercase, 0.14em tracking, `walnut` #B88A63. Key caps = JetBrains Mono 700. Brand casing is sacred: PUSHTYPE, PUSH and TYPE in caps; never lowercase display.
- **Product window (frames 1 and 2 share it exactly):** a real screen recording (2080×1560 file, a 1040×780 design space at 2×) shown in a 1000×750 box at left 840, top 135 (scale 0.9615 from design space). The Notes window shape inside it is the design-space rect x 20, y 16, w 999, h 661, radius 24 → on screen left 859.2, top 150.4, 960.5×635.6, radius 23. Mask the video to that rounded rect (`clip-path: inset(...) round ...` on a wrapper, or an SVG clipPath) so the recording's own backdrop never shows. Behind it, a rim: a rounded rect of the same geometry with `box-shadow: 0 0 0 1px rgba(239,237,232,0.16), 0 0 48px rgba(239,237,232,0.06)` (box-shadow, never CSS drop-shadow filter on video). Video gets `filter: brightness(1.14)`.
- **Motion grammar:** smooth long-tail settles (`power3.out`, `expo.out` on fast arrivals), no bounce or overshoot, entrances with `fromTo`. Reveals follow the on-screen words: nothing appears before its beat. Holds are still; subtle jitter at most.
- **Rhythm:** frame 1 builds, frame 2 swaps in place (same window, same headline slot; it feels like one shot that changes its mind), frame 3 is the held breather: the wordmark lands and holds.
- **Negative list:** no slideshow (everything dumped at t=0 then frozen), no screensaver (independent floating), no lazy breathing, no back-half slow pan or push, no bounce, no stock icons, no fake UI, no cursor, no second accent color. No caption pill.
- **Audio:** the music bed `assets/music/clean-pulse-10s.mp3` (the explainer's "Clean Pulse" bed, its last 10s with the original ending) is host audio at the root; frames embed no audio. Footage is muted.

## Frame 1 — PUSH to talk

- scene: "PUSH to talk." builds on the left while the real Notes window on the right streams spoken words into the pill, the key releases, and clean text lands in the note
- duration: 3.6s
- transition_in: cut
- type: product_intro
- beat: the promise, shown working
- voiceover: "PUSH to talk."
- asset_candidates: assets/footage/talk-clip.mp4
- blueprint: device-surface-showcase (Adapt)
- focal: assets/footage/talk-clip.mp4
- roles: talk-clip = supporting hero (masked window, right 55%) · headline = focal type (left 40%)
- poster: 3.3s
- handoff_out: product window — left 859.2, top 150.4, 960.5×635.6, scale 1, opacity 1, static (no motion at the cut); headline block — left 100, baseline of line 1 at y 470, scale 1, opacity 1, static; key cap — left 100, top 560, scale 1, opacity 1, static
- src: compositions/frames/01-push-to-talk.html
- status: animated

Adapt: keep the floating-window-held-as-hero signature (a real surface completing its core loop on screen); one window, no device frame, and the headline sits beside it instead of title cards bracketing it.

Exact layout. Left column x 100–800. Kicker "DICTATION AND AUTOCOMPLETE FOR THE MAC" at left 100, top 300 (walnut mono). Headline "PUSH to talk." one line at left 100, baseline y 470 (112px Archivo 800 stretch 112 ≈ 680px; it must fit within 700px, step down to 104px only if it overflows). Key cap at left 100, top 560: a rounded-rect chip 14px radius, 1px border rgba(239,237,232,0.22), fill #141416, text cream, containing "⌥" (JetBrains Mono 700, 44px) at 96×88px, followed 24px to the right by a label "hold to talk" (JetBrains Mono 400, 22px, cream-muted). Right: the product window per Video direction, holding TWO muted video layers of `assets/footage/talk-clip.mp4`, both `data-start` = the frame start, `data-media-start="0"`, identical box (left 840, top 135, 1000×750):
- layer A masked to the Notes window rect (design space x 20, y 16, w 999, h 661, r 24);
- layer B masked to the live-preview pill rect (design space x 79, y 706, w 883, h 59, r 29.5 → on screen left 916, top 813.8, 849×56.7, radius 28.4), with its own rim rect behind it.
In the clip, the pill streams words from 0.0s, the pill closes at 2.65s and the cleaned text lands in the note at 3.07s.

Scene 1 (0.0–0.7s): ground holds; the product window (layer A + its rim) rises into place, y +40 → 0 and opacity 0 → 1, `power3.out` (→ `spring-pop-entrance`, smooth settle); the pill layer B and its rim come with it. The kicker fades up at 0.15s.
Scene 2 (0.25–1.1s): the headline assembles word by word: "PUSH" lands first, then "to", then "talk." (→ `dynamic-content-sequencing`, `power3.out`, y +30 → 0, 0.12s stagger). Asymmetric 40/60 framing, three depth layers (ground glows, window, type).
Scene 3 (1.0–2.65s): the key cap enters (opacity 0 → 1, y +16 → 0) and immediately goes to its pressed state: scale 0.94, border turns fire-orange #FF5A45, a faint fire-orange glow `box-shadow: 0 0 24px rgba(255,90,69,0.35)` (→ `press-release-spring`, but no overshoot). It stays pressed while the pill streams the words (the footage is the motion here).
Scene 4 (2.65–3.6s): at 2.65s exactly the key releases (scale 1, border back to rgba(239,237,232,0.22), glow off, `power3.out` 0.25s) and at the same moment the pill layer B and its rim fade to 0 over 0.15s (the pill closes in the footage, and its backdrop must never show). At 3.07s the clean text lands in the note on its own. Then hold still to the cut.

## Frame 2 — Tab to TYPE

- scene: the same window, now a message being typed; the headline swaps in place to "Tab to TYPE." and the key cap becomes Tab, pressed exactly when the gray suggestion is accepted
- duration: 3.6s
- transition_in: cut
- type: feature_showcase
- beat: the second half of the promise, shown working
- voiceover: "Tab to TYPE."
- asset_candidates: assets/footage/type-clip.mp4
- blueprint: kinetic-type-beats (Adapt)
- focal: assets/footage/type-clip.mp4
- roles: type-clip = supporting hero (masked window, right 55%) · headline = focal type (left 40%)
- poster: 2.2s
- handoff_in: product window — left 859.2, top 150.4, 960.5×635.6, scale 1, opacity 1, static; headline block — left 100, baseline of line 1 at y 470, scale 1, opacity 1, static; key cap — left 100, top 560, scale 1, opacity 1, static
- handoff_out: none (crossfade into the end card)
- src: compositions/frames/02-tab-to-type.html
- status: animated

Adapt: keep the in-place token swap signature (a fixed line slot whose words change; the swap is the beat) and set it beside the product window, which holds its position across the cut so only its contents change.

Exact layout: identical to Frame 1 (same kicker text and position, same headline slot, same key cap slot, same window box and Notes-window mask). One video layer of `assets/footage/type-clip.mp4` (muted, `data-media-start="0"`) masked to the Notes window rect only; no pill layer. In the clip, gray suggested text is visible after the caret; Tab accepts "take" at 1.67s, and the next gray suggestion appears right after. The sentence sits in the upper half of the note (design space y ≈ 200–370).

Scene 1 (0.0–0.5s): at t=0 everything is already in place (handoff), the kicker and window unchanged. The headline swaps in place: the outgoing "PUSH to talk." is NOT in this frame; "Tab to TYPE." waterfall-reveals word by word from y +24 with a slight blur 6px → 0 (→ `cut-catalog.md` waterfall cut, `power3.out`, 0.08s stagger), completing by 0.5s. The key cap is present at rest with "Tab" (JetBrains Mono 700, 34px; chip widened to 132×88) and label "Tab to take it".
Scene 2 (0.2–1.1s): zoom-to-target on the window (→ `coordinate-target-zoom`): scale the window group 1 → 1.18 about the point (design space x 300, y 290 → on screen ≈ x 1128, y 414), `power3.inOut`, done by 1.1s, so the typed line reads big. Then it holds; no further camera motion. The rim scales with the window (same group).
Scene 3 (1.67–1.95s): at 1.67s exactly the key cap presses (scale 0.94, fire-orange border and glow, as in Frame 1) for 0.18s and releases (`power3.out`), the moment the footage accepts the gray word.
Scene 4 (1.95–3.6s): hold. The footage keeps typing on its own; nothing else moves.

## Frame 3 — PUSHTYPE

- scene: the end card: the PUSHTYPE wordmark with its red dot, one privacy line, and the web address
- duration: 2.8s
- transition_in: crossfade
- type: cta
- beat: brand lockup and where to get it
- voiceover: "PUSHTYPE. Your words stay on your Mac. www.pushtype.app"
- asset_candidates: none (type only)
- blueprint: titlecard-reveal (Adapt)
- focal: the wordmark
- roles: wordmark = focal · privacy line = supporting · URL = supporting
- poster: 2.4s
- handoff_in: none (crossfade)
- src: compositions/frames/03-end-card.html
- status: animated

Adapt: keep the single restrained move per element then a still hold; a three-line lockup instead of a card chain.

Exact layout, centered on x 960. Wordmark "PUSHTYPE" Archivo 800, `font-stretch: 112%`, 168px, letter-spacing -0.02em, cream, optically centered with its dot at y ≈ 450 (cap-height center); the brand dot is a round #FF5A45 circle 30px across sitting on the baseline 14px after the final E (a circle, not a period glyph). Privacy line "Your words stay on your Mac." Instrument Sans 500, 40px, cream-muted, centered, top ≈ 560. URL "www.pushtype.app" JetBrains Mono 400, 30px, cream, centered, top ≈ 650, inside a pill chip (radius 999, 1px border rgba(239,237,232,0.22), padding 14px 28px).

Scene 1 (0.0–0.7s): the wordmark rises y +24 → 0, opacity 0 → 1 with blur 8px → 0 (→ `spring-pop-entrance`, smooth `expo.out`); the red dot pops in after it at 0.45s: scale 0 → 1 `power3.out` (no overshoot).
Scene 2 (0.7–1.1s): the privacy line fades up y +16 → 0 (`power3.out`).
Scene 3 (1.1–1.5s): the URL chip fades up y +16 → 0 (`power3.out`).
Scene 4 (1.5–2.8s): hold still to the last frame (the music's own ending carries it out). No exit motion.
