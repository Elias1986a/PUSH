# PUSHTYPE 10.0 — release-readiness review

Date: 2026-10-14. Scope: the app (main at e86f15f), the draft launch PR #55 (branch `launch`, not merged), the website, the Netlify functions, and the legal documents. Read-only: nothing was changed or committed.

Method: six focused reviewers (licensing, security/privacy, core runtime, website, legal, in-app UI) read the code in parallel; the claims that drive the verdict were re-verified from source or against the live site by the lead. `swift build` passes, `swift test` passes (606 tests, 19 skipped, 0 failures; the self-correction eval prints 44/50, which is an eval score, not a test failure), and `node --test website/netlify/test/*.test.mts` passes (20/20). Paths are repo-relative.

## Verdict

The launch PR itself is correct and small. The product is close, but **do not tag 10.0 yet**. Four things will hit a real buyer on day one, and all four are cheap:

1. **TYPE is dead after a fresh install** until the user relaunches or toggles it — the key tap never retries after Accessibility is granted (Blocker 1).
2. **The legal pages show "DRAFT. Not legal advice." to customers today**, on the live site and inside the app bundle (Blocker 2).
3. **The licence gate can be switched off from Terminal in the release build** (High 1).
4. **The update feed and download URLs still point at the GitHub repo you plan to make private** — every 10.0 install would stop updating that day (High 4).

Beyond those: the privacy story has one real gap (iCloud sync of dictionary/name/About note is on by default while the headline says "never leaves your Mac"), the site runs Google Analytics next to "no analytics", the security headers in `netlify.toml` are not live, and the Settings window is sized twice. Everything else is polish, and there is a lot of it worth doing — the spacing tables alone take ~1,500–2,000 px off the home page and a row's insets off ~13 settings captions without losing a word.

## Ship gate (in order)

| # | Item | Where | Effort |
|---|---|---|---|
| 1 | Retry the TYPE event tap until Accessibility is granted | `PUSH/Typing/TypingKeyTap.swift:68-79` | small |
| 2 | Strip the DRAFT / "Before release" blockquotes, rebuild legal pages | `legal/*.md`, `website/build_legal.py` | small |
| 3 | `#if DEBUG` the `licence.offered` read; `return true` in release | `PUSH/Core/LicenseModel.swift:26` (launch) | one line |
| 4 | Move `SUFeedURL` + enclosure URLs to pushtype.app in the plist and build script; host the ZIP + appcast there | `PUSH/Info.plist:62`, `build_distribution.sh:31` | medium |
| 5 | Confirm `pushtype://activate` before replacing an existing key | `PUSH/App/AppDelegate.swift:134-143` | small |
| 6 | No model on disk → `modelUnavailable = true`; engines stop self-downloading from a hotkey press | `PUSH/Core/ModelLoader.swift:90-93`, `PUSHCore/ML/ParakeetEngine.swift:102-105` | small |
| 7 | Guard the audio format before `installTap` (no-mic Macs crash) | `PUSH/Core/AudioRecorder.swift:255,324`, `WakeWordListener.swift:55,83` | small |
| 8 | Move the `[[headers]]` block into `website/netlify.toml`; add X-Frame-Options, Permissions-Policy | `netlify.toml`, `website/netlify.toml` | small |
| 9 | Decide GA: remove it (Netlify Analytics) or reword `index.html:217` + consent | `website/*.html`, `build_legal.py:96-104` | small |
| 10 | Fix the Settings window size (drop `.resizable` + the 820×620) | `PUSH/Views/Settings/SettingsWindowController.swift:42-43` | one line |
| 11 | Legal: name the party, licence the standalone $12, OFL text, dates | `legal/*.md` | small, then attorney |
| 12 | Success URL on BOTH Polar checkout links = `https://pushtype.app/thanks/?checkout_id={CHECKOUT_ID}` | Polar dashboard (not verifiable from the repo) | check |

Then: NOTES' own checklist (10.0 in Info.plist, archive release notes, delete appcast.xml, test purchase with a 100 %-off code, one real purchase + refund).

---

## The launch PR (#55, `launch` → main)

`git diff main...launch`: 8 files, +82/−26.

- `PolarConfig.production` ids match the website's two `buy.polar.sh` links exactly; `current` is production under `#if !DEBUG`, and `build_distribution.sh:45` builds with `-c release`, so the shipped binary uses the live store and `swift run` keeps the sandbox. Correct.
- `LicenseModel.isOffered` defaults to true. Correct intent, but see High 1 — the override is not DEBUG-only as the comment claims.
- Website: noindex off home + benchmark, Buy → live link, Extra Mac note links the $12 checkout and says "same email". robots.txt (disallows `/thanks/`, `/api/`) and sitemap (3 URLs: home, benchmark, support) are right; legal pages keep noindex on purpose.
- `PolarProductionConfigTests`: good, except `testTheReleaseBuildUsesTheLiveStore` is wrapped in `#if !DEBUG` so `swift test` never runs it — assert on `PolarConfig.production` instead.
- NOTES: the merge publishes the site changes instantly, so merge it with the 10.0 release, not before. Still right.
- NOTES says 18 node tests; there are 20.

---

## Blockers

### B1. TYPE never starts on a fresh install until relaunch
`PUSH/Typing/TypingKeyTap.swift:68-79`: when `CGEvent.tapCreate` returns nil the thread exits and `thread = nil`; nothing retries. `AppDelegate.swift:77` calls `TypingCoordinator.shared.setActive(typeEnabled)` before the wizard has granted Accessibility, `typeEnabled` defaults on (`FeatureSwitches.swift:15-17`), and `setActive` guards `on != active` (`TypingCoordinator.swift:133-134`) — its only other caller is the `typeEnabled` setter (`AppState.swift:187`). The wizard even says "no need to restart PUSH" (`OnboardingView.swift:449`). Verified: no relaunch anywhere in onboarding. Talk doesn't have this bug because `HotkeyManager.requestAccessibilityAndRetry` polls every 2 s (`HotkeyManager.swift:294`).
**Fix:** same 2 s retry in `TypingKeyTap` while `!AXIsProcessTrusted()`, or have HotkeyManager's success path (`:176-188`) call `TypingKeyTap.shared.start()`.

### B2. DRAFT banners are public
`legal/EULA.md:3-4`, `TERMS_OF_SALE.md:3-4`, `PRIVACY.md:3-5` render "DRAFT. Not legal advice. … Review it before launch" and `THIRD_PARTY_NOTICES.md:48-53` ends with "Before release: confirm each model license… Hugging Face was unreachable". Verified live on pushtype.app/legal/eula.html and /legal/notices.html today. `build_distribution.sh:67` also copies `legal/` into `PUSH.app/Contents/Resources/Legal`, so they ship inside the app. noindex keeps Google out, not buyers.
**Fix:** delete the blockquotes (the model licences were re-verified this session; see the dependency table), run `build_legal.py`, keep noindex until the attorney signs off.

---

## High

### H1. `licence.offered` disables licensing in the release build
`PUSH/Core/LicenseModel.swift:26` (launch): `UserDefaults.standard.object(forKey: "licence.offered") as? Bool ?? true`, no `#if DEBUG`. `defaults write com.push.voicetotext licence.offered -bool false` makes `allowsUse` true forever (`HotkeyManager.swift:378`, `TypingCoordinator.swift:318`, `MenuBarView.swift:42`) and hides the License pane. The doc comment says a debug build can switch it off; the code lets any build. **Fix:** wrap the read in `#if DEBUG`, `return true` otherwise. Also update the stale comment at `LicenseModel.swift:13-15` ("Nothing here stops dictation yet") — it now gates Talk, TYPE and the wake word.

### H2. `pushtype://activate?key=` rebinds the licence from any web page
`AppDelegate.swift:134-143` takes any 8–80 char key-shaped token (`LicenseKeyText.swift:27-38`); if it differs from the stored key it activates it, overwrites the Keychain record and pushes it to iCloud Keychain (`LicenseModel.swift:115-123`), so every Mac on the Apple Account adopts it. A page doing `location='pushtype://activate?key=…'` (browsers prompt once, then "always allow") can swap a paying user's key for a revoked one across all their Macs, or burn seats on a key the attacker controls; the old seat is orphaned on Polar. **Fix:** when `stored != nil`, show an alert with the masked key (Cancel default) or open the License pane prefilled; never auto-replace from a URL.

### H3. A hotkey press with no model on disk starts an unasked 600 MB download and parks the app
`ModelLoader.activateAtLaunch` (`ModelLoader.swift:90-93`) returns with `modelUnavailable == false` when nothing is on disk, so the pill says "Loading model..." forever (`FloatingPillView.swift:263-264`) and `HotkeyManager.handleKeyDown` (`:387`) lets the press through. `ParakeetEngine.transcribe` (`:102-105`) then calls `loadModel()` → `AsrModels.downloadAndLoad` (`:61`); same in `ParakeetStreamingEngine.swift:156-158`. That is exactly the launch-never-downloads rule in CLAUDE.md, broken from a key press, with no watchdog, no progress, and no timeout on a blocked network; `isProcessing` stays true and silences TYPE and the wake word; Esc resets flags but not the download. Reachable on every fresh Mac the moment Accessibility is granted before the model step finishes, and whenever the user deletes a model. **Fix:** `activateAtLaunch` sets `modelUnavailable = true` with a "No model downloaded" status; engines throw `.notInitialized` instead of self-loading; the pipeline awaits `ModelLoader`'s in-flight activation when `!isModelReady` (keeps the "record ahead of the load" case).

### H4. Update feed and downloads die when the repo goes private
`PUSH/Info.plist:62` `SUFeedURL` = `raw.githubusercontent.com/Elias1986a/PUSH/main/appcast.xml`; `build_distribution.sh:31` hard-codes enclosure URLs to `github.com/…/releases/download/`. Changing only the plist leaves the 10.0 appcast pointing at GitHub enclosures, which 404 the day the repo is private — for 10.0 users, not only 9.x. 9.x Macs read the feed URL baked into their own binary, so they keep polling GitHub regardless. The plist also still carries the owner's GitHub handle (the one place the "name off everything" pass hasn't reached), and `PRIVACY.md:48` names the old host. **Fix:** parametrise a `FEED_BASE` in the script (enclosure URL + a check that `SUFeedURL` starts with it), host the ZIP and appcast on pushtype.app, update the privacy row, and accept that 9.x Macs (yours only — no users yet) need a manual install.

### H5. Crash on a Mac with no input device
`AudioRecorder.swift:255` reads `inputNode.outputFormat(forBus: 0)` and hands it to `installTap` (`:324`); with no input device that is 0 Hz / 0 channels and AVAudioEngine raises an ObjC `NSInternalInconsistencyException` nothing catches. `WakeWordListener.swift:55, 83` has the same path. Mac mini / Studio buyers without a mic are a real slice of a paid audience. **Fix:** `guard sampleRate > 0, channelCount > 0 else { status "No microphone"; return }` in both.

### H6. Security headers are not live
Root `netlify.toml:10-14` declares `X-Content-Type-Options` and `Referrer-Policy`, but the base directory is `website`, so Netlify reads `website/netlify.toml` (`[build]` only). Verified: `curl -sI https://pushtype.app` returns only HSTS. **Fix:** move `[[headers]]` into `website/netlify.toml`, delete the root copy, add `X-Frame-Options = "DENY"`, `Permissions-Policy = "camera=(), microphone=(), geolocation=()"`, and a CSP once the three inline scripts (`index.html:454`, `support/index.html:84`, `thanks/index.html:58`) move to `assets/*.js` — the thanks page holds the full licence key in the DOM, so `frame-ancestors 'none'` matters. Suggested CSP after removing GA: `default-src 'self'; img-src 'self' data:; media-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`.

### H7. Google Analytics vs. "no analytics"
gtag `G-VFSBVHWZLN` loads on home, benchmark, support, support/sent and every legal page (`build_legal.py:96-104`), not on /thanks. The privacy policy discloses it (`PRIVACY.md:71`), so it is not a false statement, but `index.html:217` says "No sign-up, no login, no analytics" on a page that sets `_ga` cookies, `PRIVACY.md:13` says "PUSHTYPE has no analytics" two sections earlier, analytics cookies without consent is an ePrivacy problem for the EU buyers the Terms contemplate (`terms.html:51`), and it is the only third-party request on the site (and forces `googletagmanager.com` into any CSP). **Recommendation:** drop gtag for Netlify Analytics (server-side, no cookies, no script) and delete the GA paragraph. If it stays: consent banner, `index.html:217` → "No sign-up, no login, and nothing in the app phones home.", `PRIVACY.md:13` → "The app has no analytics, no ads, and no account (the website uses Google Analytics; see below)."

### H8. Settings window sized twice, resizable around a fixed root
`SettingsView.swift:83` fixes the content at 720×640; `SettingsWindowController.swift:42-43` then sets 820×620, adds `.resizable`, and autosaves the frame. Verified. Result: 100 pt dead space on the right, 20 pt clipped at the bottom, and any user resize shows blank area. **Fix:** drop `.resizable` and the `setContentSize` (or make it 720×640); keep the autosave for position.

### H9. Legal: four things before the attorney sees it
- **Contracting party is not a legal person.** `EULA.md:8`, `TERMS_OF_SALE.md:6`, `PRIVACY.md:7`: "PUSHTYPE, a business in California". A DBA is a trade name; the contract is with you personally ("[Name] d/b/a PUSHTYPE") unless the LLC exists first. NOTES already lists DBA/LLC; make the docs change with it.
- **The standalone $12 single has no licence grant.** `TERMS_OF_SALE.md:17` says Extra Mac is "One more Mac on your existing license"; `EULA.md:16-19` grants seats only "when you buy PUSHTYPE". NOTES and `thanks/index.html:91` say a $12 alone yields a 1-Mac key. Suggested Terms row: "Extra Mac — $12 each, once — One Mac. Adds one to a license you already have, or works on its own for one Mac." EULA §1: "…(three for a PUSHTYPE license, one for each Extra Mac)."
- **OFL text missing.** `THIRD_PARTY_NOTICES.md:83-92` credits Archivo, Instrument Sans, JetBrains Mono, Shrikhand (served as woff2) but `legal/third-party/` has no OFL-1.1 text or per-font copyright / Reserved Font Name lines. Add `OFL-1.1.txt` + four copyright lines.
- **No assent step.** The app never shows or links the EULA (`GeneralSettingsView.swift:54` links Privacy + Acknowledgements only; the activation page `OnboardingView.swift:719-728` has no "by activating you agree"); the Buy button (`index.html:401-402`) has no "By buying you agree to the Terms of Sale and EULA"; Polar's checkout shows Polar's terms. One sentence under `#buy-note` and in the License pane footnote (`LicenseSettingsView.swift:64`), both linking the EULA.

---

## Medium

### Licensing
- **A forged Keychain record is never re-checked.** `LicenseKeychain` (`LicenseModel.swift:201-237`) is a plain login-keychain item; `security add-generic-password -s com.push.voicetotext.licence -a licence -w '<json>'` with `lastValidated` in 2100 means `revalidateIfDue` (`:156-158`) never fires. Clamp `lastValidated = min(lastValidated, now)` on load and treat a never-validated `activationID` as due now.
- **Offline grace is infinite and revalidation runs only at launch.** `.unreachable` is swallowed with no cap (`:169-171`); `revalidateIfDue` is called once from `applicationDidFinishLaunching` (`AppDelegate.swift:410`). A menu-bar app runs for weeks, so a refund takes effect at the next relaunch ≥24 h later, and `/etc/hosts` keeps a refunded key forever. If unlimited offline is the deliberate choice, write it in NOTES; otherwise a timer / `didWakeNotification` call and a soft cap (~30 days).
- **`last_validated_at` is the wrong "in use" signal.** `website/netlify/lib/seats.mts:157` keeps a later key only if `last_validated_at` is set, but the app's `activate()` (`LicenseModel.swift:115`) calls `/activate`, which doesn't set it; the first `/validate` is 24 h later. A second-order key activated inside that window is switched off by any later `reconcileSeats` run (webhook retry, `order.updated`, next purchase), and that Mac then fails its daily check with "no longer active". Fix: call `validate` right after a successful activation (one line; also refreshes `activationLimit`, below), or have seats.mts fetch `/v1/license-keys/{id}` and skip keys with activations.
- **Refunding an Extra Mac does not free the Mac.** `seats.mts:143` lowers `limit_activations` to 3 while 4 activations stand; Polar doesn't evict. After lowering below the count, deactivate the newest activation through the customer session the function already holds. `countsAsSeat` also treats `partially_refunded` as fully paid (`:93`).
- "Macs: Up to N with this key" goes stale after buying an Extra Mac — `LicenseSettingsView.swift:21-23` shows the limit captured at activation; `PolarLicenseClient.validate` (`PolarLicense.swift:106-116`) discards the body that carries `limit_activations`.
- Disabled-key message is a dead end (`LicenseModel.swift:193`): for the known "later order's emailed key is disabled" edge, point at the main key (thank-you page Activate, the other Mac, Polar's portal).
- In-app "Add this Mac for $12" (`LicenseSettingsView.swift:127`) doesn't say "with the same email"; the website line does.
- Thanks page `no_licence` branch is dead (`thanks/index.html:78-82,112`): `purchase.mts` never returns it.
- Teleprompter is ungated (`TeleprompterSession.swift:290-305` loads Parakeet Streaming and records with no `allowsUse` check). Decide.
- `/api/purchase` uses `co.modified_at` as "paid at" (`purchase.mts:54`); any later edit re-opens the 1-hour window. Prefer the order's `created_at`.

### Security / privacy
- **iCloud sync defaults ON and sends the dictionary, your name and the About-you note to iCloud KVS in plaintext.** `AppState.swift:399` (`iCloudSyncEnabled = true`; `:689` only overrides a saved value); `CloudSync.liveSettingKeys` pushes `typing.name`/`typing.about`, `pushDictionary()` pushes the whole dictionary as JSON (`CloudSync.swift:36-39, 203-209`). KVS is not end-to-end encrypted. The homepage says "What you say and type never leaves your Mac" (`index.html:70, 414`); the privacy page says "If Sync is on" as if it were a choice. Either default off and ask in onboarding (the "Copy from my other Mac" step exists), or say "…never leaves your Mac or your own iCloud" and list dictionary/name/About in the FAQ.
- **Speech models come from Hugging Face `main` with no integrity check.** FluidAudio 0.17.4 builds `resolve/main` URLs (`ModelRegistry.swift:124-126`) and `AssetDownloader` has no size/hash check, while the TYPE path (`TypingModel.swift:44-67`) pins commits and SHA-256. Set `ModelRegistry.revisionOverrides` to commit hashes for the Parakeet/Nemotron repos and verify sizes after `downloadAndLoad` (`ParakeetEngine.swift:61`).
- **Shell string built from the bundle path.** `HotkeyManager.swift:267-270`: `/bin/sh -c "sleep 1; open \"\(path)\""`. A path with `"` or `$(…)` executes. Use `Process` with `/usr/bin/open` + arguments, or `NSWorkspace.openApplication(at:)`.
- Stale "never synced" statements for typing history: `TypingHistoryStore.swift:9-10`, `TypingHistory.swift:6`, CLAUDE.md — `LearnedWritingSync` ships.

### Core runtime
- **Modal alert on every launch when the microphone is denied.** `AppDelegate.swift:167-190`: `requestAccess` returns false instantly once denied, so `NSAlert.runModal()` runs on every launch on the main queue — a nested run loop that freezes every `Task { @MainActor }` (the deadlock `UpdaterManager.swift:52-59` documents) while it is up. Show once (defaults flag), non-modally, plus a pill status.
- **Wake word on = ~4 s main-thread stall at launch.** `HotkeyManager.swift:72-74` calls `WakeWordListener.startListening()` synchronously, which does `AVAudioEngine()` + `inputNode.outputFormat` on main (`WakeWordListener.swift:50-55`) — the device init AudioRecorder measured at 4.3 s and moved off main (`AudioRecorder.swift:83-95`). Off by default, but anyone who turns it on pays it inside `applicationDidFinishLaunching`.
- **Quit can still hit the llama.cpp Metal abort.** `AppDelegate.swift:155-162` waits ≤2 s for `LlamaEngine.unload()`; a cold 4,000-token prompt on an M1 can exceed that, so a quit mid-generation times out and the static destructor aborts (the 9.1.2 crash returns). Call `TypingCoordinator.shared.setActive(false)` first (cancels generation, `LlamaEngine.swift:169`), then wait.
- **Mic denied after launch = silent failure.** Zeros reach Silero, every press ends in "No speech detected" (`HotkeyManager.swift:470-472`). Check `AVCaptureDevice.authorizationStatus` in `handleKeyDown` → "Microphone access off".

### Website
- No 404 page (`website/404.html` missing; live `/nope` serves Netlify's generic page).
- No cache headers: everything is `max-age=0, must-revalidate`, including 283 KB of fonts and 6.9 MB of video; the `?v=` busters show the intent. `/assets/fonts/*`, `/assets/video/*`, `/assets/*.png` → `public, max-age=31536000, immutable`.
- Three autoplaying videos ≈ 7 MB per visit (`index.html:100,123,300`; autoplay overrides `preload="metadata"`). `preload="none"` + poster, play from an `IntersectionObserver`, skip autoplay under `prefers-reduced-motion`. `teleprompter.mp4` is 3.1 MB for 20 s; re-encode 720p CRF 28.
- 463 KB favicon: `assets/icon.png` (512×512) is `rel="icon"` on every page. Use a 32 px PNG/SVG; add `apple-touch-icon` (`assets/app-icon.png` exists) and `theme-color`.
- Fonts: no `preload` for the two above-the-fold fonts, so the hero reflows under `font-display: swap`; `fonts.css:49-86` registers JetBrains Mono twice with the same file for 400 and 700 (merge into one block with `font-weight: 400 700` if variable).
- Sharing metadata only on home: benchmark and support have no `og:*`/`twitter:*`; no `<link rel="canonical">` on any page. Add per-page OG + canonical, and a `SoftwareApplication` JSON-LD on home (`operatingSystem: "macOS 15 or later"`, `offers: {price: "35", priceCurrency: "USD"}`).
- `legal/notices` lists "Parakeet Unified, Parakeet Streaming" (Unified removed 8.2.5) and calls Ultra "(default)" (default is Streaming on English Macs). `:69` "All four speech-model licenses" sits under the typing-models table.
- Legal/benchmark measure: `.doc { max-width: 820px }` at 17 px ≈ 95 characters per line (`site.css:149,153`). 720 px.
- Sub-page nav wraps at 375 px: "← Back to PUSHTYPE" breaks beside the 44 px toggle (`benchmark/index.html:39`, `support/index.html:38`, `thanks/index.html:24`, legal `:38`). "← Back" or `white-space: nowrap`.
- Theme toggle ARIA: `aria-pressed` + a label that flips meaning announces "Switch to light mode, pressed" (`index.html:57`, `theme.js:12-13`). Fixed `aria-label="Dark mode"` + `aria-pressed`. `theme.js` also ignores system theme changes after load.
- Contrast: `.cali .keeps` white on the coral part of the gradient is 2.56:1 (`site.css:120`) — use `var(--sunset-ink)`. `.field-demo .ghost` #8e8e93 on #edebe6 is 2.74:1 (`:245`) — intentional "gray suggestion" demo; #6e6e73 stays gray and reads. All token pairs otherwise pass in both themes.
- Terms say "about 600 MB of free space for each speech model" (`terms.html:48`); the FAQ says 1.3–5.3 GB for TYPE (`index.html:411`). Align.

### Legal
- Two governing laws on one purchase: Polar's buyer terms (Delaware, JAMS arbitration, refunds "in conjunction with the Supplier") vs `EULA.md:99-102` California / LA County. Not a contradiction, but `TERMS_OF_SALE.md:9-10` should say "Polar's buyer terms govern the payment and receipt; this page and the EULA govern the license." and who issues the refund ("We ask Polar to refund you; it reaches your card in a few days.").
- Sparkle row (`PRIVACY.md:48`) will be wrong at launch (host moves), says "macOS version" is sent (it isn't — no `SUEnableSystemProfiling`; only a User-Agent with app + Sparkle version), and doesn't mention that the update file itself comes from GitHub releases.
- `PRIVACY.md:81-84` "nothing is stored": the tab keeps checkout id + session token in `sessionStorage` (`thanks/index.html:66-67`) and Netlify keeps function logs (status codes only). Say "nothing on our side; your browser keeps the order number until you close the tab".
- Support email via ImprovMX → Gmail: neither is named as a processor; `PRIVACY.md:86-88` covers only the Netlify form.
- Gemma 4 E4B licence not re-verified today (E2B is Apache-2.0 per the HF API; `THIRD_PARTY_NOTICES.md:67` claims the same for E4B). One-minute check.

### App UI
- **Speech-model onboarding page is a dead end on a blocked network.** `OnboardingView.swift:550-558` shows "Downloading… 0%" forever (FluidAudio has no timeout); no Cancel (TypingModelRow has one, `:67`), cards disabled mid-download (`:531`), Continue locked (`:1101`), and closing the window doesn't mark the wizard seen until a model is on disk (`OnboardingWindowController.swift:113`), so it reopens every launch. Add Cancel, surface the stall watchdog's message in-page, allow Skip/close after one failed attempt.
- **Popover has no missing-permission state.** `MenuBarView.swift:459-468` says "Ready" with Accessibility denied, when the hotkey silently does nothing. Add "Needs Accessibility" / "Needs Microphone" ahead of "Ready", tappable to `PermissionGuide.shared.show(.accessibility)`. (Same gap in the unlicensed state: one button with no explanation, `:100-112`.)
- **Pill ignores Reduce Motion.** `FloatingPillView.swift:7` reads `accessibilityReduceMotion` and never uses it; `repeatForever` dots (`:282-296`) and the spring (`:44-49`) always run. VoiceGlow, NotchEdgePulse, PermissionGuide and TeleprompterView all do it right.
- **Destructive actions with no confirmation:** Delete speech model (`ModelsSettingsView.swift:160`, 600 MB), Delete typing model (`TypingModelRow.swift:78`, 1.3–5.3 GB), Remove This Mac (`LicenseSettingsView.swift:30`, deactivates the licence). Personal's Delete All (`PersonalSettingsView.swift:116-122`) is the pattern.
- VoiceOver: `Picker("", …)` + `.labelsHidden()` at `MenuBarView.swift:156,170,191,237,251`, `Toggle("")` at `:207`, `DictionarySettingsView.swift:270` have no name (pass the caption as the title; labelsHidden still hides it). Icon-only buttons without `accessibilityLabel` (`.help` is a tooltip, not a name): `DictationSettingsView.swift:162-176`, `DictionarySettingsView.swift:51-58, 196-202, 252-259`, `TypingSettingsView.swift:159-163`, `PersonalSettingsView.swift:92-95`, `TypingPauseControl.swift:22`, `LearningPauseControl.swift:25`. Tap-gesture "radio" rows invisible to assistive tech: `ModelsSettingsView.swift:150`, `TypingModelRow.swift:61`, `OnboardingView.swift:529`, `PillSettingsView.swift:31`.
- Models pane holds half the models: TYPE's list + a duplicate "Downloaded models / Show in Finder" row live in the TYPE pane (`TypingSettingsView.swift:16-34, 52-55`). Merge into Models as a second section, or rename "Speech Models". The Pill pane (two Talk-only sections) can fold into Talk; suggested tab order General, Talk, TYPE, Models, Dictionary, Personal, Teleprompter, License (`SettingsView.swift:38`).
- Onboarding can lose two pages (10 → 8): merge `personal` + `screenText` into "Make it yours"; put the two feature switches on `welcome` (its highlights `:162-188` re-describe `features` `:366-384`). The `.otherMac` page shows a disabled Continue beside its own Yes/No (`:1098`, `:1072`) — hide it like Back (`:1046-1048`). The finish page's `:964` copy is wrong for TYPE-only users and `:978` draws a mic glyph the menu icon won't have (`MenuBarController.swift:79-85`).
- `TypingModelRow.swift:84-88`: Download also selects the model, so "In use" moves to a model not yet on disk for the length of a 5 GB download. Select on completion.
- TYPE's master switch is "Suggest as I type" (`TypingSettingsView.swift:43`, `OnboardingView.swift:629`) while Talk's is "Talk". Use "TYPE".

---

## Low / nits (condensed)

**Licensing:** machine identity is only Polar's activation id (`activatedHereKey` in UserDefaults, `LicenseModel.swift:45,97`), so an OS reinstall takes a new seat while the old lingers — the 4th-Mac copy (`:191`) should mention the portal lists stale Macs. `.gitignore` lacks `.env*` (none committed; a `git log -S` for `polar_oat_`, `whsec_`, `polar_cst_` found nothing).

**Security:** no `IsSecureEventInputEnabled()` guard in `TypingKeyTap.swift:140-147` (keystrokes sit in `KeystrokeBuffer` until the next focus read; never persisted or shown — defence in depth). `push_debug.log` records which app was dictated into and when (`TextInjector.swift:107`, `HotkeyManager.swift:354-360`), 512 KB rolling, never deleted, no Clear Log UI. No "remove all PUSHTYPE data" path: Delete All (`TypingHistoryStore.swift:284-303`) leaves the iCloud sync key and KVS chunks; dragging the app to the Trash leaves `Application Support/PUSH/*`, `FluidAudio/Models/*`, UserDefaults (incl. the plaintext Teleprompter script, `TeleprompterState.swift:64`), and three Keychain items. DMG is not signed/notarized (`build_distribution.sh:270`; only the ZIP is submitted, `:233`). Unused Apple-events entitlements (`PUSH.entitlements:5-6, 27-30`). `TypingHistoryVault.makeKey` (`TypingHistoryStore.swift:350-357`) sets `ThisDeviceOnly` on a legacy item where macOS ignores it. Test fixtures contain the author's first name + `@gmail.com` (`TypingFieldPolicyTests.swift`, `TypingSurfaceLineTests.swift`) in a public repo.

**Core:** `TextInjector.swift:151-152` semaphore on main ≤350 ms; two dictations inside 1 s restore the first transcript as "the clipboard" (`:174-199`); converter input block always returns `.haveData` (`AudioRecorder.swift:429-432`, `WakeWordListener.swift:177-180`); `PUSH_TYPE_SPIKE` + `print` ship in release (`AppDelegate.swift:97-106`); `WakeWordListener.pauseListening` never stops its engine (two engines hold the mic while recording — why the indicator never goes out in wake-word mode). `Info.plist` has `UIBackgroundModes` (iOS key) and a no-op ATS exception. Untested: HotkeyManager state machine, `ModelLoader.performActivation` supersede rules, `TypingKeyTap` start/failure, `TextInjector` snapshot/restore ordering, a first-launch run against empty defaults — B1, H3 and the Metal-abort case would all fall out of a "fresh Mac, no permissions, no models" test.

**Website:** Oxford comma misses at `support/index.html:22`, `benchmark/index.html:22`, `legal/privacy.html:52`, `legal/eula.html:53`; straight quotes at `index.html:243,351` and throughout the legal pages while home uses curly; footer social icons are 20 px with 18 px gaps (`site.css:329-330`) — pad to 44 px; no skip link; breakpoints are `max-width` (desktop-first, against the CSS rule — not worth pre-launch churn); `.duo .card h3` orphans "it." at 375 px (`text-wrap: balance`); benchmark says "PUSH 8.2.4" (`benchmark/index.html:46`) — re-run or say unchanged; `build_legal.py:98` "personalisation" in an HTML comment; `support/index.html:78` hint changes without `aria-live`.

**Legal:** `EULA.md:49` path `PUSH.app/Contents/Resources/Legal` breaks on the PUSHTYPE.app rename ("inside the app bundle under Contents/Resources/Legal"); EULA §2 never says the app checks daily for updates and that it can be turned off; `LICENSE:3-4` says "PUSH … End User Licence Agreement" with British spelling (repo-facing, first thing a visitor reads); dates differ (EULA Oct 14, Privacy Oct 13, Terms undated); `TERMS_OF_SALE.md:40` "Deactivate the old one" — the button is "Remove This Mac"; EULA banner says "Placeholders are in [brackets]" and none remain; theme preference in localStorage not mentioned; GitHub's privacy policy not linked where Hugging Face's and Polar's are.

**App UI:** `MenuBarView.swift:81` "Switched off on this Mac" is unreachable; learning-share wording differs (`PersonalSettingsView.swift:60` vs `OnboardingView.swift:338`); `OnboardingView.swift:670` hardcodes "` takes all of it" (unreadable at 15 pt tertiary, ignores a custom key — use `AcceptKeyResolver.name(of:layout:)`); 10 pt text at `MenuBarView.swift:82,183` (raise to 11); `AcceptKeyRecorder.swift:27` "Press a key…" has no visible way out; `GeneralSettingsView.swift:46` "Offline voice to text" predates TYPE; `:90` is a five-sentence caption; `DictionarySettingsView.swift:285` "what is it? (e.g. a person named Hamer)" — sentence case, no real-looking surname.

---

## Copy fixes (app)

No British spellings reached user-visible strings except one; "licence/colour/grey/behaviour" occur only in comments and stored keys, which must stay. No "Voice"/"Dictation" used as a feature name; no lowercase Push/Type. No placeholder or debug strings in user-visible paths.

| file:line | Current | Suggested | Rule |
|---|---|---|---|
| `GeneralSettingsView.swift:53` | Acknowledgements | Acknowledgments | American |
| `ModelLoader.swift:415` | …in PUSH's Settings. | …in PUSHTYPE's Settings ▸ Models. | Product name |
| `OnboardingView.swift:449` | …no need to restart PUSH. | …no need to restart PUSHTYPE. | Product name |
| `PermissionGuideCard.swift:26` | "PUSH. Drag into the list above." | "PUSHTYPE. Drag into the list above." | Product name (VoiceOver) |
| `TeleprompterSettingsView.swift:72` | Voice-following needs the Parakeet model. Download it in Models. | Follow my voice needs Parakeet Streaming. Download it in Settings ▸ Models. | Two Parakeet models; `TeleprompterSession.swift:97` checks Streaming |
| `GeneralSettingsView.swift:46` | Offline voice to text | Dictation and autocomplete, on your Mac. | Tagline covers TYPE |
| `TypingSettingsView.swift:43`, `OnboardingView.swift:629,631` | Suggest as I type | TYPE | Feature name, parity with "Talk" |
| `TypingSettingsView.swift:76`, `OnboardingView.swift:659` | Xcode, VS Code and Cursor | Xcode, VS Code, and Cursor | Oxford comma |
| `TypingSettingsView.swift:177` | password managers, Keychain Access and System Settings | …Keychain Access, and System Settings | Oxford comma |
| `PersonalSettingsView.swift:51` | Passwords, sign-in fields and terminals | …sign-in fields, and terminals | Oxford comma |
| `OnboardingView.swift:176` | your phrases, names and tone | …names, and tone | Oxford comma |
| `OnboardingView.swift:253` | your settings, dictionary and what it knows about you | …dictionary, and what it knows about you | Oxford comma |
| `OnboardingView.swift:540` | …Spanish, French, German and other European languages. | …German, and other European languages. | Oxford comma |
| `OnboardingView.swift:544` | …Hindi, Russian and more. | …Russian, and more. | Oxford comma |
| `OnboardingView.swift:979` | …the pill's position and your dictionary | …position, and your dictionary | Oxford comma |
| `PUSHCore/WhisperModel.swift:90` | …Italian, Portuguese and more | …Portuguese, and more | Oxford comma |
| `PUSHCore/WhisperModel.swift:94` | …Russian, Greek and more / Spanish, French and German | …Greek, and more / …French, and German | Oxford comma |
| `FloatingPillView.swift:260,261,264,268` | "Warming up...", "Processing...", "Loading model..." | Use the ellipsis character … | Matches `MenuBarView.swift:463-466` |
| `FloatingPillView.swift:261` | Processing... | Transcribing… | Same state is "Transcribing…" in the popover `:464` |
| `MenuBarView.swift:81` | Switched off on this Mac | delete | Unreachable |
| `DictationSettingsView.swift:44` | Add microphone | Add Microphone… | Title Case for a menu button |
| `TypingModelRow.swift:82` | Needs 16 GB | Needs 16 GB of memory | Clarity |
| `NotificationManager.swift:46-47` | Microphone Access Required / …Please grant access in System Settings. | Microphone is off for PUSHTYPE / Turn it on in System Settings ▸ Privacy & Security ▸ Microphone. | Next step, drop "Please" |
| `NotificationManager.swift:54-55` | Transcription Failed / Unable to transcribe audio. Please try again. | Nothing was transcribed / Hold the key and try again. If it keeps happening, pick another model in Settings ▸ Models. | Next step |
| `NotificationManager.swift:62-63` | Model Error / …Open Settings to choose or re-download one. | Speech model didn't load / Open Settings ▸ Models to pick or re-download one. | Exact location |
| `AppDelegate.swift:179-182` | "\(permission) Access Required" / "…Please grant access in System Settings > Privacy & Security." / "Open Settings" | "PUSHTYPE can't use the microphone" / "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone." / "Open System Settings…" | Next step; button names what it opens |
| `OnboardingView.swift:670` | Tab takes a word, ` takes all of it. | Tab takes a word, \(wholeKeyName) takes all of it. | Honours a custom key |
| `OnboardingView.swift:338` | Share it with my other Macs, through my iCloud | Share what it learns with my other Macs | Match `PersonalSettingsView.swift:60` |
| `OnboardingView.swift:964` | Recommended. Talk is only useful if it is already running… | When Talk is off: "Recommended. Suggestions only appear while PUSHTYPE is running." | Wrong for TYPE-only users |
| `DictionarySettingsView.swift:285` | what is it? (e.g. a person named Hamer) | What is it? For example, a person's name | Sentence case; no real-looking name |
| `AcceptKeyRecorder.swift:27` | Press a key… | Press a key (Esc cancels)… | Way out is invisible |

---

## Spacing: app

Suggested scale: **4 / 6 / 8 / 12 / 16** only. Today the popover uses 1.5/2/5/6/8/9/10/11/14, onboarding 2–36 in twelve steps, settings rows 2–26 in nine. The biggest win is structural: ~13 captions that each occupy their own `.formStyle(.grouped)` row (a full row's insets each) — move them into the section `footer:` (as `TypingSettingsView.swift:127-133` does) or into the toggle's label VStack (as `:65-72`). None of this removes information.

| file:line | Modifier | Current | Suggested |
|---|---|---|---|
| `SettingsWindowController.swift:42-43` | styleMask / setContentSize | `.resizable`, 820×620 | no `.resizable`, 720×640 |
| `SettingsView.swift:83` | `.frame` | 720×640 | 680×600 once captions move |
| `SettingsView.swift:93` | sidebar width | 196 | 168 |
| every `.formStyle(.grouped)` Form | row insets | default (~10 pt/row) | `.environment(\.defaultMinListRowHeight, 22)` + `.controlSize(.small)` |
| `DictationSettingsView.swift:78,101,130`; `DictationTextSections.swift:27,50,58`; `PillSettingsView.swift:37,54`; `TeleprompterSettingsView.swift:51,59,66,80,93`; `ModelsSettingsView.swift:35`; `GeneralSettingsView.swift:90` | caption as its own Form row | one full row each (~13) | section `footer:` or the toggle's label VStack |
| `MenuBarView.swift:65` | popover width | 290 | 272 |
| `MenuBarView.swift:94-95` | header padding | h 14, v 11 | h 12, v 8 |
| `MenuBarView.swift:110-111` | activateRow padding | h 14, v 10 | h 12, v 8 |
| `MenuBarView.swift:124-125` | featureSwitch padding | h 14, v 8 | h 12, v 6 |
| `MenuBarView.swift:143-144` | hotkeyRow padding | h 14, v 9 | h 12, v 4 |
| `MenuBarView.swift:153, 223-224` | controls spacing / padding | 9 / h 14, v 10 | 6 / h 12, v 8 |
| `MenuBarView.swift:235, 284-285` | typingControls spacing / padding | 9 / h 14, v 10 | 6 / h 12, v 8 |
| `MenuBarView.swift:181, 299` | caption gutter width | 62 | 56 |
| `MenuBarView.swift:402,419` | `Divider().padding(.vertical)` | 4 | 2 |
| `MenuBarView.swift:425-426` | commands padding | h 8, v 8 | h 6, v 4 |
| `MenuBarView.swift:541-542` | CommandRow label padding | h 6, v 5 | h 6, v 4 |
| `OnboardingWindowController.swift:18` | window | 640×600 | 620×560 after the rows below |
| `OnboardingView.swift:102-103` | content padding | h 36, top 34 | h 28, top 24 |
| `OnboardingView.swift:107-108` | footer padding | h 24, v 14 | h 20, v 10 |
| `OnboardingView.swift:150,219,721,745,804` | step VStack spacing | 18 | 12 |
| `OnboardingView.swift:360,397,952` | step VStack spacing | 16 / 20 / 16 | 12 |
| `OnboardingView.swift:1034-1036` | stepHeader title / subtitle | 22 pt / `.title3` (15) | 20 pt / `.body` (13) |
| `OnboardingView.swift:937,1170` | featureCard / permission row padding | 14 | 12 |
| `OnboardingView.swift:817` | sandbox TextEditor height | 120 | 96 |
| `OnboardingView.swift:666` | typing sandbox height | 84 | 72 |
| `OnboardingView.swift:151` | app icon | 84 | 64 |
| `PermissionGuideCard.swift:17,44` | card size / trailing padding | 470×92 / 34 | 440×80 / 28 |
| `TeleprompterSettingsView.swift:21` | script minHeight | 160 | 120 |
| `PersonalSettingsView.swift:24` | About TextEditor height | 64 | 56 |
| `GeneralSettingsView.swift:34,38` | about row spacing / icon | 15 / 56 | 12 / 48 |
| `PillSettingsView.swift:24,35` | thumbnail spacing / v padding | 26 / 6 | 16 / 4 |
| `PillPositionThumbnail.swift:33,58,63` | thumbnail frame / pills | 176×112 / 96×20, 84×22 | 152×96 / 82×17, 72×19 |
| `FloatingPillView.swift:81-83` | notch tab padding | h 16, top 3, bottom 7 | h 14, top 2, bottom 6 |
| `FloatingPillView.swift:106-107` | capsule padding | h 12, v 6 | keep |
| `TypingSettingsView.swift:136,217` | swatch spacing / size | 10 / 20 | 8 / 16 |
| `ModelsSettingsView.swift:75,80` / `TypingModelRow.swift:18,23` | row HStack / VStack spacing | 10 / 3 | 8 / 2 |

## Spacing: website

The home page is over 9,800 px tall at 1280 px wide. This table takes roughly 1,500–2,000 px off without dropping a word. Selectors are in `website/assets/site.css` unless noted.

| Selector | Property | Current | Suggested | Note |
|---|---|---|---|---|
| `.section` (:30) | padding-block | 104px | 72px | Biggest single win; 11 sections |
| `.hero-solo` (:283) | padding-block | 72px 96px | 48px 56px | Hero height |
| `.hero-solo + .section` (:286) | padding-top | 104px | 64px | Stacks with hero bottom → 200 px gap today |
| `.hero .stack` inline (`index.html:67`) | gap | 28px | 20px | |
| `.hero-solo h1` (:284) | font-size | clamp(52px, 7.6vw, 108px) | clamp(48px, 6.5vw, 92px) | Two lines either way |
| `.stack` inline (`index.html:131,171,202,235,257`) | gap | 48px | 32px | Heading-to-grid |
| `#features .stack` (`index.html:307`) | gap | 56px | 36px | |
| `.card` (:21) | padding | 28px | 22px | All cards |
| `.duo .card` (:237) | padding / gap | 36px / 18px | 28px / 14px | |
| `.price-card` (:128) | padding / gap | 40px / 24px | 32px / 18px | |
| `.price` (:129) | font-size | 80px | 64px | |
| `.pricing .h2` (:127) | font-size | clamp(40px, 5.5vw, 64px) | same as `.h2` | One scale fewer |
| `.grid` (:26) | gap | 24px | 16px | |
| `.ticks` (:33) | gap | 12px | 8px | |
| `.body` (:18) | line-height | 1.6 | 1.5 | |
| `.faq` (:133) | gap | 36px 64px | 24px 48px | |
| `#faq .stack` (`index.html:408`) | gap | 40px | 28px | |
| `.feature-lists` (:107) | padding-top / gap | 40px / 40px | 28px / 28px | |
| `.learn-note` (:341) | margin-top | -16px | -8px | Prevent overlap after the gap cut |
| `.cali .wrap` (:112) | padding-block / gap | 88px / 36px | 56px / 24px | |
| `.cali` (:111) | margin-bottom | 96px | 56px | |
| `.cali-card` (:115) | padding / gap | 32px 36px / 26px | 24px 28px / 18px | |
| `.about .wrap` (:138) | padding-block | 56px | 36px | |
| `.footer .wrap` (:143) | padding-block / gap | 56px / 20px | 36px / 14px | |
| `.footer .socials` (:329) | margin-top | 18px | 0 | Row gap already applies |
| `.nav` (:38) | height | 80px | 64px | Matches the ≤620 px value |
| `.doc` (:149) | padding-block / max-width | 48px 104px / 820px | 32px 64px / 720px | Legal pages |
| `.doc h2` (:151) | margin | 48px 0 12px | 32px 0 8px | |
| `.doc p, .doc li` (:153) | line-height | 1.65 | 1.55 | |
| `.bench` (:191) | padding-block / gap | 56px 104px / 64px | 32px 64px / 40px | Benchmark, support, thanks |
| `.bench td` (:203) | padding | 14px 16px | 10px 14px | |
| `@media (max-width: 960px) .section` (:168) | padding-block | 72px | 48px | Mobile |

### Asset weights

| File | Size | Note |
|---|---|---|
| `assets/video/teleprompter.mp4` | 3.1 MB (20 s) | Autoplays; re-encode |
| `assets/video/dictation.mp4` | 1.95 MB (32 s) | Autoplays |
| `assets/video/typing.mp4` | 1.85 MB (32 s) | Autoplays |
| `assets/icon.png` | 463 KB, 512×512 | Favicon on every page |
| `assets/share.png` | 181 KB, 1200×630 | Fine (crawlers only) |
| video posters (3 JPGs) | 69–121 KB each | Fine |
| fonts (7 woff2) | 283 KB total | `font-display: swap`, no preload |
| CSS (4 sheets) | ~30 KB | Fine |
| gtag.js | ~90 KB gz | The only external request |

---

## Verified and fine (no action)

- **Launch PR:** config ids, DEBUG/release split, website links, robots, sitemap.
- **Netlify functions:** webhook uses Standard Webhooks HMAC over `id.timestamp.body`, `timingSafeEqual`, 5-minute tolerance, both `whsec_` readings, unknown events 202'd, product/benefit allow-list before any write; replay inside the window just re-runs an idempotent reconcile. `/api/purchase`: v4 UUID checkout ids (not enumerable), 1-hour window, 30/min/IP rate limit, `no-store`, no CORS headers (same-origin only), session token reused only after `/me` matches the checkout's customer; the Polar access token never leaves Netlify. Race between `/api/purchase` and the webhook is benign (both PATCH the same computed limit).
- **Secrets:** none tracked; `.gitignore` covers `*.dmg`, `*.zip`, `.claude/`, `*.gguf`; EdDSA private key and notary credentials live in the login Keychain. Git history scanned for Polar/webhook token prefixes: clean.
- **Signing:** hardened runtime, notarized, stapled (app + ZIP); no `disable-library-validation` / `allow-jit` / `get-task-allow`; `SUPublicEDKey` present; feed over https; no `SUEnableSystemProfiling`; `NSAllowsArbitraryLoads` false.
- **Privacy in code:** audio never written to disk; `PushLogger` interpolates only counts, roles, app ids, durations; typing history AES-GCM with a Keychain key at `TypingHistoryStore.swift:310`; shared history zlib + AES-GCM with a synchronizable data-protection key; licence key is a synchronizable data-protection item in access group `B8R5B24PMP.com.push.voicetotext` (`PUSH.entitlements:50-54`); pastes carry `org.nspasteboard.TransientType` + `AutoGeneratedType` and the previous clipboard is restored with all flavors; TYPE model downloads are commit-pinned + SHA-256; secure fields and password-manager clipboard types are skipped (`FocusReader.swift:82,97`, `ScreenTextReader`, `ClipboardContext`); Screen Recording is only requested from Settings. No analytics or crash SDK in the app. Dependencies current: Sparkle 2.9.3, FluidAudio 0.17.4, llama.cpp b11147 (checksummed binary target).
- **Legal consistency:** $35 / 3 Macs / $12 across home, thanks, Terms, EULA; 14-day no-questions refund everywhere; macOS 15+ / Apple silicon everywhere; the privacy policy matches the code almost line for line (24 h revalidation, Mac model label, iCloud Keychain, history path); `website/legal/*.html` is byte-identical to a fresh render of `legal/*.md`. No GPL/AGPL/LGPL anywhere; the repo `LICENSE` (proprietary, MIT ≤ 8.2.2) is consistent with EULA §4 and with `git show v8.2.2:LICENSE`.
- **Website:** no horizontal overflow at a true 375 px viewport; one h1 per page, `lang="en"`; videos have aria-labels and no speech (no captions needed); http→https, www→apex, `/benchmark`→`/benchmark/` redirects live; support form is Netlify Forms with a honeypot and a hidden subject, posting to the noindexed `/support/sent/`; `typography.py` run on a scratch copy changed nothing; 0.04 s / 20× on home is the Ultra figure and the benchmark page explains Streaming's 0.02 s / 38×.
- **House style in the app:** naming (Talk / TYPE / PUSH / PUSHTYPE), American spelling, download sizes disclosed before every download, colour-only states none, custom-colour contrast fine.

## Dependency licences

| Dependency | Licence | Notice | Commercial |
|---|---|---|---|
| FluidAudio 0.17.4 (+ NemoTextProcessing, fastcluster, VBx, Kokoro frontends) | Apache-2.0 / MIT / BSD-2 | yes | yes |
| Sparkle 2.9.3 | MIT (+ BSD / public-domain parts) | yes | yes |
| LaunchAtLogin-Modern 1.1.0 | MIT | yes | yes |
| llama.cpp b11147 | MIT | yes | yes |
| voice-glow (ported) | MIT | yes | yes |
| moondream/parakeet-ultra (+ nvidia/parakeet-tdt-0.6b-v3) | CC-BY-4.0 | yes | yes |
| nvidia/parakeet-unified-en-0.6b (Streaming) | NVIDIA Open Model License | yes | yes (not redistributed) |
| nvidia/nemotron-3.5-asr-streaming-0.6b | OpenMDW-1.1 | yes | yes |
| Silero VAD | MIT | yes | yes |
| Qwen/Qwen3.5-2B-Base GGUF | Apache-2.0 | yes | yes |
| google/gemma-4-E2B GGUF | Apache-2.0 (verified today) | yes | yes |
| google/gemma-4-E4B GGUF | claimed Apache-2.0 | yes | verify |
| Fonts: Archivo, Instrument Sans, JetBrains Mono, Shrikhand | OFL-1.1 | named only — text + copyright lines missing | yes once added |

## Questions for the attorney

1. Entity: individual d/b/a PUSHTYPE vs LLC before the first sale; which name goes in all three documents; whether a postal address must appear (Cal. B&P §17538 for online sellers; CAN-SPAM if "product news" email is ever sent) or whether Polar as merchant of record carries that.
2. Is a licence grant inside the EULA for the standalone $12 single enough, or should the Terms list it as a separate product?
3. Governing-law split: Polar (Delaware, arbitration) for the sale vs California / LA for the licence — fine as drafted, or should the EULA defer to Polar's terms for anything about payment?
4. Is "email us within 14 days, full refund, no questions" plus "your key stops working" sufficient as the refund policy Polar's buyer terms reference, and is it compatible with EU 14-day withdrawal for digital content once the key is activated?
5. California: enforceability of the reverse-engineering clause (with carve-out) and the liability cap at price paid; whether a Civ. Code §1789.3 consumer notice is needed on the site.
6. Privacy: is one policy for app + website enough; add GDPR legal basis / transfer language and a retention period for Polar order data, or is "we hold name, email, country, order" adequate for a seller with no EU presence?
7. Does a clickwrap at purchase or first launch materially improve enforceability over footer + Settings links for a $35 consumer licence?

## Notes on process

- Reviewers could not confirm anything that lives only in the Polar or Netlify dashboards: the success URL on both checkout links, `POLAR_SERVER=production`, the webhook secret, and the Netlify base-directory setting (inferred from the live headers).
- The in-app UI findings are from code, not screenshots (launching the app takes over the screen). The website was rendered headless at 1280 px and in a true 375 px viewport; screenshots are in this session's scratchpad, not the repo.
