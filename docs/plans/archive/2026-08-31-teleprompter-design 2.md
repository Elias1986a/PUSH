# Teleprompter — design

Date: 2026-08-31
Status: design agreed, implementation starting with `ScriptAligner`

## What this is

A second thing PUSH does: a teleprompter that hangs off the notch and **scrolls
because it heard the words you said**, not because a timer told it to.

Target scenario is a talking-head video recording. The text sits directly under
the lens so the eyeline stays natural, and the window is excluded from screen
recordings.

It is a separate feature from dictation — its own window, its own settings, its
own name — that happens to reuse infrastructure PUSH already has.

## Why we can build it cheaply

Three of the four pieces already exist:

- `ParakeetStreamingEngine` (`PUSHCore/ML/`) emits partial transcripts through
  `onPartial` while you are still speaking.
- `AudioRecorder` already feeds it live samples (`AudioRecorder.swift:168`).
- `FloatingPillView.notchTab` already renders a black tab hanging off the top
  edge that reads as the notch continuing downward, with an acid-green edge
  pulse.

The missing piece is alignment, and alignment is a matcher — not a model.

## Prior art: NotchPrompter

<https://github.com/jpomykala/NotchPrompter> — 632 stars, ships on the Mac App
Store. Read the source before designing this.

### What their "voice activation" actually is

`AudioMonitor.swift` computes an RMS level with `vDSP_rmsqv`.
`PrompterViewModel` uses it as a gate:

```swift
let detected = rmsLevel > self.audioThreshold   // PrompterViewModel:182
offset += CGFloat(speed) * CGFloat(dt)          // PrompterViewModel:245
```

That is a **noise gate on a constant-speed crawl**. Any sound scrolls the text
at a preset speed; silence pauses it. It does not know which words you said, so
speaking faster or slower than the dial drifts, and the fix is hotkeys.

Two implementation details we must not copy:

- The smoothing is `(rmsLevel * 0.0001 - 127) + (rms * 0.0001) * 2.2`, which is
  approximately `-127 + tiny`. The usable threshold range is razor-thin.
- It publishes to `@Published` from the audio tap on every 256-frame buffer via
  `DispatchQueue.main.async` — roughly 187 main-thread hops per second. In PUSH
  that pattern gets the CGEvent tap disabled and silently kills the hotkey.
- `show()` calls `NSApp.activate(ignoringOtherApps: true)`, which steals focus
  from whatever you are recording.

### What to take from it

- `window.sharingType = .none` to hide from screen capture — exposed as a user
  toggle, not hardcoded, because tutorial screencasts may want it visible.
  Default: hidden.
- Offset the window up by ~4pt so the top corner radius tucks under the notch.
  Their own `MARK` notes this breaks multi-display placement; derive it from the
  target `NSScreen` instead of assuming the main one.
- Slide-down-from-the-screen-edge frame animation for show/hide.
- Hotkeys for speed ±, scroll ±, and a "scroll back" for a fumbled line.
- Multi-screen picker and left/center/right alignment.

### The differentiator

NotchPrompter scrolls when it hears **noise**. PUSH scrolls when it hears **the
words**. This is the launch story, and PUSH already ships the ASR that makes it
true.

## Architecture

Four pieces, split so the interesting part is testable without a UI or a mic.

| Piece | Path | Role |
|---|---|---|
| `ScriptAligner` | `PUSHCore/Teleprompter/` | Pure value type. Script tokens + partial transcript → position. No AppKit, no actors, no I/O. |
| `TeleprompterState` | `PUSH/Teleprompter/` | Own `ObservableObject`. Not more surface on `AppState`. |
| `TeleprompterSession` | `PUSH/Teleprompter/` | Lifecycle: activate the streaming engine, run capture, drive the aligner. |
| `TeleprompterView` + window | `PUSH/Teleprompter/` | The 3-line display in its own `NSWindow`. |

Shared with dictation: only the *visual language*. Extract the tab shape and
edge pulse from `FloatingPillView` into a reusable `NotchTab` so both read as
the same hardware, with no coupling beyond appearance.

Deliberately not included: no new model, no LLM, no new dependency.

### Why its own window

The dictation pill's window sets `ignoresMouseEvents = true` and a specific
`collectionBehavior` (`AppDelegate.swift:116`). The prompter needs mouse
interaction and different sharing behaviour. A separate window means we never
touch the shipped dictation path, so this feature cannot regress it.

### Engine constraint

`AudioRecorder.swift:163` only feeds the streaming engine when
`activeModel.engineType == .parakeetStreaming`. With TDT v2 or Apple Speech
selected there are no partials at all, so voice-following has nothing to align
against.

`TeleprompterSession` therefore asks `ModelLoader` to activate
`.parakeetStreaming` on entry and restores the previous model on exit. Only
`ModelLoader` activates models (CLAUDE.md); the session must not load engines
directly.

If the streaming model is not downloaded, the prompter still opens and runs in
timed mode, with the voice-follow toggle disabled and an explanation.

## Display

**Three lines, always.** Line count is not a setting and not a consequence of
anything else. Tab height is derived:
`3 × lineHeight(fontSize) + housing inset + padding`.

**The active line is pinned.** Second of the three slots, at a constant Y under
the housing band. Line 1 above is what you just said, dimmed to ~35%. Line 3
below is what is coming, at ~60%. Text flows *up through* the pinned slot; the
slot never moves, so your eyes hold one position.

**Size changes type, not line count.** Its own `PrompterSize` enum — not the
dictation preview's `PreviewSize`, which is a different feature with different
distances:

| | font | column width |
|---|---|---|
| Small | 18 | 420 |
| Medium | 24 | 520 |
| Large | 32 | 640 |

The column stays narrow deliberately. The preview widens to 800 because "a
wider box costs nothing at the bottom of the screen" — true there, wrong here.
A wide line makes the eyes track left-to-right, and horizontal scanning is the
same on-camera tell as vertical scanning. Broadcast prompters use narrow columns
for this reason.

Type is the condensed system font at `.semibold`. Thin strokes on black at
reading distance are the first thing to go.

## The aligner

**Tokenize once.** Script → normalized tokens (lowercased, punctuation stripped,
digits spelled out — reuse `TextProcessing` helpers where they exist). Each
token keeps a back-reference to its character range in the original text, so the
view highlights real text while matching happens on normalized text.

**Windowed search, never global.** Keep `cursor` = last confidently matched
token. On each partial, take the trailing ~6 transcript tokens and search only
`[cursor − 4, cursor + 25]`. Score by exact match, else Levenshtein ratio ≥ 0.75
to absorb ASR errors and homophones.

The window is the load-bearing decision. Searched globally, a repeated "and
then" or "so" teleports the cursor across the document — which is how naive
implementations of this fail.

**Above threshold** → advance cursor. **Below threshold** → hold.

### Three states

A real take has all three.

- **Tracking** — matches landing steadily. Cursor advances; a spring animation
  chases the target so it glides rather than jerks.
- **Adrift** — no match above threshold for ~1.5s. You ad-libbed, or ASR mangled
  a word. Hold position and widen the forward search to `cursor + 60` so
  rejoining mid-sentence snaps back onto you. Visually nothing happens: a
  prompter that lurches because it got confused is worse than one that waits.
- **Lost** — no match for ~5s. Fall back to timed drift at the WPM measured from
  matched tokens per second — your pace, not a dial. The edge pulse shifts from
  acid green to amber so you know it is guessing. Any confident match
  re-acquires instantly.

The Lost state is what makes this safe to trust on a take: worst case it
degrades to exactly what NotchPrompter does, at a speed it learned from you.

## Testing

`ScriptAligner` being a pure value type is what makes this testable without a
mic. Into `Tests/PUSHTests`, feeding synthetic partial sequences:

- clean read → cursor advances monotonically
- repeated phrase ("and then … and then") → cursor does not teleport
  (the windowing regression test)
- ASR substitutions ("their/there", "to/two") → still tracks
- skipped sentence → re-acquires forward
- ad-lib for 3s then rejoin → Adrift, then snaps back
- silence → Lost, drift at measured WPM
- degenerate input: empty script, single-token script, cursor at final token

## Open questions

- Script source: paste into settings, open a `.txt`/`.md` file, or pull from the
  clipboard. Probably all three eventually; paste is enough for v1.
- Whether the prompter gets its own hotkey or lives behind a menu bar item.
