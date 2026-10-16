# Promo clips

Finished clips, full quality. Videos built from them are made in Remotion in
`studio/`, labeled by where they go: **Website** (the hero), **Social** (the ad
in 16:9, 4:5 and 9:16) and **Archive** (not in use). See `studio/CLAUDE.md` and
`PROMO-PLAYBOOK.md`. The website uses a compressed copy of
`live-preview.mp4` (`website/assets/video/live-preview.mp4`). How they are
recorded: `scripts/promo/README.md`.

| File | What | Used |
|---|---|---|
| `talk-hero.mp4` | Talk: pill at the top (live preview off) on the dark backdrop, the voice dictating the passage into Notes, cleaned text landing on release. 32 s, with voice. **Real time, no edits**: the voice sits exactly where it was played. | Website, Talk section (`dictation.mp4`) (2026-10-14) |
| `type-demo.mp4` | TYPE: a message to a friend about a Lisbon trip, typed in Notes on the dark backdrop. Shows the spelling fix ("excitd" → excited, Tab), a whole suggestion (`), three single Tabs, and typing on past a suggestion. 38.5 s, no sound. **Real time, real suggestions**: names, places and times are typed; TYPE only finishes everyday phrasing, and every stop was dry-run through the model first. | Website, TYPE section (`typing.mp4`) (2026-10-14) |
| `live-preview.mp4` | Live preview, tight 4:3 shot: small pill at the bottom streaming the words, a small note above it where the cleaned text lands on release. 30.7 s, with voice. | Website, Live preview section (2026-10-14) |
| `type-small.mp4` | TYPE in the tight 4:3 frame of `live-preview.mp4` (1040×780): the same Lisbon message as `type-demo.mp4` in a small note (`freshnote-small.applescript` at 500×372, no pill). 35 s, no sound. **Real time, real suggestions**; live, the whole suggestion after "we could" ran on to "…have dinner at a", so the script continues it with "little place by the water." | Promo candidate (2026-10-15) |
| `live-preview-large-pill.mp4` | The same take idea with the pill at Large, wide 16:9 frame. 30.6 s, with voice. | Promo video candidate |
| `voice/benchmark-passage-jessica.mp3` | The ElevenLabs voice (Jessica) reading the benchmark passage, 27.4 s; speech runs 0.04–27.18 s. | Source audio for both |

`raw/` holds the screen takes these were cut from. It is local only (git
ignores it): re-cut from there rather than recording again.

## What is real and what was edited

Recorded with the debug build and the voice played through the speakers into
the microphone, so the transcription, the live words and the cleanup are the
app's own. Two edits, agreed with the user ("it's a promo, not a church"):

- `live-preview.mp4`: the voice sits so the pill trails it by about 0.5 s
  (really about 1.8 s), and the stretch from the first words to the key
  release plays 7% slower, so the voice still ends right as the key comes up.
  From the release on, everything is real speed: the text lands about 0.35 s
  later.
- `live-preview-large-pill.mp4`: the voice moved 0.7 s later, no slowdown.

The voice track is the original file laid under the video afterwards
(`screencapture` records no sound).
