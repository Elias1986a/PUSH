# NOTES

## Current state (2026-09-29, v8.2.2)

**Release notes live in `release-notes/<version>.md`** — write one before every
release; `build_distribution.sh` refuses to build without it. The same file is
the GitHub release text (`--notes-file`), and `scripts/release_notes.py` turns
all of them (newest first, down to 8.1.0) into the HTML Sparkle's update window
shows. Older appcast items are stripped of notes so the feed doesn't grow. This
is where small behaviour changes get announced instead of permanent Settings
captions (the user's call).

8.2.2: spoken layout ("new line", "new paragraph", "bullet point",
numbered lists from "number one … number two …" counting up from one
— only at a break, never before a preposition/verb) and a ranked microphone
list (first attached wins; built-in mic skipped with the lid closed). Needs a
real-voice check of where Parakeet puts commas around the commands, and a look
at the new Microphone section in Settings ▸ Dictation.

### Competitive backlog — bring up when the user asks "what else are we missing?"
From the 2026-09-29 competitor review (Wispr Flow, Superwhisper, VoiceInk,
MacParakeet). Not committed to; each needs the user's go-ahead.
- **Mid-sentence insertion** — read the text before the cursor (AX) so a
  dictation dropped mid-sentence doesn't start with a capital or end with a
  period. Medium effort; AX is unreliable in Chrome/Electron.
- **Noisy rooms** — the user isn't convinced. Options: measure first (script v2
  over café noise, PUSH vs Wispr), headset via mic ranking, macOS voice
  processing before ASR (may cost accuracy), wait for a better model.
- **Rewrite selected text by voice** (Wispr Command Mode, MacParakeet/VoiceInk
  Transforms): highlight, speak "make this shorter". To explore. Needs a
  language model — open, local only (no Apple AI); small local models lost to
  rules on self-correction, so size/quality is the open question.
- **A purpose-trained cleanup model** — back pocket. VoiceInk Refine V1
  (huggingface.co/beingpax/VoiceInk-Refine-V1) is Qwen3.5-2B fine-tuned only for
  transcript cleanup, 4-bit, 1.08 GB. Our bake-off used general small models
  (Qwen 0.5B/1.5B, Llama 1B) and dropped them on size vs. gain; a model trained
  for this one job is the version that might earn its size. If revisited: run it
  through `eval/run_llm_eval.py` against the rules (44/50). Its licence
  forbids use outside VoiceInk (no other apps, commercial use or
  redistribution without permission), so the model itself is out; the recipe
  is not — fine-tune an openly licensed Qwen ourselves on our eval shapes.
  The user likes the idea of PUSH having its own model. Plan if picked up:
  LoRA fine-tune of Qwen 0.5B–1.5B (Apache 2.0; confirm the exact release) with
  MLX on the M4 / 24 GB Mac mini (hours; a rented GPU if not); the real work is
  a few thousand generated messy→clean pairs. Ship only if it clearly beats the
  rules' 44/50 at interactive latency — target ~350 MB at 4-bit.
- Rejected, don't re-propose: transcript history / paste-last (privacy),
  snippets, meeting notetaker, usage stats, per-app tone styles, SenseVoice
  (weaker than Parakeet on English; the user dropped it 2026-09-29).

8.2.1: onboarding "Choose a speech model" step (Ultra preselected on a first
run, Continue gated on the model being loaded, no Skip and no seen-on-close
while no speech model is on disk); launch no longer downloads a speech model
on its own. Shared `ModelDownload.run` for Settings and the wizard.


8.2.0: **Apple Speech removed** (worst in every benchmark; the user won't have
Apple's AI in the product) — the lineup is Parakeet Ultra/Unified/Streaming +
Nemotron, and a saved "apple-speech" falls back to Ultra. **California mode**
(Settings ▸ Text, off by default): `removeCasualLike` drops casual "like" and
keeps the verb, comparisons, "like I said", "like 30 minutes" and quotative
"was like,". Self-corrections: emphasis ("cold, I mean very cold") is no
longer resolved; restarts drop their period; cross-sentence number runs
replace whole. Eval set `eval/self_corrections.jsonl`: 44/50. The model-based
resolver was tried (three open models, none beat the rules) and dropped.
README benchmark now leads with script v2. Next: onboarding model-choice step
(below, "Still open").


8.1.3: self-corrections on by default; unclosed questions get "?" (also behind a
closed quote); quotes after "said," capitalised; capital after a removed
sentence-opening filler; unit after a number vetoes clock-time conversion;
space kept before a later-sentence correction. Benchmark script v2 in NOTES.


8.1.2 (PR #20): decimals no longer read as sentence ends in self-corrections
("15.2 … I mean 1.52"); a filler opening a later sentence (". Um, …") is
stripped; "Umbrella" no longer loses "Um". Built with stable Xcode 27.1 —
Xcode-beta is no longer installed.


8.1.1: self-corrections may reach back across a sentence break when a short fix
lines up with the previous sentence's tail (name/number/day/month/same word);
Parakeet Unified and Streaming are per-encoder downloads (delete one, keep the
other — `ParakeetUnifiedEngine.hasMode/deleteMode`).

### Benchmark series — append here, don't overwrite

Runs of `BenchmarkScript.text` through `compare/`. Same words every time, so
these rows are comparable to each other. **Add a row, never replace the table.**
Anything measured on a different utterance goes under "off-script" below and is
not comparable to these.

Per second of audio (`s/s`) is the column to read across runs — the raw seconds
move with how long you took to read it.

| date | held | Ultra | Apple Speech | Wispr Flow | Ultra s/s | notes |
|---|---|---|---|---|---|---|
| 2026-09-29 | 22.0s | 0.14s · 152× | 0.28s · 79× | 0.66s + 0.13s net | 0.0064 | Unified/Streaming/Nemotron not on disk |
| 2026-09-29 | 21.0s | 0.15s · 142× | 0.29s · 73× | 1.04s + 0.09s net | 0.0071 | Wispr's slow run |
| 2026-09-29 | 20.1s | 0.14s · 140× | 0.26s · 76× | 0.66s + 0.13s net | 0.0070 | |
| 2026-09-29 | 19.6s | 0.16s · 122× | 0.28s · 69× | 0.58s + 0.10s net | 0.0082 | Unified 0.15s/134×, Streaming 0.40s/48× |
| 2026-09-29 | 21.6s | 0.15s · 145× | 0.27s · 79× | 0.61s + 0.08s net | 0.0069 | Unified 0.16s/135×, Streaming 0.39s/55× |

That closes **script v1** at five runs. Unified and Streaming only have the last
two. Unified ties Ultra (0.15–0.16s either way); Streaming's 0.39–0.40s is
batch-mode only — in the app it decodes while you talk, which this tool cannot
show. On the last two runs Unified and Streaming both dropped the final `?`
("…confirm before Friday"), fixed by `closeUnfinishedQuestion`; with
self-corrections on, all three Parakeet engines end on `1.52 seconds`.

**Script v2 (2026-09-29 on):** adds "Priya said, quote, ship it anyway, end
quote." before the question. Cards show `script v2`. Start a new table below
for it; don't average v1 and v2 rows.

#### Script v2 — append here

| date | held | Ultra | Unified | Streaming | Apple Speech | Wispr Flow |
|---|---|---|---|---|---|---|
| 2026-09-29 | 22.7s | 0.15s · 149× | 0.15s · 150× | 0.42s · 54× | 0.30s · 76× | 0.81s + 0.13s net |
| 2026-09-29 | 25.5s | 0.17s · 147× | 0.17s · 149× | 0.50s · 51× | 0.32s · 79× | 0.71s + 0.12s net |
| 2026-09-29 | 24.8s | 0.20s · 123× | 0.15s · 162× | 0.45s · 55× | 0.29s · 85× | 0.79s + 0.13s net |

Medians: Unified 0.15s/150×, Ultra 0.17s/147×, Apple 0.30s/79×, Streaming
0.45s/54× (batch only — it decodes while you talk in the app), Wispr 0.79s +
0.13s/31×. Ultra beats Wispr's server time by 4.6×, 5.4× with their network;
Unified by 5.2×/6.1×. Ultra's 0.20s in run 3 is the widest local spread so far.

Accuracy, re-run through the current pipeline with self-corrections on:
- Ultra: clean 2/3; run 1 misheard "So asked the Zurich team".
- Streaming: clean 2/3 apart from names; run 1 heard "30-some percent" for 37%.
- Unified: run 2 lost all punctuation after "15.2 seconds." (engine), so the
  correction could not resolve and the question could not close; run 3 dropped
  the commas round "quote", so the quote is a lowercase fragment (correct).
- Apple: "one. 52 seconds" 3/3, "Prius"/"Larry Pri" for Priya, "430 p.m." once.
  Run 2's raw "target, um, latency" loses its break when the filler and both
  commas go ("target latency came back"). Apple-only so far; not fixed.
- Quotes: `Priya said, "Ship it anyways."` everywhere the engine wrote the
  commas. Question mark: closed everywhere once `closeUnfinishedQuestion` saw
  past the closing quote (fixed after run 3).

Medians: Ultra 0.14s/142×, Apple 0.28s/76×, Wispr 0.66s + 0.13s/32×. Ultra beats
Wispr's server-side processing by 4.7×, 5.6× counting their network, and Apple
by 2×. Ultra's spread is 0.14–0.15, Apple's 0.26–0.29, Wispr's 0.66–1.04 — the
cloud is the only one whose worst run is 1.6× its best, which is the argument
for medians rather than single reads.

Accuracy over the three runs:

| exercise | Ultra | Apple Speech | Wispr Flow |
|---|---|---|---|
| `$5 million` | `$5 million` in raw, 3/3 | `$5000000` → `$5,000,000` (ours) | `five million dollar` → `$5 million` (theirs) |
| `4:30 PM` | `4.30 p.m.` → `4:30 p.m.` | same | `4:30 PM` raw |
| `1.52 seconds` | 3/3 | `one. 52 seconds` 3/3 ✗ | 3/3 |
| `Zürich` | `Zurich` 2/3, `Zurek` once | `Zurich` | `Zurich` → `Zürich` |
| `37%` `Q3` `March 3rd` `?` | 3/3 | dropped "Priya" once | 3/3 |

Apple's `one. 52` is a recognition failure, not something our pipeline can
repair — don't spend time on it.

**What the script actually caught: a bug in our own self-correction resolver.**
Wispr resolves "15.2 seconds, I mean 1.52 seconds" down to `1.52` in all three
runs and says so in its UI. Ours would not have, even switched on, because
every dot-scanning pass in `TextProcessing+SelfCorrections` read the decimal
point in `1.52` as a sentence terminator. The correction became the single word
`1`, and `startOfLastSentence` rebuilt the sentence it was correcting starting
from the dot inside `15.2`. `resolveTrailing` had the "a dot followed by a
digit is not a sentence end" rule from the day it was written; `correctionWords`,
`resolveAcrossSentences` and `startOfLastSentence` did not. Fixed with a shared
`isClauseBreak`, tests in `testDecimalsAreNotSentenceBoundaries` and
`testGroupedNumbersAreNotClauseBoundaries`.

Digits only — requiring whitespace after the terminator would also reclassify
`p.m.` and every other abbreviation, which is a bigger change than this bug
justifies.

One run of the three also had Wispr rewrite "so ask the Zürich team to re-run
it" into "Can the Zürich team rerun it?" — an instruction turned into a
question. It did not repeat, so don't build a claim on it; note it if it
reappears.

**The comparison tool has a self-corrections toggle** (header, default on to
match the app since 8.1.3). It re-derives `final` from stored `raw`, so it
flips past rows too. Switching it on found two more bugs, both fixed: the
space before a later-sentence correction was dropped ("target.Um"), and
`normalizeClockTimes` turned "at 1.52 seconds" into "1:52" (a unit behind
the number now overrules "at"). The sentence-opening "Um" is stripped and the
next word capitalised (`stripSentenceOpener`).

Nemotron has no row: it is not on disk, and for English it would not be
chosen anyway (`TranscriptLanguage.ultraCovers`).

**Script v3 (2026-09-30 on):** rewritten for the public "How we measured"
page — no named people, nothing a reader could take personally — and adds
California mode's casual "like" and a spoken "New paragraph" (read the likes without pauses; comma-wrapped ", like,"
is removed by the default filler pass, so it would show nothing). Target is
**25 readings**; the compare tool's header shows medians and "n of 25" for the
current script. California mode is a header toggle, **on** by default here
(off in PUSH). Expected paste pinned in `BenchmarkPassageTests`. Writing it
exposed "could you like send…" keeping its "like" (after "you" it read as the
verb); fixed — a bare verb right after "like" (NLTagger `.verb`, not "-ing")
means it is filler. Script v3 is final: don't edit it mid-series.

#### Script v3 — append here

| date | held | Ultra | Unified | Streaming | Wispr Flow |
|---|---|---|---|---|---|

#### Off-script runs (not comparable to the series)

**2026-09-29, one 15.2s utterance, before the script existed.** Ultra 0.18s/84×,
Apple Speech 0.20s/77×, Wispr 0.62s + 0.12s network. That gave 3.4× against
Wispr where the scripted run gives 4.7×, on the same three engines and the same
machine — Ultra ran 0.012 s/s there against 0.0064 s/s on script. Nothing
changed in the engine between them; the clip was shorter, so Ultra's fixed
overhead was amortised over less audio, and the machine state differed. This
pair is exactly why the script is fixed now. Don't quote the 3.4× or the 8×
(August, Unified, 8.3s clip) as if they were the same measurement as the series.

### v8.1.0

Shipped 2026-09-26/27 (8.0.3 → 8.1.0): FluidAudio 0.17.4; Parakeet Ultra (now the
default); #16 merged (per-Mac model choice, no launch downloads, no wedged loads);
per-transcript language detection for Ultra (`TranscriptLanguage`); clock times
→ "3:30" (`normalizeClockTimes`); spoken quotes incl. self-closing "quote" and
"quote unquote" (`TextProcessing+Quotes.swift`); TDT v2 removed; strict spoken
self-corrections with "sorry"/"correction" (`TextProcessing+SelfCorrections.swift`).
GitHub cleaned by the user: only `main`, releases/tags 8.0.0+ only; appcast
lists 8.0.3+.

**Ultra kept (2026-09-27) and made the default; the language split is done (8.0.9).**
`WhisperModel.defaultModel` = `.parakeetUltra`. Nemotron's picker filters out
`TranscriptLanguage.ultraLanguageSubtags`; `NemotronMultilingualEngine.resolvedLanguage`
maps a missing/Ultra-covered saved language to the Mac's language if Nemotron has
it, else zh-CN. Not done: deleting the now-unreachable `latin` build code path
(`vocabVariant`) — harmless, left for a cleanup. Teleprompter voice-following
still needs the Unified/Streaming bundle, which a fresh install no longer has.

Other loose ends: remote branches were all verified merged/superseded but
deletion was blocked by the permission classifier — the user has the command.
PR #9 still open (superseded by `livePartialText`); close it with the branches.

## Current state (2026-08-24, v7.1.2 — clipboard latency)

Fixed slow injection into Outlook on a managed work Mac. `TextInjector` used to
back up the clipboard by deep-copying every flavor of every pasteboard item
immediately before pasting — a synchronous cross-process read, on the main
thread, sitting inside the latency between the user finishing a sentence and
the text appearing. The snapshot now happens when recording *starts*, on a
background queue, and is reused at inject time when `changeCount` says the
clipboard hasn't moved.

**Things worth not re-learning:**

- **`NSPasteboard` is lazy.** `item.data(forType:)` asks the *owning app* to
  render that flavor on demand, synchronously. Apps that advertise many rich
  flavors (Outlook, Word, Excel) make that slow; endpoint DLP agents that scan
  every clipboard access make it much slower. Never do it on a latency path.
- **Snapshots cross an isolation boundary**, so they're held as
  `[[String: Data]]` rather than `NSPasteboardItem` (which isn't `Sendable`).
  Items are rebuilt from memory at restore time — cheap, no IPC.
- The fix is reasoned, not measured. The user could not run diagnostics on the
  work Mac (locked down, `CB`-prefixed fleet machine), so the log was never
  read. If Outlook is still slow after 7.1.2, the remaining suspect is
  Outlook's *own* paste handling after Cmd+V, which PUSH cannot influence.

**Still open:**

- The app icon is a stock-looking 3D render (`ICON/AppIcon.iconset`) and is now
  the weakest release-readiness signal. Raised, not actioned.
- Permissions pane is new behaviour: it polls on appear and on
  `didBecomeActive` because macOS never notifies. Watch for reports that it
  shows stale state.

---

## Current state (2026-08-23, v7.1.0 — released)

Settings redesigned from four tabs into a 720x640 sidebar window: General,
Dictation, Text, Pill, Models, Dictionary. Shipped, notarized, appcast pushed.

**Things worth not re-learning:**

- **`NavigationSplitView` does not work in a `Settings` scene.** It treats
  `.frame()` as advisory and sizes from content — the window opened at 450x480,
  then 720x720, then 900x696 across three attempts. `SettingsView` now uses a
  plain `HStack` (sidebar 196 + detail 524 = 720). Do not "fix" this back.
- **macOS persists the settings window frame** under
  `NSWindow Frame com_apple_SwiftUI_Settings_window` in the app's defaults. A
  stale frame from an older version silently overrides layout, which is what
  the first 450x480 actually was. `defaults delete` it when testing sizing.
- **SwiftUI `Form` aligns text field values trailing on macOS**, parking the
  caret at the right edge of an empty field — it reads as right-to-left. Every
  field in the window carries `.multilineTextAlignment(.leading)` for this.
- **`TextField("placeholder", text:)` inside a `Form` renders that string as a
  LABEL beside the field**, not as placeholder text, so it drew twice and
  squeezed the field. Use `TextField("", text:, prompt:)` + `.labelsHidden()`.
- **Verifying this app's UI hijacks the user's screen** (LSUIElement + menu bar
  extra + `screencapture`). Ask first, batch every pane into one scripted pass,
  `pkill -x PUSH` after. `osascript ... key code 53` first — a menu left open
  blocks all System Events queries and looks like "the window never opened".
- The caret fix is the one thing never confirmed on screen; the user was asked
  to eyeball it after installing.

**Still open:**

- The app icon is a stock-looking 3D render (`ICON/AppIcon.iconset`) and is now
  the weakest release-readiness signal. Raised, not actioned.
- Permissions pane is new behaviour: it polls on appear and on
  `didBecomeActive` because macOS never notifies. Watch for reports that it
  shows stale state.

---

## Previous

## Current state (2026-08-18, v6.5.2 — released)

Seven releases across three days: 6.4.1 (updater menu), 6.4.2 (iCloud
entitlement + KVS spike), 6.4.3 (spoken self-corrections), 6.5.0 (real iCloud
sync + Settings tab lag), 6.5.1 (filler "like"), 6.5.2 (filler "like" via the
POS tagger).

Nothing is left unmerged. Both feature branches that were waiting are in.

### The comparison tool works, and here are the numbers

`compare/` — its own package, local only, never shipped. One recording through every
engine plus Wispr Flow. Build and run it with `./compare/build_compare.sh`.

Measured on one 8.3s utterance, all seven engines plus Wispr:

| engine | transcribe | × realtime |
|---|---|---|
| Parakeet Unified | 0.061s | 136× |
| Parakeet v2 | 0.074s | 112× |
| Apple Speech | 0.118s | 70× |
| Parakeet Streaming | 0.161s | 52× |
| Wispr Flow (cloud) | 0.492s + 0.095s network | 17× |
| Whisper Small | 0.947s | 8.8× |
| Whisper Large V3 Turbo | 1.106s | 7.5× |
| Moonshine Tiny | fails | — |

**Parakeet Unified beats Wispr's server-side processing by 8×**, before counting their
network. Accuracy is still unmeasured — that is what the side-by-side is for.

(Superseded by the 29 September 2026 re-run at the top of this file: Ultra is the
default now, TDT v2 and Whisper are gone, and the Wispr multiple measured 3.4× on a
longer utterance. These August figures stay as the record of why Whisper was dropped.)

**Things that cost time here, worth not re-learning:**

- **Wispr's database is WAL-mode.** The main file's mtime read *February*, and
  `sqlite3` returned CANTOPEN, and both had one cause. Recent rows live in
  `flow.sqlite-wal`; the `-shm` sidecar exists only while Wispr runs, and a read-only
  connection may not create one. So: **Wispr must be running to be read**, and the open
  must never use `immutable` — that flag ignores the WAL and hands back the February
  checkpoint. Diagnosed as a stale database first; it wasn't.
- **`compare/.build` must be symlinked out of iCloud**, exactly like the root's. iCloud
  duplicated a file inside a dependency checkout (`GenerateDoccReference 2.swift`) and
  the build failed on it.
- **moonshine-swift renames its product between versions** — `Moonshine` in v0.0.48,
  `MoonshineVoice` in v0.1.3. The root pins v0.0.48, so `compare/Package.resolved` is
  copied from the root's to keep both on the same revision.
- **Whisper Large v3 Turbo's first inference compiles for ~2 minutes** on the ANE, at 0%
  CPU, then caches (3.8s afterwards). It is not hung.
- A missing Wispr row now says *why*: not installed / not running / not triggered.
  Rendering nothing was indistinguishable from a broken integration.

### Two Apple engines

Plan: `~/.claude/plans/recursive-churning-moore.md` — Apple models, then a `PUSHCore`
library split, then a local engine-comparison tool. Stages 3–4 not started.

**Apple SpeechAnalyzer** is a fourth ASR engine (`ML/AppleSpeechEngine.swift`). No
weights to fetch — the OS owns the assets, so `loadModel()` installs and reserves a
*locale*, and the settings row reports system asset status rather than offering a
Download button. 5.18s of speech in 0.12s, punctuates natively, writes "4.8 million"
itself.

**Apple Intelligence cleanup** (`Core/AppleTextCleanup.swift`) is an *alternative* to
`postProcess`, not a stage after it — running a model over already-formatted text would
undo the number handling and make the A/B meaningless. Off by default. 4s timeout falls
back to the rule result computed alongside it.

**The guard is the part worth reading before touching this.** Dictating "what's the
capital of france" came back as "Paris is the capital of France." and the original
length-based check passed it, because a short question gets a short answer. Length is the
wrong invariant. The right one is vocabulary: cleanup deletes words but never invents
them. Digits are exempt (number rewriting is wanted), stopwords are exempt (contractions
expand). Don't relax this without re-running
`AppleTextCleanupTests/testDictationPhrasedAsAQuestionIsNeverAnswered`.

Verified without a microphone: the Apple Speech test synthesizes its clip with `say`,
which also means never asking the user to read a script aloud.

### Released in 6.5.3: the number pipeline, fixed in three rounds

Shipped nothing yet; `main` is four commits ahead of v6.5.2.

The first fix was incomplete and the user caught it twice. The lesson is in
the second commit: **these passes were each tested in isolation, and every bug
was an interaction between them.** The chain is now extracted as
`postProcess(_:hasNativePunctuation:)` and the regression tests run end to end
against that. Test composed, not per-pass.

Fixed, with the output each produced before:

| dictated | was | now |
|---|---|---|
| `4.8 million` | `4.8 1,000,000` | `4.8 million` |
| `four point eight million` | `4.8000000` | `4.8 million` |
| `three point one four` | `3.5` | `3.14` |
| `five million dollars` | `5,000,$000` | `$5,000,000` |
| `one thousand people` | `1000 people` | `1,000 people` |
| `nineteen ninety nine` | `118` | `1999` |
| `thirty first` | `31St` | `31st` |
| `50 percent off` | `50% Off` | `50% off` |

The last three only surface on Whisper/Moonshine — Parakeet writes numbers as
digits itself and skips the punctuation passes, so the user never saw them.
Worth remembering when a bug report and a harness disagree: **check which
pipeline variant the active engine actually runs** before calling it real.

Still broken, deliberately left:

- `twenty twenty four` → `24`. `removeStutteredWords` eats the repeated
  "twenty" before any number pass runs. Same pass fixes real stutters; needs
  its own decision.
- `a sixty forty split` → `a 100 split`. Pre-existing; the year parser
  declines it on purpose (6040 is not a year).

### Bare magnitude words no longer expand

Dictating "4.8 million" produced "4.8 1,000,000". `normalizeNumberWords`
matched the lone word "million" as a run of its own, and `parseNumberRun`
applies an implicit multiplier of 1 when nothing smaller precedes a magnitude
— right inside "one hundred five", wrong when the run *is* the magnitude. The
4.8 outside the run was dropped and `groupThousands` then formatted the
invented value. Same fault behind "30 million" → "30 1,000,000", "$5 million",
"a hundred people" → "a 100 people", "a thousand times" → "a 1000 times".

Fix: `isBareMagnitudeRun` skips runs made of nothing but hundred/thousand/
million. Runs with a real multiplier are untouched, so "thirty million" still
expands to 30,000,000.

This leaves a deliberate asymmetry: spelled "thirty million" expands to
30,000,000 (requested in fe61caa) while digit-form "30 million" stays
"30 million" (AP style). Same phrase, different output depending on what the
ASR chose to write. Decided 2026-08-20 to keep it that way — both forms are
readable and neither mangles the number. Do not "fix" the inconsistency.

### The notch: checked on the MacBook, and it's fine

The deferred check finally happened on the notched laptop. The flanks, the
pulse terminating at the notch's lower corners and the 37pt of camera clearance
all read correctly in practice — no `NotchFilletShape`, no geometry change
needed. That closes the item that had been carried for three days.

### 6.5.2 — filler "like" now uses the part-of-speech tagger

Replaces 6.5.1's string patterns, which real dictation got through: "how are
you not like irate" and "as if he like lives on another planet" both survived,
since the patterns only knew prepositions and sentence starts.

Extending the patterns is not safe, and this was measured rather than assumed.
The senses are not separable by the tag on "like" alone — filler and comparison
both come back `Preposition` — nor by the neighbours alone, because "I like
pizza" and "he like lives" have the same shape. It takes both signals: the tag
rules out the verb, the neighbours rule out the comparison. A regex matching
pronoun + "like" turns "I like pizza" into "I pizza"; that is the whole reason
this is not a regex, and there is a test named for it.

Cost: 0.25ms with "like" present, 0.008ms without, against a 64ms finalize.

The two known misses are deliberate and unchanged — "is just like human level
common courtesy", "never put like a corporate lens". They are the LLM
resolver's job (see below), not a looser rule's.

### Smarter self-correction — model bake-off (2026-09-29)

`eval/self_corrections.jsonl` (50 cases) + `eval/run_llm_eval.py` (llama-server,
few-shot, temperature 0; an answer is accepted only if every word in it was
spoken, else the rules' output is used). Rules alone, after two bug fixes: **43/50**.

| model | score | non-corrections kept | median / max |
|---|---|---|---|
| rules | 43/50 | 14/15 | — |
| Qwen2.5-0.5B Q4 | 35/50 | 13/15 | 66 / 152 ms |
| Qwen2.5-1.5B Q4 | 37/50 | 15/15 | 138 / 324 ms |
| Llama-3.2-1B Q4 | 36/50 | 9/15 | 99 / 222 ms |

None beats the rules as a free-form rewriter. Qwen 1.5B is safe (never deleted a
non-correction) but mostly timid — returned the text unchanged or kept the
mistake ("The red car, I mean the blue car" left as is). Llama deletes
aggressively: 6 of 15 ordinary sentences lost words ("It's great." from "It's
great. I mean, it really works."). The word check cannot catch a wrong
*deletion*, only an invented word, so free-form output is the wrong shape for
models this small.

**Dropped (user's call, 2026-09-29):** not worth the download or the effort for
a handful of edge cases. Models deleted. Stay on the rules (43/50). The eval set
and scorer stay in `eval/` as a regression check. Known rule misses, unfixed:
emphasis read as a correction ("It's cold, I mean very cold." → "Very cold."),
multi-word names ("San Francisco, I mean Oakland" → "San Oakland"), and a comma
left after a replaced subject ("The blue car, is outside.").

### Still open

- **Onboarding model step — built; layout checked on a dev build** (2026-09-29). Step 3
  of 7, "Choose a speech model": four cards (Ultra preselected), Download with
  progress via the shared `ModelDownload.run` (Settings uses it too), Continue
  disabled until the chosen model is loaded. Skip hidden and closing the window
  doesn't mark it seen while no speech model is on disk. `activateAtLaunch`
  now loads nothing when nothing is on disk (`launchModel` returns nil); the
  small supporting models still load at launch. Unverified: the true
  no-model first run (needs the models deleted or a clean user account).
- ~~Cross-Mac sync end to end~~ — tested by the user across both Macs, works
  (confirmed 2026-09-29).
- **Phase 2, the LLM resolver.** Job description below; unchanged. The user
  wants this improved — it is the standing answer to the span heuristic's
  wrong guesses now that self-corrections are on by default (8.1.3).
- ~~Stale remote branches~~ — origin has only `main` (2026-09-29). The Aug 31
  worktree under `.claude/worktrees/` was clean and in main; removed.
  One stash remains, `Teleport auto-stash` on `claude/push-onboarding-waveform`
  (2026-09-04): swaps `nextel_chirp.mp3` for `push_chime.wav` in SoundPlayer.
  Left for the user to keep or drop.

### Release pipeline gotcha found today

`DEVELOPER_DIR` is **not** `/Applications/Xcode-beta.app`. Xcode-beta lives on
the external volume: `/Volumes/Part 2/Applications/Xcode-beta.app/Contents/
Developer`. `xcode-select -p` already points there, so running
`./build_distribution.sh` with no override works; a wrong explicit override
fails in step 1 with "missing DEVELOPER_DIR path".

### iCloud sync: proven, and how it reconciles

KVS works unsandboxed on a Developer ID build — a write on the MacBook reached
the Mac Mini in **2 seconds**. No account, no login, no server.

Three different rules, because one rule loses data:

- **Settings** — last-writer-wins per *key*, so a hotkey change on one Mac and a
  preview-size change on the other both survive.
- **Dictionary** — union by entry id, newest `modifiedAt` wins. Never LWW on the
  list; that drops entries.
- **Deletions** — tombstones. Union by id without them resurrects everything the
  user deletes, from the other machine's copy. Expire after 30 days.
- **Independent duplicates** — the same word added on both Macs has two uuids and
  one meaning; deduped by content, oldest kept so the surviving id is stable.

`pillPosition` deliberately does **not** sync: a notched laptop and an external
display are exactly where the same person wants different answers.

11 merge tests cover each failure mode, including idempotency and stable
ordering — an unstable merge makes two Macs push at each other forever.

**A crash worth remembering:** the first signed build died on launch with a
`dispatch_once` trap. `CorrectionsStore.shared` init → `load()` → `didSet` →
`save()` → `CloudSync` → read `CorrectionsStore.shared` back, while that
initialiser was still running. All 11 merge tests passed against an app that
could not launch. Unit tests do not substitute for running the signed build.

### iCloud key-value storage: proven to work unsandboxed

The open question was whether KVS functions without the sandbox, which PUSH
cannot have. It does:

- Apple grants `ubiquity-kvstore-identifier` on a **Developer ID** profile
  (`B8R5B24PMP.*`, to 2044) — outside-App-Store distribution is no barrier.
- The signed app launches with the entitlement, `synchronize()` returns true,
  and a second launch reads back the previous process's stamp, so the store
  outlives the process.
- **Still unproven:** that writes reach iCloud. KVS also persists locally when
  the cloud is unavailable, so single-machine persistence cannot tell the two
  apart. Hence check 2 above.
- `~/Library/SyncedPreferences/` does not exist on this macOS; don't go looking
  for the backing store on disk, it's a dead end.

**The release pipeline now depends on a provisioning profile.** It lives at
`~/Library/Developer/PUSH-signing/`, deliberately out of the repo. iCloud is a
*restricted* entitlement: `PUSH.entitlements` claims it, and an app signed with
it but no embedded profile **refuses to launch, for everyone**.
`build_distribution.sh` embeds it and hard-fails if missing. Those two changes
must never be separated.

### Spoken self-corrections (6.4.3)

Stage one of the hybrid — heuristic only, no LLM. `resolveSelfCorrections` runs
before the formatting pipeline, while markers are intact; filler removal only
eats um/uh/like so it doesn't interfere.

Measured: **0.125ms** with a correction present, **0.040ms** without, against a
64ms Parakeet finalize. The LLM resolver was scoped at ~200-400ms even in the
hybrid's best case, which is why the heuristic went first — it may turn out to
be enough.

**Marker choice is the load-bearing decision, don't loosen it casually.** This
is the only post-processing step that *deletes words the user said*, so a false
positive loses meaning silently rather than formatting something oddly. Every
marker is a phrase. Bare "sorry", "actually" and "rather" are excluded and
tested for: "I'm sorry about that", "I'd rather go" are ordinary speech. Those
are the LLM resolver's job description — if the misses cluster there, that is
the signal to build stage two.

### The LLM resolver now has a job description

Two independent findings point at the same missing capability, both from real
dictation rather than invented examples:

1. **Correction markers.** Bare "sorry", "actually", "rather" are excluded from
   `resolveSelfCorrections` — "I'm sorry about that", "I'd rather go" are
   ordinary speech.
2. **Filler "like".** "is just like human level common courtesy" and "never put
   like a corporate lens" are misses, and deliberately so. Their POS tag *and*
   their neighbours are identical to "she looks just like her mother" and "it
   was like a dream". Verified with NLTagger, not assumed.

Both need the same thing: knowing whether a comparison is actually being made.
That is semantic, and no amount of part-of-speech work reaches it. Phase 2's
measured ~110ms for a one-token classification is the right shape — "is this a
real comparison, yes or no" — and the five SwiftLlama patches are recorded in
`phase2_llm_gate_findings`.

**The asymmetry that governs all of this:** a miss leaves one visible stray
word. A false positive deletes a word and leaves a sentence that still reads
fine, so it is never noticed. Widen these rules only with evidence, never for
tidiness.

### Release pipeline

`build_distribution.sh` now depends on a provisioning profile at
`~/Library/Developer/PUSH-signing/`, deliberately outside the repo. iCloud is a
*restricted* entitlement: `PUSH.entitlements` claims it, and an app signed with
it but no embedded profile **refuses to launch, for everyone**. The script
hard-fails if the profile is missing. Never separate those two changes.

Releases below v6 were deleted from GitHub; their **tags were kept**, so any v5
is still checkoutable and rebuildable from source.

## Previous state (2026-08-15, v6.4.0 — released)

The pill can now hang from the top of the screen instead of floating at the
bottom. Prompted by Talkify (MIT, `tornikegomareli/Talkify`), whose HUD is worth
reading if this area grows: measured-vs-simulated notch split, a fixed-size host
window whose origin moves but never resizes, and `NotchFilletShape` — a square
minus a quarter disc on its *outer* corner, which is the flare we still don't
have.

**Bottom is still the default.** Top is opt-in via Settings → Pill.

### Untested: this has never run on a notched display

Everything below was verified on a 2304x1296 external monitor, which reports
`safeAreaInsets.top == 0`. The whole point of the design — flanks meeting a real
notch — is unverified. Before trusting it on a MacBook, check:

- whether the flanks line up with the notch sides or need the fillet
- whether the glow terminating at the notch's lower corners reads as intentional
- whether 37pt of camera clearance plus content is too tall in practice

### What the geometry does

- Clearance above the content is **hardware only**. A notch gets its measured
  `safeAreaInsets.top`; every other display gets 6pt. Reserving the menu bar's
  full 30pt was wrong — the tab is drawn *over* the menu bar at `mainMenu + 3`,
  and the centre where it sits is empty. That mistake was a third of the
  shape's height (59pt → 30pt on the external display).
- The window **pins its top edge on every resize**. AppKit resizes from the
  bottom-left, so a pill that grows taller pushes its own top edge down and
  opens a gap against the screen edge.
- Minimum width 280pt. A bare "Listening" pill is ~100pt and would vanish behind
  a ~200pt notch entirely; the flanks either side are what sell the illusion.

### The edge pulse

Acid green, 2pt, sweeping the three open sides on a 3.2s cycle. Two things that
are load-bearing and will look like arbitrary complexity later:

- **Trim the top run before blurring, then again after.** Blurring the full
  outline first spreads the top line's green ~5pt down, so trimming afterwards
  leaves a faint green bar across the top. The user caught this after I'd called
  it done. Measured between the flanks: 15/13/11/9/7 down rows 6-10 before, 0
  after.
- The glow is drawn **inside** the silhouette. The window is sized to the shape
  exactly — that is what stops it wasting desktop — so an outer glow would need
  transparent slack around the window, which is the thing that got removed for
  looking like stray pixels.

### Testing a dev build without losing Accessibility

TCC keys Accessibility on bundle ID **and** signature. An ad-hoc build of
`com.push.voicetotext` cannot get its own entry alongside the installed app, and
is denied against the existing one however the toggle looks — the symptom is
`Failed to create event tap`, retrying every 2s forever, with the app otherwise
running fine. Sign the test bundle with the real Developer ID and the grant
applies with no prompt. Notarisation is irrelevant to TCC.

Also: when the pill seems to have vanished, check the placement preference
before suspecting the code. `CGWindowListCopyWindowInfo` gives the truth in one
call — `layer=25` is the bottom capsule, `layer=27` the top tab. Racing
screenshots against a 4s warm-up window wastes far more time.

## Previous state (2026-08-12, v6.3.3 — released)

Live preview shipped (6.2.x). Startup/press latency work closed out in 6.3.3.
Confirmed working in production by the user.

### The one thing to understand before touching this area

**Blocking the main thread breaks the hotkey.** The CGEvent tap's run loop
source lives on the main thread, and macOS disables any tap whose callback does
not return promptly (`kCGEventTapDisabledByTimeout`). The callback itself is
already trivial — the problem is that a blocked main thread never gets to *call*
it. Every symptom chased today traced back to this:

- ~4s main-thread warm-up → key-down never delivered, nothing happened at all
- ~1-2s block during a press → release swallowed, pill stuck holding the
  transcript until the user pressed a second time
- recovery was itself queued via `Task { @MainActor }`, i.e. behind the very
  stall that broke it — measured 9s to re-enable once

So: nothing on the launch path or the press path may block the main actor.

### Where the time actually goes (measured, do not re-derive)

Cold, first launch. `AudioRecorder.buildEngine()` logs these four parts:

    engine build — alloc 0ms, inputNode 3310ms, format 0ms, prepare 167ms

`engine.inputNode` — the first bind to the audio input HAL in the process — is
essentially the entire cost. Not our code. Machine has a **USB TONOR TM310** as
default input plus **eqMac's virtual driver**; untested whether the built-in mic
is faster. That test is the next useful data point if this comes up again: if
`inputNode` drops to a few hundred ms on the built-in mic, most users never see
a deaf window at all.

Press → recording, once warm: **110-140ms** (was 216-298ms).

### What 6.3.3 changed

- Warm-ups (capture engine, chirp) run **off the main thread**, started
  immediately and in parallel with the model load. Launch→warm ~5s → ~3.5s.
- One `AVAudioEngine` per process, stopped rather than discarded between
  recordings, rebuilt on `.AVAudioEngineConfigurationChange`. The old prewarm
  built a *local* engine that was released on return, tearing the device back
  down, so the first press paid the cold cost anyway (`inputFormat` 724ms → 0-2ms).
- A press landing mid-warm-up **joins the build already in flight** and awaits
  it. Starting a second engine and blocking on it cost 1336ms of pinned main
  thread while the background build finished moments later. `startRecording` is
  async for this and bails if the key is released first.
- `SoundPlayer`: warmed with a silent play, wound down with **`pause()`, never
  `stop()`** — `stop()` is documented to undo `prepareToPlay()`'s setup, which
  is why three earlier "prewarm" attempts still cost ~1s. `playChirp` also runs
  off the main actor and skips entirely if not yet warm.
- **Release watchdog**: while the key is held, a run-loop timer asks the hardware
  every 250ms whether the modifier is really still down, and ends the take if it
  isn't (two consecutive readings required). Confirmed catching a real dropped
  release. Deliberately evidence-independent — it doesn't care *why* an event
  went missing.
- Tap re-enabled **synchronously** inside the callback (already on the main run
  loop) rather than via a main-actor hop.
- `AppState.isCapturing` — the pill only says "Listening" once the mic is
  genuinely live. It used to say it through a measured 4.2s wait, and the user
  spoke the whole time into nothing.
- `AppState.isPrewarming` — warm-up indicator covers model + chirp + engine +
  VAD, not just `isModelReady` (which flips in ~0.1s and was a dishonest signal).
  Cleared in a `defer`, logged as `warm-up complete, indicator cleared`.
- `AppState.pillShouldShow` — single source of truth. The view and AppDelegate
  each had their own copy of the visibility condition; adding `isPrewarming` to
  only one meant the window was ordered out before the view could ever draw.
- Pill sizes itself via `NSHostingController.sizingOptions = .preferredContentSize`
  instead of hand-rolled refits. Every manual refit had to name the moments worth
  re-measuring, and each missed one clipped the text.

### How to measure this

Release builds log to `~/Library/Application Support/PUSH/push_debug.log`
(capped 512KB). `log show` surfaces nothing from release builds.

`PressTiming` is in the shipping build and prints offsets from key-down:

    main-actor hop → state set → chirp → startRecording enter → engine ready
      → inputFormat → engine.start → beginDictation → recording started

Compare a press right after launch against one a minute later. **Beware:** most
of today's "clean" runs were warm presses read as if they were cold — the cold
path stayed broken for hours behind that mistake.

For local test builds without notarising, see the throwaway script pattern:
`swift build -c release`, swap the binary + `.bundle` into an existing signed
`PUSH.app`, re-sign with the Developer ID (keeps the Accessibility grant), then
`open -n` it. `open` on the path alone can get redirected to `/Applications`.

### Open / next

- **Deaf window**: ~3.3s after launch where a press waits on the audio HAL. Only
  full fix is starting the engine at launch, which lights the system mic
  indicator — rejected by default for the same reason wake-word ships off.
  Test the built-in mic first.
- Event tap still runs on the main run loop. Moving it to a dedicated thread is
  the structural fix, but the two `nonisolated(unsafe)` Bools in the callback
  become a genuine cross-thread race, and event ordering must stay FIFO
  (`DispatchQueue.main.async`, not `Task`). Held back as too risky to bundle;
  the watchdog covers the observed failure.
