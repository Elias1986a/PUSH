---
name: promo
description: Make or change a PUSHTYPE video (social ad, website hero, explainer, intro) end to end, in Remotion (promo/studio) or HyperFrames (videos/), and decide where every media file goes (the content/ library). Use for any request to create, edit, re-cut, re-record footage for, render, or deliver a promo or marketing video, or to make or save music, voice, images, AI shots or other reusable media with any tool (ElevenLabs, Higgsfield, fal, screen recording).
---

# /promo: make or change a PUSHTYPE video

Every PUSHTYPE video goes through these steps, in order. The detail lives in
three files; read them first and follow them over anything general:
`promo/PROMO-PLAYBOOK.md` (brand, claims, voice, look), `promo/studio/CLAUDE.md`
(how to build in Remotion here), `scripts/promo/README.md` (recording real
footage), `content/README.md` (where every file goes). Work in `promo/studio`
for Remotion videos, in `videos/<project>` for HyperFrames ones.

## 0. Where every file goes, whatever the tool
All media lives in `content/`: git-ignored (iCloud backs it up; it never goes
to GitHub). Read `content/README.md`; the short version:
- **Finished:** 9:16 and 4:5 in `content/social/`, 16:9 in `content/videos/`,
  images in `content/images/`. Deliver at 4K, -14 LUFS, true peak -1, named
  `<name>-<ratio>-4k.mp4` (`pushtype-intro-california-9x16-4k.mp4`; a 1080 file
  drops `-4k`). Only the current cut sits there: the one it replaces moves to
  `content/archive/<date>-<name>…`, never left beside it as a lookalike.
- **For review before final:** `content/temp/`; clear it once approved.
- **Workbench:** screen-take masters in `content/raw/takes/`, drafts and tests
  in `content/raw/drafts/`, intermediate renders in `content/raw/renders/<project>/`.
- **Reusable pieces:** `content/assets/` → `music/`, `videos/` (`higgsfield/`
  AI people, `app/` screen recordings), `elements/` (the pill, note stills),
  `voice/` (Jessica, Brad), `brand/` (icon art, fonts), `sfx/`. Save every new
  ElevenLabs track, Higgsfield/fal output or element there the moment it exists,
  with a plain descriptive name and a line in that folder's README (what it
  is, length, tempo/mood or what is said, where it is used).
- **Copies next to code:** Remotion only reads `promo/studio/public/`, a
  HyperFrames project only its own `assets/`; copy the asset in from the
  library and keep those copies in git. Finished app clips stay git-tracked
  in `promo/` too.
- Nothing stays in Downloads or on the Desktop (`~/Desktop/PUSH Content` is a
  shortcut to `content/`).

## 1. Scope, in one line, before anything else
Say back what you will do in one short line and get a yes:
**fix the current video** (default) or **make a new one**, and **which
destination**: Website (the hero), Social (16:9 YouTube, 4:5 feed, 9:16
Reels/Stories/TikTok) or both. The user dictates; a yes to a proposal can mean
"fix it", not "rebuild it" (it has gone wrong before). No scripts to read: say
it short.

## 2. Words and voice
- New lines: write the script to the playbook's story spine and claim checks
  (no competitor names, "www.pushtype.app", qualifiers on screen).
- Narrator in ElevenLabs (playbook §4): all lines for one format in one
  generation, then cut per line into `public/vo/<video>/` and write word
  timings into `TIMINGS.txt` (ElevenLabs transcription with word timestamps).
- Save every take into `content/assets/voice/` (described in its README); the
  copy a video uses goes in `promo/voice/` or the project's assets.

## 3. Footage
- Real app footage carries the video. Anything a viewer must read up close is
  recorded as its own element with `scripts/promo/pilltake.swift` at full
  Retina resolution, holding the key until every word shows. Announce the
  screen takeover first; restore everything after (recipe in the scripts README).
- AI people (Higgsfield) only frame the product. Use the user's pay-as-you-go
  API through `node scripts/promo/higgsfield-gen.mjs` (client in
  `~/Dev/higgsfield-mcp`, key in the Keychain, priced first, capped by
  BUDGET_USD), not the claude.ai Higgsfield connector (a subscription).
- **fal** (`fal` MCP, user scope, pay per run) for image editing: editing a
  still (same person, new angle or setting, removing a logo), background
  removal, upscaling, cleanup; and as the backup for video models Higgsfield
  lacks or when it is down. Search its catalog for the right model, check
  `get_pricing` and say the cost before any paid run. Save results into
  `content/assets/` (described), plus `promo/studio/public/` if a video uses them.
- Check stills before animating, never re-run a billable call.

## 4. Build
- Destination decides the folder and id: `src/videos/<website|social|archive>/`,
  ids `Web…`, `Social…`, `Archive…` + `16x9|4x5|9x16`, registered in `Root.tsx`.
- Reuse `components/` and `footage.ts`; time everything in seconds via `s()`
  from the VO map; hold on stills (`Crop still`), never a frozen video.
- Website copies: same cut with `web` on (bigger small text, captioned hook).
- Keep Studio open (`npm run dev`) so the user can watch.

## 5. Check before showing
Run `./scripts/check.sh <Id>` for every composition you touched (add the
seconds you changed: `./scripts/check.sh <Id> 22.5 24`). Read the sheet it
prints: every word readable at that size, nothing outside the red safe box on
vertical frames, nothing blank or cut off. `npx tsc` must be clean.
**Every 9:16 must stay clear of the TikTok/Reels buttons:** nothing that
matters past x 960 or below y 1500 (the red line). A crossing frame is a fail,
not a note.

## 6. Show, then render
Open Studio on the composition (`open http://localhost:3000/<Id>`) and tell
the user the exact seconds to look at. Render only once they are happy:
`npm run render -- <Id>…` (or `render:website`, `render:social`), then
`./scripts/check.sh <Id>` again for the loudness line (-14 LUFS, true peak
≤ -1).

## 7. Deliver
- Social: render at 4K and copy the finals out of `out/social/` into the
  library (§0): 4:5 (feed ads) and 9:16 (Stories/Reels/TikTok) to
  `content/social/`, 16:9 (YouTube) to `content/videos/`, archiving what they
  replace. HyperFrames: `npx hyperframes render --resolution <landscape|portrait>-4k
  --crf 10`, normalize to -14 LUFS, and the 4:5 is the 4K 9:16 cropped
  `crop=2160:2700:0:570`.
- Website: `npm run to-website`, bump the `?v=` on the hero files in
  `website/index.html` and `website/assets/home.js`, commit, PR, merge, then
  confirm on https://pushtype.app (www redirects there) that the file sizes match.
- Commit at every checkpoint; update `promo/README.md` for new clips.
