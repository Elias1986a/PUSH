# NOTES

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

### Still open

- **Cross-Mac sync has still only been exercised on one machine.** The
  capability is proven (a KVS write crossed in 2 seconds), but the shipped
  feature has not been watched end to end. Now that both Macs can run 6.5.2:
  add a dictionary word on one, watch it appear on the other.
- **Phase 2, the LLM resolver.** Job description below; unchanged.
- **Stale remote branches.** `claude/realtime-speech-display-quculk` (Aug 12)
  never merged — live preview shipped down a different path and main's version
  is well past it. The other `claude/*` branches are merged and can go too.

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
