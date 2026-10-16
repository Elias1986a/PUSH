---
name: promo
description: Make or change a PUSHTYPE video (social ad, website hero, explainer) end to end in promo/studio. Use for any request to create, edit, re-cut, re-record footage for, render, or deliver a promo or marketing video.
---

# /promo: make or change a PUSHTYPE video

Every PUSHTYPE video goes through these steps, in order. The detail lives in
three files; read them first and follow them over anything general:
`promo/PROMO-PLAYBOOK.md` (brand, claims, voice, look), `promo/studio/CLAUDE.md`
(how to build in Remotion here), `scripts/promo/README.md` (recording real
footage). Work in `promo/studio`.

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
- Keep every source file in the repo (`promo/voice/`, `promo/`), never only in
  Downloads or on the Desktop.

## 3. Footage
- Real app footage carries the video. Anything a viewer must read up close is
  recorded as its own element with `scripts/promo/pilltake.swift` at full
  Retina resolution, holding the key until every word shows. Announce the
  screen takeover first; restore everything after (recipe in the scripts README).
- AI people (Higgsfield) only frame the product. Use the user's pay-as-you-go
  API through `node scripts/promo/higgsfield-gen.mjs` (client in
  `~/Dev/higgsfield-mcp`, key in the Keychain, priced first, capped by
  BUDGET_USD), not the claude.ai Higgsfield connector (a subscription). fal
  (`fal` MCP, pay per run) is the backup for models Higgsfield lacks or when
  it is down; check `get_pricing` first. Check stills before animating, never
  re-run a billable call.

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

## 6. Show, then render
Open Studio on the composition (`open http://localhost:3000/<Id>`) and tell
the user the exact seconds to look at. Render only once they are happy:
`npm run render -- <Id>…` (or `render:website`, `render:social`), then
`./scripts/check.sh <Id>` again for the loudness line (-14 LUFS, true peak
≤ -1).

## 7. Deliver
- Social: hand over the files in `out/social/` (4:5 for feed ads, 9:16 for
  Stories/Reels/TikTok, 16:9 for YouTube); copy dated finals to
  `promo/raw/<campaign>/` if they should be kept.
- Website: `npm run to-website`, bump the `?v=` on the hero files in
  `website/index.html` and `website/assets/home.js`, commit, PR, merge, then
  confirm on https://pushtype.app (www redirects there) that the file sizes match.
- Commit at every checkpoint; update `promo/README.md` for new clips.
