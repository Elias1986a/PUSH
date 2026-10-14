# Context-Aware Dictionary — Design

- **Date:** 2026-07-01
- **Status:** Approved design, not yet implemented
- **Target version:** 5.0.0
- **Author:** brainstormed with Claude Code

## Problem

The v4.1.5 custom dictionary applies corrections as an unconditional,
case-insensitive, whole-word find/replace (`CorrectionsStore.apply`). This
corrupts text when the "heard as" word is also a legitimate word with another
meaning. Concrete case:

> "email to **Hammer**. I have a big **hammer**."

The user wants the first "Hammer" to become the person **Hamer**, but the
second "hammer" (the tool) must be left alone. A blind replace can't tell them
apart and turns both into "Hamer".

Key observation from testing: with the dictionary entry **deleted**, raw
Whisper already transcribed both correctly (it even capitalized the name after
"to"). **Lesson: the biggest risk is corrupting output that was already right.
The system should fail toward *not* intervening.**

## Goals

- Apply a correction only when context agrees it's the intended entity.
- Keep the everyday path at today's (effectively instant) speed.
- Generalize beyond hand-curated trigger lists.

## Non-goals (YAGNI for 5.0.0)

- Full LLM rewrite/cleanup of the whole transcript (approach "B") — a later POC.
- Decoder-level vocabulary biasing (approach "C") — later, speed permitting.
- Automatic learning of corrections from user edits.

## Constraints

- **Added latency ≤ 200 ms** after the user stops speaking (target p95).
  Budget band: 50–150 ms typical.
- A **tiny instruct model is assumed already warm/loaded** (startup load and
  resident-memory cost are out of scope for this design; tracked separately).

## Chosen approach — Hybrid gate (approach 3 of 3)

Not every entry is risky. Pure jargon ("Kubernetes", a product codename) is
never anything else and should apply instantly. Only entries whose "heard as"
word has an alternate meaning need judging. So we split entries into two lanes
and only spend the latency budget on the ambiguous ones.

### Data model

```swift
struct Correction: Codable, Identifiable, Equatable {
    var id = UUID()
    var wrong: String            // "Hammer"  (heard as)
    var right: String            // "Hamer"   (should be)
    var kind: Kind = .always     // .always | .contextual
    var entity: String?          // "a person named Hamer" — hint for the gate
}
enum Kind: String, Codable { case always, contextual }
```

- **`.always`** (default): unconditional whole-word replace — today's behavior,
  ~0 ms. For unique jargon/names never meant otherwise.
- **`.contextual`**: routed through the gate. `entity` is the only context the
  model needs, and the user already knows it when adding the entry.
- Auto-suggest `.contextual` when `NSSpellChecker` recognizes the "heard as"
  word as real English (ambiguity likely). User can override.

### Pipeline placement & flow

Runs where the dictionary runs today — after transcription, **before** the
formatting pipeline (so corrected words still feed number/punctuation
formatting). The single `apply(...)` call becomes a fast lane + gated lane:

```
transcript ("...email to Hammer. I have a big hammer.")
   │
   ├─ 1. apply .always entries → unconditional regex replace   (~0 ms)
   │
   ├─ 2. scan for .contextual matches → collect ambiguous spans
   │        "Hammer"@[9..15], "hammer"@[31..37]
   │
   ├─ 3. GATE the spans:
   │        a. heuristic pre-filter (capitalization, trigger words)
   │           resolves the easy ones, shrinking what reaches the model
   │        b. remaining truly-ambiguous spans → ONE batched warm-LLM call
   │
   └─ 4. apply only gate-approved spans → formatting → paste
```

**Load-bearing decision:** step 3b is a **single batched inference**, not one
call per match. The model gets the whole sentence plus every unresolved span at
once and returns a per-span verdict. Latency is ~constant regardless of match
count — the only option that provably holds the 200 ms ceiling. (Per-match with
a warm model at ~30–80 ms each breaches the budget at 3+ spans.)

On a typical transcript with no `.contextual` entries, steps 2–3 find nothing
and we are back at today's speed.

### The gate call

```
System: You resolve ambiguous words in dictated text. For each numbered
item, reply with only the item number and PERSON or TOOL.

User: Sentence: "email to Hammer. I have a big hammer."
Candidates:
  1. "Hammer" (offset 9)  — could be a person named Hamer, or the tool
  2. "hammer" (offset 31) — could be a person named Hamer, or the tool

Answer:
```

- **Constrained decoding** to a tiny grammar (`\d+ (PERSON|TOOL)` per line) so
  output is a few tokens and cannot ramble. (The PERSON/TOOL labels here are
  illustrative; the real labels are `APPLY`/`KEEP` per span, derived from each
  entry's `entity`.)
- Parse verdicts back to spans by number. Approved spans get the replacement;
  the rest stay as Whisper wrote them.

### Fallback — fail-safe toward *not* corrupting

In priority order:

1. Model not loaded → **skip** contextual corrections (leave raw transcript).
2. Inference exceeds a hard ~150 ms deadline → cancel, **skip**.
3. Unparseable output → **skip**.

Never fall back to "apply anyway." This encodes the deletion lesson: raw
Whisper is usually right, so when unsure, don't touch it.

## Measurement

Instrument the gate to record heuristic time, LLM inference time, total time,
and span counts via `PushLogger`. **Privacy-safe: timings and counts only,
never transcript text** (consistent with the existing pipeline). Provides
p50/p95 to validate against the 200 ms ceiling.

## UX (Dictionary tab)

- Add/edit an entry gains a toggle: *"This word has other meanings — decide by
  context."* Off = `.always`; On = `.contextual`, revealing one field:
  *"What is it?"* → the `entity` hint.
- Auto-suggest the toggle ON when `NSSpellChecker` recognizes the word.
- Fully backward compatible: untouched entries behave exactly as today.

## POC scope (go/no-go)

Smallest thing that proves it: a hidden dev flag enables the gate; one
hardcoded tiny warm model; log verdicts + timings. Feed ~15 sentences (the
Hamer/hammer pair plus others) and answer two questions:

1. Does it classify correctly?
2. Does p95 stay under 200 ms?

## Testing

- Deterministic units (no model, run in CI): always/contextual split,
  heuristic pre-filter, verdict parsing, every fallback path.
- The gate sits behind a protocol so pipeline tests inject a fake verdict
  source.
- One opt-in integration test exercises the real warm model against fixed
  sentences, asserting both verdicts and the latency budget.

## Future / to revisit

- **Per-match vs batched** as an A/B once batched ships (batched first because
  N=1 is the per-match case — no throwaway work).
- **Approach B** (full local-LLM cleanup pass) as a separate scoped POC.
- **Approach C** (decoder vocabulary biasing) if the latency budget allows.
- **Warm-up cost** of the tiny model (startup load, resident memory, app
  size/download) — deferred here, must be resolved before shipping 5.0.0.
