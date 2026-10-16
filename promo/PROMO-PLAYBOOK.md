# PUSHTYPE Promo Playbook

How we make PUSHTYPE ad videos: the rules, the look, the pipeline and what we learned. Start here for every new video.

Last updated: 2026-10-15 (first promo, "v5" intro).

---

## 1. Deliverables

Every ad promo ships in three formats, rendered at 1080 (no 4K for ads for now). The website gets its own 16:9 4K hero (`pushtype-hero-16x9-4k.mp4`: render with `--scale=2`, `-movflags +faststart`).

| Format | Size | Use it for |
|---|---|---|
| 16:9 | 1920×1080 | YouTube, website, in-stream |
| 4:5 | 1080×1350 | Facebook and Instagram Feed |
| 9:16 | 1080×1920 | Stories, Reels, TikTok |

- Design the vertical once, in 9:16, with everything important inside the 4:5 safe area. The 4:5 is the center of that layout (`Promo4x5` in Remotion), not a separate edit.
- The 16:9 is its own edit (wider layouts, longer VO), never a crop.
- In Meta Ads, put the 4:5 on Feed placements and the 9:16 on Stories and Reels in the same ad set.

### Vertical safe zones (1080×1920)

| Zone | Pixels | Rule |
|---|---|---|
| 4:5 area | y 285 to 1635 | Anything outside can be cropped in feed |
| TikTok / Reels UI | bottom 420 px, right 120 px | Buttons and captions cover it |
| **Text and key visuals** | **x 60 to 960, y 340 to 1500** | Keep everything that matters here |

Captions sit at y 370 (that is y 85 in the 4:5).

---

## 2. Look

- **Background:** near-black `#08080a`. The original charcoal looked washed out and cheap; near-black was "night and day better".
- **Dark UI on black:** give windows and cards a rim light (1px light outline plus faint halo) and lift recordings slightly (`brightness 1.14`), so the Notes window keeps visible edges. Draw rims as `box-shadow` on rounded rects behind each shape, not CSS `drop-shadow` filters: filters on video made 4K renders 3 to 4× slower.
- **Glow:** the website's soft violet (top left) and coral (bottom right) glows stay, subtle.
- **Fonts:** Archivo (display, 800, stretch 112%), Instrument Sans (body), JetBrains Mono (keys, URL). Inter only as a stand-in for macOS text typed into a recorded note.
- **Colors:** ink `#efede8`, secondary `#bdb9b1`, accent red `#ff5a45`, walnut labels `#b88a63`.
- **Brand dot:** use the round red PUSHTYPE dot (not a square period) after standalone brand statements like "$35•". Real sentences keep normal periods.
- **Video encoding:** always tagged bt709 / yuv420p (`Config.setColorSpace("bt709")`). The first renders were tagged as full-range bt470bg, which lifts blacks in many players.
- **Recordings never show their own backdrop.** Cut them to their real shapes (window, pill, notch) so no off-black rectangle shows. Zoomed crops inside a window become framed cards.

---

## 3. Brand and messaging rules

- **CTA:** always `www.pushtype.app`, with the www. A bare .app domain confuses people.
- **Hero messages:** privacy (your voice and words stay on your Mac) and price ($35 once vs. a subscription). Speed is a supporting nod in intro videos, not the hook.
- **Competitor:** never named. Say "subscription dictation" or "most dictation apps". Real numbers are fine: $12/mo, $144/yr.
- **Story spine:** problem (cloud and a monthly bill), the turn (it stays on your Mac), proof (real footage: messy speech to clean text, Tab finishing sentences), the twist (it learns you, on device), price, end card.
- **Show the product.** Real screen recordings carry most of the runtime; AI people are only framing.

### Claim checks

| Claim | Status | On-screen qualifier |
|---|---|---|
| Your voice and words stay on your Mac | Accurate | None. Avoid "nothing ever leaves": license checks, updates and iCloud settings sync do connect |
| It learns how you write | Off by default | "Learning is opt-in." |
| $35 once | Launch price ($50 regular) | "Launch price · up to 3 Macs" |
| 20× faster than cloud | PUSHTYPE's own benchmark | "PUSHTYPE benchmark, see www.pushtype.app" if used |

---

## 4. Voice and audio

- **Narrator:** male, warm, conversational, not an announcer. Current: ElevenLabs "Hey It's Brad - Clear Narrator for Documentary".
- **User voice:** Jessica (ElevenLabs), the person dictating on screen. Narrator and user are two roles, never mixed.
- **ElevenLabs workflow:** paste all narrator lines for one format as one generation, one paragraph per line, so the read stays consistent; cut into per-line clips afterward. Make one version at a time unless asked for more. Spell the name "Push-type" and write prices out ("Thirty-five dollars").
- **The messy dictation take** lives in the audio of `live-preview.mp4` (with "um", "like", "15.2... I mean, 1.52", "quote / end quote", "new paragraph"). The separate `voice/benchmark-passage-jessica.mp3` is a clean read.
- **Music:** the explainer bed ("Clean Pulse"), looped on the beat with its original ending kept (`music_loop_16x9.mp3`, `music_loop_9x16.mp3`). About 12 dB under VO, up on the end card.
- **Loudness:** normalize finals to -14 LUFS, true peak -1 dB.

---

## 5. Pipeline

1. **Script and shot list** (doc): one idea, beats timed to VO, a 16:9 and a vertical shot list.
2. **VO** in ElevenLabs, then cut per line and get word timings (faster-whisper). Timings drive every cut and caption.
3. **Screen recordings** of the real app (scripts in `scripts/promo/`). Record at the 1040×780 Notes framing for vertical-friendly layouts. Next time: record at Retina 2× with a higher bitrate; the current takes are 1x and soft.
4. **AI shots** in Higgsfield (local API on the Mac): one base still, edit it for other angles so the person matches, then image-to-video. Check stills before animating. Remove brand logos (for example the Apple logo on the laptop).
5. **Build in Remotion** (`promo/studio`; how: `promo/studio/CLAUDE.md`).
6. **QA:** stills at key moments for both formats against the safe-zone guides; transcribe the final mix to confirm VO order and timing; check loudness.
7. **Deliver** 16:9, 4:5, 9:16 to `promo/raw/explainer/<version>/`.

---

## 6. Higgsfield

| Use | Model | Cost |
|---|---|---|
| Base still | `z-image/turbo` (2k) | $0.015 |
| Still edits (same person, new angle) | `xai/grok-imagine-image-2.0` (2k) | $0.09 |
| Still edits (alt, was down 2026-10-15) | `alibaba/qwen-image-3/edit` | $0.04 to $0.075 |
| Image to video, 5s, sound off | `kling-video/v3.0/pro/image-to-video` | $0.476 |

- Kling 3.0 Pro at 5s with sound off costs the same as Turbo 1080p and looks better.
- Budget: about $1.50 to $2 per promo (one person, three clips, a few edits). First promo total: about $3.02 including the discarded draft 4 shots.
- Generations can outlast the 60s tool wait. Never re-run a billable call; check `~/Downloads/Higgsfield` for the file instead.

**Current person** (from 2026-10-15): late twenties, shoulder-length dark curly hair, olive sweater, light oak desk, soft window light. Files `shot-a-v2.mp4` (talking to laptop), `shot-b-v2.mp4` (hands typing), `shot-v.mp4` (vertical hook).

---

## 7. Remotion project

`promo/studio`, Remotion 4.0.535, React 19, in git. One project for every video; `promo/studio/CLAUDE.md` is the how-to for agents, and Remotion's own agent skills are installed in it.

| File | What |
|---|---|
| `src/brand/tokens.ts` | Colors, fonts |
| `src/lib/` | `s()` seconds-to-frames, `lerp`, `rise`, `mixRect` |
| `src/footage.ts` | The recordings: sizes, UI shapes for masks, key moments |
| `src/components/` | Crop (shape masks, cards), captions, labels, keys, price, end card, brand dot |
| `src/videos/promo/` | `Wide` (16:9), `Tall` (9:16, 4:5-safe), `Feed` (4:5), `beats` (redline, sign-off note, words to cloud) |
| `src/Root.tsx` | Compositions: `Promo16x9`, `Promo4x5`, `Promo9x16`, `Explainer16x9`, `Explainer9x16` |

```bash
npm run dev            # Studio: preview every composition
npm run render:promo   # out/Promo16x9.mp4, Promo4x5, Promo9x16, audio at -14 LUFS
npm run render -- --4k Promo16x9
```

- 4K uses `--scale=2 --concurrency=1` (the render script sets both); with the default concurrency a small machine runs out of memory.
- Frames render as PNG (`Config.setVideoImageFormat("png")`) for clean text edges.
- `public/footage` holds the recordings cleaned and upscaled 2× (denoise, Lanczos, light sharpen, 30 fps). Measured UI shapes for masks live in `SHAPES` in `src/footage.ts`.
- Key source moments: `live-preview.mp4` pill closes at 27.65s, text lands 28.07s. `type-small.mp4` Tab takes "take" at 21.97s and "you think!" at 27.77s.

---

## 8. Lessons from the first promo

- Feature tours feel flat. Lead with a problem and a turn, then prove it.
- Readability at phone size beats showing the whole screen: push in on the line that matters.
- Edges of clipped recordings show on dark backgrounds. Mask to real shapes, not rectangles.
- The live preview pill is too small for phones on its own; burned-in word captions carry it.
- AI people for framing only; about 6 seconds of a 50-second spot.

## 9. Open items

- Re-record screen takes at Retina 2× and higher bitrate.
- The sign-off name "Maya" is a placeholder.
- Optional proof shots for later videos: Wi-Fi off while dictating, teleprompter, the 20× speed race.
