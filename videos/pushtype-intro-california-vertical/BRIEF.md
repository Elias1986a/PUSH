---
workflow: product-launch-video
flow: automation
storyboard: no
message: "PUSH to talk. Tab to TYPE."
destination: website
aspect: 1080x1920 (4:5 = its center crop)
language: en
audience: Mac users who write a lot
length: 12.5s
angle: talk-plus-type
narration: no
---

## Intent

A 10-second product intro for PUSHTYPE (https://pushtype.app), a Mac app for
dictation and autocomplete. It sells the product, not a site tour. Two beats
from the site's own headline: "PUSH to talk." then "Tab to TYPE.", closing on
the PUSHTYPE wordmark and pushtype.app.

## Assets

- assets/footage/talk-clip.mp4 — real Talk recording (repo `promo/studio/public/footage/live-preview.mp4`, 25.0–30.3s, cleaned 2×): pill streams words, text lands at 3.07s. Frame 1.
- assets/footage/type-clip.mp4 — real TYPE recording (repo `type-small.mp4`, 20.3–24.2s): Tab accepts "take" at 1.67s. Frame 2.
- assets/music/clean-pulse-11s-ducked.mp3 — ducked about 10 dB under Jessica for 0–2.7 s, back up by 3.3 s; the explainer's "Clean Pulse" bed (repo `music_loop_16x9.mp3`, last 11.5s with its original ending), -14 LUFS. Root music bed.

## Notes

- Music (2026-10-16, user: "a lot more upbeat, California vibes", one ElevenLabs generation only): `assets/music/source/elevenlabs-california-surf-13s.mp3` (Music v2.5, instrumental, 13 s; prompt: sunny West Coast surf-pop, ~118 BPM, spring-reverb guitar, bouncy bass, handclaps). Its final hit is at 8.62 s, so it is laid 1.08 s late to land on the end card (9.7 s), then loudnormed and ducked to 0.2 under the voice to 2.7 s, full by 3.3 s: `assets/music/california-surf-12s-ducked.mp3`.
- Vertical review (2026-10-16, user: the Notes window was "just too far away" for the dictation part): frame 1 drops the Notes recording for the live pill alone, `assets/footage/pill-clip.mp4` = `promo/raw/pill-large-take.mov` (master of `promo/pill-large.mp4`) 27.0–31.8 s. Shown at 1.12× masked to its right end (source x 940–1743 on screen x 60–960, left edge faded), with a slow push-in. Played at 1.25× from source 0.57 s so each chunk lands just after she says it: "Could you like" 0.65 s, "send the final numbers" 1.46 s, "before Friday" 2.33 s; the sunset wipes up at 2.75 s.
- Vertical versions (2026-10-16): the straight-to-California cut re-laid for 9:16, everything that matters inside the TikTok/Reels-safe column x 60–960, y 340–1500 (promo/PROMO-PLAYBOOK.md). Footage boxes at 0.92 (Talk) and 0.836 (TYPE, zooming to 1.12 about the window's center so it ends 900 wide); headlines 116 px; the California title on two lines and the sentence on three with fixed breaks. The 4:5 is the 9:16 cropped at y 285–1635, not a separate edit: `ffmpeg -vf crop=1080:1350:0:285`. Renders: `renders/pushtype-intro-california-9x16-1080x1920.mp4`, `renders/pushtype-intro-california-4x5-1080x1350.mp4`.
- Straight-to-California cut (2026-10-16, user: "only show California mode after she says it… instead of showing the render of the finalized text"): copied from `videos/pushtype-intro-voice`. The sunset wipes up at 2.75 s as her voice ends and covers the note before the text lands (3.2 s); the California card is the first place the sentence is seen. Frame 1 ends at 3.3 s, California 2.75–6.4 s, Tab to TYPE 6.1 s, end card 9.7–12.5 s. Review: the clean-sentence hold was 1.5 s too long; 15 s is a maximum, not a target. Music bed re-cut to 12.5 s so its ending still lands on the end card.
- Review 3 (California mode): a 3.5 s beat after Talk shows the "like" she said being removed by California mode, in the website's California styling. Total 15 s. Frame 1 runs to 5.6 s under the wipe; Tab to TYPE starts at 8.6 s, the end card at 12.2 s. Her "like" is not echoed in the audio: an isolated cut could not be confirmed by transcription.

- Version 2 (voice): Jessica's real voice under the Talk section, `assets/voice/jessica-final-question.wav` = `promo/voice/benchmark-passage-jessica.mp3` 24.55–27.40 s, laid at 0 s (the take's measured 0.45 s offset, so it matches the footage). She says "Could you, like, send the final numbers before Friday?"; the note lands with "Could you send the final numbers before Friday?". The live pill trails her by about 2 s in this take (real), so it still shows the previous sentence while she speaks.

- Review 1: hold the landed Talk text about 2s before cutting (it went by too fast to read). Frame 1 is now 5.1s; total 11.5s.

- Users see the name PUSHTYPE. Feature names: Talk and TYPE (all caps); PUSH always in caps.
- American spelling. On-screen copy should be short enough to read in 10 seconds.
- Privacy line, if used: "What you say and type never leaves your Mac."
- No narrator. Jessica (the user dictating on screen) is the only voice.
