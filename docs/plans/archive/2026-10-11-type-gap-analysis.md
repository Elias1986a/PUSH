# Type — gap analysis against Cotypist and Cotabby

Date: 2026-10-11 (overnight, after the user's first hands-on test: "something's off
from the nuts and bolts piece").
Sources: cotypist.app (home, /help, /help/tips, /help/personalization,
/help/shortcuts) and Cotabby's source (ARCHITECTURE.md, CompletionContentPolicy,
DecodeStopPolicy, SuggestionLengthPolicy, SuggestionConfiguration,
LlamaRuntimeCore, CredentialFieldDetector, MailHeaderFieldDetector,
ConfidenceSuppressionPolicy, MODEL_EVAL.md). Cotabby is AGPL: ideas only.

## The headline

**A prompt ending in a space was broken.** A BPE model writes a word with its
leading space (" see" is one token); after a bare space it has no normal word
left and reaches for digits, years and HTML. You pause after a space most of
the time, so most suggestions were drawn from the junk end of the model.
Measured, prompt ending in a space, raw → fixed (Gemma 4 E2B):

| Text | Before | After |
|---|---|---|
| "…would love to " | 2018. | meet up with you. |
| "…overall it looks " | (empty) | good. |
| "…the latest version of the " | 2019-2020 version | app? |
| "Let me know if you have any " | `<b>questions</b>.` | questions. |
| "…need the artwork by " | 10am on Thursday. | the end of the day. |

Qwen 2B shows the same pattern. Fixed by moving trailing spaces into the forced
start, as the partial word already was (Cotabby hands the boundary whitespace
to its required prefix the same way). The Phase 0 eval missed it because none
of its scenarios ended in a space — **the eval must cover that case**.

## Fixed tonight (each committed with tests)

| Gap | Evidence / source | Fix |
|---|---|---|
| Trailing-space prompts | table above | heal the space |
| Context window slid every keystroke | prompt start changed → KV cache missed → whole window reprocessed per key | start moves in 512-char steps; window 1,500 → 4,000 chars (Cotabby: up to 14,000) |
| Greedy decoding looped ("3 3 3 3") | Cotabby: repetition penalty 1.025 | penalty over the last 64 tokens incl. the user's text; greedy kept (Cotabby's temp/top-k sampling flipped "Paris" and doubled latency here) |
| Per-token confidence pass cost 25–35 ms/token | measured | opt-in (diagnostics only); per keystroke back to 46 / 52 / 34 ms |
| 150 ms debounce | Cotabby 20 ms; Cotypist "updates within a letter or two" | 50 ms |
| Copy rule too broad | Cotabby: a whole-window rule dropped 168/179 in a note with a repeated paragraph | only "restarts the last four words"; 1–3 word loops; punctuation after a typed space; forum residue; talk-back |
| Sign-in fields, Mail header | Cotabby detectors; Tab moves fields in Mail | stand down |
| Typos | Cotabby holds while a typo forms; Cotypist: fix it first | no suggestion on a misspelled last word (names exempt) |
| Esc came straight back | Cotypist pauses the field | 3 s pause on that field |
| Ghost text jumped | top-aligned in a caret-tall box | centred on the caret |
| Silent rules | Cotabby logs suppression reasons | one log line per "no suggestion", rule name only |

Earlier the same night (user-reported): persona / self-description / explicit /
web-debris / other-script filters, three-word minimum (user's call), field
fitting, caret prediction after accept, fresh field reads.

## Still missing — ranked

1. **Personalization (biggest quality lever).** Cotypist's quality comes from
   learning the user's writing ("vocabulary, names, the way you phrase
   things"), opt-in, encrypted, local; plus short custom instructions
   (pre-filled from language/region) and per-app instructions. Cotabby: opt-in
   typing history (AES-GCM, Keychain key, never synced), two similar past
   passages added to the prompt, and a phrase predictor. The generic primer
   experiment showed examples steer the model well — but copy verbatim, which
   is right only for the user's own text. *Decision for the user:* do Phase 6's
   history + instructions before Phase 5's settings polish?
2. **An eval through the real pipeline.** Tonight's worst bugs (trailing space,
   sliding window, sampler cost) were in the pipeline, not the model, and the
   model-only eval could not see them. Cotabby replays ~190 phrases per
   category through its app code at word and mid-word checkpoints. Build a
   replay: prompt (TypingPrompt) → engine → filters, with trailing-space and
   mid-word variants.
3. **Hold while the host shows its own prediction or IME composition**
   (Cotabby: marked text). macOS inline predictive text is on on this Mac and
   also uses Tab.
4. **"Trailing space after single-word completions"** option (Cotypist), and
   **Option+Tab sends a real Tab** for forms.
5. **Per-app / per-domain controls** — on/off, pause in this app, force-activate
   (Cotypist Ctrl+`), per-app instructions. Phase 5.
6. **Model tier:** Cotabby also ships Gemma 4 E4B (5 GB, "pro") and uses Gemma
   E2B at Q6 rather than Q4. Worth an A/B by feel.
7. **Sentence stop vs. minimum length:** Cotabby lets the model run past a
   sentence end until the preset's minimum ("report." alone made lengths
   jumpy). We stop at every sentence end (Phase 0: drift after it). Revisit
   with the replay eval.
8. **Speculative generation after a full accept** (Cotabby) — the next
   suggestion is ready before the next key.
9. **Geometry quality + pixel baseline** (Cotabby measures the painted
   baseline; needs Screen Recording). Only if centring is not enough.
10. **Word alternatives / synonyms** (Cotypist Labs). Later.

## Confirmed as right

Base models with the caret text last; no instructions; name only at a
sign-off; code editors off in the main editor (Cotypist: sidebar chats only);
terminals only in agent prompts; Tab = next word, key above Tab = whole;
nothing leaves the Mac. Cotypist's own guidance matches what we saw: "Expect
the first word or two to be what you meant. Longer completions drift," and it
is weak for "terse chat messages with little context".
