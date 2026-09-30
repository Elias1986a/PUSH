# Third-party notices

PUSH is built on open-source software and open speech models. We're grateful to
the people who made them. This file lists each one, its licence and what the
licence asks of us. The full licence texts are in `legal/third-party/`, and the
release build copies this whole folder into `PUSH.app/Contents/Resources/Legal`.

The companies named here have not endorsed PUSH. Their names are used only to
say where each component comes from.

## Software shipped inside PUSH.app

These are compiled into the app or bundled with it. Their licences require us
to include the copyright notice and licence text with every copy we distribute.

| Component | Version | Licence | Copyright | Full text |
|---|---|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | 0.17.4 | Apache License 2.0 | FluidInference | `third-party/FluidAudio/LICENSE.txt` |
| ↳ NemoTextProcessing (text-processing-rs), linked by FluidAudio | 0.3.1 | Apache License 2.0 (with MIT/Apache sub-components) | FluidInference and contributors | `third-party/FluidAudio/NemoTextProcessing-LICENSE.md` |
| ↳ fastcluster, compiled into FluidAudio | — | BSD 2-Clause | © 2011 Daniel Müllner; © Google Inc. | `third-party/FluidAudio/fastcluster-LICENSE.md` |
| ↳ [VBx](https://github.com/BUTSpeechFIT/VBx), ported in FluidAudio | — | Apache License 2.0 | VBx authors | `third-party/FluidAudio/vbx-LICENSE.md` |
| ↳ Kokoro text frontends, in FluidAudio | — | Apache 2.0 / MIT / BSD (see file) | Various | `third-party/FluidAudio/JapaneseG2P-LICENSE.md`, `KokoroAneSpanishFrenchG2P-LICENSE.md` |
| [Sparkle](https://sparkle-project.org) | 2.9.3 | MIT, plus BSD-style and public-domain components (bsdiff, sais-lite, ed25519, SUSignatureVerifier) | Andy Matuschak and the Sparkle contributors | `third-party/Sparkle-LICENSE.txt` |
| [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) | 1.1.0 | MIT | Sindre Sorhus | `third-party/LaunchAtLogin-Modern-LICENSE.txt` |
| [voice-glow](https://github.com/Jakubantalik/Libraries.dev), ported as `VoiceGlow.swift` | — | MIT | © 2026 Jakub Antalik | `third-party/voice-glow-LICENSE.txt` |

We didn't change FluidAudio, Sparkle or LaunchAtLogin. They're used as released.
Apache 2.0 §4(b) asks that modified files be marked; since we modified nothing,
there is nothing to mark.

## Speech models (downloaded on first use, not bundled)

PUSH doesn't ship model weights. When you press **Download** in Settings, PUSH
fetches the model you picked straight from its public Hugging Face repository
onto your Mac. PUSH never sends your audio anywhere; the models run on your Mac.

We don't redistribute the weights, but we credit them anyway: it's what their
authors ask for, and CC BY 4.0 requires it when a work is shared.

| In PUSH | Model | Made by | Licence | Notice |
|---|---|---|---|---|
| Parakeet Ultra (default) | [moondream/parakeet-ultra](https://huggingface.co/moondream/parakeet-ultra), a post-training of [nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3); Core ML conversion [FluidInference/parakeet-ultra-coreml](https://huggingface.co/FluidInference/parakeet-ultra-coreml) | Moondream, from NVIDIA's Parakeet TDT 0.6B v3; converted by FluidInference | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | "Parakeet Ultra" by Moondream, based on "Parakeet TDT 0.6B v3" by NVIDIA, licensed under CC BY 4.0; converted to Core ML by FluidInference. |
| Parakeet Unified, Parakeet Streaming | [nvidia/parakeet-unified-en-0.6b](https://huggingface.co/nvidia/parakeet-unified-en-0.6b); Core ML conversion [FluidInference/parakeet-unified-en-0.6b-coreml](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml) | NVIDIA; converted by FluidInference | [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/) | Licensed by NVIDIA Corporation under the NVIDIA Open Model License. |
| Nemotron Multilingual | [NVIDIA Nemotron 3.5 ASR Streaming Multilingual 0.6B](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b); Core ML conversion [FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML) | NVIDIA; converted by FluidInference | [OpenMDW-1.1](https://openmdw.ai/license/1-1/) | NVIDIA Nemotron 3.5 ASR Streaming Multilingual, © NVIDIA Corporation, made available under OpenMDW-1.1. |
| Voice activity detection | [Silero VAD](https://github.com/snakers4/silero-vad); Core ML conversion [FluidInference/silero-vad-coreml](https://huggingface.co/FluidInference/silero-vad-coreml) | Silero Team; converted by FluidInference | MIT | Copyright (c) 2020-present Silero Team. |

> **Before release: confirm each model licence on its Hugging Face card.**
> We compiled the table above from FluidAudio's source and documentation plus
> public listings of the upstream models. Hugging Face was unreachable from the
> environment this file was written in. Before the first paid release, open
> each model card, check the licence field and copy any `NOTICE` text word for
> word. If you find a mismatch, fix it here and in the website's legal page.

All four licences allow commercial use. What each one requires:

- **CC BY 4.0.** Credit the creators, link to the licence, say whether changes
  were made (we made none) and don't imply endorsement.
- **NVIDIA Open Model License.** When redistributing, pass on the agreement and
  include the notice "Licensed by NVIDIA Corporation under the NVIDIA Open
  Model License". Rights end if you sue over the model's IP, or if you bypass
  its guardrails without a substitute. Using NVIDIA's trademarks isn't granted:
  we name NVIDIA only to say where the model comes from, and never use its logo.
- **OpenMDW-1.1.** When redistributing, keep the licence and the notices of
  origin. Rights end on patent or copyright litigation over the model. There
  are no restrictions on outputs, so your transcripts are yours.
- **MIT (Silero VAD).** Keep the copyright notice.
