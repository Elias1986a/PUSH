# Type model eval — 2026-10-10

`python3 eval/run_autocomplete_eval.py` over `eval/autocomplete_scenarios.jsonl`
(60 scenarios: 50 with a surface line, 10 without, 15 mid-word, 5 sign-offs).
Mac mini M4, 24 GB. Homebrew `llama-server` build 10566, `-c 4096 -ngl 99`,
greedy, one 32-token run per scenario cut to each length preset.

## Summary

| Model | Size | First-word hit (healed) | Mean prefix words | Mid-word | 1,500-char cold p90 | Per keystroke p90 | Repetitive @20 words |
|---|---|---|---|---|---|---|---|
| Qwen3.5 0.8B Base Q6_K | 0.63 GB | 34/60 | 0.72 | 14/15 | 180 ms | 43 ms | 4 |
| Granite 4.0 1B Base Q4_K_M | 1.02 GB | 40/60 | 0.83 | 14/15 | CPU only¹ | CPU only¹ | 5 |
| Qwen3.5 2B Base Q4_K_M | 1.27 GB | 36/60 | 0.82 | 14/15 | 408 ms | 74 ms | 2 |
| SmolLM3 3B Base Q4_K_M | 1.92 GB | 38/60 | 0.80 | 13/15 | 663 ms | 45 ms | 12 |
| Gemma 4 E2B Base Q4_K_M | 3.43 GB | 40/60 | 0.80 | 14/15 | 527 ms | 93 ms | 2 |
| *Control:* Qwen3 4B instruct, chat prompt | 2.50 GB | 35/60 (raw) | 0.73 | 11/15 | 969 ms | 133 ms | 0 |

¹ Granite on Metal returns `@@@@…` after a few requests (fine on the CPU), and
llama.cpp's grammar sampler threw on it until it was moved to the CPU. Its quality
is scored on the CPU; its latency is not comparable. Re-tested on the pinned
b11147 framework (`LlamaSmokeTests.testRepeatedRequestsWithCacheReuseStayCoherent`):
still garbage on Metal, even single-shot for prompts over ~8 tokens. Ruled out.

**Leaks: 0 for every model** at every length.

## Findings

- **Token healing is required.** A prompt ending inside a word ("really appreci")
  makes every base model start a new word: mid-word 1–2/15 raw. Backing off the
  partial word and forcing the output to start with it again through a llama.cpp
  grammar ("healed") gives 13–14/15 and lifts the overall first-word hit by 10–13
  scenarios per model. The app must do this (llama.cpp grammar sampler).
- **The grammar must not forbid `\n`.** `[^\n]*` makes the model run on past where
  it would stop; use "forced start, then anything" and let the `\n` stop cut.
- **Cold vs. per keystroke.** A 1,500-char prompt costs 180–530 ms cold. With the
  prompt cache reused (the user typed one more character), first token is
  43–93 ms. The app reuses the KV cache across keystrokes (Task 3.1), so cold
  happens on focus change only.
- **Base beats instruct per unit of cost.** The 4B instruct control matches the
  0.8B base on hits at 3× the per-keystroke latency and 5× the cold latency.
- **Past the first sentence, every model drifts**: invented names (Tim Ferriss,
  James Clear), placeholder emails, loops ("I'm so sad" ×5, ". . . ."). Gemma and
  Qwen 2B mostly stop at the sentence end on their own; SmolLM3 and Granite run on.
- Scores are exact-match against one plausible continuation on 60 scenarios:
  a 2–4 hit difference is noise. Read the samples in `.autocomplete_eval.json`.

## Raw tables
```

== qwen3.5-0.8b-base
   1,500-char prompt first token: cold median 179 / p90 180 ms; per keystroke (cache hit) median 33 / p90 43 ms

   -- raw
   scenario first token: median 65 ms, p90 67 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 21/60 | 0.48 |
   | with surface | 50 | 18/50 | 0.52 |
   | no surface | 10 | 3/10 | 0.30 |
   | mid-word | 15 | 1/15 | 0.20 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 20 |
   | 7 | 0 | 0 | 31 |
   | 12 | 0 | 1 | 40 |
   | 20 | 0 | 4 | 49 |

   -- healed
   scenario first token: median 38 ms, p90 68 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 34/60 | 0.72 |
   | with surface | 50 | 27/50 | 0.70 |
   | no surface | 10 | 7/10 | 0.80 |
   | mid-word | 15 | 14/15 | 1.13 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 22 |
   | 7 | 0 | 0 | 33 |
   | 12 | 0 | 2 | 41 |
   | 20 | 0 | 4 | 48 |

== granite4-1b-base
   1,500-char prompt first token: cold median 3152 / p90 3162 ms; per keystroke (cache hit) median 40 / p90 41 ms

   -- raw
   scenario first token: median 247 ms, p90 352 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 26/60 | 0.58 |
   | with surface | 50 | 23/50 | 0.64 |
   | no surface | 10 | 3/10 | 0.30 |
   | mid-word | 15 | 1/15 | 0.20 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 11 |
   | 7 | 0 | 0 | 19 |
   | 12 | 0 | 2 | 24 |
   | 20 | 0 | 5 | 32 |

   -- healed
   scenario first token: median 41 ms, p90 254 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 40/60 | 0.83 |
   | with surface | 50 | 33/50 | 0.84 |
   | no surface | 10 | 7/10 | 0.80 |
   | mid-word | 15 | 14/15 | 1.13 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 12 |
   | 7 | 0 | 0 | 22 |
   | 12 | 0 | 2 | 26 |
   | 20 | 0 | 5 | 33 |

== qwen3.5-2b-base
   1,500-char prompt first token: cold median 407 / p90 408 ms; per keystroke (cache hit) median 59 / p90 74 ms

   -- raw
   scenario first token: median 125 ms, p90 128 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 25/60 | 0.58 |
   | with surface | 50 | 21/50 | 0.62 |
   | no surface | 10 | 4/10 | 0.40 |
   | mid-word | 15 | 2/15 | 0.27 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 26 |
   | 7 | 0 | 0 | 38 |
   | 12 | 0 | 0 | 45 |
   | 20 | 0 | 1 | 49 |

   -- healed
   scenario first token: median 57 ms, p90 127 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 36/60 | 0.82 |
   | with surface | 50 | 29/50 | 0.82 |
   | no surface | 10 | 7/10 | 0.80 |
   | mid-word | 15 | 14/15 | 1.27 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 25 |
   | 7 | 0 | 0 | 38 |
   | 12 | 0 | 1 | 44 |
   | 20 | 0 | 2 | 48 |

== smollm3-3b-base
   1,500-char prompt first token: cold median 651 / p90 663 ms; per keystroke (cache hit) median 44 / p90 45 ms

   -- raw
   scenario first token: median 103 ms, p90 158 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 27/60 | 0.57 |
   | with surface | 50 | 23/50 | 0.60 |
   | no surface | 10 | 4/10 | 0.40 |
   | mid-word | 15 | 1/15 | 0.20 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 6 |
   | 7 | 0 | 0 | 10 |
   | 12 | 0 | 2 | 14 |
   | 20 | 0 | 10 | 18 |

   -- healed
   scenario first token: median 48 ms, p90 109 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 38/60 | 0.80 |
   | with surface | 50 | 32/50 | 0.82 |
   | no surface | 10 | 6/10 | 0.70 |
   | mid-word | 15 | 13/15 | 1.20 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 8 |
   | 7 | 0 | 0 | 12 |
   | 12 | 0 | 3 | 16 |
   | 20 | 0 | 12 | 21 |

== gemma4-e2b-base
   1,500-char prompt first token: cold median 523 / p90 527 ms; per keystroke (cache hit) median 87 / p90 93 ms

   -- raw
   scenario first token: median 160 ms, p90 167 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 28/60 | 0.58 |
   | with surface | 50 | 24/50 | 0.62 |
   | no surface | 10 | 4/10 | 0.40 |
   | mid-word | 15 | 2/15 | 0.27 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 24 |
   | 7 | 0 | 0 | 33 |
   | 12 | 0 | 0 | 42 |
   | 20 | 0 | 2 | 49 |

   -- healed
   scenario first token: median 79 ms, p90 164 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 40/60 | 0.80 |
   | with surface | 50 | 32/50 | 0.78 |
   | no surface | 10 | 8/10 | 0.90 |
   | mid-word | 15 | 14/15 | 1.13 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 22 |
   | 7 | 0 | 1 | 30 |
   | 12 | 0 | 1 | 39 |
   | 20 | 0 | 2 | 46 |

== qwen3-4b-instruct
   1,500-char prompt first token: cold median 964 / p90 969 ms; per keystroke (cache hit) median 129 / p90 133 ms

   -- raw
   scenario first token: median 197 ms, p90 204 ms
   | slice | n | first-word hit | mean prefix words |
   |---|---|---|---|
   | all | 60 | 35/60 | 0.73 |
   | with surface | 50 | 29/50 | 0.76 |
   | no surface | 10 | 6/10 | 0.60 |
   | mid-word | 15 | 11/15 | 0.80 |
   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |
   |---|---|---|---|
   | 3 | 0 | 0 | 15 |
   | 7 | 0 | 0 | 27 |
   | 12 | 0 | 0 | 33 |
   | 20 | 0 | 0 | 42 |
```
