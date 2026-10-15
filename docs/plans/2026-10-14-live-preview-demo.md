# Live preview demo clip (plan, not recorded)

**Goal:** a 15–20 s muted clip for the website's Live preview band and the
promo video: words appear in the pill while the sentence is still being
spoken, then the clean text lands in Notes on release.

## The shot

- Notes, same recipe as the TYPE demo (Window ▸ Open Note in New Window,
  1088×592 at 608,352, plain backdrop, Format ▸ Body, View ▸ Zoom In ×4,
  record region 512,288,1280,720 with `screencapture -v`).
- Settings for the take: Parakeet Streaming, Settings ▸ Pill ▸ "Show text in
  the pill as you speak" on, pill at the **top (notch)** so the words sit
  right above the note, text size Large. Restore the user's settings after.
- The note starts with content, no title line ("Hi Sam,").
- One sentence per press, two presses:
  1. "Can we move the launch to Thursday and send the deck tonight?"
  2. "I'll bring the numbers, you bring the coffee."
- What has to be visible: the pill filling word by word *during* each
  press, then the cleaned sentence (capital, punctuation) appearing in the
  note the moment the key is released.

## Who speaks

The clip is muted, but the model needs real audio.

- **Option A, your voice (best result).** Two short, everyday sentences, so
  nothing to read: I put them on screen as a one-line card beside the note
  before each take, you hold ⌥ and say it however it comes out. Any wording
  works; we keep the take that reads best. About 5 minutes.
- **Option B, no voice from you.** Install BlackHole (free, `brew install
  blackhole-2ch`), route `say` into it, and pick BlackHole as PUSHTYPE's
  microphone for the take. I can record unattended. Caveat: synthetic voice
  is a smoke test for formatting (NOTES: "3.30" vs "3 30"); for plain words
  like these it is fine. Remove BlackHole afterwards if you like.

## Dry run with the promo voice (2026-10-14, done)

The ElevenLabs file from the promo video (Jessica, 27.4 s) is the benchmark
passage ("Let's move the Q3 planning review to Tuesday…"). Fed through
Parakeet Streaming the way the app does during a press, it gave 26 partials,
about one a second, each extending the last cleanly. The partials keep the
raw speech ("Um,", "like", "I mean, 1.52 seconds", "quote … end quote",
"New paragraph"), so one take shows both features: the rough words in the
pill while it talks, then the cleaned text landing in the note on release.
That makes it **Option C, the best one**: the same voice as the promo, no
speaking from the user, and no rehearsal needed for the words.

Getting the file into the microphone still needs either BlackHole (Option
B's route, cleanest) or playing it from the speakers into the TONOR mic
(no install, but room sound; try once and compare).

## Before recording

- Dry-run both sentences offline through Parakeet Streaming (an XCTest that
  feeds a recorded or `say` clip) to confirm the partials and final text.
- Then one rehearsal take, review, final take.

## Where it goes

- Website: replace the animated mock pill in the Live preview band with the
  clip (or keep the mock beside it on phones).
- Promo video: the clip as its own beat after "Hold a key. Speak. Let go."
