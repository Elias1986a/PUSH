# Autocomplete — design

Date: 2026-10-10
Status: draft, awaiting review before Phase 0

## What this is

The third thing PUSH does. As you type in any app, a gray suggestion appears
after the cursor; `Tab` accepts it a word at a time. Generation runs on this Mac
with a small open model. It knows *where* you are typing (Slack channel, email
subject, website, the text already in the field) and uses that to guess better.

PUSH then has three features, each one switched on or off on its own:

| Feature | Needs | Model |
|---|---|---|
| **Dictation** (voice to text) | Microphone, Accessibility | Speech model (~600 MB) |
| **Teleprompter** | Dictation's streaming speech model | none of its own |
| **Autocomplete** (this doc) | Accessibility (+ optional Screen Recording later) | Text model (0.6–3.4 GB) |

Hard rule, same as the teleprompter's: **this must not be able to regress
dictation.** Its own event tap, its own window, its own model, its own settings
pane. Shared with dictation: the permissions model and onboarding chrome only.

## Prior art (read 2026-10-10)

**Cotypist** (closed source, `/Applications/Cotypist.app`, v2026.4). Inspected
from its bundle, settings and strings — no disassembly. Swift + llama.cpp +
Gemma 4 E2B Q4. Context: Accessibility text around the caret, window title,
field placeholder, browser domain, screenshot OCR (ScreenCaptureKit + Vision),
clipboard, user's custom instructions, OS username and locales. Prompt labels it
leaves readable: `Context in which I am typing (e.g. domain/contact/channel/document):`,
`The part of my writing I am currently typing:`. The rest of its prompt is
encrypted in the binary; we did not and will not decrypt it.

**Cotabby** (<https://github.com/FuJacob/cotabby>, **AGPL-3.0**). Same product,
open source, very well documented. **We read it for ideas and write our own
code — no copying.** Copying any of it would force PUSH to be AGPL. What we take,
as ideas:

1. **Base models, not instruct models.** A base model only continues text, which
   is the whole job. Instruct models leak prompt scaffolding into suggestions.
   Both of the user's earlier prototypes (`~/Dev/Autocomplete`, `~/Dev/Autocmplete `)
   used Qwen3 4B *Instruct* with "Continue the following text…" — the known-bad
   pattern, and heavier than needed.
2. **Caret text last, no label.** Context is a short descriptive preface; the
   text before the caret is the final bytes of the prompt so the model just
   continues it.
3. **Compact surface line:** `Format: chat; App: Slack; Title: #design; Field: Message #design.`
   Window titles have the ` - AppName` suffix stripped and are capped (80 chars).
   Browsers add `Domain: host` (host only, `www.` dropped, no path).
4. **No surface line for code editors and terminals** — app metadata pushes a
   small model toward code/numbers.
5. **Priority budget.** Every section has a priority and a char cap; the caret
   text has top priority and is trimmed from the *start* so the words nearest
   the caret survive.
6. **User's name only at a sign-off** ("Thanks,\n"). Elsewhere the model kept
   inserting it.
7. **Clipboard only if copied < 5 min ago AND it shares a word with the draft.**
8. **Screen OCR: keep lines nearest the caret**, same column first, then
   restore reading order.

## Decisions

### Runtime: llama.cpp, in-process

- Official prebuilt `llama-<tag>-xcframework.zip` as an SPM `binaryTarget`
  (pinned tag + checksum). Metal library is embedded in the framework, so none
  of the MLX metallib-signing pain from the Gemma audio attempt.
- Why not MLX (which `docs/MODELS.md` prefers for LLM work): autocomplete needs
  prompt-prefix KV-cache reuse across keystrokes, fast cancellation and GGUF
  base checkpoints that exist for every candidate. llama.cpp has all three and
  both reference apps ship on it. Phase 0 measures it; MLX stays the fallback
  if latency fails the gate.
- Runs on the GPU. Speech models run on the ANE, so the two do not contend, and
  dictation and typing do not happen at the same instant.
- Model is loaded only while Autocomplete is on.

### Model catalog (starting point — Phase 0 eval decides)

All Apache-2.0, all base checkpoints, GGUF from `mradermacher/*-i1-GGUF`
(pinned by revision + SHA-256):

| Tier | Model | File | Size |
|---|---|---|---|
| Lite | Qwen3.5 0.8B Base | `Qwen3.5-0.8B-Base.i1-Q6_K.gguf` | 0.63 GB |
| **Recommended** | Qwen3.5 2B Base | `Qwen3.5-2B-Base.i1-Q4_K_M.gguf` | 1.27 GB |
| Best quality | Gemma 4 E2B Base | `gemma-4-E2B.i1-Q4_K_M.gguf` | 3.43 GB |

Also evaluated in Phase 0, added only if they beat a tier above:
Granite 4.0 1B Base (Apache-2.0), SmolLM3 3B Base (Apache-2.0).

Excluded: LFM2.5 1.2B Base (custom licence), Llama 3.2 1B (gated community
licence), Gemma 3 1B (Gemma terms, gated). Apple Foundation Models: out by the
user's standing choice (CLAUDE.md).

### Feature switches

- `dictationEnabled` — new, **defaults to true** when the key is absent, so every
  existing install is unchanged.
- `autocompleteEnabled` — new, defaults to false.
- Teleprompter needs dictation's streaming model; when dictation is off its menu
  item is disabled with one line saying why.
- Neither key goes into `CloudSync.mirroredSettingKeys`: models are per-machine,
  so whether a feature can run is too.
- Dictation off means: no dictation hotkey, no wake word, no speech-model load
  at launch, no pill, no microphone request. Implemented as guards at the
  existing start sites in `AppDelegate` — no change inside the dictation path.

### Onboarding

New step order, computed from the switches by a pure function
(`OnboardingFlow.steps(dictation:autocomplete:)`, unit-tested):

```
welcome → features → permissions → [speech model] → [typing model] → [try it] → [pill] → more → finish
```

- **features** (new): two cards with switches — Dictation (on) and Autocomplete
  (off). Teleprompter is described under Dictation. Continue needs at least one on.
- **permissions:** Microphone row only when dictation is on. Accessibility always.
- **speech model:** today's step, unchanged, only when dictation is on.
- **typing model** (new): same card pattern as the speech step, the three tiers
  above, Recommended preselected. Continue waits for the chosen model to be ready.
- **try it:** dictation sandbox when dictation is on; a typing sandbox with live
  suggestions when autocomplete is on (Phase 5).
- **pill:** only when dictation is on.
- **Skip** on welcome: allowed when every enabled feature already has a model on
  disk (today: when a speech model is on disk).

Existing users never see onboarding again; they turn Autocomplete on from its
Settings pane, which offers the download there.

### Context captured

**Phase A (ships first, Accessibility only):**

- Text before the caret (window: last 1,500 chars) and after it (first 200).
- Field placeholder (`AXPlaceholderValue`), window title, app bundle id → surface
  class (email / chat / browser / code / terminal / other).
- Browser page host via `kAXURLAttribute` on the web area or window.
- Secure text fields: never read, never suggested into.

**Phase B (later, each opt-in, off by default):**

- Screen text: ScreenCaptureKit window capture → Vision OCR → nearest lines.
  Needs the Screen Recording permission.
- Clipboard, with the 5-minute + shared-word rule.
- Custom instructions ("I'm a PM in streaming TV; short sentences").
- The user's own recent sentences as voice examples (stored locally, never
  synced, deletable).

### Trigger, display, accept

- Debounce ~150 ms after a keystroke. A new keystroke cancels the generation in
  flight; a result is shown only if focus, caret and field text still match the
  request.
- Up to ~6 words; stop at a newline. Mid-word: only show a continuation that
  starts with the letters already typed (token-constrained decoding is a later
  improvement).
- Ghost text in a non-activating, click-through `NSPanel` at the caret rect
  (`kAXBoundsForRangeParameterizedAttribute`). Never takes focus. When the caret
  rect cannot be read, no suggestion is shown (no guessing in v1).
- Its own `CGEvent` tap, separate from `HotkeyManager`. Swallows `Tab` (accept
  next word) and `Esc` (dismiss) only while a suggestion is visible; every other
  key passes through untouched.
- Accepted text is typed with synthesized Unicode key events
  (`CGEventKeyboardSetUnicodeString`), not pasted, so the clipboard is never
  touched for a few words. This is a deliberate exception to "injection is
  clipboard-paste only", which is about dictation-length text. Phase 0 checks it
  in Mail, Slack, Chrome, Safari, Notes and an Electron app, and falls back to
  `TextInjector` where it fails.
- Hidden while dictation is recording and while a teleprompter take runs.

### Privacy

- Never log typed text or suggestions (same rule as transcripts).
- Phase A stores nothing.
- Default excluded apps: terminals, password managers, Keychain Access, System
  Settings, PUSH itself. Per-app exclusion list in Settings.

### Settings and menu bar

- New **Autocomplete** pane: on/off, model picker with download and delete,
  suggestion length, accept key, excluded apps; Phase B context toggles later.
- The existing **Models** pane stays speech-only (no change to dictation UI).
- Menu bar popover: an Autocomplete row with on/off and "Pause for this app".

## Open questions for the user

1. User-facing name: "Autocomplete", "Type-ahead", something PUSH-branded?
2. Accept key: `Tab` (Cotypist and Cotabby both use it) or configurable from day one?
3. Default suggestion length: short (~3 words) or longer (~6)?

## Phases

0. Spike + model eval (go/no-go)
1. Feature switches + onboarding restructure
2. Pure core in `PUSHCore/Autocomplete` (TDD)
3. Engine + model catalog + downloads
4. Focus reading, ghost text, key tap, coordinator
5. Settings pane, menu bar, onboarding typing step + try-it
6. Phase B context (OCR, clipboard, instructions, history)
7. Release

Detailed tasks: `2026-10-10-autocomplete-plan.md`.
