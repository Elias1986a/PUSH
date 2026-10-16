# Explainer video plan (2026-10-15)

20 seconds, two cuts from one Remotion project: 16:9 (1920×1080, website) and
9:16 (1080×1920, Instagram, TikTok, and X). 30 fps. Talk and TYPE get the
time; the teleprompter gets one beat.

## Voiceover (Jessica, ElevenLabs; the user generates it)

Paste as one take. About 38 words, ~15 s spoken, leaving room between beats.

> Hold a key, and just talk.
> PUSHTYPE turns your voice into clean text, right where you're typing.
> Or start typing, and it finishes your sentence. Press Tab to take it.
> On camera? The teleprompter follows your voice.
> PUSHTYPE. Everything stays on your Mac.

Save as `promo/voice/explainer-vo.mp3`. I cut the picture to the voice.

## Storyboard

| Time | Picture | Source |
|---|---|---|
| 0–2.5 s | A person at a desk presses a key and starts speaking; the screen faces away or is out of focus | Higgsfield shot A |
| 2.5–8 s | Animated pill grows from the key press; cut into the real Talk clip: words land in Notes on release | `promo/talk-hero.mp4` (real), Remotion |
| 8–9.5 s | Hands on a keyboard, close | Higgsfield shot B |
| 9.5–14 s | The real TYPE clip: gray suggestion, Tab chip pops on each accept | `promo/type-demo.mp4` (real), Remotion |
| 14–16.5 s | A person facing a camera, eyes on the top of the screen; the real prompter tab animates in over it | Higgsfield shot C + a new 3 s screen recording of the teleprompter |
| 16.5–20 s | End card: PUSHTYPE wordmark, "PUSH to talk. Tab to TYPE.", "Everything stays on your Mac.", pushtype.app | Remotion |

Look: the website's (dark background, orange accent, mono labels). Captions
follow the voice, large, so the vertical cut works muted.

## Honesty rules (from the demo clips)

- Every app UI shown is a real recording. Generated shots never show a
  screen with UI on it: screens face away or are out of focus.
- No speed shown that isn't real; TYPE only finishes everyday phrasing.
- No real person's name or likeness; Higgsfield people are invented.

## Higgsfield (budget $5)

Kling 3.0 Turbo, 1:1 at 1080p, 4 s each (~$0.38 per clip, Higgsfield's own
estimate). Square fits both cuts: full-bleed blocks in the vertical cut, a
panel beside the UI in the wide one. One character still first (image model),
then image-to-video for each shot, so it is the same person throughout.

| Shot | Prompt idea |
|---|---|
| A | Warm evening light, person at a desk with a laptop, thumb presses a key, starts talking naturally; laptop screen turned away from camera |
| B | Close-up of hands typing on a laptop keyboard, shallow focus on the keys, screen blurred |
| C | Person facing a small camera on a tripod, ring light, recording themselves, eyes reading near the top of a monitor that is out of frame |

Expected: ~$1.20 for three shots, up to ~$2.50 with one retry each, plus the
still. Every request is estimated first and stops if it would pass $5 in
total.

## Still needed

- The voiceover mp3 (user).
- Music: a 20 s bed. ElevenLabs can make one, or none.
- A 3 s real recording of the teleprompter (needs the Mac for ~2 min).

Remotion project: `promo/explainer/` (node_modules ignored); renders to
`promo/explainer-16x9.mp4` and `promo/explainer-9x16.mp4`.
