# iOS 27 — Can We Ship PUSH as a Keyboard?

**Research date:** 2026-06-26
**Question:** Does iOS 27 finally allow us to build a custom keyboard that runs PUSH (push-to-talk voice → text)?

## TL;DR

**No — not as a keyboard.** The single feature PUSH depends on, microphone access,
is still kernel-blocked for keyboard extensions in iOS 27, exactly as it has been
since custom keyboards shipped in iOS 8. No amount of "Full Access" changes this.
A keyboard literally cannot record audio, so a *voice-to-text keyboard* remains
impossible.

**But iOS 27 is a great release for shipping PUSH as a standalone app.** Apple now
exposes the two engines PUSH is built on — on-device speech-to-text
(`SpeechAnalyzer` / `SpeechTranscriber`) and an on-device LLM (the Foundation
Models framework) — directly to third-party developers. These can replace
WhisperKit + llama.cpp natively, with no model downloads and no memory ceiling.

## The hard blocker: keyboards can't use the microphone

This is the wall, and it has not moved:

- iOS **blocks microphone access from keyboard extensions at the kernel level**.
  This is a deliberate privacy decision: the system has no reliable way to signal
  to the user that a *keyboard* is listening, so Apple forbids it entirely.
- The restriction holds **even with "Full Access" enabled**. Full Access unlocks
  network and shared-container access — it does **not** unlock the microphone.
- iOS 27 did not change this. The only in-keyboard dictation that works is
  Apple's *own* system dictation (the mic button on the stock keyboard), which is
  privileged and not available to third-party keyboards.

Because PUSH's entire premise is "hold a key, speak, get text," and a keyboard
extension can't capture the speech, **the keyboard form factor is a dead end for
this app.** Every third-party "voice keyboard" on the App Store works around this
the same way (see "Workarounds" below) — none of them records audio inside the
keyboard.

## The secondary blocker: memory

Even setting the microphone aside, keyboard extensions run under a tight memory
budget (historically ~60 MB, device-dependent). PUSH's models are far larger:

| Model            | Size      |
|------------------|-----------|
| Moonshine Tiny   | ~45 MB    |
| Whisper Base     | ~150 MB   |
| Parakeet TDT v2  | ~400 MB   |
| Whisper Large V3 | ~632 MB   |
| Qwen3-ASR        | ~680 MB   |

None of the accurate models fit in a keyboard's memory budget. iOS 27 did **not**
raise the keyboard-extension memory limit. (This is moot given the mic block, but
it's a second independent reason the keyboard can't host PUSH's current stack.)

## What iOS 27 *does* give us (for a standalone app)

iOS 27 ships the exact capabilities PUSH reimplements on macOS, now as first-party
on-device frameworks available to any developer:

- **`SpeechAnalyzer` / `SpeechTranscriber`** — on-device speech-to-text, runs
  entirely offline, no cloud. This is the same engine behind the system's improved
  dictation. It replaces WhisperKit / Parakeet / Moonshine with a system model
  (zero download, no memory ceiling, ANE-accelerated).
- **Foundation Models framework** — an on-device LLM with structured outputs,
  tool-calling, multi-turn sessions, and (new in iOS 27) on-device fine-tuning.
  This replaces the SwiftLlama / llama.cpp post-processing PUSH uses for
  punctuation/cleanup. The transcribe-then-clean-up pipeline runs fully on-device.
- **Advanced Dictation (AFM Core Advanced)** — on iPhone 17 Pro / 17 Pro Max /
  iPhone Air, a higher-quality on-device dictation model with automatic
  punctuation and capitalization. (System feature, not a developer API, but shows
  where the platform STT quality now sits.)

All of these are usable from a **normal app** (which has microphone entitlement).
None of them are usable from a keyboard extension (no mic).

## Viable iOS architectures for PUSH

Since the keyboard can't record, the realistic options are:

### 1. Standalone app (recommended)
A normal PUSH iOS app: tap-to-talk in the app, `SpeechAnalyzer` transcribes,
Foundation Models cleans up, result is shown / copied / shared. This is the
cleanest path and uses iOS 27's new frameworks natively. It loses the
"works in any text field" magic of the macOS version, but it's fully App
Store-compliant and needs no model downloads.

### 2. App + companion keyboard (clipboard handoff)
Ship a standalone app *plus* a thin keyboard extension. The **app** records and
transcribes (it has mic access); the **keyboard** only reads the latest result
from a shared App Group container / clipboard and inserts it into the current
field. The user still has to leave the text field to record in the app, then
return — the keyboard is just a paste shortcut. This is how Spokenly, Speechify,
and similar apps approximate "dictation everywhere." It's the closest we can get
to the macOS UX, but the recording step cannot live in the keyboard.

### 3. Rely on system dictation
Do nothing custom — iOS 27's improved system dictation already provides
on-device, punctuated voice typing in every app via the stock keyboard's mic
button. If the goal is "good voice typing on iPhone," the OS now largely covers
it. PUSH's differentiator would have to be model choice, custom vocabulary, or
LLM post-processing — all of which require option 1 or 2.

## Bottom line

- **Keyboard that runs PUSH: still not possible in iOS 27.** Mic access is
  kernel-blocked for keyboards, and the memory budget is too small for the models.
  This did not change.
- **Standalone PUSH app: very viable, and easier than on macOS.** iOS 27's
  `SpeechAnalyzer` + Foundation Models give us native, offline STT + LLM cleanup
  with no model downloads. If we want an iOS presence, build the app (option 1),
  optionally with a clipboard-handoff keyboard (option 2) for quick insertion.

## Sources

- [On the Limitations of iOS Custom Keyboards — MacStories](https://www.macstories.net/notes/on-the-limitations-of-ios-custom-keyboards/)
- [Limitations of custom iOS keyboards — Medium / inFullMobile](https://medium.com/@inFullMobile/limitations-of-custom-ios-keyboards-3be88dfb694)
- [Are There Any Limitations When Creating Custom Keyboards on iOS? — Fleksy](https://www.fleksy.com/blog/limitations-of-custom-keyboards-on-ios/)
- [App Extension Programming Guide: Custom Keyboard — Apple](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- [Creating a custom keyboard — Apple Developer](https://developer.apple.com/documentation/UIKit/creating-a-custom-keyboard)
- [SpeechAnalyzer — Apple Developer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Bring advanced speech-to-text to your app with SpeechAnalyzer — WWDC25](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Apple Foundation Models in iOS 27: Builder Guide — ChatForest](https://chatforest.com/builders-log/apple-foundation-models-ios-27-on-device-llm-api-builder-guide/)
- [iOS 27 Has Two Dictation Systems — Tech Between The Lines](https://www.techbetweenthelines.com/ios-27-has-two-dictation-systems-here-is-which-one-is-on-your-iphone/)
- [The new dictation feature in iOS 27 beta 1 — 9to5Mac](https://9to5mac.com/2026/06/12/ai-advanced-dictation-preview-ios-27-beta/)
- [iOS 27: Everything We Know — MacRumors](https://www.macrumors.com/roundup/ios-27/)
