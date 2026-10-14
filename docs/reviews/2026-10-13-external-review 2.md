# PUSHTYPE: product, engineering, security, and launch review

**Reviewed:** 13 October 2026  
**Scope:** macOS app, Swift packages, local models, licensing and checkout code, release workflow, marketing site, and legal pages. This review is based on the checked-in source. The browser inspection tool could not fetch the public site, so I did not verify the deployed build or its live response headers.

## Readout

PUSHTYPE has a strong product core: real-time on-device dictation, inline autocomplete, shared dictionary, optional local writing history, and a voice-following teleprompter are a more distinct bundle than another dictation utility. The website already tells much of that story well, and the product has unusually thoughtful local privacy controls and testable text/model logic.

The biggest remaining risks are around the boundary between those promises and the launch plumbing. The local license implementation and the buyer-facing iCloud activation promise disagree; the thank-you page loads Google code beside checkout credentials; Type handles system-wide key events before deciding whether a field is safe; and the automated release currently fails before it can produce an artifact. The prelaunch Polar sandbox, disabled license UI, placeholder checkout, and `noindex` directives are treated here as intentional controls, not defects.

### Do before the first paid sale

1. Decide whether licenses should auto-activate on a buyer's other Macs. The current implementation is device-only; update the code or correct the delivery and privacy copy.
2. Remove third-party scripts from the checkout success page, clear checkout credentials from its address bar, and bind the returned key to the specific purchase.
3. Clear Type's keystroke buffer when focus is secure or unsupported and on Type stop/start; prevent secure-field text from becoming fallback context or learning history.
4. Complete live Polar configuration and an end-to-end purchase/activation/refund test before enabling the Buy CTA or license UI.
5. Finalize the EULA and privacy/terms review. The rendered EULA still contains `[date of first paid release]` and `[County]` placeholders.
6. Repair or replace the automated release path. The latest `v9.1.2` workflow failed because its required iCloud provisioning profile is absent from the GitHub runner.

## Security and privacy findings

### High: Type captures key text before secure-field checks

`TypingKeyTap.handle` reads Unicode characters for every key-down and sends them to `TypingCoordinator`; the coordinator adds them to its in-memory `KeystrokeBuffer` before it reads focus and rejects secure fields. The secure-field check is later in `supportedSurface`. This prevents a suggestion for that field, but it does not prevent the password characters from entering PUSH's buffer. On a first focus with no `bufferElement`, a transition without a click can leave those characters in the buffer; an inaccessible following text field can use the buffer as its `before` text. With writing history enabled, that text can also reach the local history path. No code here sends it to a server, but it contradicts the strong “passwords are never read” promise and creates an avoidable local retention path.

**Evidence:** `PUSH/Typing/TypingKeyTap.swift:107-149`, `PUSH/Typing/TypingCoordinator.swift:215-218, 471-493`, `PUSHCore/Typing/KeystrokeBuffer.swift:28-42`, `PUSH/Typing/TypingCoordinator.swift:517-520`.

**Action:** Clear the buffer and reset its field identity whenever focus is secure, unsupported, changes, or Type stops; ensure a new field never falls back to text accumulated for another field. Consider gating character capture on the most recent eligible-focus state. Add a regression test for password → Tab/focus change → inaccessible text field, both with learning off and on. Update the privacy copy only if the implementation intentionally keeps a global transient keystroke buffer.

### High: Checkout credentials share a page with third-party JavaScript

The thank-you page receives `checkout_id` and `customer_session_token` in the URL, then uses them to fetch the license key. The same page loads `gtag.js` from Google. Setting the analytics `page_location` to the path limits the normal page-view field; it does not sandbox the third-party script from reading `location.search` or page content. Those query values are bearer credentials for the purchase lookup, and the page later puts the returned key in the DOM and a custom URL.

**Evidence:** `website/thanks/index.html:4-17, 80-105`; the API accepts the checkout ID at `website/netlify/functions/purchase.mts:36-46` and returns the key at `:96-103`.

**Action:** Do not load analytics or third-party fonts/scripts on the thank-you page. Read the two parameters and immediately replace the URL with a clean path using `history.replaceState`; keep the current no-store API response. If conversion measurement is needed, send a minimal first-party event after the credentials have been removed, without a key, checkout ID, session token, or order number.

### Medium: License lookup is not bound tightly to the checkout

The function lists all license keys for the checkout's customer, picks one created near the checkout, and falls back to that customer's newest granted key if none matches. It does not verify that the checkout is for one of the expected PUSHTYPE products or that the selected key belongs to that exact order. If Polar has not granted the new key yet, or a customer has multiple purchases, the quick-start page can return a different purchase's key.

**Evidence:** `website/netlify/functions/purchase.mts:52-56, 77-94`. The response is rate-limited and `no-store`, which are good safeguards (`:20-24, 106-110`).

**Action:** Verify the checkout product against the production product allowlist and resolve the key from the order/product relationship. If no matching key exists yet, return `not_ready` and keep retrying; remove the `granted[0]` fallback. Keep the buyer session scoped to this checkout/customer and document the checkout ID as a bearer credential.

### High launch-readiness mismatch: Other Macs do not auto-activate in this code

The privacy page says the license key goes into iCloud Keychain and that the buyer's other Macs activate automatically. The quick-start success page repeats that promise. `LicenseKeychain.save` instead sets `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; there is no synchronizable keychain item or license key in `CloudSync.mirroredSettingKeys`. The existing device-only storage is sensible for a per-Mac seat, but the user-facing claim is not implemented.

**Evidence:** `PUSH/Core/LicenseModel.swift:131-161`, `PUSH/Core/CloudSync.swift:34-58`, `legal/PRIVACY.md:45-47`, `website/thanks/index.html:58-60`.

**Action:** Choose one behavior. Either sync only the license key securely and activate a separate seat on each Mac, with matching privacy disclosure, or remove the auto-activation promise and explain that the buyer enters the emailed key on each Mac. Do not sync an activation ID between devices. Include the 3-seat and extra-seat paths in the purchase test.

### Medium: Release workflow interpolates the version input into shell source

`workflow_dispatch`'s user-controlled `version` is inserted directly inside a quoted shell assignment. Quotes do not stop shell expansion of injected `$(...)` or backticks. A user allowed to dispatch the release workflow could execute shell commands in the signing job after the profile problem is fixed.

**Evidence:** `.github/workflows/release.yml:7-11, 57-75`, especially `:61`.

**Action:** Pass the version through a step `env:` variable instead of inline expression substitution, validate it against the expected `vMAJOR.MINOR.PATCH` pattern, and derive the release asset version from the checked-out tag when running on tag pushes. Restrict signing secrets to a protected GitHub Environment and protect release tags.

### Medium: Build output makes a system-wide privacy promise that is too broad

The marketing copy says “Nothing leaves your Mac” and “there's no server,” while the app does contact Polar for license activation/revalidation, GitHub for updates, Hugging Face for model downloads, and Apple iCloud when sync is enabled. Those requests do not carry speech or typed content, and the privacy page lists most of them; the short headline can still be read as no network traffic at all. The site also loads Google Fonts, whose request is not listed in the privacy page.

**Evidence:** `website/index.html:72, 205-228`, `website/legal/privacy.html:48-57`, `website/index.html:38-44`, `website/legal/privacy.html:64-77`.

**Action:** Lead with the narrower, supportable statement “What you say and type stays on your Mac.” Change “there's no server” to “there's no speech or typing cloud service.” Self-host the fonts or disclose the third-party font request. Keep the network-connections table as the canonical full explanation.

### Medium: Static-site security headers are minimal

Netlify currently sets `X-Content-Type-Options` and `Referrer-Policy`; there is no source-level Content Security Policy, HSTS, frame restriction, or Permissions Policy. External fonts, Google Analytics, and inline scripts mean a strict CSP needs a deliberate allowlist or script extraction.

**Evidence:** root `netlify.toml:9-14`; `website/index.html:4-44` and legal template `website/build_legal.py:91-118`.

**Action:** Add a tested CSP (prefer self-hosted assets and extracted inline scripts), HSTS, `frame-ancestors 'none'`, and a Permissions Policy that denies unused camera/microphone/geolocation access. Keep the success-page policy stricter and third-party-free. Verify the deployed response headers after the Netlify deploy.

### Scan notes and good controls

- No tracked `.env`, signing key, or obvious API credential file surfaced in the targeted scan. `gitleaks` is not installed in this environment, so the full Git-history scan remains to be run before launch; `.gitignore` also does not yet exclude `.env*`.
- Typing-model downloads pin a Hugging Face revision and SHA-256 (`PUSHCore/Typing/TypingModel.swift:41-83`, `PUSHCore/Typing/ModelFileDownloader.swift:96-108`). Sparkle uses a public EdDSA key, and its feed is designed to carry signed ZIPs (`PUSH/Info.plist`, `build_distribution.sh:275-284`).
- Writing history is opt-in, AES-GCM encrypted, capped, locally keyed, and has a Delete All path (`PUSH/Typing/TypingHistoryStore.swift:21-38, 159-225`; `PUSHCore/Typing/TypingHistory.swift:176-188`). Typed text is not intentionally logged.
- Secure fields, sign-in labels, code editors, browser address bars, password managers, and Mail headers have dedicated exclusion logic. Keep those rules and the user-visible per-app controls.

## App and architecture

### What is working well

- The `PUSH` app / `PUSHCore` split keeps UI and OS integration out of text processing, model wrappers, and prompt decisions. The comparison app can reuse production engine code.
- Model activation has explicit cancellation/generation handling; model downloads are user-started rather than hidden at launch. The code and UI also expose the storage cost of the large local models.
- `AppState` uses read-tracked `@Observable`; core field classification, prompt construction, typing buffers, transcript cleanup, and model selection have small testable seams.
- The repo has 61 Swift test files, including field policy, typing history, licensing, model loading, update-related logic, and text processing. I did not run tests as part of this review.

### Actions

1. **Add pull-request CI.** The only checked-in workflows are the monthly reminder and release workflow; the release workflow does not run `swift test`. Add a macOS/Xcode job for `swift build` and `swift test`, with the Xcode `DEVELOPER_DIR` the project requires. Keep release signing separate from untrusted PR execution.
2. **Fix the automated release prerequisites.** `build_distribution.sh` expects `~/Library/Developer/PUSH-signing/PUSH_Developer_ID_iCloud.provisionprofile` and exits when it is missing. The latest run failed at this exact step: [GitHub Actions v9.1.2](https://github.com/Elias1986a/PUSH/actions/runs/38516841493). Supply and validate the profile in the protected runner environment, or keep a documented/manual release path until CI can install it safely.
3. **Clean Swift 6 warnings.** The latest build emits concurrency/isolation warnings in `CloudSync.swift`, `TypingCoordinator.swift`, and `LlamaEngine.swift`. Resolve these while targets are still in Swift 5 mode, before a future compiler/language-mode bump turns them into errors.
4. **Refresh model and site docs.** `docs/MODELS.md` still labels its findings as reviewed in June 2026 and carries old upgrade candidates; `docs/website/PLAN.md` says nothing has been built although the site and benchmark page now exist. Update or archive them so monthly model reviews and new contributors use current product facts.
5. **Keep the state machine boundaries explicit.** `AppState.shared`, `ModelLoader`, `TypingCoordinator`, and per-feature singletons are carrying most runtime coordination. Avoid a broad rewrite, but continue moving pure policy into `PUSHCore` and add boundary tests where macOS accessibility, licensing, updater, or download behavior meets those pure decisions.

## Website, positioning, and marketing

### The strongest story

The site has already elevated the best differentiator: one local tool for speaking and typing, with optional learning from both that stays encrypted on-device. “One dictionary, both ways” is concrete and easy to understand. The one-time $35 price, three Macs, 14-day refund, real screen videos, teleprompter, wake word, and measured benchmark give the page tangible proof. Keep the “same passage / same Mac” framing and the honest note that Wispr Flow handled Zürich better.

### Improve before the public launch

1. **Make the hero's privacy promise precise.** Change “Nothing leaves your Mac” to “What you say and type stays on your Mac.” The nuance is that product content stays local while model/update/license/iCloud requests still happen.
2. **Show the permission and storage commitment before Buy.** State that cross-app dictation/Type needs Microphone and Accessibility, Screen Recording is optional for apps whose text is not exposed through Accessibility, speech models are about 600 MB, and Type models range from 1.3–5.3 GB. The FAQ already covers model size and Mac compatibility; bring the permission ask into the purchase decision too.
3. **Promote the unusual features in the decision path.** Add the voice-following teleprompter to the pricing inclusion list, and make the shared dictionary and opt-in “learn from your writing and voice” visible alongside the two headline tools. These are real differentiators over a generic local dictation app.
4. **Qualify “works in every app.”** The product intentionally stands down in secure/sign-in fields, address bars, password managers, Mail headers, and some unsupported surfaces. Say “most text fields across your Mac,” then link the supported-app examples and exclusions.
5. **Choose the first-run offer.** The checkout is intentionally closed right now. Before launch, decide whether $35 is the first and only path or whether visitors can download a trial/demo. A large initial model download plus Accessibility permission is a substantial commitment; a short in-app tryout or clear demo can reduce uncertainty.
6. **Broaden benchmark evidence over time.** The current page is transparent about date, M4 hardware, one passage, sample count, range, and misses. Add a second speaker, noisy-room and multilingual runs, and a non-M4 Mac before making the speed ratio the primary repeated ad claim. Keep the version and date attached to every ratio.
7. **Expose the correct app name/install artifact.** The user-facing brand is PUSHTYPE while the executable, bundle path, repository, and DMG volume retain PUSH. The thank-you steps call the installed app PUSHTYPE. Make the DMG and installation instructions visually identify `PUSHTYPE.app` (or explicitly explain the PUSH bundle name) without changing the shipped bundle identifier or TCC identity.

### Launch-site checklist

- The homepage `noindex`, benchmark `noindex`, and placeholder Buy link are appropriate while the store is closed. Before announcing, remove `noindex` from the marketing and benchmark pages, publish a `robots.txt` and `sitemap.xml`, add canonical/structured product metadata, and make every Buy button open the production checkout.
- Keep legal pages reachable before checkout. The current EULA visibly marks itself as a draft and includes unresolved placeholders; complete legal review and regenerate the HTML from `legal/*.md` before accepting money.
- Make the legal/website copy match actual retention and connectivity: exact license-key storage, per-Mac activation, optional history, iCloud dictionary sync, analytics, fonts, model downloads, update checks, and support-form handling.
- Add purchase-state messaging for expired, failed, delayed, and refunded orders. The current success page keeps the manual email/portal route available, which is a useful fallback; retain that fallback after tightening the quick-start API.

## Suggested order of work

### Before first sale

- Finish license behavior/copy; implement or remove cross-Mac auto-activation promise.
- Harden the thank-you page and purchase-key binding.
- Stop secure-field characters entering or surviving in Type's buffer.
- Complete live Polar configuration, real test purchase, activate three Macs, extra Mac, remove-seat, refund/revocation, and offline revalidation cases.
- Finalize the EULA placeholders and privacy/terms review.
- Make one release path produce a signed, notarized, launchable artifact and a valid Sparkle feed.

### First month after launch

- Add PR CI for build and unit tests, fix Swift concurrency warnings, and run a release smoke check before tagging.
- Add site headers, self-host fonts, finish SEO metadata and verify mobile navigation and checkout on desktop/mobile browsers.
- Update model tracking docs and add benchmark coverage beyond the single M4/script.
- Collect feedback voluntarily through support, with an explicit, transcript-free diagnostic bundle.

## Review limits

This was a static code/config/content review. I did not run the app or tests, execute a paid checkout, request macOS permissions, inspect the deployed Netlify response, or conduct a legal review. `gitleaks` was unavailable; the targeted secret-file/text scan is not a substitute for its history scan.
