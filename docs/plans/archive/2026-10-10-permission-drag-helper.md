# Permission drag helper — design and plan

Date: 2026-10-10
Status: built 2026-10-10 on `feature/permission-drag-helper`. Verified end to end on a
Developer-ID-signed build: card shown 01:15:59Z, Accessibility granted by drag
01:16:10Z, card closed itself, hotkey tap created 01:16:12Z with no relaunch.
Not yet checked: second display, moving/resizing System Settings mid-flow,
Reduce Motion. Deviation from plan: the card rises into place instead of
flying from the button (simpler, same idea).
Independent of Autocomplete; can ship first, on its own branch off `main`.

## What this is

When PUSH sends you to System Settings → Privacy & Security → Accessibility, a
small floating card appears over the bottom of the System Settings window:

```
 ↑  Drag PUSH to the list above to allow Accessibility
 ✕  [ (icon) PUSH ]          ← a real drag source
```

You drag the PUSH row into the list and macOS adds PUSH and switches it on
(after its own Touch ID/password prompt). The card follows the window, hides
when System Settings is not frontmost, and closes itself the moment PUSH sees
the permission granted. No hunting for a `+` button, no Finder, no "where is
PUSH.app".

Prior art: Cotabby (`Services/Permission/Guidance/`, AGPL-3.0). **Read for the
idea, written from scratch** — no code copied.

## Where it applies

| Permission | Helper? | Why |
|---|---|---|
| Accessibility | **Yes** | List-based pane; the one that confuses people today (onboarding already needs a paragraph explaining it) |
| Screen Recording (Autocomplete Phase 6) | **Yes** | Same list-based pane |
| Microphone | No | macOS shows a normal Allow prompt; nothing to drag |

## How it works

1. **Open the pane** — existing `PermissionsModel.openAccessibilitySettings()`.
2. **Find the System Settings window.** `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`,
   owner = running app with bundle id `com.apple.systempreferences`, layer 0,
   largest window. Bounds only — no window titles — so this needs **no Screen
   Recording permission**. Convert CG (top-left origin) to AppKit (bottom-left)
   per screen, so it is right on a second display.
3. **Show the card.** `NSPanel` subclass, `.borderless + .nonactivatingPanel`,
   `canBecomeKey/Main = false`, level `.statusBar`,
   `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`,
   `hidesOnDeactivate = false`. Anchored bottom-centre over the content area
   (right of the sidebar), clamped to the screen's visible frame.
4. **Track.** A 0.3 s timer plus `NSWorkspace.didActivateApplicationNotification`.
   A pure state function decides present / reposition / hide / no-op, so the
   window is only touched when the answer changes (no flicker when the macOS
   auth sheet takes focus).
5. **Drag.** `NSView` + `NSDraggingSource`; `mouseDown` starts a session with
   `NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)`, operation
   `.copy`, drag image = snapshot of the row. Using `NSURL` as the writer (not
   hand-made pasteboard data) makes System Settings register exactly this
   bundle's identity.
6. **Done.** `PermissionsModel` already polls every second; when
   `accessibility == .granted` the helper closes. ✕ closes it too.
7. **Polish (last):** the card flies from the button the user clicked into its
   anchored spot along a short arc, ~0.7 s, critically damped.

## Gotchas

- `swift run` has no app bundle, so `Bundle.main.bundleURL` is a folder, not
  `PUSH.app` — **test only with a real `.app`** (CLAUDE.md). Hide the helper
  when `Bundle.main.bundleURL.pathExtension != "app"`.
- A stale TCC entry from an older signed build can show PUSH already in the
  list but off; the copy says "switch PUSH on, or drag it in" in that case.
  (This is the known post-update relaunch case `HotkeyManager` already handles.)
- Never steal focus from System Settings; the panel must never become key.
- Respect Reduce Motion: skip the arc, fade in place.

## Tasks

### Task 1: Window locator (pure geometry, TDD)
- Create `PUSH/Core/PermissionGuide/SettingsWindowLocator.swift`; test
  `Tests/PUSHTests/SettingsWindowLocatorTests.swift`.
- Pure function `appKitFrame(cgFrame:screens:)` tested with two fake screens
  (main 1512×982 at origin, external 2560×1440 to its right and above):
  a window on each converts correctly; a window spanning both picks the larger
  overlap. Pure function `anchoredOrigin(settings:visible:cardSize:)` tested for
  centring and clamping. The `CGWindowList` call itself is a thin wrapper.
- Commit.

### Task 2: Presentation state (pure, TDD)
- Create `PUSH/Core/PermissionGuide/PermissionGuideTracker.swift`; tests for
  `transition(frame:presented:visible:lastFrame:) -> .present | .reposition | .hide | .none`:
  first frame → present; same frame → none; moved → reposition; nil while
  visible → hide; nil while hidden → none; frame again after hide → present.
- Commit.

### Task 3: Drag row and card
- Create `PUSH/Views/PermissionGuide/PermissionDragRow.swift` (AppKit `NSView`,
  `NSDraggingSource`) and `PermissionGuidePanel.swift` (`NSPanel` +
  `NSVisualEffectView` popover material, arrow, title, ✕, row). Light and dark.
- Commit.

### Task 4: Controller and wiring
- Create `PUSH/Core/PermissionGuide/PermissionGuideController.swift`
  (`@MainActor`): `show(for: .accessibility, from: buttonFrameInScreen)` opens
  the pane, starts tracking, closes on grant/✕/timeout (10 min).
- Wire into every place PUSH sends the user to Accessibility today:
  `OnboardingView.swift:190` (permissions step button),
  `GeneralSettingsView.swift:105` (Accessibility row's `openSettings`), and the
  `AppDelegate.swift:132` Privacy deep link. `HotkeyManager.swift:289` only
  triggers the system prompt; leave it, but follow it with the helper when the
  wizard is not showing.
- Commit.

### Task 5: Verify on a real build
- Build the `.app`, remove PUSH from the Accessibility list
  (`tccutil reset Accessibility com.push.voicetotext`), run onboarding, drag,
  confirm the hotkey works without relaunch. Then: external display, System
  Settings moved/resized mid-flow, switching apps (card hides and returns),
  dark and light mode, Reduce Motion. Screenshot each.
- Commit.

### Task 6: Fly-in animation
- Arc + spring from the source button; Reduce Motion falls back to fade.
- Re-verify, commit, then release as its own point version (or fold into the
  next release).
