# CLAUDE.md — PUSHTYPE studio (Remotion)

Motion graphics for PUSHTYPE (the website hero, the social ads), written as
React and rendered with Remotion 4. **Brand, messaging,
claims, voice and the ad pipeline live in `../PROMO-PLAYBOOK.md`; read it
before making or changing any video.** This file is how to build one here.

## Where each video goes
Everything is labeled by destination: the Studio folder, the composition id's
prefix, the source folder and the render folder all say the same thing.

| Destination | Studio folder | Ids | Source | Renders to | Then |
|---|---|---|---|---|---|
| pushtype.app | Website | `WebHero16x9` (laptops), `WebHero4x5` (phones): the promo's website edition | `src/videos/website/` | `out/website/` | `npm run to-website` writes the small copies + posters into `website/assets/video/` |
| Ads and posts | Social | `SocialPromo16x9` (YouTube), `SocialPromo4x5` (Instagram/Facebook feed), `SocialPromo9x16` (Reels, Stories, TikTok) | `src/videos/social/` | `out/social/` | copy the approved finals into the content library: `content/social/` (9:16, 4:5), `content/videos/` (16:9), as `pushtype-promo-<ratio>-4k.mp4` |
| Not in use | Archive | `ArchiveHeroShort16x9`/`4x5` (a 21 s product-first hero, not chosen), `ArchiveExplainer16x9`/`9x16` | `src/videos/archive/` | `out/archive/` | nothing |

`out/` is this project's scratch (each render overwrites it). Finished files,
reusable media and takes live in the git-ignored `content/` library at the
repo root: read `content/README.md`. Remotion only reads `public/`, so copy an
asset from `content/assets/` into `public/` to use it.

The website hero is the promo itself (the user likes it as it is) in its
website edition: `<Wide web />` / `<Feed web />`. The site plays it muted at
about a quarter of its size, so `web` raises every small text to a minimum
(`MinText`: 44 px wide, 40 px feed; read it with `useLegible(size)` in any new
small text) and captions the hook. Change the cut in `videos/social/promo` and
both follow. Check website stills scaled to their real size (496 px wide for
the 16:9, 327 px for the 4:5) before calling them done.

## Commands (run in promo/studio)
- `npm run dev`: Remotion Studio at http://localhost:3000. Every composition is
  in the left sidebar, grouped by destination, with a timeline you can scrub. It hot-reloads
  on save; keep it open while you work so the user can watch.
- `npx remotion still <Id> out/check.png --frame=<n>`: one frame as PNG. Use
  stills to check your work (read the PNG back), not just the type check.
- `npm run typecheck`: `tsc`; must be clean.
- `npm run render:website` / `render:social` / `render:archive` / `npm run render -- <Id>...`:
  renders to `out/<group>/<Id>.mp4` (git-ignored), then normalizes audio to
  -14 LUFS, -1 dBTP. `npm run render -- --4k <Id>` renders at 2× (`<Id>-4k.mp4`).
- `npm run to-website`: after `render:website`, encodes the site's copies
  (`hero.mp4`, `hero-4x5.mp4` and their `.jpg` posters) into `website/assets/video/`.
- `npx remotion add <package>`: add any `@remotion/*` package. It pins the
  same version as `remotion`; mismatched versions break the bundle.
- `./scripts/check.sh <Id> [seconds…]`: stills at the size people see them,
  tiled into `out/check/<Id>.png`, safe-zone guides on vertical frames, and the
  render's loudness. Run it on every composition you change.
- `ffmpeg` / `ffprobe` (Homebrew, full build) for anything else; `npx remotion
  ffmpeg` is a trimmed fallback (no ebur128, psnr, tile, fps, rawvideo). In zsh
  scripts, brace variables before a colon (`${LN}:${x}`): `$x:l…` is a zsh
  modifier and silently mangles ffmpeg filter strings.
- The whole flow, step by step: the `/promo` skill (`.claude/skills/promo`).

## Layout
```
src/
  Root.tsx              registers every composition in Website / Social / Archive folders
  brand/tokens.ts       color, font (importing it loads the fonts)
  lib/time.ts           FPS (30), s(seconds) → frames
  lib/anim.ts           lerp, rise, mixRect, clamp, Box/Rect
  footage.ts            catalogue of real recordings: sizes, SHAPES, key moments, SHOTS
  components/           shared: Scene, Glow, FullShot, Label, Headline, BrandDot,
                        WordCaptions, KeyChip, Meter, icons, Crop, EndCard, PriceStack
  videos/website/Hero.tsx     the site hero: the promo with `web` on
  videos/social/promo/  the ad: Wide (16:9), Tall (9:16), Feed (4:5), beats
  videos/archive/       hero-short/ (unused 21 s hero), explainer/ (unused)
public/
  fonts/  footage/  shots/  music/  vo/<video>/    shared assets; staticFile("footage/…")
  explainer/            the archived explainer's own copies
.agents/skills/         Remotion's official agent skills (.claude/skills links here)
scripts/render.sh       render + loudness normalize, into out/<group>/
scripts/to-website.sh   web-size copies + posters of the hero for the site
```

## Making a new video
1. Script and VO first (playbook §5): cut the VO per line into `public/vo/<video>/`
   and write word timings into `TIMINGS.txt` beside them. Timings drive every cut.
2. Decide where it goes (table above) and create `src/videos/<destination>/<video>/`.
   For social: a 16:9 edit (`Wide`), a 9:16 edit designed 4:5-safe (`Tall`), and
   `Feed`, the 4:5 crop of `Tall` (copy `videos/social/promo/Feed.tsx`). The 16:9
   is its own edit, never a crop.
3. Register them in `Root.tsx` in that destination's `<Folder>`, ids
   `<Destination><Video><Format>` (`SocialLaunch9x16`, `WebPricing16x9`), sizes
   from `SIZE`, `fps={FPS}`, `durationInFrames={s(seconds)}`. render.sh files
   renders by the prefix and refuses an id without one.
4. Build from `components/` and `footage.ts`. Put anything with baked-in words
   in the video's own folder (as `videos/social/promo/beats.tsx` does). Promote a piece
   to `components/` once a second video needs it.
5. Check stills at each beat in every format, then render.

## Scenes and timing
- Write every time in **seconds of the finished video** and convert with `s()`.
  Keep a map of when each VO line starts (`VO_AT` in `videos/social/promo/Wide.tsx`) and
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
- The live preview pill is `PillTake` (the sharp Large-pill take) laid where
  live-preview.mp4's own soft pill was; push in with `pillPushIn()` so its
  pixels stay ≤ 1.4×. Never zoom the old pill. Record new UI as its own element
  at full Retina resolution (`scripts/promo/pilltake.swift`), not with
  `screencapture -v` (~1–2 Mbps).
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

**Rule (user, 2026-10-15): every 9:16 stays clear of the TikTok/Reels
buttons.** Nothing that matters may cross x 960 (the like/comment/share
column) or sit below y 1500. `check.sh` draws that line in red on every 9:16;
a frame that crosses it is not done. The vertical cut is shared with the 4:5,
so the 9:16 turns on `clearOfButtons` (cards 870 wide instead of 900, the
headline and cloud pulled in); give any new shared vertical layout the same
switch.

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
- The archived explainer (`videos/archive/explainer`) uses the old charcoal palette
  and its own assets in `public/explainer`. Edit it only on request.
- To hold on a moment of a recording, cut to a PNG still of that frame
  (`Crop still`), never `<Freeze>` around a video: Studio's preview reloads the
  frozen video at its first frame, so the hold shows the wrong picture there
  even though renders look right (the release shot, 2026-10-15).
- Composition props must be a `type`, not an `interface` (Remotion needs
  `Record<string, unknown>`).
- `remotion.config.ts` applies to the CLI and Studio only: PNG frames (clean
  text), bt709 color tagging, rspack.
- 4K on this Mac: `--concurrency=1` (render.sh sets it), or the compositor runs
  out of memory.
- `npm install` warns that esbuild's install script was skipped; that's harmless.
- The repo sits in iCloud-synced ~/Documents. If Studio or a render hangs reading
  files, iCloud may have evicted part of `node_modules`: `rm -rf node_modules && npm install`.
