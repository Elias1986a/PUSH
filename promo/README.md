# Promo clips

Finished clips, full quality. The website uses a compressed copy of
`live-preview.mp4` (`website/assets/video/live-preview.mp4`). How they are
recorded: `scripts/promo/README.md`.

| File | What | Used |
|---|---|---|
| `live-preview.mp4` | Live preview, tight 4:3 shot: small pill at the bottom streaming the words, a small note above it where the cleaned text lands on release. 30.7 s, with voice. | Website, Live preview section (2026-10-14) |
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
