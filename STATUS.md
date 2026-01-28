# Autocomplete Feature - Status & Next Steps

**Branch:** `type`  
**Date:** January 27, 2026  
**Status:** Skeleton Complete ✅

---

## ✅ What's Been Done

### Files Created (5 files, 991 lines)

1. **`PUSH/ML/TextPredictionEngine.swift`** (128 lines)
   - Skeleton for LLM inference using SwiftLlama
   - `loadModel()` - loads GGUF model from disk
   - `predictNext()` - generates text predictions (stub)
   - Error handling structure
   - Ready for SwiftLlama API integration

2. **`PUSH/Core/KeystrokeMonitor.swift`** (229 lines)
   - Global keystroke monitoring via CGEventTap
   - Context buffer (last 500 characters typed)
   - Prediction trigger after 0.3s pause
   - Callbacks for context updates and predictions
   - Special key handling (delete, return, escape, tab)

3. **`PUSH/Views/PredictionOverlayView.swift`** (207 lines)
   - Floating overlay window for showing predictions
   - Follows cursor position using Accessibility API
   - Grayed-out text style (like Cotypist)
   - Ignores mouse events (doesn't block clicks)
   - SwiftUI + NSWindow integration

4. **`PUSH/Core/AutocompleteManager.swift`** (224 lines)
   - Orchestrates all components
   - Enable/disable autocomplete
   - Tab key accepts prediction
   - Escape key dismisses prediction
   - Manages lifecycle and callbacks
   - Model enum (TinyLlama, Qwen 2.5, Phi-3.5)

5. **`AUTOCOMPLETE.md`** (203 lines)
   - Full implementation roadmap
   - 5 phases with priorities
   - Model recommendations
   - Testing plan
   - Technical challenges and solutions

### Architecture Set Up

```
User Types
    ↓
KeystrokeMonitor (monitors globally)
    ↓
AutocompleteManager (orchestrates)
    ↓
TextPredictionEngine (SwiftLlama inference) → Prediction
    ↓
PredictionOverlayView (shows at cursor)
    ↓
User presses Tab → TextInjector (inserts text)
```

### Dependencies Already in Place

- ✅ SwiftLlama in `Package.swift` (not yet used)
- ✅ TextInjector (from existing PUSH)
- ✅ ModelManager (can be extended for text models)
- ✅ Accessibility permissions (already required)

---

## 🎯 What To Do First

### Priority 1: Verify SwiftLlama Works (15 minutes)

**Why:** Need to confirm the dependency compiles before implementing.

**Steps:**
1. Build the project:
   ```bash
   cd ~/clawd/PUSH
   swift build
   ```

2. Check for errors:
   - If builds successfully → SwiftLlama is ready ✅
   - If errors → need to fix dependencies first ⚠️

**Expected Outcome:**
```
Build complete! (XX.XXs)
```

**If it fails:** Read error messages and research SwiftLlama requirements.

---

### Priority 2: Download TinyLlama Model (5 minutes)

**Why:** Need a small, fast model for testing inference.

**Steps:**
1. Create directory:
   ```bash
   mkdir -p ~/Library/Application\ Support/PUSH/models/text
   ```

2. Download TinyLlama (600 MB):
   ```bash
   cd ~/Library/Application\ Support/PUSH/models/text
   curl -L -o tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
     https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
   ```

3. Verify download:
   ```bash
   ls -lh ~/Library/Application\ Support/PUSH/models/text/
   # Should show ~600 MB file
   ```

**Expected Outcome:**
Model file ready at known path.

---

### Priority 3: Implement `loadModel()` (1-2 hours)

**Why:** Can't test predictions without loading the model first.

**File:** `PUSH/ML/TextPredictionEngine.swift`

**What to do:**
1. Study SwiftLlama documentation:
   - https://github.com/ShenghaiWang/SwiftLlama
   - Look for `Llama.init()` or similar

2. Replace the TODO in `loadModel()`:
   ```swift
   func loadModel(path: String) async throws {
       print("TextPredictionEngine: Loading model from \(path)")
       
       guard FileManager.default.fileExists(atPath: path) else {
           throw PredictionError.modelNotFound
       }
       
       // TODO: Replace this with actual SwiftLlama code
       // Example (pseudo-code - adjust based on actual API):
       llama = try await Llama(modelPath: path)
       
       modelPath = path
       isModelLoaded = true
       
       print("TextPredictionEngine: Model loaded successfully")
   }
   ```

3. Test loading:
   ```swift
   // In a test or temporary code
   let engine = TextPredictionEngine.shared
   try await engine.loadModel(
       path: "~/Library/Application Support/PUSH/models/text/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
   )
   print("Model loaded: \(engine.isModelLoaded)")
   ```

**Expected Outcome:**
Model loads without errors, `isModelLoaded` becomes `true`.

**If it fails:**
- Read SwiftLlama docs more carefully
- Check model file isn't corrupted
- Look at SwiftLlama example code

---

### Priority 4: Implement `predictNext()` (2-3 hours)

**Why:** Core feature - generates the actual predictions.

**File:** `PUSH/ML/TextPredictionEngine.swift`

**What to do:**
1. Study SwiftLlama's text generation API:
   - How to pass a prompt
   - How to set max tokens (we want ~10-20)
   - How to get generated text back

2. Replace the TODO in `predictNext()`:
   ```swift
   func predictNext(context: String) async -> String {
       guard isModelLoaded else {
           print("TextPredictionEngine: No model loaded")
           return ""
       }
       
       guard !context.isEmpty else {
           return ""
       }
       
       isProcessing = true
       defer { isProcessing = false }
       
       print("TextPredictionEngine: Predicting from context: '\(context.suffix(50))...'")
       
       do {
           // TODO: Replace with actual SwiftLlama code
           // Example (pseudo-code):
           let prompt = formatPrompt(context)
           let tokens = try await llama?.generate(
               prompt: prompt,
               maxTokens: maxTokens,
               temperature: temperature,
               topP: topP
           )
           
           let prediction = extractPrediction(from: tokens ?? [])
           currentPrediction = prediction
           return prediction
           
       } catch {
           print("TextPredictionEngine: Prediction failed: \(error)")
           return ""
       }
   }
   ```

3. Implement helper methods:
   ```swift
   private func formatPrompt(_ context: String) -> String {
       // For TinyLlama, simple format works
       // Just pass the context and let it complete
       return context
   }
   
   private func extractPrediction(from tokens: [String]) -> String {
       // Join tokens, trim, clean up
       let joined = tokens.joined()
       
       // Take only first sentence or ~20-30 chars
       // We want short predictions for autocomplete
       let trimmed = joined.prefix(50)
       
       return String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
   }
   ```

4. Test with simple input:
   ```swift
   let engine = TextPredictionEngine.shared
   try await engine.loadModel(path: "...")
   
   let prediction = await engine.predictNext(context: "The quick brown fox")
   print("Prediction: \(prediction)")
   // Should output something like: "jumps over the lazy dog" (or similar)
   ```

**Expected Outcome:**
Given typing context, returns reasonable next-word prediction in <200ms.

**If it's too slow:**
- Try smaller model (TinyLlama should be fast)
- Reduce `maxTokens` (fewer tokens = faster)
- Check if Metal acceleration is enabled

**If predictions are nonsense:**
- Prompt formatting might be wrong
- Try different temperature/topP values
- Model might need specific prompt template

---

### Priority 5: Wire to AutocompleteManager (30 minutes)

**Why:** Connect the working prediction to the UI.

**What to do:**
1. In `AutocompleteManager.generatePrediction()`, the call to `predictionEngine.predictNext()` is already there
2. Just need to test the full flow:
   - Enable autocomplete
   - Type something
   - Wait 0.3s (prediction trigger)
   - See overlay appear with suggestion
   - Press Tab to accept

3. Test flow:
   ```swift
   // In app startup or test
   let manager = AutocompleteManager.shared
   let engine = TextPredictionEngine.shared
   
   // Load model
   try await engine.loadModel(path: "...")
   
   // Enable autocomplete
   await manager.enable()
   
   // Now type in any app and watch for predictions
   ```

**Expected Outcome:**
Full pipeline works: type → predict → show → accept.

---

## 📊 Success Metrics

After completing priorities 1-5, you should have:

- ✅ SwiftLlama compiling and working
- ✅ TinyLlama model loaded successfully
- ✅ Predictions generating in <200ms
- ✅ Overlay appearing at cursor with suggestion
- ✅ Tab key accepting prediction
- ✅ Full autocomplete cycle working in at least one app (Notes, TextEdit)

---

## 🚧 Known Challenges

### 1. SwiftLlama API is unknown
**Risk:** High  
**Impact:** Might need to adjust implementation based on actual API  
**Mitigation:** Study docs first, look for examples

### 2. Inference speed
**Risk:** Medium  
**Impact:** If >200ms, feels laggy  
**Mitigation:** Use TinyLlama (smallest/fastest), reduce maxTokens

### 3. Cursor position tracking
**Risk:** Medium  
**Impact:** Overlay might not appear in right place  
**Mitigation:** Accessibility API is complex, might need trial/error

### 4. App compatibility
**Risk:** Low  
**Impact:** Might not work in some apps (password fields, etc.)  
**Mitigation:** Test in multiple apps, add exclusion list if needed

---

## 📝 Notes

- All code is stubbed out - just need to fill in SwiftLlama calls
- Architecture is solid - monitoring → prediction → display → accept
- TinyLlama is the right starting model (small, fast, good enough)
- Once TinyLlama works, adding Qwen/Phi-3 is just swapping models

---

## 🎯 Next Session Goals

**Immediate (this session if time):**
1. Run `swift build` and verify it compiles
2. Download TinyLlama model
3. Research SwiftLlama API documentation

**Next session:**
1. Implement `loadModel()` with SwiftLlama
2. Test model loading
3. Implement `predictNext()` with basic inference
4. Test end-to-end prediction

**Goal:** Working autocomplete in 1-2 more coding sessions (4-8 hours)

---

**Questions? Issues?**
Check `AUTOCOMPLETE.md` for full details, or ask! ⚡
