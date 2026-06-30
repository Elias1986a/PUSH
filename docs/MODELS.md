# PUSH — Model Tracking & Upgrade Watch

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

| Component | SDK / package | Pinned | Model in use | Engine |
|-----------|---------------|--------|--------------|--------|
| ASR (Whisper) | WhisperKit | `from: 0.9.0` | Base / Small / Distil-Large V3(+Turbo) / Large V3 Turbo | CoreML/ANE |
| ASR (edge) | moonshine-swift | `from: 0.0.48` | Moonshine Tiny / Base | ONNX |
| ASR (fastest) | FluidAudio | `from: 0.13.6` | **Parakeet TDT 0.6b v2** (English-only) | CoreML/ANE |
| ASR (MLX) | speech-swift (Qwen3-ASR) | **disabled** | — | MLX+CoreML |
| LLM post-proc | SwiftLlama (llama.cpp) | branch `main` | Qwen (GGUF) | llama.cpp (Metal) |

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
- **2026-06-30** — Broadened beyond existing deps. Added Apple SpeechAnalyzer
  (native on-device, macOS 26), Qwen3-ASR (MLX path, already half-wired),
  Google Gemma 3n/4 open-weight on-device audio (MLX; could unify ASR + LLM
  post-proc), and Canary-Qwen. Excluded cloud/paid options (Chirp 3, Vercel AI
  Gateway / speech-to-speech) as off-axis vs PUSH's offline design.
