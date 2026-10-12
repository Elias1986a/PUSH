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
