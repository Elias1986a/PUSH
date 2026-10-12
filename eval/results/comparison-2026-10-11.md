# Side-by-side: Cotypist vs Cotabby vs PUSH Type (2026-10-11)

One app running at a time. Ten sentences typed into TextEdit at 70 ms a key (a
script, `cmp/run.sh` in the session scratchpad). The window was captured 0.6 s and 2.5 s
after the last key, then Tab was pressed and it was captured again.

Setups as the user had them:
- Cotypist 2026.5 used Gemma 4 E2B and the user's own style note.
- Cotabby 0.6.2-beta used Qwen3.5 2B.
- PUSH was run with Gemma E2B, Qwen 2B and Gemma E4B. It used the About note and history.

## Suggestions (as shown 2.5 s after the last key)

| Typed | Cotypist (E2B) | Cotabby (Qwen 2B) | PUSH E2B | PUSH Qwen 2B | PUSH E4B |
|---|---|---|---|---|---|
| …proposal over. I | ’ve reviewed the proposal and have | have reviewed it and I am pleased to inform you | ’ve reviewed it and have some questions. | ’ve reviewed it and I think it’s | ’ve reviewed it and have some feedback. |
| Can we move our meeting to | next week? | 10:30? | tomorrow? | 10:30? | 10:30am? |
| I really appreci | ate that you’re taking the | — (nothing) | ate your time and consideration. | ate your suggestion. | ate your feedback. |
| Sorry for the late reply, I was | on vacation and I | busy with other things. | out of town. | busy with other things. | out of town. |
| Let me know if you have any␣ | questions or concerns. | questions. | questions. | questions. | questions. |
| …launch is planned for | October 2026. | the 15th of this month. | next week. | next week. | 2 weeks from now. |
| Hope you had a great | weekend! | weekend. | weekend! | weekend. | weekend! |
| We need the final artwork | for the proposal. | for the new website. | by 10 am tomorrow. | for the proposal. | by 12/31/2022. |
| Could you send me the␣ | link to the website? | proposal? | proposal? | email? | link to the video? |
| Happy birthday! I hope | you have a wonderful day. | you’re having a great day. | you have a great day! | you’re having a great day. | you have a wonderful day. |

## Speed (suggestion on screen 0.6 s after the last key)

| | Cotypist | Cotabby | PUSH (all three models) |
|---|---|---|---|
| Shown by 0.6 s | 10/10 | 7/10 (the mid-word case never showed) | 10/10 |
| Shown after Tab | 10/10 | 10/10 | 10/10 |

After a Tab that finishes a sentence, PUSH already shows the next sentence (prefetch). Cotabby
does too. Cotypist keeps its Tab inside the sentence. It leaves trailing punctuation as ghost
text, so it seldom reached a sentence end here.

## What it says about PUSH

1. **Dates and times.** Cotypist's “October 2026” is today’s month, which suggests it gives the
   model the date. PUSH doesn’t. Its misses here are invented specifics: “by 10 am tomorrow”,
   “12/31/2022”, and next sentences such as “I’m available at 10am or 2pm.” Giving the model today’s date
   should fix the wrong-year cases. Invented times are a separate habit.
2. **Font.** Cotypist draws in the field’s own font, so its ghost text matches the typed text
   exactly. PUSH draws in the system font sized from the caret height (`GhostTextPanel.font`).
   In TextEdit’s Helvetica 12, PUSH’s text looks slightly smaller and more widely spaced. Cotabby is
   larger still, adds a gap and a “Tab” badge.
3. **Quality with the same model.** PUSH E2B and Cotypist E2B are close. PUSH E4B is no better than
   E2B on these ten sentences and is the worst on dates.

## Follow-up the same day: speed, measured properly

The user still felt Cotypist was faster, so a finer probe was used. It typed at 10 keys a second and
polled the screen right of the caret. While typing, "visible" means a suggestion was on screen 80 ms after a key.

| | Visible while typing | Key to suggestion (median) |
|---|---|---|
| Cotypist (its new Q4_C model) | 58% | — |
| PUSH before | 10% | 96 ms |
| PUSH after | **61%** | **57 ms** |

Where the 96 ms went:
- a 50 ms pause before suggesting, now 10 ms;
- llama.cpp's grammar sampler scanning all 262k tokens on every step (35 ms a token against 18). The engine
  now enforces the healed word itself (`ForcedStart`);
- a judge that waited a step for a word to end even when it already was one.

The same day also brought:
- the font match;
- today's date in the prompt;
- the stop before numbers nobody wrote.

## Round 2 (evening): PUSH vs Cotypist only

Both had the user's same bio. PUSH ran Gemma E2B, gray, in the field's font; Cotypist ran its updated
Q4_C model. Ten fresh sentences were used for quality and ten for speed, so neither app had seen them.

**Look.** In TextEdit the two are now the same: same font and size, same gray.

**Quality** (suggestion 2.5 s after the last key, Cotypist / PUSH):
- **The same:** "tomorrow." / "tomorrow."; "great weekend!" ×2; "in a meeting." ×2; "the same content." /
  "the same movies and shows that I've".
- **Cotypist better:** "please start | without me." / "with the next section."; "let me know | if there are…" /
  "if you have any questions?".
- **PUSH better:** "discuss the | design and then I'll" / "release notes for the upcoming release." (it uses
  the earlier text).
- **After Tab:** PUSH accepts "tomorrow." and shows the next sentence at once. Cotypist leaves the period behind as
  a suggestion and offers nothing further.

**Speed** (visible 80 ms after a key, typing at 10 keys a second, same sentences):

| | Visible while typing |
|---|---|
| Cotypist | 70% |
| PUSH, 0.1 s fade-in | 63% |
| PUSH, no fade | 68% |

The fade costs about 5 points on this probe. A partly faded suggestion falls under the probe's brightness
threshold, though a person may already see it.
