# CLAUDE.md — PUSHTYPE studio (Remotion)

Motion graphics for PUSHTYPE: the ad promo (16:9, 4:5, 9:16) and the website
explainer, written as React and rendered with Remotion 4. **Brand, messaging,
claims, voice and the ad pipeline live in `../PROMO-PLAYBOOK.md`; read it
before making or changing any video.** This file is how to build one here.

## Commands (run in promo/studio)
- `npm run dev`: Remotion Studio at http://localhost:3000. Every composition is
  in the left sidebar, grouped by video, with a timeline you can scrub. It hot-reloads
  on save; keep it open while you work so the user can watch.
- `npx remotion still <Id> out/check.png --frame=<n>`: one frame as PNG. Use
  stills to check your work (read the PNG back), not just the type check.
- `npm run typecheck`: `tsc`; must be clean.
- `npm run render:promo` / `npm run render:explainer` / `npm run render -- <Id>...`:
  renders to `out/<Id>.mp4` (git-ignored), then normalizes audio to -14 LUFS,
  -1 dBTP. `npm run render -- --4k <Id>` renders at 2× (`out/<Id>-4k.mp4`).
- `npx remotion add <package>`: add any `@remotion/*` package. It pins the
  same version as `remotion`; mismatched versions break the bundle.
- `npx remotion ffmpeg` / `npx remotion ffprobe`: ffmpeg is not installed on
  this Mac; use Remotion's. It is a trimmed build: loudnorm, aac and mp4 work, but
  rawvideo, md5, psnr and ebur128 don't. Measure loudness with
  `-af loudnorm=print_format=summary -f null -`.

## Layout
```
src/
  Root.tsx              registers every composition, one <Folder> per video
  brand/tokens.ts       color, font (importing it loads the fonts)
  lib/time.ts           FPS (30), s(seconds) → frames
  lib/anim.ts           lerp, rise, mixRect, clamp, Box/Rect
  footage.ts            catalogue of real recordings: sizes, SHAPES, key moments, SHOTS
  components/           shared: Scene, Glow, FullShot, Label, Headline, BrandDot,
                        WordCaptions, KeyChip, Meter, icons, Crop, EndCard, PriceStack
  videos/<video>/       one folder per video; promo/ (Wide, Tall, Feed, beats), explainer/
public/
  fonts/  footage/  shots/  music/  vo/<video>/    shared assets; staticFile("footage/…")
  explainer/            the explainer's own frozen copies
.agents/skills/         Remotion's official agent skills (.claude/skills links here)
scripts/render.sh       render + loudness normalize
```

## Making a new video
1. Script and VO first (playbook §5): cut the VO per line into `public/vo/<video>/`
   and write word timings into `TIMINGS.txt` beside them. Timings drive every cut.
2. Create `src/videos/<video>/` with one component per format: a 16:9 edit
   (`Wide`), a 9:16 edit designed 4:5-safe (`Tall`), and `Feed`, the 4:5 crop of
   `Tall` (copy `videos/promo/Feed.tsx`). The 16:9 is its own edit, never a crop.
3. Register them in `Root.tsx` inside a `<Folder name="…">`, ids `<Video><Format>`
   (`Launch16x9`), sizes from `SIZE`, `fps={FPS}`, `durationInFrames={s(seconds)}`.
4. Build from `components/` and `footage.ts`. Put anything with baked-in words
   in the video's own folder (as `videos/promo/beats.tsx` does). Promote a piece
   to `components/` once a second video needs it.
5. Check stills at each beat in every format, then render.

## Scenes and timing
- Write every time in **seconds of the finished video** and convert with `s()`.
  Keep a map of when each VO line starts (`VO_AT` in `videos/promo/Wide.tsx`) and
  time scenes and animations from it.
- `<Scene at until fade>` is a `Sequence` with short fades. Inside it,
  `useCurrentFrame()` counts from the scene's start, so in-scene times are local.
  Comment the local zero (`// Local 0 = 23.4 s`).
- Overlap neighbouring scenes by 0.05–0.25 s so the fades cross instead of dipping to black.
- Times inside a recording are seconds into the source file (`from`, `rate` on
  `Crop`); key moments are in `footage.ts`. Land the on-screen action under the
  word that names it (Tab pressed under "Tab").

## Animating typography and graphics
- Animate only from `useCurrentFrame()` with `interpolate`/`lerp`/`spring`. CSS
  transitions, CSS animations and Tailwind animate classes do not render.
- House motion: `rise()` (fade + 30 px rise, spring damping 200, no bounce) for
  entrances; stagger by 6–8 frames. Use a bouncy spring (damping 12–14) only for
  a hit, such as the price slam or the meter.
- Text: `Headline` (Archivo 800, stretch 112%, -0.02em, one accent phrase in
  `color.onAir`), `Label` for walnut section tags, `WordCaptions` for word-by-word
  burned-in captions (vertical cuts need them; viewers watch muted).
- Use only `color`/`font` from `brand/tokens.ts`; never hard-code a new hex.
  Use `BrandDot` after standalone brand statements ("$35•").
- Real UI: `Crop` a recording. Use `shapes={[SHAPES.…]}` to keep only the real
  window/pill/notch, or `card` for a zoomed crop framed as a card. Never show a
  recording's own backdrop rectangle. Push in with `mixRect` + `lerp`.
- Rim light is `box-shadow`, never CSS `drop-shadow` or blur filters on video
  (3–4× slower at 4K).

## Audio
- VO: one `<Sequence from={s(VO_AT.x)}><Audio src={staticFile("vo/…")} /></Sequence>`
  per line.
- Music: the `volume={(f) => interpolate(...)}` callback. About 0.16 under VO
  (~12 dB down), 0.32 on the end card, fade out over the last 0.7–0.8 s.
- Dictation audio (Jessica) comes from inside `live-preview.mp4`, cut to match;
  keep it in sync with the footage it was cut from.
- `render.sh` normalizes the final; don't normalize sources.

## Formats and safe zones
16:9 1920×1080 · 4:5 1080×1350 · 9:16 1080×1920. In 9:16, keep text and key
visuals inside x 60–960, y 340–1500 (4:5 area is y 285–1635; TikTok/Reels UI
covers the bottom 420 px and right 120 px). Captions sit at y 370.

## Remotion skills vs. house rules
`.agents/skills/remotion-*` (installed with `npx remotion skills add`, refresh
with `npx remotion skills update`) are Remotion's general guidance: load
`remotion-best-practices` when unsure. Where they differ, this file wins:
- Time is seconds through `s()`, not `n * fps` inline.
- The existing videos use `OffthreadVideo` and `Audio` from `remotion` and are
  pixel-verified; leave them. New code may use `@remotion/media` as the skills
  suggest (`npx remotion add @remotion/media`).
- Don't start renders on your own; preview in Studio and render when asked or
  when delivering.

## Gotchas
- The explainer (`videos/explainer`) shipped on the old charcoal palette with its
  own assets in `public/explainer`. It is frozen: edit it only on request.
- Composition props must be a `type`, not an `interface` (Remotion needs
  `Record<string, unknown>`).
- `remotion.config.ts` applies to the CLI and Studio only: PNG frames (clean
  text), bt709 color tagging, rspack.
- 4K on this Mac: `--concurrency=1` (render.sh sets it), or the compositor runs
  out of memory.
- `npm install` warns that esbuild's install script was skipped; that's harmless.
- The repo sits in iCloud-synced ~/Documents. If Studio or a render hangs reading
  files, iCloud may have evicted part of `node_modules`: `rm -rf node_modules && npm install`.
