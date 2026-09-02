# PUSH — Model Tracking & Upgrade Watch

> **Last reviewed: 2026-08-10 (v6.0.0).** This document was written in June 2026
> and its findings table predates the 6.0.0 model refresh. What changed since,
> verified by A/B on real dictation rather than published benchmarks:
>
> - **FluidAudio 0.13.6 → 0.15.5.** Added **Parakeet Unified 0.6B** (offline,
>   1.82% WER) and **Parakeet Streaming** (chunked-attention). Streaming is now
>   the default: latency after release is near-constant (0.068s on 6s of audio,
>   0.086s on 26s) where the offline encoder scales with length (0.148s → 0.492s).
> - **WhisperKit 0.15.0 → 1.1.0.** Fixed a hang where a Whisper model reported
>   loaded but activation never completed.
> - **Removed:** Distil-Large V3, Distil-Large V3 Turbo, Moonshine Base —
>   superseded by the Parakeet family on both speed and accuracy.
> - **Evaluated and rejected:** Apple SpeechAnalyzer (macOS 26+). Zero download,
>   but benchmarks at 150–400ms vs Parakeet's sub-100ms. Only interesting as a
>   no-download fallback.
> - **Still open:** Parakeet EOU (120M) streaming with end-of-utterance detection
>   is untried and could replace Silero VAD for wake-word auto-stop.

> **Updated 2026-09-01 (multilingual).** Multilingual dictation shipped, and it
> is **not** Parakeet TDT v3. See the 2026-09-01 review-log entries below for
> what was measured; the short version:
>
> - **Nemotron 3.5 ASR Streaming Multilingual 0.6B** is the multilingual engine,
>   via FluidAudio's `StreamingNemotronMultilingualAsrManager`. It is cache-aware
>   *streaming*, so multilingual costs nothing in latency relative to the English
>   streaming path. Two vocab builds: `latin` (en/es/fr/it/pt/de, pruned vocab,
>   faster joint) and `multilingual` (full 13,087-token vocab, incl. zh/ja).
>   **All six latin languages share one 600 MB download**; switching between them
>   is a prompt-id swap with no reload.
> - **Parakeet TDT v3 was evaluated and NOT given a language picker.** Its
>   `language:` parameter is a *script* filter (Latin/Cyrillic/Greek — see
>   `TokenLanguageFilter.swift`), so it cannot distinguish Spanish from French,
>   and it auto-detects regardless. A 25-entry dropdown where 22 entries behave
>   identically would be decorative. It remains a benchmark contestant.
> - **Apple Speech gained an explicit language selector** — genuinely per-locale
>   (`SpeechTranscriber(locale:)`), 45 locales on macOS 27.


This file tracks the ML models / SDKs PUSH ships, the versions currently
pinned, and known upgrade opportunities. It exists so model research doesn't
have to start from scratch each time. **Update the "Last reviewed" date and the
findings table whenever a check is run** (a monthly reminder is scheduled).

**Last reviewed:** 2026-06-30

## Platform preference
- Target is **Apple Silicon macOS only**. Prefer on-device, offline inference.
- For Mac we prefer **MLX** (Apple's GPU framework) or **CoreML/ANE** variants of
  models over generic CPU/llama.cpp builds where a quality/perf win exists.
- Caveat: the MLX ASR path (`soniqo/speech-swift`) is currently **disabled** in
  `Package.swift` — *"TODO: Re-enable once MLX metallib bundling is resolved."*
  FluidAudio (CoreML/ANE) is the working native-Swift Parakeet path today and
  keeps the GPU free; MLX remains the goal for the LLM post-processing step.

## Currently pinned (see `Package.swift`)

*Corrected 2026-09-01 against `Package.swift` / `Package.resolved` — the previous
version of this table listed WhisperKit and Moonshine, both removed in v7.0.0
(`a6a4c9d`), and claimed Parakeet TDT **v3** was in use when the code loads `.v2`.*

| Component | SDK / package | Pinned | Model in use | Engine |
|-----------|---------------|--------|--------------|--------|
| ASR (default, English) | FluidAudio | `from: 0.15.5` @ `19600a48` | **Parakeet Unified 0.6B** (`-en-`) offline + streaming | CoreML/ANE |
| ASR (English, older) | FluidAudio | same | Parakeet TDT 0.6b **v2** (`.v2`, 400 MB) | CoreML/ANE |
| ASR (multilingual) | FluidAudio | same | **Nemotron 3.5 Streaming Multilingual 0.6B** — `latin` or `multilingual` build, 2240 ms tier | CoreML/ANE |
| ASR (OS) | — | macOS 26+ | Apple `SpeechTranscriber`, per-locale (45 locales) | system |
| VAD | FluidAudio | same | Silero VAD | CoreML |
| ASR (MLX) | speech-swift (Qwen3-ASR) | **disabled** | — | MLX+CoreML |
| LLM post-proc | SwiftLlama (llama.cpp) | **not shipped** | Phase 2 gate was reverted in v5.0.3 | llama.cpp (Metal) |

**Removed, do not reinstate without re-measuring:** WhisperKit and Moonshine
(v7.0.0). Moonshine never worked — its weights only ever existed in the upstream
package's test resources. Parakeet won on the **ANE**, not on CPU; any non-Apple
port must re-run the bake-off.

## Upgrade opportunities (as of 2026-06-29)

1. **Parakeet TDT v2 → v3 (highest value).** FluidAudio now ships
   `parakeet-tdt-0.6b-v3`: 25-language multilingual with automatic language
   detection, ~6.34% avg WER, retains native punctuation. In `ParakeetEngine`
   this is `AsrModels.downloadAndLoad(version: .v3)` (today it's `.v2`). Would
   give multilingual support the app currently lacks. Validate model dir name
   (`parakeet-tdt-0.6b-v2` → `-v3`) and size/RAM impact.

2. **FluidAudio 0.13.6 → 0.15.4.** Brings Parakeet v3, plus
   **Nemotron Speech Streaming 0.6B** (2.12% WER, 6.4× RTFx) and streaming
   End-of-Utterance detection — relevant if real-time/streaming dictation is
   wanted. Check API/breaking changes before bumping.

3. **WhisperKit 0.9.0 → 1.0.0 (May 2026).** Repo renamed to
   `argmaxinc/argmax-oss-swift`; Swift 6 compatible; now bundles SpeakerKit
   (diarization) + TTSKit (Qwen3-TTS) in one MIT package. Import path /
   package name likely changed — treat as a migration, not a flag bump.

4. **MLX for the LLM post-processing step.** SwiftLlama (llama.cpp/Metal) works,
   but an MLX Swift path (mlx-swift / mlx-audio ecosystem) is the preferred
   Apple-Silicon direction. Blocked historically by metallib bundling; revisit.

## New models / engines *outside* the current set (2026-06-30)

These aren't upgrades to existing dependencies — they're new options worth
considering, found by looking beyond what PUSH already ships.

1. **Apple SpeechAnalyzer (macOS 26 / WWDC 2025).** Native, fully on-device
   ASR built into the OS — **zero dependencies, no model download, no audio
   duration cap**. For a privacy-first offline dictation app this is a strong
   fit and could be a zero-overhead default/fallback engine alongside the
   current `EngineType` cases. Highest-signal new option for PUSH.

2. **Qwen3-ASR (Alibaba, Jan 2026).** 52 languages w/ language ID, timestamps;
   sizes 0.6B and 1.7B. This is the model behind the **MLX path already
   half-wired but disabled** in `Package.swift` (`soniqo/speech-swift`, the
   `qwen3ASR` enum case). Directly aligns with the "prefer MLX on Mac" goal —
   revisit once the metallib bundling blocker is resolved.

3. **Google Gemma 3n / Gemma 4 (E2B, E4B) — open weights.** Multimodal models
   with a USM-based audio encoder that do **on-device ASR + speech translation**,
   with first-class **MLX** support on Apple Silicon (mlx-vlm). Open-weight,
   commercial-use licensed. Notable angle: a single Gemma could potentially
   cover **both** transcription *and* the LLM cleanup/formatting step — i.e.
   replace Whisper-or-Parakeet **and** the SwiftLlama/Qwen post-processor with
   one model. Trade-off: heavier (~2–4B effective) than dedicated Parakeet
   (0.6B), so for pure dictation latency a specialized ASR likely still wins;
   Gemma's value is consolidation + multilingual + the MLX direction. Worth a
   prototype, not an obvious default.

4. **NVIDIA Canary-Qwen / Canary-1B-v2.** Multilingual ASR + speech translation
   (paired with Parakeet v3 in the same Sept-2025 NVIDIA paper). Heavier than
   Parakeet; consider only if translation/AST becomes a goal.

> Excluded — cloud / paid: Google Chirp 3 (Cloud Speech-to-Text API) and
> gateway speech-to-speech offerings (Vercel AI Gateway / OpenAI Realtime /
> xAI Grok voice). Off-axis for PUSH's offline, on-device, privacy-first design.

## Sources
- Parakeet v3: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3 ·
  https://arxiv.org/pdf/2509.14128
- FluidAudio: https://github.com/FluidInference/FluidAudio/releases ·
  https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml
- WhisperKit 1.0.0: https://github.com/argmaxinc/WhisperKit/releases ·
  https://www.argmaxinc.com/blog/whisperkit
- MLX path: https://github.com/senstella/parakeet-mlx ·
  https://github.com/soniqo/speech-swift
- Apple SpeechAnalyzer: https://www.forasoft.com/blog/article/speech-recognition-with-neural-networks-on-ios-1621
- Qwen3-ASR / engine comparison: https://dicta.to/blog/speech-to-text-engine-comparison-mac-2026/ ·
  https://www.gladia.io/blog/best-open-source-speech-to-text-models
- Google Gemma audio (3n/4, MLX, on-device ASR): https://ai.google.dev/gemma/docs/capabilities/audio ·
  https://ai.google.dev/gemma/docs/integrations/mlx · https://deepmind.google/models/gemma/gemma-3n/

## Review log
- **2026-06-29** — Initial sweep. Found Parakeet v3 (multilingual), FluidAudio
  0.15.4, WhisperKit 1.0.0. No code changes made yet — opportunities logged above.
- **2026-06-30** — Applied upgrades to existing models: FluidAudio
  `0.13.6 → 0.15.4`, WhisperKit `0.9.0 → 1.0.0` (Package.swift floors). Needs a
  Mac build + `swift package update` to regenerate Package.resolved and verify
  the WhisperKit 1.0 API — not compile-checked on Linux. Also added a GitHub
  Actions workflow (`monthly-model-check.yml`) that opens a tracking issue
  monthly.
  > **Correction (2026-09-01):** this entry originally also claimed Parakeet
  > **v2 → v3** was applied. **It never landed.** `git log -S"version: .v3"`
  > returns nothing, and `ParakeetEngine.swift` still loads `.v2`. The entry was
  > written in a non-building context ("not compile-checked on Linux") and the
  > change was evidently dropped before commit. Corrected rather than deleted so
  > the failure mode stays visible: a review log written from a context that
  > cannot build is a record of intent, not of fact.
- **2026-06-30** — Broadened beyond existing deps. Added Apple SpeechAnalyzer
  (native on-device, macOS 26), Qwen3-ASR (MLX path, already half-wired),
  Google Gemma 3n/4 open-weight on-device audio (MLX; could unify ASR + LLM
  post-proc), and Canary-Qwen. Excluded cloud/paid options (Chirp 3, Vercel AI
  Gateway / speech-to-speech) as off-axis vs PUSH's offline design.
- **2026-09-01** — **Read the pinned checkout instead of the model cards.** The
  FluidAudio revision PUSH already builds against (`19600a48`, matching
  `Package.resolved`) ships far more than this file recorded. Everything below
  was verified in `.build/checkouts/FluidAudio/Sources/FluidAudio/ModelNames.swift`,
  not from release notes:

  | Repo case | What it is |
  |---|---|
  | `nemotronMultilingual` | Nemotron 3.5 Streaming Multilingual 0.6B — `latin` + `multilingual` vocab builds, 4 chunk tiers |
  | `senseVoiceSmall` | SenseVoiceSmall (FunASR), non-autoregressive, 50+ languages |
  | `paraformerLargeZh` | Paraformer-large, Chinese |
  | `parakeetJa` | Parakeet 0.6B, Japanese |
  | `cohereTranscribeCoreml` | Cohere transcribe 03-2026, q8 |
  | `parakeetEou160/320/1280` | Parakeet EOU 120M, cache-aware streaming w/ end-of-utterance |

  Note the English-only ones are named as such: `parakeet-unified-**en**-0.6b`,
  `nemotron-speech-streaming-**en**-0.6b`. That is why the shipping English
  engines could never have served another language.

- **2026-09-01** — **Multilingual shipped.** `NemotronMultilingualEngine`
  (`af03fd3`, `ec823a9`) + per-engine language selector (`01095fd`, `3389f3c`) +
  an English-only gate on the post-processing chain (`fc8f58a`), so spoken-number
  conversion, `capitalizeI` and the `ContextGate` entity heuristic no longer run
  over non-English transcripts. `compare/` gained audio-file input (`6eca120`) so
  a bake-off can be run from a corpus rather than by reading aloud.

  **Open, not yet measured:** no WER comparison has been run between Nemotron
  Multilingual, TDT v3, SenseVoiceSmall and Apple Speech on the same audio. The
  bake-off harness exists; the bake-off does not. Until then, no claim in this
  file about which multilingual model is *better* is measured — see
  `docs/plans/2026-08-31-multilingual-dictation-plan.md` for the three-tier
  protocol (synthesized smoke → corpus WER → the user's own ear on pt-BR/es/fr,
  which are the only languages available to judge by feel).
