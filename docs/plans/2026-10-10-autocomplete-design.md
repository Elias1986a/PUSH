# Type — design

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
| **Type** (this doc) | Accessibility (+ optional Screen Recording later) | Text model (0.6–3.4 GB) |

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
- Model is loaded only while Type is on.

### Model catalog (chosen by the Phase 0 eval, 2026-10-10)

All Apache-2.0, all base checkpoints, GGUF from `mradermacher/*-i1-GGUF`
(pinned by revision + SHA-256). Measured on a Mac mini M4 with a 1,500-char
prompt; full numbers in `eval/results/2026-10-autocomplete.md` and `docs/MODELS.md`.

| Tier | Model | File | Size | Hit | Per keystroke p90 | Cold p90 |
|---|---|---|---|---|---|---|
| Lite | Qwen3.5 0.8B Base | `Qwen3.5-0.8B-Base.i1-Q6_K.gguf` | 0.63 GB | 34/60 | 43 ms | 180 ms |
| **Recommended** | Qwen3.5 2B Base | `Qwen3.5-2B-Base.i1-Q4_K_M.gguf` | 1.27 GB | 36/60 | 74 ms | 408 ms |
| Best quality | Gemma 4 E2B Base | `gemma-4-E2B.i1-Q4_K_M.gguf` | 3.43 GB | 40/60 | 93 ms | 527 ms |

Also evaluated: Granite 4.0 1B Base (40/60 but breaks on Metal in llama.cpp
build 10566 and runs on past one sentence; re-test on the pinned xcframework),
SmolLM3 3B Base (no gain, slowest, loops), and the earlier prototypes' Qwen3 4B
instruct (same hits as the 0.8B base at 3–5× the latency). No model leaked
the surface line.

**What the eval changed in the design:**

- **Token healing.** A prompt that ends inside a word ("really appreci") makes
  every model start a new word (mid-word 1–2/15). The engine backs off the
  partial word and uses llama.cpp's grammar sampler to force the output to start
  with it again: 13–14/15. This replaces "only show a continuation that starts
  with the letters already typed" below, and it also covers a caret right after
  a complete word.
- **Latency is per keystroke, from the KV cache.** A cold 1,500-char prompt costs
  180–530 ms on every model, so the 150 ms gate is met only by reusing the
  previous request's cache (43–93 ms). Cold happens on focus change; Phase 4
  prefills the context as soon as a field takes focus, before the first key.

Excluded: LFM2.5 1.2B Base (custom licence), Llama 3.2 1B (gated community
licence), Gemma 3 1B (Gemma terms, gated).

**Apple's on-device model (Foundation Models): left out (decided 2026-10-10).**
Cotabby offers it as an engine. For: zero download. Against: CLAUDE.md says
Apple's AI stays out of PUSH by the user's choice; it needs macOS 26 + Apple
Intelligence switched on (PUSH supports macOS 15); it is instruction-tuned only
(no base model); Cotabby's own measurement (2026-09-24) put it at ~420–520 ms to
first suggestion vs our ≤150 ms gate, with gaps where it produced nothing.

### Feature switches

- `dictationEnabled` — new, **defaults to true** when the key is absent, so every
  existing install is unchanged.
- `typeEnabled` — new, defaults to false.
- Teleprompter needs dictation's streaming model; when dictation is off its menu
  item is disabled with one line saying why.
- Neither key goes into `CloudSync.mirroredSettingKeys`: models are per-machine,
  so whether a feature can run is too.
- Dictation off means: no dictation hotkey, no wake word, no speech-model load
  at launch, no pill, no microphone request. Implemented as guards at the
  existing start sites in `AppDelegate` — no change inside the dictation path.

### Onboarding

New step order, computed from the switches by a pure function
(`OnboardingFlow.steps(dictation:type:)`, unit-tested):

```
welcome → features → permissions → [speech model] → [typing model] → [try it] → [pill] → more → finish
```

- **features** (new): two cards with switches — Dictation (on) and Type
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

Existing users never see onboarding again; they turn Type on from its
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
- Length comes from the user's length setting (below); stop at a newline.
  Mid-word: token healing (see Model catalog) — the partial word is forced as
  the start of the output by the grammar sampler.
- Ghost text in a non-activating, click-through `NSPanel` at the caret rect
  (`kAXBoundsForRangeParameterizedAttribute`). Never takes focus. When the caret
  rect cannot be read, no suggestion is shown (no guessing in v1).
- Its own `CGEvent` tap, separate from `HotkeyManager`. Swallows the accept keys
  (below) and `Esc` (dismiss) only while a suggestion is visible; every other
  key passes through untouched.

### Accept keys

| Action | Default | Customisable |
|---|---|---|
| Accept next word | `Tab` | yes |
| Accept whole suggestion | the `` ` ``/`~` key (left of `1`) | yes |
| Dismiss | `Esc` | no |

- The whole-suggestion key is matched by the **character it types in the current
  keyboard layout**, not a fixed key code, so it is right on non-US layouts.
  If no key in the layout types `` ` ``, the default falls back to `⌥Tab` and the
  Type pane says so.
- Both keys are only swallowed while a suggestion is showing. Trade-off: someone
  typing a Markdown backtick while a suggestion is up accepts it instead —
  `Esc` first, or rebind. Revisit if it bites.
- Shortcut recorder in Settings → Type, with conflict checks against the
  dictation hotkey and each other.

### Length

Word-range presets, like Cotabby: **1–3, 4–7, 8–12, 12–20 words.** The model
stops at a natural break (`.`, `,`, `;`, `?`, `!`) inside the range, otherwise
at the top of the range.

Each model in the catalog carries a **maximum preset** it handles well, set
from the Phase 0 eval. The picker only offers presets up to the selected model's
maximum; switching to a smaller model clamps the setting down.

| Model | Max preset | Why (eval, 2026-10-10) |
|---|---|---|
| Lite (Qwen3.5 0.8B) | 4–7 | Coherent for a clause, then invents and drifts |
| Recommended (Qwen3.5 2B) | 8–12 | Stops at the sentence end; a second sentence drifts |
| Best (Gemma 4 E2B) | 12–20 | Steadiest long continuations, 2/60 loops at 20 words |

Default: 4–7. Tokens stream into the ghost text as they arrive, so long presets
do not delay the first words.
- Accepted text is typed with synthesized Unicode key events
  (`CGEventKeyboardSetUnicodeString`), not pasted, so the clipboard is never
  touched for a few words. This is a deliberate exception to "injection is
  clipboard-paste only", which is about dictation-length text. Phase 0 checks it
  in Mail, Slack, Chrome, Safari, Notes and an Electron app, and falls back to
  `TextInjector` where it fails.
  **Insertion spike (Task 0.6, in progress)** — `KeystrokeTyper` from the
  Developer-ID-signed build (inherits PUSH's Accessibility grant), test string
  `hello wörld 👋 naïve café 🎬 across chunks` (accents, emoji, >20 UTF-16 units):

  | App | Result |
  |---|---|
  | Notes | correct (exact, read back over AX) |
  | Mail, Chrome (Gmail + textarea), Safari | not yet run |
  | Slack, VS Code | not installed; stand-ins Discord / Claude.app (Electron) and Antigravity IDE (VS Code fork) not yet run |
- Hidden while dictation is recording and while a teleprompter take runs.

### Compatibility: as universal as possible

Goal: Type works in every app where you type, and when it cannot read an app
properly it degrades rather than going silent. Four tiers, each with its own
technique:

| Tier | Examples | How we read text + caret |
|---|---|---|
| 1. Native AppKit/SwiftUI | Messages, Mail, Notes, Pages, TextEdit | Accessibility value + selected range + caret rect. Works out of the box. |
| 2. Browsers | Safari, Chrome, Arc, Dia, Brave, Firefox | Accessibility on the web area. Chromium browsers need `AXEnhancedUserInterface` set on the app element before they expose a full tree. |
| 3. Electron / Chromium apps | Slack, Discord, Notion, VS Code, Cursor, WhatsApp | Set `AXManualAccessibility = true` on the app element (Electron's documented switch), then as tier 2. |
| 4. Terminals | Terminal, iTerm2, Warp, Ghostty | Special mode, below. |

**Fallbacks for when Accessibility is incomplete** (any tier):

- **Own keystroke buffer.** PUSH's tap already sees every key. Keep a
  per-focus buffer of what was typed since focus last changed (reset on click,
  focus change, arrow keys; never stored or logged). When an app exposes no
  readable value, this buffer is the "text before the caret". Cotypist does the
  same (`InputBuffer`).
- **No caret rect → mirror card.** When the caret position cannot be read, show
  the suggestion in a small card under the focused field (or the window), not
  inline. Cotypist calls this "Text Mirroring". Better a slightly detached
  suggestion than none.
- **Caret from pixels** (later, only if the matrix shows it is needed): locate
  the blinking caret in a screenshot of the field. Needs Screen Recording, so
  opt-in only.

**Terminals.** Hard for three reasons: the whole scrollback is one text area,
the "field" is just the current prompt line, and `Tab` already means shell
completion. Plan:

- Read the terminal's text area, take the line at the cursor, strip the prompt
  (`$ `, `% `, `❯ `, `>`); that line is the "before" text. Cotypist does this
  per terminal (`TerminalAttributeCustomizer`, `ITerm2…`, `Ghostty…`).
- **Agent prompts first** — Claude Code, Codex and similar draw a boxed input
  line. Detect it (box-drawing borders around the cursor line) and treat it like
  a chat field: prose suggestions, chat-style context. This is where suggestions
  actually help in a terminal (writing prompts), and it is how Cotypist handles
  terminals ("No TUI agent prompt detected; hiding completions").
- Plain shell prompts: off by default (commands, not prose; a wrong suggestion
  is dangerous). A switch in Settings → Type turns them on later.
- In terminals the next-word key defaults to `→` (as in fish/zsh autosuggest)
  so `Tab` keeps doing shell completion; the whole-suggestion key is unchanged.
- **Integrated terminals** (the terminal panel inside VS Code, Cursor and
  other editors) share the editor's bundle id, so they are detected from the
  focused element's Accessibility tree (an xterm.js terminal), not the app.
  Same rules as standalone terminals: agent prompts on, plain shell off.
  (Cotabby: its "Suggest in Integrated Terminals" switch covers only these;
  standalone Terminal/iTerm2 are hard-blocked in its code regardless.)
- Ghostty exposes little through Accessibility today; it falls back to the
  keystroke buffer + mirror card.

**Compatibility matrix.** A checked-in table (`docs/TYPE_COMPATIBILITY.md`)
of ~30 apps × (reads text / caret rect / inline / accept works / notes),
filled in during Phase 4 and re-run before each release. An app only counts as
supported when it is in the table as passing.

**Default exclusions stay small:** password/secure fields (always), password
managers, Keychain Access. Everything else is on unless the user excludes it.

### Privacy

- Never log typed text or suggestions (same rule as transcripts).
- Phase A stores nothing.
- Default excluded apps: password managers, Keychain Access, System Settings,
  PUSH itself; secure fields everywhere. Terminals are *not* excluded (see
  Compatibility). Per-app exclusion list in Settings.

### Settings and menu bar

- New **Type** pane: on/off, model picker with download and delete, length,
  both accept keys, excluded apps; Phase B context toggles later.
- The existing **Models** pane stays speech-only (no change to dictation UI).
- Menu bar popover gets a **Type** section, modelled on Cotabby's (screenshot
  2026-10-10): on/off switch · **Pause ▾** (1 hour / until tomorrow / in
  <frontmost app>) · **Model** picker · **Length** picker · Clipboard context
  switch (once Phase B ships). The menu's Model picker lists downloaded models
  only — a menu click must never start a multi-GB download (same rule as the
  speech model switcher).

## Decided 2026-10-10

1. Name: **Type** (for now). Code uses `Typing…` names (`Type` is a Swift keyword-ish metatype name).
2. Keys: `Tab` = next word, `` ` ``/`~` key = whole suggestion, both rebindable.
3. Length: presets capped per model; default 4–7.

4. Apple's on-device model: **left out** — the zero-download appeal doesn't outweigh the macOS 26 requirement, instruct-only model and ~3× latency. Revisit only if Apple ships a faster base model.

## Phases

0. Spike + model eval (go/no-go)
1. Feature switches + onboarding restructure
2. Pure core in `PUSHCore/Typing` (TDD)
3. Engine + model catalog + downloads
4. Focus reading, ghost text, key tap, coordinator
5. Settings pane, menu bar, onboarding typing step + try-it
6. Phase B context (OCR, clipboard, instructions, history)
7. Release

Detailed tasks: `2026-10-10-autocomplete-plan.md`.
